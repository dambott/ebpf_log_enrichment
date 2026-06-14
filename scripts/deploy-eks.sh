#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ebpflogs}"
AWS_REGION="${AWS_REGION:-us-west-2}"
CORALOGIX_PRIVATE_KEY="${CORALOGIX_PRIVATE_KEY:?Set CORALOGIX_PRIVATE_KEY}"
HELM_RELEASE="${HELM_RELEASE:-otel-coralogix-integration}"
NAMESPACE="${NAMESPACE:-ebpflogs}"
# Comma-separated app names to rebuild (go,java,python,node,ruby,dotnet). Empty = all.
APPS="${APPS:-}"

export DOCKER_BUILDKIT=1

AWS_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

ensure_repo() {
  aws ecr describe-repositories --repository-names "$1" --region "${AWS_REGION}" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$1" --region "${AWS_REGION}" >/dev/null
}

ecr_uri() {
  echo "${ECR_REGISTRY}/ebpflogs-logdemo-$1:latest"
}

resolve_image() {
  local name="$1"
  local deploy="logdemo-${name}"
  local uri
  uri="$(ecr_uri "${name}")"
  local current
  current="$(kubectl -n "${NAMESPACE}" get deploy "${deploy}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  if [[ -n "${current}" && "${current}" != *__IMAGE_*__ ]]; then
    echo "${current}"
  else
    echo "${uri}"
  fi
}

should_build() {
  local name="$1"
  if [[ -z "${APPS}" ]]; then
    return 0
  fi
  [[ ",${APPS}," == *",${name},"* ]]
}

build_push() {
  local name="$1"
  local dockerfile="$2"
  local context="$3"
  local repo="ebpflogs-logdemo-${name}"
  local uri
  uri="$(ecr_uri "${name}")"

  ensure_repo "${repo}"
  echo "Building logdemo-${name} (linux/amd64)..."
  docker build --progress=plain --platform linux/amd64 -t "${repo}:latest" -f "${dockerfile}" "${context}"
  docker tag "${repo}:latest" "${uri}"
  docker push "${uri}"
  case "$name" in
    go) IMAGE_GO="$uri" ;;
    java) IMAGE_JAVA="$uri" ;;
    python) IMAGE_PYTHON="$uri" ;;
    node) IMAGE_NODE="$uri" ;;
    ruby) IMAGE_RUBY="$uri" ;;
    dotnet) IMAGE_DOTNET="$uri" ;;
  esac
}

if should_build go; then
  echo "Building logdemo-go binary for linux/amd64..."
  (cd "${ROOT}/logdemo-go" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o app .)
  build_push go "${ROOT}/logdemo-go/Dockerfile" "${ROOT}/logdemo-go"
else
  IMAGE_GO="$(resolve_image go)"
  echo "Skipping go build; using ${IMAGE_GO}"
fi

for name in java python node ruby dotnet; do
  case "${name}" in
    java) dockerfile="${ROOT}/logdemo-java/Dockerfile"; context="${ROOT}/logdemo-java" ;;
    python) dockerfile="${ROOT}/logdemo-python/Dockerfile"; context="${ROOT}/logdemo-python" ;;
    node) dockerfile="${ROOT}/logdemo-node/Dockerfile"; context="${ROOT}/logdemo-node" ;;
    ruby) dockerfile="${ROOT}/logdemo-ruby/Dockerfile"; context="${ROOT}/logdemo-ruby" ;;
    dotnet) dockerfile="${ROOT}/logdemo-dotnet/Dockerfile"; context="${ROOT}/logdemo-dotnet" ;;
  esac
  if should_build "${name}"; then
    build_push "${name}" "${dockerfile}" "${context}"
  else
    case "${name}" in
      java) IMAGE_JAVA="$(resolve_image java)"; echo "Skipping java build; using ${IMAGE_JAVA}" ;;
      python) IMAGE_PYTHON="$(resolve_image python)"; echo "Skipping python build; using ${IMAGE_PYTHON}" ;;
      node) IMAGE_NODE="$(resolve_image node)"; echo "Skipping node build; using ${IMAGE_NODE}" ;;
      ruby) IMAGE_RUBY="$(resolve_image ruby)"; echo "Skipping ruby build; using ${IMAGE_RUBY}" ;;
      dotnet) IMAGE_DOTNET="$(resolve_image dotnet)"; echo "Skipping dotnet build; using ${IMAGE_DOTNET}" ;;
    esac
  fi
done

helm repo add coralogix-charts-virtual https://cgx.jfrog.io/artifactory/coralogix-charts-virtual 2>/dev/null || true
helm repo update coralogix-charts-virtual

kubectl apply -f "${ROOT}/k8s/namespace.yaml"
sed -e "s|__IMAGE_GO__|${IMAGE_GO}|g" \
    -e "s|__IMAGE_JAVA__|${IMAGE_JAVA}|g" \
    -e "s|__IMAGE_PYTHON__|${IMAGE_PYTHON}|g" \
    -e "s|__IMAGE_NODE__|${IMAGE_NODE}|g" \
    -e "s|__IMAGE_RUBY__|${IMAGE_RUBY}|g" \
    -e "s|__IMAGE_DOTNET__|${IMAGE_DOTNET}|g" \
    "${ROOT}/k8s/apps.yaml" | kubectl apply -f -

kubectl -n "${NAMESPACE}" delete cronjob logdemo-traffic --ignore-not-found

kubectl -n "${NAMESPACE}" create secret generic coralogix-keys \
  --from-literal=PRIVATE_KEY="${CORALOGIX_PRIVATE_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Coralogix OpenTelemetry Helm chart..."
helm upgrade --install "${HELM_RELEASE}" coralogix-charts-virtual/otel-integration \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${ROOT}/helm/values.yaml" \
  --timeout 20m

RESTART_APPS=(logdemo-go logdemo-java logdemo-python logdemo-node logdemo-ruby logdemo-dotnet)
if [[ -n "${APPS}" ]]; then
  RESTART_APPS=()
  IFS=',' read -ra BUILD_LIST <<< "${APPS}"
  for name in "${BUILD_LIST[@]}"; do
    RESTART_APPS+=("logdemo-${name}")
  done
fi

for app in "${RESTART_APPS[@]}"; do
  if ! kubectl -n "${NAMESPACE}" get deploy "${app}" >/dev/null 2>&1; then
    echo "Waiting for new deployment/${app}..."
  else
    kubectl -n "${NAMESPACE}" rollout restart "deployment/${app}"
  fi
  kubectl -n "${NAMESPACE}" rollout status "deployment/${app}" --timeout=600s
done

echo "Node kernel (need 6.12+ for log enricher):"
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}{"\n"}'

echo "Deploy complete."
echo "  Traffic sidecar: kubectl -n ebpflogs logs -l app=logdemo-go -c traffic -f"
echo "  Enriched logs:   kubectl -n ebpflogs logs -l app=logdemo-dotnet -f | tr -d '\\000' | grep trace_id"
echo "  Manual test:     APP=logdemo-dotnet ./scripts/test-traces.sh"
