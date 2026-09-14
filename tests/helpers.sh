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

verify_rendered_pricing_routes() {
  local rendered direct_count proxied_count
  if ! rendered="$(compose config)"; then
    fail 'Docker Compose configuration could not be rendered'
  fi
  direct_count="$(printf '%s\n' "$rendered" | awk -v value='PRICING_UPSTREAM_URL: http://pricing-api:8080' '$0 == "      " value { count++ } END { print count + 0 }')"
  proxied_count="$(printf '%s\n' "$rendered" | awk -v value='PRICING_UPSTREAM_URL: http://toxiproxy:8666' '$0 == "      " value { count++ } END { print count + 0 }')"
  if [ "$direct_count" -ne 2 ] || [ "$proxied_count" -ne 1 ]; then
    fail "rendered pricing routes are direct=$direct_count proxied=$proxied_count; want direct=2 proxied=1"
  fi
}

container_id() {
  local service="$1"
  local id
  if ! id="$(compose ps --quiet "$service")" || [ -z "$id" ]; then
    fail "could not find running container for $service"
  fi
  printf '%s\n' "$id"
}

verify_service_networks() {
  local service="$1"
  local expected="$2"
  local actual
  actual="$(docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{printf "%s\n" $name}}{{end}}' "$(container_id "$service")" | awk 'NF' | LC_ALL=C sort)"
  if [ "$actual" != "$expected" ]; then
    fail "networks for $service are ${actual:-none}; want $expected"
  fi
}

verify_runtime_topology() {
  local deadline proxy_list bindings
  deadline=$((SECONDS + 60))
  while :; do
    if proxy_list="$(compose exec --no-TTY toxiproxy /toxiproxy-cli list 2>/dev/null)" &&
      printf '%s\n' "$proxy_list" | awk '
        BEGIN { valid = 1 }
        NF {
          rows++
          if (NF != 5 || $1 != "pricing" || ($2 != "0.0.0.0:8666" && $2 != "[::]:8666") || $3 != "pricing-api:8080" || $4 != "enabled" || $5 != 0) valid = 0
        }
        END { exit !(rows == 1 && valid) }
      '; then
      break
    fi
    if (( SECONDS >= deadline )); then
      fail 'toxiproxy must expose exactly one enabled pricing proxy at 0.0.0.0:8666 with upstream pricing-api:8080 and zero toxics within 60 seconds'
    fi
    sleep 1
  done

  verify_service_networks pricing-api "${COMPOSE_PROJECT_NAME}_fault_net
${COMPOSE_PROJECT_NAME}_operator_net"
  verify_service_networks checkout-1 "${COMPOSE_PROJECT_NAME}_operator_net"
  verify_service_networks checkout-2 "${COMPOSE_PROJECT_NAME}_operator_net"
  verify_service_networks checkout-3 "${COMPOSE_PROJECT_NAME}_fault_net
${COMPOSE_PROJECT_NAME}_operator_net"
  verify_service_networks toxiproxy "${COMPOSE_PROJECT_NAME}_fault_net"

  bindings="$(docker inspect --format '{{range $port, $bindings := .NetworkSettings.Ports}}{{if $bindings}}{{printf "%s\n" $port}}{{end}}{{end}}' "$(container_id toxiproxy)")"
  if [ -n "$bindings" ]; then
    fail "toxiproxy has host port bindings: $bindings"
  fi
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
