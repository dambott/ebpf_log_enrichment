#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/languages.sh
source "${ROOT}/scripts/languages.sh"

INVOCATION="${SELECT_DEMOS_NAME:-select-demos.sh}"

usage() {
  cat <<EOF
Usage: ${INVOCATION} [command] [languages]

Choose which logdemo languages are active on EKS. Disabled apps scale to
replicas=0 (saves pod IPs); the traffic sidecar on logdemo-go curls only
enabled targets from the demo-traffic-targets ConfigMap.

Commands:
  (none)              Interactive multi-select menu (default)
  apply [langs]       Enable only listed keys (comma-separated), or saved file
  status              Show saved selection and live cluster replica counts
  deploy [langs]      apply + build/deploy selected langs (CORALOGIX_PRIVATE_KEY)
  test [langs]        Run trace enrichment tests for selected languages
  list                Print enabled keys as comma-separated (for APPS=...)
  help                Show this message

Language keys:
  $(demo_keys_to_csv "${DEMO_LANG_KEYS[@]}")

Quick start:
  ${INVOCATION}                       # pick languages interactively
  ${INVOCATION} apply go,java,rust    # enable three demos on the cluster
  ${INVOCATION} status                # see what's enabled vs running
  ${INVOCATION} test                  # test saved selection for trace_id
  make select-demos                   # same as interactive (via Makefile)

Common workflows:
  # Demo only JVM stacks on a small cluster
  ${INVOCATION} apply go,java,kotlin,scala,dotnet

  # Build and deploy just what you changed
  ${INVOCATION} deploy rust,php

  # Re-apply last saved .demo-selection after a full deploy
  ${INVOCATION} apply

  # Test everything (ignore .demo-selection)
  TEST_ALL=1 ./scripts/test-traces.sh

Interactive menu keys:
  1-13   toggle a language    a=all    c=clear    d=done
  p1     original 5 (go,java,python,node,ruby)
  p2     original 5 + dotnet
  p3     JVM (go,java,kotlin,scala,dotnet)
  p4     scripting (go,python,node,ruby,php,perl,crystal)
  p5     systems (go,rust,cpp)
  ?      show this help inside the menu

Selection file: ${DEMO_SELECTION_FILE}
More docs:      ${ROOT}/README.md#selecting-which-demos-to-run
EOF
}

show_banner() {
  cat <<EOF

${INVOCATION} — enable only the language demos you need

  ./${INVOCATION} apply go,rust,php   enable specific languages (non-interactive)
  ./${INVOCATION} status              show saved selection + cluster state
  ./${INVOCATION} test                verify trace_id enrichment (uses .demo-selection)
  ./${INVOCATION} --help              full command reference

EOF
}

ensure_go_for_traffic() {
  if demo_is_enabled go; then
    return 0
  fi
  echo "Note: enabling go — required for the traffic sidecar on logdemo-go."
  DEMO_ENABLED_KEYS=("go" "${DEMO_ENABLED_KEYS[@]}")
}

parse_lang_csv() {
  local csv="$1"
  DEMO_ENABLED_KEYS=()
  local part
  IFS=',' read -ra parts <<< "${csv}"
  for part in "${parts[@]}"; do
    part="$(echo "${part}" | tr -d '[:space:]')"
    [[ -z "${part}" ]] && continue
    if demo_index_for_key "${part}" >/dev/null; then
      DEMO_ENABLED_KEYS+=("${part}")
    else
      echo "Unknown language: ${part}" >&2
      exit 1
    fi
  done
}

dedupe_enabled_keys() {
  local seen=() key
  local out=()
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    local found=0
    for s in "${seen[@]:-}"; do
      [[ "${s}" == "${key}" ]] && found=1 && break
    done
    if [[ "${found}" -eq 0 ]]; then
      seen+=("${key}")
      out+=("${key}")
    fi
  done
  DEMO_ENABLED_KEYS=("${out[@]}")
}

interactive_select() {
  local toggled=()
  local i key
  for key in "${DEMO_LANG_KEYS[@]}"; do
    toggled+=("0")
  done

  if [[ -f "${DEMO_SELECTION_FILE}" ]]; then
    demo_load_enabled_keys
    for i in "${!DEMO_LANG_KEYS[@]}"; do
      if demo_is_enabled "${DEMO_LANG_KEYS[$i]}"; then
        toggled[$i]=1
      fi
    done
  else
    for i in "${!DEMO_LANG_KEYS[@]}"; do
      toggled[$i]=1
    done
  fi

  while true; do
    echo
    echo "OBI logdemo — select languages to enable"
    echo "────────────────────────────────────────"
    for i in "${!DEMO_LANG_KEYS[@]}"; do
      local mark="[ ]"
      [[ "${toggled[$i]}" -eq 1 ]] && mark="[x]"
      printf " %2d) %s %-8s  %s  (:%s)\n" "$((i + 1))" "${mark}" "${DEMO_LANG_KEYS[$i]}" "${DEMO_LANG_LABELS[$i]}" "${DEMO_LANG_PORTS[$i]}"
    done
    echo
    echo "Toggle 1-13 · a=all · c=clear · d=done · ?=help"
    echo "Presets: p1=original 5 · p2=+dotnet · p3=JVM · p4=scripting · p5=systems"
    echo -n "> "
    read -r choice

    case "${choice}" in
      d|D|"") break ;;
      '?'|h|H|help)
        show_banner
        usage | sed -n '/Interactive menu keys:/,\$p'
        continue
        ;;
      a|A)
        for i in "${!toggled[@]}"; do toggled[$i]=1; done
        ;;
      c|C)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        ;;
      p1)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        for key in go java python node ruby; do
          toggled[$(demo_index_for_key "${key}")]=1
        done
        ;;
      p2)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        for key in go java python node ruby dotnet; do
          toggled[$(demo_index_for_key "${key}")]=1
        done
        ;;
      p3)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        for key in go java kotlin scala dotnet; do
          toggled[$(demo_index_for_key "${key}")]=1
        done
        ;;
      p4)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        for key in go python node ruby php perl crystal; do
          toggled[$(demo_index_for_key "${key}")]=1
        done
        ;;
      p5)
        for i in "${!toggled[@]}"; do toggled[$i]=0; done
        for key in go rust cpp; do
          toggled[$(demo_index_for_key "${key}")]=1
        done
        ;;
      *|[1-9]|1[0-3])
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DEMO_LANG_KEYS[@]} )); then
          local idx=$((choice - 1))
          toggled[$idx]=$((1 - toggled[idx]))
        else
          echo "Invalid choice: ${choice}"
        fi
        ;;
    esac
  done

  DEMO_ENABLED_KEYS=()
  for i in "${!DEMO_LANG_KEYS[@]}"; do
    [[ "${toggled[$i]}" -eq 1 ]] && DEMO_ENABLED_KEYS+=("${DEMO_LANG_KEYS[$i]}")
  done
  if [[ ${#DEMO_ENABLED_KEYS[@]} -eq 0 ]]; then
    echo "Select at least one language." >&2
    exit 1
  fi
}

cmd_apply() {
  if [[ $# -gt 0 ]]; then
    parse_lang_csv "$1"
  elif [[ -f "${DEMO_SELECTION_FILE}" ]]; then
    demo_load_enabled_keys
  else
    echo "No languages specified and no ${DEMO_SELECTION_FILE}. Run interactively or pass e.g. go,rust" >&2
    exit 1
  fi
  dedupe_enabled_keys
  ensure_go_for_traffic
  dedupe_enabled_keys
  demo_save_enabled_keys

  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace ${NAMESPACE} not found. Deploy the stack first: ./scripts/deploy-eks.sh" >&2
    exit 1
  fi

  echo "Applying selection: $(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"

  kubectl apply -f "${ROOT}/k8s/traffic-config.yaml" >/dev/null
  demo_traffic_targets > "${ROOT}/.demo-traffic-targets.tmp"
  kubectl -n "${NAMESPACE}" create configmap demo-traffic-targets \
    --from-file=targets="${ROOT}/.demo-traffic-targets.tmp" \
    --dry-run=client -o yaml | kubectl apply -f -
  rm -f "${ROOT}/.demo-traffic-targets.tmp"

  local key replicas deploy
  for key in "${DEMO_LANG_KEYS[@]}"; do
    deploy="$(demo_deploy_name "${key}")"
    if demo_is_enabled "${key}"; then
      replicas=1
    else
      replicas=0
    fi
    if kubectl -n "${NAMESPACE}" get deploy "${deploy}" >/dev/null 2>&1; then
      kubectl -n "${NAMESPACE}" scale "deployment/${deploy}" --replicas="${replicas}" >/dev/null
      echo "  ${deploy} -> replicas=${replicas}"
    fi
  done

  if kubectl -n "${NAMESPACE}" get deploy logdemo-go >/dev/null 2>&1; then
    kubectl -n "${NAMESPACE}" rollout restart deployment/logdemo-go >/dev/null
    kubectl -n "${NAMESPACE}" rollout status deployment/logdemo-go --timeout=180s >/dev/null || true
  fi

  echo
  echo "Saved to ${DEMO_SELECTION_FILE}"
  echo "Traffic sidecar will curl only enabled targets (see: make traffic)"
}

cmd_status() {
  if [[ -f "${DEMO_SELECTION_FILE}" ]]; then
    demo_load_enabled_keys
    echo "Saved selection: $(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"
  else
    echo "Saved selection: (none — all languages enabled by default)"
    DEMO_ENABLED_KEYS=("${DEMO_LANG_KEYS[@]}")
  fi
  echo
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Cluster: namespace ${NAMESPACE} not found"
    return 0
  fi
  echo "Cluster deployments:"
  local key deploy ready
  for key in "${DEMO_LANG_KEYS[@]}"; do
    deploy="$(demo_deploy_name "${key}")"
    if kubectl -n "${NAMESPACE}" get deploy "${deploy}" >/dev/null 2>&1; then
      ready="$(kubectl -n "${NAMESPACE}" get deploy "${deploy}" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')"
      printf "  %-18s replicas %s\n" "${deploy}" "${ready:-0/0}"
    else
      printf "  %-18s (not deployed)\n" "${deploy}"
    fi
  done
}

cmd_test() {
  if [[ $# -gt 0 ]]; then
    parse_lang_csv "$1"
    demo_save_enabled_keys
  else
    demo_load_enabled_keys
  fi
  dedupe_enabled_keys
  local key deploy idx
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    deploy="$(demo_deploy_name "${key}")"
    idx="$(demo_index_for_key "${key}")"
    APP="${deploy}" "${ROOT}/scripts/test-traces.sh" || true
  done
}

cmd_deploy() {
  local langs
  if [[ $# -gt 0 ]]; then
    langs="$1"
    cmd_apply "${langs}"
  else
    cmd_apply
    langs="$(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"
  fi
  CORALOGIX_PRIVATE_KEY="${CORALOGIX_PRIVATE_KEY:?Set CORALOGIX_PRIVATE_KEY}" \
    APPS="${langs}" "${ROOT}/scripts/deploy-eks.sh"
  cmd_apply "${langs}"
}

main() {
  local cmd="${1:-interactive}"
  shift || true

  case "${cmd}" in
    -h|--help|help) usage ;;
    apply) cmd_apply "${1:-}" ;;
    status) cmd_status ;;
    test) cmd_test "${1:-}" ;;
    deploy) cmd_deploy "${1:-}" ;;
    list)
      demo_load_enabled_keys
      demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}"
      ;;
    interactive|pick|select)
      interactive_select
      dedupe_enabled_keys
      ensure_go_for_traffic
      dedupe_enabled_keys
      demo_save_enabled_keys
      echo
      echo "Selected: $(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"
      echo -n "Apply to cluster now? [Y/n] "
      read -r confirm
      if [[ "${confirm}" != [nN]* ]]; then
        cmd_apply "$(demo_keys_to_csv "${DEMO_ENABLED_KEYS[@]}")"
      else
        echo "Saved selection only (run: ${INVOCATION} apply)"
      fi
      ;;
    *)
      if [[ "${cmd}" == *","* ]] || demo_index_for_key "${cmd}" >/dev/null 2>&1; then
        cmd_apply "${cmd}"
      else
        echo "Unknown command: ${cmd}" >&2
        echo "Run: ${INVOCATION} --help" >&2
        exit 1
      fi
      ;;
  esac
}

# Default: interactive menu (no subcommand).
if [[ $# -eq 0 ]]; then
  show_banner
fi

main "${1:-interactive}" "${@:2}"
