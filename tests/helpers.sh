#!/usr/bin/env bash
set -euo pipefail

phase_not_implemented() {
  printf 'Phase 0 placeholder: %s is not implemented; %s owns its implementation.\n' "$1" "$2" >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  phase_not_implemented 'tests/helpers.sh' 'Phase 1'
fi
