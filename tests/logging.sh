#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase4-logging-$$"
LABFAULT="$REPO_ROOT/scenario/fault/control/labfault"
trap on_exit EXIT

expect_status() {
  local name="$1" expected="$2" request_id="$3" url="$4" status

  if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 \
    -H "X-Request-ID: $request_id" "$url")"; then
    fail "$name request failed"
    return 1
  fi
  if [ "$status" != "$expected" ]; then
    fail "$name returned $status; want $expected"
    return 1
  fi
}

log_content() {
  local service="$1" file="$2"
  docker cp "$(container_id "$service"):/logs/$file" - | tar -xO
}

record_for_id() {
  local content="$1" request_id="$2"
  printf '%s\n' "$content" | grep -F "\"request_id\":\"$request_id\""
}

expect_record() {
  local name="$1" content="$2" request_id="$3"

  if ! record_for_id "$content" "$request_id" >/dev/null; then
    fail "$name does not contain request ID $request_id"
    return 1
  fi
}

expect_record_attribute() {
  local name="$1" content="$2" request_id="$3" attribute="$4"

  if ! record_for_id "$content" "$request_id" | grep -F "$attribute" >/dev/null; then
    fail "$name does not contain $attribute for request ID $request_id"
    return 1
  fi
}

if ! compose up --build --detach; then
  fail 'could not build and start the Phase 4.2 stack'
fi
wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
pause_loadgen

expect_status checkout-1 200 logging-healthy http://127.0.0.1:18081/checkout
"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
expect_status checkout-3 504 logging-degraded http://127.0.0.1:18083/checkout

checkout_1_file="$(log_content checkout-1 checkout-1.jsonl)"
checkout_1_stdout="$(docker logs "$(container_id checkout-1)")"
checkout_3_file="$(log_content checkout-3 checkout-3.jsonl)"
checkout_3_stdout="$(docker logs "$(container_id checkout-3)")"
pricing_file="$(log_content pricing-api pricing.jsonl)"
pricing_stdout="$(docker logs "$(container_id pricing-api)")"

expect_record checkout-1-file "$checkout_1_file" logging-healthy
expect_record_attribute checkout-1-file "$checkout_1_file" logging-healthy '"outcome":"success"'
expect_record checkout-1-stdout "$checkout_1_stdout" logging-healthy
expect_record_attribute checkout-1-stdout "$checkout_1_stdout" logging-healthy '"outcome":"success"'
expect_record checkout-3-file "$checkout_3_file" logging-degraded
expect_record_attribute checkout-3-file "$checkout_3_file" logging-degraded '"outcome":"timeout"'
expect_record checkout-3-stdout "$checkout_3_stdout" logging-degraded
expect_record_attribute checkout-3-stdout "$checkout_3_stdout" logging-degraded '"outcome":"timeout"'
expect_record pricing-file-healthy "$pricing_file" logging-healthy
expect_record_attribute pricing-file-healthy "$pricing_file" logging-healthy '"status":200}'
expect_record pricing-file-degraded "$pricing_file" logging-degraded
expect_record_attribute pricing-file-degraded "$pricing_file" logging-degraded '"status":200}'
expect_record pricing-stdout-healthy "$pricing_stdout" logging-healthy
expect_record_attribute pricing-stdout-healthy "$pricing_stdout" logging-healthy '"status":200}'
expect_record pricing-stdout-degraded "$pricing_stdout" logging-degraded
expect_record_attribute pricing-stdout-degraded "$pricing_stdout" logging-degraded '"status":200}'

if ! record_for_id "$checkout_3_file" logging-degraded | grep -F '"error":"context deadline exceeded"' >/dev/null; then
  fail 'checkout-3 degraded log does not record the genuine deadline'
fi

printf 'logging acceptance passed: correlated healthy and degraded records reached checkout and pricing files and stdout.\n'
