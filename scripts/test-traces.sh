#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/languages.sh
source "${ROOT}/scripts/languages.sh"

NAMESPACE="${NAMESPACE:-ebpflogs}"

test_app() {
  local deploy="$1"
  local port="$2"
  local container="$1"

  echo "========================================"
  echo "Testing ${deploy} (port ${port})"
  echo "========================================"

  if ! kubectl -n "$NAMESPACE" get deploy "${deploy}" >/dev/null 2>&1; then
    echo "SKIP: deployment/${deploy} not found"
    echo
    return 0
  fi

  pod=$(kubectl -n "$NAMESPACE" get pod -l "app=${deploy}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "${pod}" ]]; then
    echo "SKIP: no running pod for ${deploy}"
    echo
    return 0
  fi
  kubectl -n "$NAMESPACE" wait --for=condition=ready "pod/$pod" --timeout=180s

  echo "--- UNPRIMED ---"
  kubectl -n "$NAMESPACE" run "curl-u-${deploy}" --restart=Never --rm -i --image=curlimages/curl:8.5.0 \
    -- curl -sf -H 'Connection: close' "http://${deploy}.${NAMESPACE}.svc.cluster.local:${port}/work" || true
  sleep 2
  kubectl -n "$NAMESPACE" logs "$pod" -c "$container" --tail=8 | tr -d '\000'

  echo
  echo "--- PRIMED (traceparent all-a) ---"
  kubectl -n "$NAMESPACE" run "curl-p-${deploy}" --restart=Never --rm -i --image=curlimages/curl:8.5.0 \
    -- curl -sf -H 'Connection: close' -H 'traceparent: 00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01' \
    "http://${deploy}.${NAMESPACE}.svc.cluster.local:${port}/work" || true
  sleep 2
  kubectl -n "$NAMESPACE" logs "$pod" -c "$container" --tail=8 | tr -d '\000'

  echo "--- enriched log lines ---"
  kubectl -n "$NAMESPACE" logs "$pod" -c "$container" --tail=30 | tr -d '\000' \
    | grep -E 'request complete|trace_id' | tail -5
  echo
  echo "--- trace_id values ---"
  kubectl -n "$NAMESPACE" logs "$pod" -c "$container" --tail=30 | tr -d '\000' \
    | grep -oE '"trace_id":"[0-9a-f]{32}"|"trace_id": "[0-9a-f]{32}"' | sort -u \
    || echo "(none — check kernel is 6.12+ and log is JSON on stdout)"
  echo
}

if [[ -n "${APP:-}" ]]; then
  key="${APP#logdemo-}"
  if idx="$(demo_index_for_key "${key}")"; then
    test_app "$(demo_deploy_name "${key}")" "$(demo_port_at "${idx}")"
    exit 0
  fi
  echo "Unknown APP=${APP}"
  exit 1
fi

if [[ -f "${DEMO_SELECTION_FILE}" ]] && [[ "${TEST_ALL:-}" != 1 ]]; then
  demo_load_enabled_keys
  echo "Testing saved selection: $(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"
  echo "(set TEST_ALL=1 to test every deployed language)"
  echo
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    idx="$(demo_index_for_key "${key}")"
    test_app "$(demo_deploy_name "${key}")" "$(demo_port_at "${idx}")"
  done
  exit 0
fi

for i in "${!DEMO_LANG_KEYS[@]}"; do
  test_app "$(demo_deploy_name "${DEMO_LANG_KEYS[$i]}")" "$(demo_port_at "${i}")"
done
