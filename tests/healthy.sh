#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
trap on_exit EXIT

verify_gateway_backends
if ! compose up --build --detach; then
  fail 'could not build and start the Phase 1 stack'
fi

wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz

pause_loadgen
for ((request = 1; request <= 90; request++)); do
  if ! status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 2 \
    -H "X-Request-ID: healthy-$request" http://127.0.0.1:18084/checkout)"; then
    fail "request $request to checkout-gateway failed"
  fi
  if [ "$status" != 200 ]; then
    fail "request $request to checkout-gateway returned $status; want 200"
  fi
done

wait_for_health pricing-api http://127.0.0.1:18080/healthz
restore_loadgen
printf 'healthy acceptance passed: 90 gateway requests returned 200; pricing-api remained healthy.\n'
