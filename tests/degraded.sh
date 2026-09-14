#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase2-degraded-$$"
LABFAULT="$REPO_ROOT/scenario/fault/control/labfault"
trap on_exit EXIT

expect_status() {
  local name="$1"
  local expected="$2"
  local request_id="$3"
  local url="$4"
  local status

  if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 \
    -H "X-Request-ID: $request_id" "$url")"; then
    fail "$name request failed"
  fi
  if [ "$status" != "$expected" ]; then
    fail "$name returned $status; want $expected"
  fi
}

verify_timeout_debug() {
  local response elapsed_ms

  if ! response="$(curl --silent --show-error --fail --max-time 2 \
    -H 'X-Request-ID: degraded-checkout-3-debug' http://127.0.0.1:18083/debug/upstream)"; then
    fail 'checkout-3 debug upstream request failed'
  fi
  case "$response" in
    *'"outcome":"timeout"'*) ;;
    *) fail "checkout-3 debug outcome is not timeout: $response" ;;
  esac
  elapsed_ms="$(printf '%s\n' "$response" | awk -F'"elapsed_ms":' 'NF == 2 { print $2 }' | tr -d '}[:space:]')"
  if ! [[ "$elapsed_ms" =~ ^[0-9]+$ ]] || [ "$elapsed_ms" -lt 480 ]; then
    fail "checkout-3 debug elapsed_ms is ${elapsed_ms:-missing}; want at least 480"
  fi
}

verify_gateway_distribution() {
  local request status successes=0 timeouts=0

  for ((request = 1; request <= 90; request++)); do
    if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 \
      -H "X-Request-ID: degraded-gateway-$request" http://127.0.0.1:18084/checkout)"; then
      fail "gateway request $request failed"
    fi
    case "$status" in
      200) successes=$((successes + 1)) ;;
      504) timeouts=$((timeouts + 1)) ;;
      *) fail "gateway request $request returned $status; want 200 or 504" ;;
    esac
  done

  if [ "$successes" -ne 60 ] || [ "$timeouts" -ne 30 ]; then
    fail "gateway results were 200=$successes 504=$timeouts; want 200=60 504=30"
  fi
}

verify_pricing_toxic() {
  local output expected

  if ! output="$(compose exec --no-TTY toxiproxy /toxiproxy-cli inspect pricing)"; then
    fail 'could not inspect pricing-latency after fault activation'
  fi
  expected=$'pricing-latency\ttype=latency\tstream=downstream\ttoxicity=1.00\tattributes=[\tjitter=0\tlatency=800\t]'
  if [ "$output" != "$expected" ]; then
    fail "pricing-latency inspection did not match the required toxic: $output"
  fi
}

verify_pricing_toxic_absent() {
  local output

  if ! output="$(compose exec --no-TTY toxiproxy /toxiproxy-cli inspect pricing)"; then
    fail 'could not inspect pricing-latency after fault deactivation'
  fi
  if printf '%s\n' "$output" | awk '$1 == "pricing-latency" { found = 1 } END { exit !found }'; then
    fail 'pricing-latency remains after fault deactivation'
  fi
}

verify_gateway_backends
verify_rendered_pricing_routes
if ! compose up --build --detach; then
  fail 'could not build and start the Phase 2 stack'
fi

wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz
verify_runtime_topology

"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
verify_pricing_toxic

expect_status checkout-1 200 degraded-checkout-1 http://127.0.0.1:18081/checkout
expect_status checkout-2 200 degraded-checkout-2 http://127.0.0.1:18082/checkout
expect_status checkout-3 504 degraded-checkout-3 http://127.0.0.1:18083/checkout
verify_timeout_debug
wait_for_health pricing-api http://127.0.0.1:18080/healthz

pause_loadgen
verify_gateway_distribution

"$LABFAULT" off "$COMPOSE_PROJECT_NAME"
"$LABFAULT" off "$COMPOSE_PROJECT_NAME"
verify_pricing_toxic_absent
expect_status checkout-3 200 recovered-checkout-3 http://127.0.0.1:18083/checkout
for request in 1 2 3; do
  expect_status checkout-gateway 200 "recovered-gateway-$request" http://127.0.0.1:18084/checkout
done
wait_for_health pricing-api http://127.0.0.1:18080/healthz
restore_loadgen

printf 'degraded acceptance passed: idempotent fault activation produced 60 gateway 200s and 30 gateway 504s, then recovered.\n'
