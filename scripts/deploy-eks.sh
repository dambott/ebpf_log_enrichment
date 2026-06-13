#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ebpflogs}"
AWS_REGION="${AWS_REGION:-us-west-2}"
CORALOGIX_PRIVATE_KEY="${CORALOGIX_PRIVATE_KEY:?Set CORALOGIX_PRIVATE_KEY}"
HELM_RELEASE="${HELM_RELEASE:-otel-coralogix-integration}"
NAMESPACE="${NAMESPACE:-ebpflogs}"

AWS_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

ensure_repo() {
  aws ecr describe-repositories --repository-names "$1" --region "${AWS_REGION}" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$1" --region "${AWS_REGION}" >/dev/null
}

build_push() {
  local name="$1"
  local dockerfile="$2"
  local context="$3"
  local repo="ebpflogs-logdemo-${name}"
  local uri="${ECR_REGISTRY}/${repo}:latest"

  ensure_repo "${repo}"
  echo "Building logdemo-${name}..."
  docker build --platform linux/amd64 -t "${repo}:latest" -f "${dockerfile}" "${context}"
  docker tag "${repo}:latest" "${uri}"
  docker push "${uri}"
  case "$name" in
    go) IMAGE_GO="$uri" ;;
    java) IMAGE_JAVA="$uri" ;;
    python) IMAGE_PYTHON="$uri" ;;
    node) IMAGE_NODE="$uri" ;;
    ruby) IMAGE_RUBY="$uri" ;;
  esac
}

echo "Building logdemo-go for linux/amd64..."
(cd "${ROOT}/logdemo-go" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o app .)
build_push go "${ROOT}/logdemo-go/Dockerfile" "${ROOT}/logdemo-go"
build_push java "${ROOT}/logdemo-java/Dockerfile" "${ROOT}/logdemo-java"
build_push python "${ROOT}/logdemo-python/Dockerfile" "${ROOT}/logdemo-python"
build_push node "${ROOT}/logdemo-node/Dockerfile" "${ROOT}/logdemo-node"
build_push ruby "${ROOT}/logdemo-ruby/Dockerfile" "${ROOT}/logdemo-ruby"

helm repo add coralogix-charts-virtual https://cgx.jfrog.io/artifactory/coralogix-charts-virtual 2>/dev/null || true
helm repo update coralogix-charts-virtual

kubectl apply -f "${ROOT}/k8s/namespace.yaml"
sed -e "s|__IMAGE_GO__|${IMAGE_GO}|g" \
    -e "s|__IMAGE_JAVA__|${IMAGE_JAVA}|g" \
    -e "s|__IMAGE_PYTHON__|${IMAGE_PYTHON}|g" \
    -e "s|__IMAGE_NODE__|${IMAGE_NODE}|g" \
    -e "s|__IMAGE_RUBY__|${IMAGE_RUBY}|g" \
    "${ROOT}/k8s/apps.yaml" | kubectl apply -f -

# Sidecar on logdemo-go is the default traffic harness. Delete CronJob if present
# to avoid scheduling an extra pod on small clusters.
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

for app in logdemo-go logdemo-java logdemo-python logdemo-node logdemo-ruby; do
  kubectl -n "${NAMESPACE}" rollout restart "deployment/${app}"
  kubectl -n "${NAMESPACE}" rollout status "deployment/${app}" --timeout=600s
done

echo "Node kernel (need 6.12+ for log enricher):"
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}{"\n"}'

echo "Deploy complete."
echo "  Traffic sidecar: kubectl -n ebpflogs logs -l app=logdemo-go -c traffic -f"
echo "  Enriched logs:   kubectl -n ebpflogs logs -l app=logdemo-ruby -f | tr -d '\\000' | grep trace_id"
echo "  Manual test:     ./scripts/test-traces.sh"
