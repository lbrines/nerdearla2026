#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase5-prometheus-$$"
LABFAULT="$REPO_ROOT/scenario/fault/control/labfault"
PROMETHEUS_URL="http://127.0.0.1:19090"
PROMETHEUS_TIMEOUT_SECONDS=45
trap on_exit EXIT

GATEWAY_ERROR_RATE='sum(rate(gateway_requests_total{outcome="error"}[30s]))'
CHECKOUT_ERROR_RATE='sum(rate(checkout_requests_total{outcome="error"}[30s])) / sum(rate(checkout_requests_total[30s]))'
CHECKOUT_ERROR_RATE_BY_INSTANCE='sum by (checkout_instance) (rate(checkout_requests_total{outcome="error"}[30s])) / sum by (checkout_instance) (rate(checkout_requests_total[30s]))'
PRICING_ERROR_RATE='sum(rate(pricing_requests_total{outcome="error"}[30s])) / sum(rate(pricing_requests_total[30s]))'
PRICING_P95='histogram_quantile(0.95, sum by (le) (rate(pricing_request_duration_seconds_bucket[30s])))'
CHECKOUT_PRICING_P95_BY_INSTANCE='histogram_quantile(0.95, sum by (le, checkout_instance) (rate(checkout_pricing_request_duration_seconds_bucket[30s])))'

prometheus_query() {
  local query="$1"

  curl --silent --show-error --fail --get --data-urlencode "query=$query" "$PROMETHEUS_URL/api/v1/query"
}

prometheus_scalar() {
  local query="$1" response pattern='"value":\[[^,]*,"([^"]+)"'

  response="$(prometheus_query "$query")" || return 1
  [[ "$response" == *'"status":"success"'* ]] || return 1
  if [[ "$response" =~ $pattern ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

prometheus_instance_value() {
  local query="$1" instance="$2" response pattern

  response="$(prometheus_query "$query")" || return 1
  [[ "$response" == *'"status":"success"'* ]] || return 1
  pattern="\"checkout_instance\":\"$instance\"[^}]*},\"value\":\\[[^,]*,\"([^\"]+)\""
  if [[ "$response" =~ $pattern ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

in_range() {
  local value="$1" minimum="$2" maximum="$3"

  awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" 'BEGIN { exit !(value >= minimum && value <= maximum) }'
}

wait_for_scalar() {
  local name="$1" query="$2" minimum="$3" maximum="$4" deadline value
  deadline=$((SECONDS + PROMETHEUS_TIMEOUT_SECONDS))

  while :; do
    if value="$(prometheus_scalar "$query")" && in_range "$value" "$minimum" "$maximum"; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      fail "$name did not reach [$minimum, $maximum] through Prometheus within ${PROMETHEUS_TIMEOUT_SECONDS} seconds (last value: ${value:-unavailable})"
      return 1
    fi
    sleep 5
  done
}

wait_for_instance_value() {
  local name="$1" query="$2" instance="$3" minimum="$4" maximum="$5" deadline value
  deadline=$((SECONDS + PROMETHEUS_TIMEOUT_SECONDS))

  while :; do
    if value="$(prometheus_instance_value "$query" "$instance")" && in_range "$value" "$minimum" "$maximum"; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      fail "$name did not reach [$minimum, $maximum] through Prometheus within ${PROMETHEUS_TIMEOUT_SECONDS} seconds (last value: ${value:-unavailable})"
      return 1
    fi
    sleep 5
  done
}

if ! compose up --build --detach; then
  fail 'could not build and start the Phase 5.1 stack'
fi
wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz
wait_for_health prometheus "$PROMETHEUS_URL/-/healthy"

wait_for_scalar 'checkout-gateway scrape target' 'sum(up{job="checkout-gateway"})' 1 1
wait_for_scalar 'pricing-api scrape target' 'sum(up{job="pricing-api"})' 1 1
wait_for_scalar 'checkout scrape targets' 'sum(up{job="checkout-api"})' 3 3

wait_for_scalar 'healthy gateway error rate' "$GATEWAY_ERROR_RATE" 0 0
wait_for_scalar 'healthy checkout error rate' "$CHECKOUT_ERROR_RATE" 0 0
wait_for_instance_value 'healthy checkout-1 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-1 0 0
wait_for_instance_value 'healthy checkout-2 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-2 0 0
wait_for_instance_value 'healthy checkout-3 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-3 0 0
wait_for_scalar 'healthy pricing error rate' "$PRICING_ERROR_RATE" 0 0
wait_for_scalar 'healthy pricing p95' "$PRICING_P95" 0 0.1

"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
wait_for_scalar 'degraded checkout error rate' "$CHECKOUT_ERROR_RATE" 0.30 0.36
wait_for_instance_value 'degraded checkout-1 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-1 0 0.02
wait_for_instance_value 'degraded checkout-2 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-2 0 0.02
wait_for_instance_value 'degraded checkout-3 error rate' "$CHECKOUT_ERROR_RATE_BY_INSTANCE" checkout-3 0.95 1
wait_for_scalar 'degraded pricing error rate' "$PRICING_ERROR_RATE" 0 0.01
wait_for_scalar 'degraded pricing p95' "$PRICING_P95" 0 0.1
wait_for_instance_value 'degraded checkout-3 observed pricing latency' "$CHECKOUT_PRICING_P95_BY_INSTANCE" checkout-3 0.48 2

printf 'prometheus acceptance passed: Prometheus observed healthy and degraded rate, target, and latency contracts.\n'
