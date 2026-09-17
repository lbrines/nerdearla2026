#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase7b-isolation-$$"
TEST_DATA_DIR=""

cleanup_isolation() {
  local body_status=$? cleanup_status=0

  if [ -n "$TEST_DATA_DIR" ] && [ -d "$TEST_DATA_DIR" ]; then
    if rm -rf -- "$TEST_DATA_DIR"; then
      :
    else
      cleanup_status=$?
      printf 'isolation acceptance cleanup failed: could not remove test data directory\n' >&2
    fi
  fi
  if cleanup; then
    :
  else
    cleanup_status=$?
  fi
  if [ "$body_status" -ne 0 ]; then
    return "$body_status"
  fi
  return "$cleanup_status"
}

read_opencode_version() {
  local values count

  values="$(awk -F= '$1 == "OPENCODE_CLI_VERSION" { print $2 }' "$VERSIONS_FILE")"
  count="$(printf '%s\n' "$values" | awk 'NF { count++ } END { print count + 0 }')"
  if [ "$count" -ne 1 ]; then
    fail "versions.env contains $count OPENCODE_CLI_VERSION values; want 1"
  fi
  OPENCODE_CLI_VERSION="$(printf '%s\n' "$values" | awk 'NF { print; exit }')"
}

run_baseline() {
  compose --profile investigator-baseline run --rm --no-deps --no-TTY \
    --env "EXPECTED_OPENCODE_VERSION=$OPENCODE_CLI_VERSION" investigator-baseline bash -s
}

read_opencode_version
TEST_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nerdearla2026-isolation.XXXXXX")"
export OPENCODE_DATA_DIR="$TEST_DATA_DIR/opencode"
export INVESTIGATION_OUTPUT_DIR="$TEST_DATA_DIR/investigation-output"
mkdir -p "$OPENCODE_DATA_DIR" "$INVESTIGATION_OUTPUT_DIR"
printf '%s\n' '{"type":"inert"}' > "$OPENCODE_DATA_DIR/auth.json"
chmod 600 "$OPENCODE_DATA_DIR/auth.json"
trap cleanup_isolation EXIT

if ! compose up --build --detach; then
  fail 'could not build and start the Baseline isolation lab'
fi
wait_for_health pricing-api http://127.0.0.1:18080/healthz
wait_for_health checkout-1 http://127.0.0.1:18081/healthz
wait_for_health checkout-2 http://127.0.0.1:18082/healthz
wait_for_health checkout-3 http://127.0.0.1:18083/healthz
wait_for_health checkout-gateway http://127.0.0.1:18084/healthz
wait_for_health prometheus http://127.0.0.1:19090/-/ready
wait_for_health grafana http://127.0.0.1:3000/api/health
verify_runtime_topology

if ! compose --profile investigator-baseline run --rm --no-deps --no-TTY investigator-baseline bash -ec 'test "$(id -u)" -ne 0'; then
  fail 'Baseline investigator image does not run as a non-root user'
fi

if ! run_baseline <<'INVESTIGATOR'
set -euo pipefail

for tool in bash curl jq getent dig grep rg opencode; do
  command -v "$tool" >/dev/null
 done
[ "$(opencode --version)" = "$EXPECTED_OPENCODE_VERSION" ]
[ "$PWD" = /investigator-workspace ]

curl --fail --silent --show-error http://pricing-api:8080/healthz >/dev/null
curl --fail --silent --show-error http://checkout-1:8080/healthz >/dev/null
curl --fail --silent --show-error http://checkout-2:8080/healthz >/dev/null
curl --fail --silent --show-error http://checkout-3:8080/healthz >/dev/null
curl --fail --silent --show-error http://checkout-gateway:8080/healthz >/dev/null
curl --fail --silent --show-error http://prometheus:9090/-/ready >/dev/null
curl --fail --silent --show-error http://grafana:3000/api/health >/dev/null

expected_logs='gateway.jsonl checkout-1.jsonl checkout-2.jsonl checkout-3.jsonl pricing.jsonl loadgen.jsonl'
deadline=$((SECONDS + 60))
while :; do
  ready=1
  for file in $expected_logs; do
    if ! test -r "/var/log/lab/$file" || ! test -s "/var/log/lab/$file"; then
      ready=0
    fi
  done
  [ "$ready" -eq 1 ] && break
  [ "$SECONDS" -lt "$deadline" ] || exit 1
  sleep 1
done
if printf denied > /var/log/lab/.isolation-write-probe; then
  exit 1
fi

! command -v docker >/dev/null
! test -S /var/run/docker.sock
! test -e /scenario/compose.yaml
! getent hosts toxiproxy >/dev/null
! curl --fail --silent --show-error --connect-timeout 2 http://toxiproxy:8474/version >/dev/null 2>&1
! env | grep -E '(^|_)(TOXIPROXY|FAULT|BROKEN_INSTANCE|INJECTED_LATENCY)=' >/dev/null
INVESTIGATOR
then
  fail 'Baseline investigator sandbox boundary assertions failed'
fi

if ! run_baseline <<'INVESTIGATOR'
set -euo pipefail
[ "$(id -u)" -ne 0 ]
[ "$(cat "$HOME/.local/share/opencode/auth.json")" = '{"type":"inert"}' ]
printf '%s\n' preserved > "$HOME/.local/share/opencode/isolation-marker"
INVESTIGATOR
then
  fail 'Baseline investigator could not use the synthetic OpenCode data directory'
fi

if ! run_baseline <<'INVESTIGATOR'
set -euo pipefail
[ "$(id -u)" -ne 0 ]
[ "$(cat "$HOME/.local/share/opencode/auth.json")" = '{"type":"inert"}' ]
[ "$(cat "$HOME/.local/share/opencode/isolation-marker")" = preserved ]
INVESTIGATOR
then
  fail 'Baseline investigator data did not persist across one-shot containers'
fi

printf 'isolation acceptance passed: Baseline has only operator access and preserves synthetic OpenCode data.\n'
