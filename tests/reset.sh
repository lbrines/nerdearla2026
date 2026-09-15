#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/scenario/compose.yaml"
VERSIONS_FILE="$REPO_ROOT/versions.env"
COMPOSE_PROJECT_NAME="nerdearla2026"

compose() {
  docker compose --env-file "$VERSIONS_FILE" --project-name "$COMPOSE_PROJECT_NAME" --file "$COMPOSE_FILE" "$@"
}

fail() {
  printf 'reset acceptance failed: %s\n' "$1" >&2
  return 1
}

assert_project_absent() {
  local services volumes

  if ! services="$(compose ps --all --services)"; then
    fail 'could not inspect remaining Compose services'
    return 1
  fi
  if [ -n "$services" ]; then
    fail "Compose services remain after cleanup: $services"
    return 1
  fi
  if ! volumes="$(docker volume ls --quiet --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")"; then
    fail 'could not inspect remaining Compose volumes'
    return 1
  fi
  if [ -n "$volumes" ]; then
    fail "Compose volumes remain after cleanup: $volumes"
    return 1
  fi
}

cleanup() {
  local body_status=$?
  local cleanup_status=0

  if make --directory "$REPO_ROOT" stop; then
    if assert_project_absent; then
      :
    else
      cleanup_status=$?
      printf 'reset acceptance cleanup did not remove the fixed lab project\n' >&2
    fi
  else
    cleanup_status=$?
    printf 'reset acceptance cleanup failed: make stop exited %s\n' "$cleanup_status" >&2
  fi
  if [ "$body_status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
    exit "$cleanup_status"
  fi
  return "$body_status"
}

trap cleanup EXIT

make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" reset

for cycle in 1 2 3 4 5; do
  printf 'reset acceptance: cycle %s/5 degraded -> reset -> healthy\n' "$cycle"
  make --directory "$REPO_ROOT" fault-on
  make --directory "$REPO_ROOT" reset
done

printf 'reset acceptance passed: reset starts healthy from stopped and after five degraded cycles.\n'
