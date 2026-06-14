#!/usr/bin/env bash
# Canonical list of OBI logdemo languages. Source from other scripts:
#   source "$(dirname "$0")/languages.sh"

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEMO_SELECTION_FILE="${DEMO_SELECTION_FILE:-${ROOT}/.demo-selection}"
NAMESPACE="${NAMESPACE:-ebpflogs}"

# Keys must match deploy-eks.sh APPS names and logdemo-<key> deployment names.
DEMO_LANG_KEYS=(go java python node ruby dotnet rust php perl cpp kotlin scala crystal)
DEMO_LANG_LABELS=(Go Java Python "Node.js" Ruby ".NET" Rust PHP Perl "C++" Kotlin Scala Crystal)
DEMO_LANG_PORTS=(8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 8090 8091 8092)

demo_key_at() {
  echo "${DEMO_LANG_KEYS[$1]}"
}

demo_label_at() {
  echo "${DEMO_LANG_LABELS[$1]}"
}

demo_port_at() {
  echo "${DEMO_LANG_PORTS[$1]}"
}

demo_index_for_key() {
  local key="$1"
  local i
  for i in "${!DEMO_LANG_KEYS[@]}"; do
    if [[ "${DEMO_LANG_KEYS[$i]}" == "${key}" ]]; then
      echo "${i}"
      return 0
    fi
  done
  return 1
}

demo_deploy_name() {
  echo "logdemo-$1"
}

demo_target_line() {
  local key="$1"
  local idx
  idx="$(demo_index_for_key "${key}")"
  echo "logdemo-${key}:${DEMO_LANG_PORTS[$idx]}"
}

# Read enabled keys from .demo-selection (one key per line). Empty file = all enabled.
demo_load_enabled_keys() {
  DEMO_ENABLED_KEYS=()
  if [[ ! -f "${DEMO_SELECTION_FILE}" ]]; then
    DEMO_ENABLED_KEYS=("${DEMO_LANG_KEYS[@]}")
    return 0
  fi
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="$(echo "${line}" | tr -d '[:space:]')"
    [[ -z "${line}" ]] && continue
    if demo_index_for_key "${line}" >/dev/null; then
      DEMO_ENABLED_KEYS+=("${line}")
    else
      echo "WARN: unknown language key in ${DEMO_SELECTION_FILE}: ${line}" >&2
    fi
  done < "${DEMO_SELECTION_FILE}"
  if [[ ${#DEMO_ENABLED_KEYS[@]} -eq 0 ]]; then
    echo "WARN: ${DEMO_SELECTION_FILE} is empty; enabling all languages" >&2
    DEMO_ENABLED_KEYS=("${DEMO_LANG_KEYS[@]}")
  fi
}

demo_save_enabled_keys() {
  local key
  : > "${DEMO_SELECTION_FILE}"
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    echo "${key}" >> "${DEMO_SELECTION_FILE}"
  done
}

demo_keys_to_csv() {
  local IFS=,
  echo "$*"
}

demo_is_enabled() {
  local want="$1"
  local key
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    [[ "${key}" == "${want}" ]] && return 0
  done
  return 1
}

demo_print_catalog() {
  local i
  for i in "${!DEMO_LANG_KEYS[@]}"; do
    printf "  %2d) %-8s  %s  (port %s)\n" "$((i + 1))" "${DEMO_LANG_KEYS[$i]}" "${DEMO_LANG_LABELS[$i]}" "${DEMO_LANG_PORTS[$i]}"
  done
}

demo_traffic_targets() {
  local key
  local lines=()
  for key in "${DEMO_ENABLED_KEYS[@]}"; do
    lines+=("$(demo_target_line "${key}")")
  done
  printf '%s\n' "${lines[@]}"
}
