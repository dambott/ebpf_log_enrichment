#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ebpflogs}"
APPS=(logdemo-go logdemo-java logdemo-python logdemo-node logdemo-ruby logdemo-dotnet)
PORTS=(8080 8081 8082 8083 8084 8085)

test_app() {
  local deploy="$1"
  local port="$2"
  local container="$1"

  echo "========================================"
  echo "Testing ${deploy} (port ${port})"
  echo "========================================"

  pod=$(kubectl -n "$NAMESPACE" get pod -l "app=${deploy}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}')
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
  case "${APP}" in
    logdemo-go) test_app logdemo-go 8080 ;;
    logdemo-java) test_app logdemo-java 8081 ;;
    logdemo-python) test_app logdemo-python 8082 ;;
    logdemo-node) test_app logdemo-node 8083 ;;
    logdemo-ruby) test_app logdemo-ruby 8084 ;;
    logdemo-dotnet) test_app logdemo-dotnet 8085 ;;
    *) echo "Unknown APP=${APP}"; exit 1 ;;
  esac
  exit 0
fi

for i in "${!APPS[@]}"; do
  test_app "${APPS[$i]}" "${PORTS[$i]}"
done
