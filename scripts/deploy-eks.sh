#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ebpflogs}"
AWS_REGION="${AWS_REGION:-us-west-2}"
CORALOGIX_PRIVATE_KEY="${CORALOGIX_PRIVATE_KEY:?Set CORALOGIX_PRIVATE_KEY}"
HELM_RELEASE="${HELM_RELEASE:-otel-coralogix-integration}"
NAMESPACE="${NAMESPACE:-ebpflogs}"
# Comma-separated app names to rebuild. Empty = all.
# go java python node ruby dotnet rust php perl cpp kotlin scala crystal
APPS="${APPS:-}"

export DOCKER_BUILDKIT=1

ALL_LANGS=(java python node ruby dotnet rust php perl cpp kotlin scala crystal)

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

set_image_var() {
  local name="$1"
  local uri="$2"
  case "${name}" in
    go) IMAGE_GO="${uri}" ;;
    java) IMAGE_JAVA="${uri}" ;;
    python) IMAGE_PYTHON="${uri}" ;;
    node) IMAGE_NODE="${uri}" ;;
    ruby) IMAGE_RUBY="${uri}" ;;
    dotnet) IMAGE_DOTNET="${uri}" ;;
    rust) IMAGE_RUST="${uri}" ;;
    php) IMAGE_PHP="${uri}" ;;
    perl) IMAGE_PERL="${uri}" ;;
    cpp) IMAGE_CPP="${uri}" ;;
    kotlin) IMAGE_KOTLIN="${uri}" ;;
    scala) IMAGE_SCALA="${uri}" ;;
    crystal) IMAGE_CRYSTAL="${uri}" ;;
  esac
}

lang_dir() {
  case "$1" in
    java) echo "${ROOT}/logdemo-java" ;;
    python) echo "${ROOT}/logdemo-python" ;;
    node) echo "${ROOT}/logdemo-node" ;;
    ruby) echo "${ROOT}/logdemo-ruby" ;;
    dotnet) echo "${ROOT}/logdemo-dotnet" ;;
    rust) echo "${ROOT}/logdemo-rust" ;;
    php) echo "${ROOT}/logdemo-php" ;;
    perl) echo "${ROOT}/logdemo-perl" ;;
    cpp) echo "${ROOT}/logdemo-cpp" ;;
    kotlin) echo "${ROOT}/logdemo-kotlin" ;;
    scala) echo "${ROOT}/logdemo-scala" ;;
    crystal) echo "${ROOT}/logdemo-crystal" ;;
  esac
}

build_push() {
  local name="$1"
  local dir
  dir="$(lang_dir "${name}")"
  local repo="ebpflogs-logdemo-${name}"
  local uri
  uri="$(ecr_uri "${name}")"

  ensure_repo "${repo}"
  echo "Building logdemo-${name} (linux/amd64)..."
  if ! docker build --progress=plain --platform linux/amd64 -t "${repo}:latest" -f "${dir}/Dockerfile" "${dir}"; then
    echo "WARN: build failed for logdemo-${name}; using existing image if available"
    set_image_var "${name}" "$(resolve_image "${name}")"
    return 1
  fi
  docker tag "${repo}:latest" "${uri}"
  docker push "${uri}"
  set_image_var "${name}" "${uri}"
}

if should_build go; then
  echo "Building logdemo-go binary for linux/amd64..."
  (cd "${ROOT}/logdemo-go" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o app .)
  ensure_repo ebpflogs-logdemo-go
  uri="$(ecr_uri go)"
  docker build --progress=plain --platform linux/amd64 -t ebpflogs-logdemo-go:latest -f "${ROOT}/logdemo-go/Dockerfile" "${ROOT}/logdemo-go"
  docker tag ebpflogs-logdemo-go:latest "${uri}"
  docker push "${uri}"
  IMAGE_GO="${uri}"
else
  IMAGE_GO="$(resolve_image go)"
  echo "Skipping go build; using ${IMAGE_GO}"
fi

for name in "${ALL_LANGS[@]}"; do
  if should_build "${name}"; then
    build_push "${name}" || true
  else
    uri="$(resolve_image "${name}")"
    set_image_var "${name}" "${uri}"
    echo "Skipping ${name} build; using ${uri}"
  fi
done

helm repo add coralogix-charts-virtual https://cgx.jfrog.io/artifactory/coralogix-charts-virtual 2>/dev/null || true
helm repo update coralogix-charts-virtual

kubectl apply -f "${ROOT}/k8s/namespace.yaml"
kubectl apply -f "${ROOT}/k8s/traffic-config.yaml"
cat "${ROOT}/k8s/apps.yaml" "${ROOT}/k8s/apps-more.yaml" \
  | sed -e "s|__IMAGE_GO__|${IMAGE_GO}|g" \
        -e "s|__IMAGE_JAVA__|${IMAGE_JAVA}|g" \
        -e "s|__IMAGE_PYTHON__|${IMAGE_PYTHON}|g" \
        -e "s|__IMAGE_NODE__|${IMAGE_NODE}|g" \
        -e "s|__IMAGE_RUBY__|${IMAGE_RUBY}|g" \
        -e "s|__IMAGE_DOTNET__|${IMAGE_DOTNET}|g" \
        -e "s|__IMAGE_RUST__|${IMAGE_RUST}|g" \
        -e "s|__IMAGE_PHP__|${IMAGE_PHP}|g" \
        -e "s|__IMAGE_PERL__|${IMAGE_PERL}|g" \
        -e "s|__IMAGE_CPP__|${IMAGE_CPP}|g" \
        -e "s|__IMAGE_KOTLIN__|${IMAGE_KOTLIN}|g" \
        -e "s|__IMAGE_SCALA__|${IMAGE_SCALA}|g" \
        -e "s|__IMAGE_CRYSTAL__|${IMAGE_CRYSTAL}|g" \
  | kubectl apply -f -

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

RESTART_APPS=(
  logdemo-go logdemo-java logdemo-python logdemo-node logdemo-ruby logdemo-dotnet
  logdemo-rust logdemo-php logdemo-perl logdemo-cpp logdemo-kotlin logdemo-scala logdemo-crystal
)
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
    kubectl -n "${NAMESPACE}" rollout restart "deployment/${app}" || true
  fi
  kubectl -n "${NAMESPACE}" rollout status "deployment/${app}" --timeout=600s || echo "WARN: rollout timed out for ${app}"
done

echo "Node kernel (need 6.12+ for log enricher):"
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}{"\n"}'

echo "Deploy complete."
echo "  Select demos:    ./select-demos.sh"
echo "  Traffic sidecar: kubectl -n ebpflogs logs -l app=logdemo-go -c traffic -f"
echo "  Test all apps:   ./scripts/test-traces.sh"

if [[ -f "${ROOT}/.demo-selection" ]] && [[ "${SKIP_DEMO_SELECTION:-}" != 1 ]]; then
  echo "  Applying saved demo selection..."
  SKIP_DEMO_SELECTION=1 "${ROOT}/scripts/select-demos.sh" apply
fi
