#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/scenario/compose.yaml"
VERSIONS_FILE="$REPO_ROOT/versions.env"
COMPOSE_PROJECT_NAME="phase1-healthy-$$"
LOADGEN_PAUSED=0

compose() {
  docker compose --env-file "$VERSIONS_FILE" --project-name "$COMPOSE_PROJECT_NAME" --file "$COMPOSE_FILE" "$@"
}

phase_not_implemented() {
  printf 'Phase 0 placeholder: %s is not implemented; %s owns its implementation.\n' "$1" "$2" >&2
  return 1
}

fail() {
  printf 'healthy acceptance failed: %s\n' "$1" >&2
  return 1
}

wait_for_health() {
  local service="$1"
  local url="$2"
  local deadline=$((SECONDS + 60))

  while ! curl --silent --show-error --fail --max-time 2 "$url" >/dev/null; do
    if (( SECONDS >= deadline )); then
      fail "$service did not become healthy at $url within 60 seconds"
    fi
    sleep 1
  done
}

verify_gateway_backends() {
  local rendered expected url count
  expected='http://checkout-1:8080,http://checkout-2:8080,http://checkout-3:8080'
  if ! rendered="$(compose config)"; then
    fail 'Docker Compose configuration could not be rendered'
  fi
  case "$rendered" in
    *"CHECKOUT_BACKEND_URLS: $expected"*) ;;
    *) fail 'gateway backends are not configured in checkout-1, checkout-2, checkout-3 order' ;;
  esac
  for url in http://checkout-1:8080 http://checkout-2:8080 http://checkout-3:8080; do
    count="$(printf '%s\n' "$rendered" | awk -v value="$url" '{ line = $0; while ((at = index(line, value)) != 0) { count++; line = substr(line, at + length(value)) } } END { print count + 0 }')"
    if [ "$count" -ne 1 ]; then
      fail "rendered Compose configuration contains $url $count times; want 1"
    fi
  done
}

pause_loadgen() {
  if ! compose stop load-generator; then
    fail 'could not stop load-generator before the controlled request sequence'
  fi
  LOADGEN_PAUSED=1
}

restore_loadgen() {
  if [ "$LOADGEN_PAUSED" -eq 1 ]; then
    if ! compose start load-generator; then
      fail 'could not restore load-generator after the controlled request sequence'
    fi
    LOADGEN_PAUSED=0
  fi
}

cleanup() {
  if ! compose down --volumes --remove-orphans; then
    printf 'healthy acceptance cleanup failed: Docker Compose could not remove the test project.\n' >&2
    return 1
  fi
}

on_exit() {
  local status=$?
  local cleanup_status=0
  if [ "$LOADGEN_PAUSED" -eq 1 ] && ! restore_loadgen && [ "$status" -eq 0 ]; then
    status=1
  fi
  if cleanup; then
    :
  else
    cleanup_status=$?
    if [ "$status" -eq 0 ]; then
      status=$cleanup_status
    fi
  fi
  exit "$status"
}
