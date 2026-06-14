#!/usr/bin/env bash
# Pick which OBI logdemo languages are active on the cluster.
#
#   ./select-demos.sh              interactive menu
#   ./select-demos.sh --help       full usage
#   ./select-demos.sh apply go,rust
#
export SELECT_DEMOS_NAME="select-demos.sh"
exec "$(dirname "$0")/scripts/select-demos.sh" "$@"
