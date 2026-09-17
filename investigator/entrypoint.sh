#!/usr/bin/env bash
set -euo pipefail

if [ "${INVESTIGATOR_PROFILE:-}" = "protocol" ]; then
  investigation_file=/investigation-output/investigation.md
  if [ ! -e "$investigation_file" ]; then
    cp /protocol-template/investigation.md "$investigation_file"
  fi
  ln -s /investigation-output/investigation.md /investigator-workspace/investigation.md
fi

exec "$@"
