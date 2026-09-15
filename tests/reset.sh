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
    if compose down --volumes --remove-orphans && assert_project_absent; then
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

log_content() {
  local file="$1" id

  if ! id="$(compose ps --all --quiet load-generator)" || [ -z "$id" ]; then
    fail 'could not find load-generator container for log snapshot'
    return 1
  fi
  docker cp "$id:/logs/$file" - | tar -xO
}

select_loadgen_marker() {
  local content="$1"

  printf '%s\n' "$content" | awk '
    index($0, "\"service\":\"loadgen\"") &&
      index($0, "\"event\":\"checkout_request\"") &&
      index($0, "\"status\":200") &&
      index($0, "\"outcome\":\"success\"") { marker = $0 }
    END { print marker }
  '
}

boot_prefix() {
  local marker="$1"

  printf '%s\n' "$marker" | awk '
    match($0, /"request_id":"loadgen-[0-9a-f]+-[0-9]+"/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^"request_id":"loadgen-/, "", value)
      sub(/-[0-9]+"$/, "", value)
      print value
      exit
    }
  '
}

wait_for_loadgen_marker() {
  local name="$1" deadline content marker
  deadline=$((SECONDS + 60))

  while :; do
    if content="$(log_content loadgen.jsonl)" &&
      marker="$(select_loadgen_marker "$content")" &&
      [ -n "$marker" ]; then
      WAITED_MARKER="$marker"
      return 0
    fi
    if (( SECONDS >= deadline )); then
      fail "$name did not produce a real successful loadgen record within 60 seconds"
      return 1
    fi
    sleep 1
  done
}

assert_recreated_log_files() {
  local file

  for file in gateway.jsonl checkout-1.jsonl checkout-2.jsonl checkout-3.jsonl pricing.jsonl loadgen.jsonl; do
    if ! log_content "$file" >/dev/null; then
      fail "recreated log file is missing or unreadable: $file"
      return 1
    fi
  done
}

trap cleanup EXIT

make --directory "$REPO_ROOT" stop
make --directory "$REPO_ROOT" reset
wait_for_loadgen_marker pre-reset
old_marker="$WAITED_MARKER"
old_prefix="$(boot_prefix "$old_marker")"
if [ -z "$old_prefix" ]; then
  fail 'pre-reset loadgen marker has no boot prefix'
fi
if ! compose stop load-generator; then
  fail 'could not pause load-generator before the pre-reset snapshot'
fi
printf 'reset acceptance: pre-reset loadgen marker prefix=%s\n' "$old_prefix"

for cycle in 1 2 3 4 5; do
  printf 'reset acceptance: cycle %s/5 degraded -> reset -> healthy\n' "$cycle"
  make --directory "$REPO_ROOT" fault-on
  make --directory "$REPO_ROOT" reset

  if [ "$cycle" -eq 1 ]; then
    wait_for_loadgen_marker post-reset
    new_marker="$WAITED_MARKER"
    new_prefix="$(boot_prefix "$new_marker")"
    if [ -z "$new_prefix" ]; then
      fail 'post-reset loadgen marker has no boot prefix'
    fi
    if ! compose stop load-generator; then
      fail 'could not pause load-generator before the post-reset snapshot'
    fi
    assert_recreated_log_files
    if ! new_loadgen_log="$(log_content loadgen.jsonl)"; then
      fail 'could not read recreated loadgen.jsonl'
    fi
    if printf '%s\n' "$new_loadgen_log" | grep -Fx -- "$old_marker" >/dev/null; then
      fail 'reset retained the complete pre-reset loadgen marker'
    fi
    if [ "$new_prefix" = "$old_prefix" ]; then
      fail "reset reused loadgen boot prefix $old_prefix"
    fi
    printf 'reset acceptance: old marker absent; new loadgen prefix=%s differs from %s\n' "$new_prefix" "$old_prefix"
  fi
done

printf 'reset acceptance passed: reset starts healthy from stopped, removes the old log marker, recreates six logs, and passes five degraded cycles.\n'
