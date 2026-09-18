#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

fail() {
  printf 'profiles acceptance failed: %s\n' "$1" >&2
  return 1
}

COMPOSE_PROJECT_NAME="phase7b-profiles-$$"
TEST_DATA_DIR=""
TEST_EVIDENCE_DIR=""

cleanup_profiles() {
  local body_status=$? cleanup_status=0

  if [ -n "$TEST_DATA_DIR" ] && [ -d "$TEST_DATA_DIR" ]; then
    if rm -rf -- "$TEST_DATA_DIR"; then
      :
    else
      cleanup_status=$?
      printf 'profiles acceptance cleanup failed: could not remove test data directory\n' >&2
    fi
  fi
  if compose --profile investigator-baseline --profile investigator-protocol down --volumes --remove-orphans; then
    :
  else
    cleanup_status=$?
  fi
  if [ "$body_status" -ne 0 ]; then
    return "$body_status"
  fi
  return "$cleanup_status"
}

profile_container_id() {
  local profile="$1"
  local id

  if ! id="$(compose --profile "$profile" ps --all --quiet "$profile")" || [ -z "$id" ]; then
    fail "could not find the $profile container"
  fi
  printf '%s\n' "$id"
}

run_profile() {
  local profile="$1"

  compose --profile "$profile" run --rm --no-deps --no-TTY "$profile" bash -s
}

profile_user() {
  local profile="$1"

  run_profile "$profile" <<'INVESTIGATOR'
set -euo pipefail
id -u
id -un
INVESTIGATOR
}

profile_networks() {
  local profile="$1"

  docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{printf "%s\n" $name}}{{end}}' "$(profile_container_id "$profile")" | awk 'NF' | LC_ALL=C sort
}

profile_required_mounts() {
  local profile="$1"

  docker inspect --format '{{range .Mounts}}{{printf "%s\t%t\n" .Destination .RW}}{{end}}' "$(profile_container_id "$profile")" |
    awk -F '\t' '$1 == "/var/log/lab" || $1 == "/home/node/.local/share/opencode" || $1 == "/investigation-output"' |
    LC_ALL=C sort
}

PROTOCOL_TEMPLATE="$(cat <<'TEMPLATE'
## FACTS

## CURRENT HYPOTHESES

| ID | Hypothesis | Status | Evidence | Next action |
|---|---|---|---|---|

## NEXT TEST
Hypothesis:
Prediction:
Test:
Falsifier:

## EVIDENCE

## UPDATED / DISCARDED
TEMPLATE
)"

TEST_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nerdearla2026-profiles.XXXXXX")"
export OPENCODE_DATA_DIR="$TEST_DATA_DIR/opencode"
export INVESTIGATION_OUTPUT_DIR="$TEST_DATA_DIR/investigation-output"
TEST_EVIDENCE_DIR="$INVESTIGATION_OUTPUT_DIR"
mkdir -p "$OPENCODE_DATA_DIR" "$TEST_EVIDENCE_DIR"
trap cleanup_profiles EXIT

if ! compose --profile investigator-baseline --profile investigator-protocol build \
  investigator-baseline investigator-protocol; then
  fail 'could not build the Phase 7B profiles'
fi
if ! compose --profile investigator-baseline --profile investigator-protocol create \
  investigator-baseline investigator-protocol; then
  fail 'could not create the Phase 7B profile containers'
fi

baseline_user="$(profile_user investigator-baseline)"
if [ "${baseline_user%%$'\n'*}" -eq 0 ]; then
  fail 'profile services run as root'
fi
if ! run_profile investigator-baseline <<'BASELINE'
set -euo pipefail

! test -e /investigator-workspace/INVESTIGATION_PROTOCOL.md
! test -e /investigator-workspace/investigation.md
BASELINE
then
  fail 'Baseline exposes Protocol material'
fi
if [ -e "$TEST_EVIDENCE_DIR/investigation.md" ]; then
  fail 'Baseline creates Protocol investigation evidence'
fi

protocol_user="$(profile_user investigator-protocol)"
if [ "$baseline_user" != "$protocol_user" ]; then
  fail 'Baseline and Protocol do not run as the same user'
fi

for marker in request_id READ-ONLY 'LOGICAL DIAGNOSIS' 'PHYSICAL MECHANISM' 'PENDING APPROVAL'; do
  grep -Fq "$marker" investigator/profiles/protocol/INVESTIGATION_PROTOCOL.md || fail "Protocol is missing $marker"
done

for profile in investigator-baseline investigator-protocol; do
  if ! run_profile "$profile" <<'INVESTIGATOR'
set -euo pipefail

for tool in bash curl jq getent dig grep rg opencode; do
  command -v "$tool" >/dev/null
done
test -r /var/log/lab
test -r /investigator-workspace/INCIDENT.md
test -w "$HOME/.local/share/opencode"
INVESTIGATOR
  then
    fail "$profile does not provide the required basic tools, log access, and OpenCode data access"
  fi
done

baseline_networks="$(profile_networks investigator-baseline)"
protocol_networks="$(profile_networks investigator-protocol)"
if [ "$baseline_networks" != "$protocol_networks" ] || ! printf '%s\n' "$baseline_networks" | grep -Fqx "${COMPOSE_PROJECT_NAME}_operator_net"; then
  fail 'Baseline and Protocol do not have the same operator_net access'
fi

baseline_mounts="$(profile_required_mounts investigator-baseline)"
protocol_mounts="$(profile_required_mounts investigator-protocol)"
if [ "$baseline_mounts" != "$protocol_mounts" ] ||
  ! printf '%s\n' "$baseline_mounts" | awk -F '\t' '$1 == "/var/log/lab" && $2 == "false" { logs = 1 } $1 == "/home/node/.local/share/opencode" && $2 == "true" { opencode = 1 } $1 == "/investigation-output" && $2 == "true" { evidence = 1 } END { exit !(logs && opencode && evidence) }'; then
  fail 'Baseline and Protocol do not have the same log, OpenCode-data, and evidence mounts'
fi

if ! run_profile investigator-protocol <<INVESTIGATOR
set -euo pipefail

[ "\$(cat /investigator-workspace/investigation.md)" = "$PROTOCOL_TEMPLATE" ]
test -w /investigator-workspace/investigation.md
grep -Fqx '> **FACTS → HYPOTHESES → PREDICTION → TEST → FALSIFIER → EVIDENCE → UPDATE**' /investigator-workspace/INVESTIGATION_PROTOCOL.md
INVESTIGATOR
then
  fail 'Protocol does not create its writable method and template evidence'
fi
if [ "$(cat "$TEST_EVIDENCE_DIR/investigation.md")" != "$PROTOCOL_TEMPLATE" ]; then
  fail 'Protocol does not persist the exact template on the host'
fi

if ! run_profile investigator-protocol <<'INVESTIGATOR'
set -euo pipefail

printf '%s\n' protocol-persistence-marker >> /investigator-workspace/investigation.md
INVESTIGATOR
then
  fail 'Protocol cannot write the evidence marker'
fi
if ! grep -Fqx 'protocol-persistence-marker' "$TEST_EVIDENCE_DIR/investigation.md"; then
  fail 'Protocol evidence marker is not persisted on the host'
fi

if ! run_profile investigator-protocol <<'INVESTIGATOR'
set -euo pipefail

grep -Fqx protocol-persistence-marker /investigator-workspace/investigation.md
INVESTIGATOR
then
  fail 'Protocol overwrites evidence on a second one-shot run'
fi
if ! grep -Fqx 'protocol-persistence-marker' "$TEST_EVIDENCE_DIR/investigation.md"; then
  fail 'Protocol evidence marker does not survive the second one-shot run'
fi

for profile in investigator-baseline investigator-protocol; do
  mounts="$(docker inspect --format '{{range .Mounts}}{{printf "%s\n%s\n" .Source .Destination}}{{end}}' "$(profile_container_id "$profile")")"
  if printf '%s\n' "$mounts" | grep -Eqi 'internal.*operator|operator.*internal'; then
    fail "$profile mounts Internal Operator material"
  fi
done

printf 'profiles acceptance passed: Baseline and Protocol have equal technical access, and Protocol persists its method evidence.\n'
