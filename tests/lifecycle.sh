#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cleanup() {
  local body_status=$?
  local cleanup_status=0

  if make --directory "$REPO_ROOT" stop >/dev/null; then
    :
  else
    cleanup_status=$?
    printf 'lifecycle acceptance cleanup failed: make stop exited %s\n' "$cleanup_status" >&2
  fi
  if [ "$body_status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
    exit "$cleanup_status"
  fi
  return "$body_status"
}

expect_placeholder() {
  local operation="$1"
  local output

  if output="$(make --directory "$REPO_ROOT" "$operation" 2>&1)"; then
    printf 'lifecycle acceptance failed: %s unexpectedly succeeded\n' "$operation" >&2
    return 1
  fi
  case "$output" in
    *"Phase 3 placeholder: operation \"$operation\" is owned by a later Phase 3 review."*) ;;
    *)
      printf 'lifecycle acceptance failed: %s did not report its Phase 3 ownership: %s\n' "$operation" "$output" >&2
      return 1
      ;;
  esac
}

expect_unknown() {
  local output status

  if output="$("$REPO_ROOT/scenario/control/labctl" unknown 2>&1)"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 2 ]; then
    printf 'lifecycle acceptance failed: unknown operation exited %s; want 2\n' "$status" >&2
    return 1
  fi
  case "$output" in
    *'unknown operation: unknown'*'usage:'*) ;;
    *)
      printf 'lifecycle acceptance failed: unknown operation did not report usage: %s\n' "$output" >&2
      return 1
      ;;
  esac
}

expect_cleanup_status() {
  local body_status="$1"
  local expected_status="$2"
  local status

  if (make() { return 23; }; trap cleanup EXIT; exit "$body_status"); then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne "$expected_status" ]; then
    printf 'lifecycle acceptance failed: cleanup after %s exited %s; want %s\n' "$body_status" "$status" "$expected_status" >&2
    return 1
  fi
}

trap cleanup EXIT
expect_cleanup_status 0 23
expect_cleanup_status 17 17

make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" start
make --directory "$REPO_ROOT" healthy-check
make --directory "$REPO_ROOT" start
make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" stop

for operation in fault-on verify fault-off reset record-ready; do
  expect_placeholder "$operation"
done
expect_unknown

printf 'lifecycle acceptance passed: fixed project start, healthy check, and stop are idempotent.\n'
