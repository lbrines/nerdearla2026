#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase4-observability-$$"
LABFAULT="$REPO_ROOT/scenario/fault/control/labfault"
trap on_exit EXIT

metric_value() {
  local url="$1" name="$2" outcome="$3" instance="${4:-}" metrics value
  if ! metrics="$(curl --silent --show-error --fail --max-time 2 "$url")"; then
    fail "could not read metrics from $url"
    return 1
  fi
  if ! value="$(printf '%s\n' "$metrics" | awk -v name="$name" -v outcome="$outcome" -v instance="$instance" '
    $1 ~ ("^" name "\\{") && $1 ~ ("outcome=\\\"" outcome "\\\"") && (instance == "" || $1 ~ ("checkout_instance=\\\"" instance "\\\"")) { print $2; found = 1; exit }
    END { exit !found }
  ')"; then
    fail "missing $name outcome=$outcome at $url"
    return 1
  fi
  printf '%s\n' "$value"
}

histogram_value() {
  local url="$1" name="$2" le="$3" metrics value
  if ! metrics="$(curl --silent --show-error --fail --max-time 2 "$url")"; then
    fail "could not read metrics from $url"
    return 1
  fi
  if ! value="$(printf '%s\n' "$metrics" | awk -v name="$name" -v le="$le" '
    $1 ~ ("^" name "_bucket\\{") && $1 ~ ("le=\\\"" le "\\\"") { print $2; found = 1; exit }
    END { exit !found }
  ')"; then
    fail "missing $name bucket le=$le at $url"
    return 1
  fi
  printf '%s\n' "$value"
}

histogram_count_value() {
  local url="$1" name="$2" instance="${3:-}" metrics value
  if ! metrics="$(curl --silent --show-error --fail --max-time 2 "$url")"; then
    fail "could not read metrics from $url"
    return 1
  fi
  if ! value="$(printf '%s\n' "$metrics" | awk -v name="$name" -v instance="$instance" '
    $1 ~ ("^" name "_count") && (instance == "" || $1 ~ ("checkout_instance=\\\"" instance "\\\"")) { print $2; found = 1; exit }
    END { exit !found }
  ')"; then
    fail "missing $name count at $url"
    return 1
  fi
  printf '%s\n' "$value"
}

assert_delta() {
  local name="$1" before="$2" want="$3" after="$4"
  if [ $((after - before)) -ne "$want" ]; then
    fail "$name delta was $((after - before)); want $want"
    return 1
  fi
}

gateway_window() {
  local name="$1" expected_success="$2" expected_error="$3" request status successes=0 errors=0
  for request in 1 2 3; do
    if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 \
      -H "X-Request-ID: $name-$request" http://127.0.0.1:18084/checkout)"; then
      fail "$name gateway request $request failed"
      return 1
    fi
    case "$status" in
      2*) successes=$((successes + 1)) ;;
      *) errors=$((errors + 1)) ;;
    esac
  done
  if [ "$successes" -ne "$expected_success" ] || [ "$errors" -ne "$expected_error" ]; then
    fail "$name gateway results were success=$successes error=$errors; want $expected_success/$expected_error"
    return 1
  fi
}

checkout_window() {
  local name="$1" expected_gateway_success="$2" expected_gateway_error="$3"
  local -a expected_success=("$4" "$6" "$8") expected_error=("$5" "$7" "$9")
  local -a ports=(18081 18082 18083) instances=(checkout-1 checkout-2 checkout-3)
  local -a checkout_success_before checkout_error_before pricing_success_before pricing_timeout_before checkout_count_before pricing_count_before
  local index port instance value observed=""
  local checkout_success_delta checkout_error_delta pricing_success_delta pricing_timeout_delta checkout_count_delta pricing_count_delta
  local pricing_success_before_window pricing_error_before_window pricing_count_before_window
  local pricing_success_after_window pricing_error_after_window pricing_count_after_window

  if ! pricing_success_before_window="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total success)"; then return 1; fi
  if ! pricing_error_before_window="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total error)"; then return 1; fi
  if ! pricing_count_before_window="$(histogram_count_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds)"; then return 1; fi

  for index in 0 1 2; do
    port="${ports[$index]}"
    instance="${instances[$index]}"
    if ! checkout_success_before[$index]="$(metric_value "http://127.0.0.1:$port/metrics" checkout_requests_total success "$instance")"; then return 1; fi
    if ! checkout_error_before[$index]="$(metric_value "http://127.0.0.1:$port/metrics" checkout_requests_total error "$instance")"; then return 1; fi
    if ! pricing_success_before[$index]="$(metric_value "http://127.0.0.1:$port/metrics" checkout_pricing_requests_total success "$instance")"; then return 1; fi
    if ! pricing_timeout_before[$index]="$(metric_value "http://127.0.0.1:$port/metrics" checkout_pricing_requests_total timeout "$instance")"; then return 1; fi
    if ! checkout_count_before[$index]="$(histogram_count_value "http://127.0.0.1:$port/metrics" checkout_request_duration_seconds "$instance")"; then return 1; fi
    if ! pricing_count_before[$index]="$(histogram_count_value "http://127.0.0.1:$port/metrics" checkout_pricing_request_duration_seconds "$instance")"; then return 1; fi
  done

  gateway_window "$name" "$expected_gateway_success" "$expected_gateway_error"

  for index in 0 1 2; do
    port="${ports[$index]}"
    instance="${instances[$index]}"
    if ! value="$(metric_value "http://127.0.0.1:$port/metrics" checkout_requests_total success "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance checkout success" "${checkout_success_before[$index]}" "${expected_success[$index]}" "$value"; then return 1; fi
    checkout_success_delta=$((value - checkout_success_before[$index]))
    if ! value="$(metric_value "http://127.0.0.1:$port/metrics" checkout_requests_total error "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance checkout error" "${checkout_error_before[$index]}" "${expected_error[$index]}" "$value"; then return 1; fi
    checkout_error_delta=$((value - checkout_error_before[$index]))
    if ! value="$(metric_value "http://127.0.0.1:$port/metrics" checkout_pricing_requests_total success "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance pricing success" "${pricing_success_before[$index]}" "${expected_success[$index]}" "$value"; then return 1; fi
    pricing_success_delta=$((value - pricing_success_before[$index]))
    if ! value="$(metric_value "http://127.0.0.1:$port/metrics" checkout_pricing_requests_total timeout "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance pricing timeout" "${pricing_timeout_before[$index]}" "${expected_error[$index]}" "$value"; then return 1; fi
    pricing_timeout_delta=$((value - pricing_timeout_before[$index]))
    if ! value="$(histogram_count_value "http://127.0.0.1:$port/metrics" checkout_request_duration_seconds "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance checkout duration count" "${checkout_count_before[$index]}" 1 "$value"; then return 1; fi
    checkout_count_delta=$((value - checkout_count_before[$index]))
    if ! value="$(histogram_count_value "http://127.0.0.1:$port/metrics" checkout_pricing_request_duration_seconds "$instance")"; then return 1; fi
    if ! assert_delta "$name $instance pricing duration count" "${pricing_count_before[$index]}" 1 "$value"; then return 1; fi
    pricing_count_delta=$((value - pricing_count_before[$index]))
    observed="${observed}${instance}: checkout=${checkout_success_delta}/${checkout_error_delta}, pricing=${pricing_success_delta}/${pricing_timeout_delta}, counts=${checkout_count_delta}/${pricing_count_delta}; "
  done

  if ! pricing_success_after_window="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total success)"; then return 1; fi
  if ! assert_delta "$name pricing success" "$pricing_success_before_window" 3 "$pricing_success_after_window"; then return 1; fi
  if ! pricing_error_after_window="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total error)"; then return 1; fi
  if ! assert_delta "$name pricing error" "$pricing_error_before_window" 0 "$pricing_error_after_window"; then return 1; fi
  if ! pricing_count_after_window="$(histogram_count_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds)"; then return 1; fi
  if ! assert_delta "$name pricing duration count" "$pricing_count_before_window" 3 "$pricing_count_after_window"; then return 1; fi
  printf '%s observed deltas: %spricing=3/0, count=3\n' "$name" "$observed"
}

assert_metric_reader_rejects_invalid_input() {
  if metric_value file:///definitely-missing-observability-metric pricing_requests_total success >/dev/null 2>&1; then
    fail 'metric reader accepted a failed scrape'
    return 1
  fi
  if metric_value file:///dev/null pricing_requests_total success >/dev/null 2>&1; then
    fail 'metric reader accepted an absent sample'
    return 1
  fi
}

assert_metric_reader_rejects_invalid_input

if ! compose up --build --detach; then
  fail 'could not build and start the Phase 4.1 stack'
fi
wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz
pause_loadgen
sleep 1

if ! pricing_success="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total success)"; then exit 1; fi
if ! pricing_error="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total error)"; then exit 1; fi
if [ "$pricing_error" != 0 ]; then
  fail "pricing error counter was $pricing_error; want 0"
fi
if ! pricing_count="$(histogram_count_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds)"; then exit 1; fi
if ! pricing_bucket="$(histogram_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds 0.5)"; then exit 1; fi
if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 http://127.0.0.1:18080/price)" || [ "$status" != 200 ]; then
  fail "direct pricing request returned ${status:-request failure}; want 200"
fi
if ! pricing_success_after="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total success)"; then exit 1; fi
if ! assert_delta 'pricing success' "$pricing_success" 1 "$pricing_success_after"; then exit 1; fi
if ! pricing_count_after="$(histogram_count_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds)"; then exit 1; fi
if ! assert_delta 'pricing duration count' "$pricing_count" 1 "$pricing_count_after"; then exit 1; fi
if ! pricing_bucket_after="$(histogram_value http://127.0.0.1:18080/metrics pricing_request_duration_seconds 0.5)"; then exit 1; fi
if ! assert_delta 'pricing duration bucket le=0.5' "$pricing_bucket" 1 "$pricing_bucket_after"; then exit 1; fi
if ! pricing_error_after="$(metric_value http://127.0.0.1:18080/metrics pricing_requests_total error)"; then exit 1; fi
if [ "$pricing_error_after" != "$pricing_error" ]; then
  fail 'pricing error counter changed during direct pricing processing'
fi

# Expected checkout-1/checkout-2/checkout-3 success/error deltas.
checkout_window healthy 3 0 \
  1 0 \
  1 0 \
  1 0

"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
checkout_window degraded 2 1 \
  1 0 \
  1 0 \
  0 1
"$LABFAULT" off "$COMPOSE_PROJECT_NAME"
restore_loadgen
printf 'observability acceptance passed: direct pricing, checkout, and gateway metrics tracked controlled healthy and degraded windows.\n'
