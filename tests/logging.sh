#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase4-logging-$$"
LABFAULT="$REPO_ROOT/scenario/fault/control/labfault"
trap on_exit EXIT

log_content() {
  local service="$1" file="$2" id

  if ! id="$(compose ps --all --quiet "$service")" || [ -z "$id" ]; then
    fail "could not find container for log snapshot: $service"
    return 1
  fi
  docker cp "$id:/logs/$file" - | tar -xO
}

record_for_id() {
  local content="$1" request_id="$2"
  printf '%s\n' "$content" | awk -v id="$request_id" 'index($0, "\"request_id\":\"" id "\"") { print }'
}

record_count() {
  record_for_id "$1" "$2" | awk 'END { print NR + 0 }'
}

expect_one_record() {
  local name="$1" content="$2" request_id="$3" count record attribute
  shift 3

  if ! count="$(record_count "$content" "$request_id")"; then
    fail "$name could not count request ID $request_id"
    return 1
  fi
  if [ "$count" -ne 1 ]; then
    fail "$name contains request ID $request_id $count times; want exactly 1"
    return 1
  fi
  if ! record="$(record_for_id "$content" "$request_id")"; then
    fail "$name could not read request ID $request_id"
    return 1
  fi
  for attribute in "$@"; do
    if ! printf '%s\n' "$record" | grep -F -- "$attribute" >/dev/null; then
      fail "$name does not contain $attribute for request ID $request_id"
      return 1
    fi
  done
}

select_loadgen_id_after() {
  local content="$1" baseline="$2" status="$3" outcome="$4"

  printf '%s\n' "$content" | awk -v baseline="$baseline" -v status="$status" -v outcome="$outcome" '
    NR > baseline &&
      index($0, "\"service\":\"loadgen\"") &&
      index($0, "\"event\":\"checkout_request\"") &&
      index($0, "\"status\":" status) &&
      index($0, "\"outcome\":\"" outcome "\"") {
        match($0, /"request_id":"[^"]+"/)
        print substr($0, RSTART + 14, RLENGTH - 15)
        exit
      }
  '
}

wait_for_loadgen_id() {
  local name="$1" baseline="$2" status="$3" outcome="$4" deadline content selected
  deadline=$((SECONDS + 60))

  while :; do
    if content="$(log_content load-generator loadgen.jsonl)" &&
      selected="$(select_loadgen_id_after "$content" "$baseline" "$status" "$outcome")" &&
      [ -n "$selected" ]; then
      WAITED_LOADGEN_ID="$selected"
      return 0
    fi
    if (( SECONDS >= deadline )); then
      fail "$name did not produce a real loadgen status=$status outcome=$outcome record within 60 seconds"
      return 1
    fi
    sleep 1
  done
}

capture_logs() {
  if ! gateway_log="$(log_content checkout-gateway gateway.jsonl)"; then
    fail 'could not read gateway.jsonl'
    return 1
  fi
  if ! checkout_1_log="$(log_content checkout-1 checkout-1.jsonl)"; then
    fail 'could not read checkout-1.jsonl'
    return 1
  fi
  if ! checkout_2_log="$(log_content checkout-2 checkout-2.jsonl)"; then
    fail 'could not read checkout-2.jsonl'
    return 1
  fi
  if ! checkout_3_log="$(log_content checkout-3 checkout-3.jsonl)"; then
    fail 'could not read checkout-3.jsonl'
    return 1
  fi
  if ! pricing_log="$(log_content pricing-api pricing.jsonl)"; then
    fail 'could not read pricing.jsonl'
    return 1
  fi
  if ! loadgen_log="$(log_content load-generator loadgen.jsonl)"; then
    fail 'could not read loadgen.jsonl'
    return 1
  fi
}

assert_chain() {
  local name="$1" request_id="$2" status="$3" outcome="$4" expected_checkout="$5"
  local checkout_1_count checkout_2_count checkout_3_count checkout_count checkout_name checkout_log

  expect_one_record "$name loadgen" "$loadgen_log" "$request_id" \
    '"service":"loadgen"' '"event":"checkout_request"' "\"status\":$status" "\"outcome\":\"$outcome\""
  expect_one_record "$name gateway" "$gateway_log" "$request_id" \
    '"service":"gateway"' '"event":"checkout_request"' "\"status\":$status" "\"outcome\":\"$outcome\""

  checkout_1_count="$(record_count "$checkout_1_log" "$request_id")"
  checkout_2_count="$(record_count "$checkout_2_log" "$request_id")"
  checkout_3_count="$(record_count "$checkout_3_log" "$request_id")"
  checkout_count=$((checkout_1_count + checkout_2_count + checkout_3_count))
  if [ "$checkout_count" -ne 1 ]; then
    fail "$name request ID $request_id appears in $checkout_count checkout records; want exactly 1"
    return 1
  fi

  case "$expected_checkout" in
    any-success)
      if [ "$checkout_1_count" -eq 1 ]; then
        checkout_name=checkout-1
        checkout_log="$checkout_1_log"
      elif [ "$checkout_2_count" -eq 1 ]; then
        checkout_name=checkout-2
        checkout_log="$checkout_2_log"
      else
        checkout_name=checkout-3
        checkout_log="$checkout_3_log"
      fi
      expect_one_record "$name $checkout_name" "$checkout_log" "$request_id" \
        '"service":"checkout"' '"event":"pricing_call"' '"outcome":"success"'
      ;;
    checkout-3-timeout)
      if [ "$checkout_3_count" -ne 1 ]; then
        fail "$name request ID $request_id did not reach checkout-3 exactly once"
        return 1
      fi
      checkout_name=checkout-3
      expect_one_record "$name checkout-3" "$checkout_3_log" "$request_id" \
        '"service":"checkout"' '"instance":"checkout-3"' '"event":"pricing_call"' \
        '"outcome":"timeout"' '"error":"context deadline exceeded"'
      ;;
    *)
      fail "unknown checkout expectation: $expected_checkout"
      return 1
      ;;
  esac

  expect_one_record "$name pricing" "$pricing_log" "$request_id" \
    '"service":"pricing"' '"event":"price_request"' '"status":200'
  printf '%s chain: loadgen ID=%s checkout=%s gateway=%s/%s\n' "$name" "$request_id" "$checkout_name" "$status" "$outcome"
}

owned_log_volume() {
  local volumes labels count

  if ! volumes="$(docker volume ls --quiet \
    --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
    --filter 'label=com.docker.compose.volume=lab_logs')"; then
    fail 'could not inspect the logging project volume'
    return 1
  fi
  count="$(printf '%s\n' "$volumes" | awk 'NF { count++ } END { print count + 0 }')"
  if [ "$count" -ne 1 ]; then
    fail "logging project owns $count lab_logs volumes; want exactly 1"
    return 1
  fi
  LOG_VOLUME="$(printf '%s\n' "$volumes" | awk 'NF { print; exit }')"
  if ! labels="$(docker volume inspect --format '{{index .Labels "com.docker.compose.project"}} {{index .Labels "com.docker.compose.volume"}}' "$LOG_VOLUME")"; then
    fail "could not inspect logging volume $LOG_VOLUME"
    return 1
  fi
  if [ "$labels" != "$COMPOSE_PROJECT_NAME lab_logs" ]; then
    fail "volume $LOG_VOLUME labels are $labels; want $COMPOSE_PROJECT_NAME lab_logs"
    return 1
  fi
}

read_go_version() {
  local versions count

  if ! versions="$(awk -F= '$1 == "GO_VERSION" { print $2 }' "$VERSIONS_FILE")"; then
    fail 'could not read GO_VERSION from versions.env'
    return 1
  fi
  count="$(printf '%s\n' "$versions" | awk 'NF { count++ } END { print count + 0 }')"
  if [ "$count" -ne 1 ]; then
    fail "versions.env contains $count GO_VERSION values; want exactly 1"
    return 1
  fi
  GO_VERSION="$(printf '%s\n' "$versions" | awk 'NF { print; exit }')"
}

if ! compose up --build --detach; then
  fail 'could not build and start the Phase 4.3 stack'
fi
wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz

wait_for_loadgen_id healthy 0 200 success
healthy_id="$WAITED_LOADGEN_ID"
pause_loadgen
capture_logs
assert_chain healthy "$healthy_id" 200 success any-success
retained_marker="$(record_for_id "$loadgen_log" "$healthy_id")"

baseline="$(printf '%s\n' "$loadgen_log" | awk 'END { print NR + 0 }')"
"$LABFAULT" on "$COMPOSE_PROJECT_NAME"
if ! compose start load-generator; then
  fail 'could not start load-generator after fault activation'
fi
LOADGEN_PAUSED=0
wait_for_loadgen_id degraded "$baseline" 504 error
degraded_id="$WAITED_LOADGEN_ID"
pause_loadgen
capture_logs
assert_chain degraded "$degraded_id" 504 error checkout-3-timeout

owned_log_volume
LOADGEN_PAUSED=0
if ! compose down --remove-orphans; then
  fail 'could not stop the logging project without removing volumes'
fi
owned_log_volume
read_go_version
if ! retained_from_volume="$(docker run --rm --network none \
  --label "phase4.logging.inspector=$COMPOSE_PROJECT_NAME" \
  --mount "type=volume,src=$LOG_VOLUME,dst=/logs,readonly" \
  "golang:${GO_VERSION}-alpine" sh -ec 'test -r /logs/loadgen.jsonl && grep -Fx -- "$1" /logs/loadgen.jsonl' sh "$retained_marker")"; then
  fail "read-only log inspector could not retain loadgen ID $healthy_id"
fi
if [ "$retained_from_volume" != "$retained_marker" ]; then
  fail "read-only log inspector did not return the complete retained marker for $healthy_id"
fi
if ! inspector_containers="$(docker ps --all --quiet --filter "label=phase4.logging.inspector=$COMPOSE_PROJECT_NAME")"; then
  fail 'could not inspect removed log inspector containers'
fi
if [ -n "$inspector_containers" ]; then
  fail "read-only log inspector containers remain: $inspector_containers"
fi

printf 'logging acceptance passed: actual loadgen IDs completed healthy and degraded chains; stop retained marker %s in %s.\n' "$healthy_id" "$LOG_VOLUME"
