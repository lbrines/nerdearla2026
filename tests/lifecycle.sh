#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/scenario/compose.yaml"
VERSIONS_FILE="$REPO_ROOT/versions.env"
COMPOSE_PROJECT_NAME="nerdearla2026"

cleanup() {
  local body_status=$?
  local cleanup_status=0

  if make --directory "$REPO_ROOT" stop >/dev/null; then
    if docker compose --env-file "$VERSIONS_FILE" --project-name "$COMPOSE_PROJECT_NAME" --file "$COMPOSE_FILE" down --volumes --remove-orphans; then
      :
    else
      cleanup_status=$?
      printf 'lifecycle acceptance cleanup failed: could not remove the fixed lab project\n' >&2
    fi
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
  local cleanup_step="$3"
  local output status

  if output="$(
    (
      if [ "$cleanup_step" = make ]; then
        make() { return 23; }
      else
        make() { return 0; }
        docker() { return 23; }
      fi
      trap cleanup EXIT
      exit "$body_status"
    ) 2>&1
  )"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne "$expected_status" ]; then
    printf 'lifecycle acceptance failed: cleanup after %s exited %s; want %s\n' "$body_status" "$status" "$expected_status" >&2
    return 1
  fi
  if [ "$cleanup_step" = volume ] && [[ "$output" != *'lifecycle acceptance cleanup failed: could not remove the fixed lab project'* ]]; then
    printf 'lifecycle acceptance failed: volume cleanup failure was not reported: %s\n' "$output" >&2
    return 1
  fi
}

expect_direct_failure_status() {
  local status

  if (
    LABCTL_TEST_MODE=1
    source "$REPO_ROOT/scenario/control/labctl"
    curl() { printf '200'; }
    expect_status() { [ "$1" != checkout-1 ]; }
    verify_timeout_debug() { return 0; }
    verify_controlled_window healthy
  ); then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 1 ]; then
    printf 'lifecycle acceptance failed: a failed direct check exited %s; want 1\n' "$status" >&2
    return 1
  fi
}

run_mock_verify() {
  local running="$1"
  local verification_status="$2"
  local restoration_status="$3"
  local signal="$4"

  if MOCK_VERIFY_OUTPUT="$(
    (
      LABCTL_TEST_MODE=1
      source "$REPO_ROOT/scenario/control/labctl"
      VERIFY_TEST_RUNNING="$running"
      VERIFY_TEST_STATUS="$verification_status"
      VERIFY_TEST_RESTORATION_STATUS="$restoration_status"
      VERIFY_TEST_SIGNAL="$signal"
      LABFAULT=labfault
      labfault() { printf 'healthy\n'; }
      compose() {
        if [ "$1" = ps ]; then
          [ "$VERIFY_TEST_RUNNING" != running ] || printf 'load-generator\n'
        elif [ "$1" = stop ]; then
          printf 'mock: stop\n'
        else
          printf 'mock: start\n'
          return "$VERIFY_TEST_RESTORATION_STATUS"
        fi
      }
      verify_controlled_window() {
        if [ -n "$VERIFY_TEST_SIGNAL" ]; then
          sh -c 'kill "-$1" "$PPID"' sh "$VERIFY_TEST_SIGNAL"
          sleep 0.1
        fi
        return "$VERIFY_TEST_STATUS"
      }
      verify
    ) 2>&1
  )"; then
    MOCK_VERIFY_STATUS=0
  else
    MOCK_VERIFY_STATUS=$?
  fi
}

expect_mock_verify() {
  local name="$1"
  local running="$2"
  local verification_status="$3"
  local restoration_status="$4"
  local signal="$5"
  local expected_status="$6"

  run_mock_verify "$running" "$verification_status" "$restoration_status" "$signal"
  if [ "$MOCK_VERIFY_STATUS" -ne "$expected_status" ]; then
    printf 'lifecycle acceptance failed: %s exited %s; want %s\n' "$name" "$MOCK_VERIFY_STATUS" "$expected_status" >&2
    return 1
  fi
  case "$running" in
    stopped)
      if [ -n "$MOCK_VERIFY_OUTPUT" ]; then
        printf 'lifecycle acceptance failed: %s changed an initially stopped load-generator: %s\n' "$name" "$MOCK_VERIFY_OUTPUT" >&2
        return 1
      fi
      ;;
    running)
      case "$MOCK_VERIFY_OUTPUT" in
        *'mock: stop'*'mock: start'*) ;;
        *)
          printf 'lifecycle acceptance failed: %s did not restore the running load-generator: %s\n' "$name" "$MOCK_VERIFY_OUTPUT" >&2
          return 1
          ;;
      esac
      ;;
  esac
}

expect_direct_failure_status
expect_mock_verify initially-stopped stopped 0 0 '' 0
expect_mock_verify running-restored running 0 0 '' 0
expect_mock_verify term-restores running 0 0 TERM 143
expect_mock_verify int-restores running 0 0 INT 130
expect_mock_verify primary-failure-wins running 17 23 '' 17
expect_mock_verify restoration-failure-status running 0 23 '' 23

if [ "${LIFECYCLE_DETERMINISTIC_ONLY:-}" = 1 ]; then
  printf 'lifecycle deterministic verification regressions passed.\n'
  exit 0
fi

trap cleanup EXIT
expect_cleanup_status 0 23 make
expect_cleanup_status 17 17 make
expect_cleanup_status 0 23 volume

make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" start
make --directory "$REPO_ROOT" healthy-check
make --directory "$REPO_ROOT" start
make --directory "$REPO_ROOT" verify
make --directory "$REPO_ROOT" fault-on
make --directory "$REPO_ROOT" fault-on
make --directory "$REPO_ROOT" verify
make --directory "$REPO_ROOT" fault-off
make --directory "$REPO_ROOT" fault-off
make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" stop

expect_placeholder record-ready
expect_unknown

printf 'lifecycle acceptance passed: fixed-project healthy and degraded transitions are idempotent.\n'
