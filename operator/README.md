# Internal Operator Runbook

This operator-only material is not part of either investigator profile and must never be copied into or mounted by an investigator container.

## Optional operator validation

`make verify` is optional operator validation. It may run during development or before preparing a comparative session. Never run it after the participant state is prepared: its probes add log and metric evidence.

## Minimal per-run preparation

Do not implement a Phase 8 dry run from this runbook. For one prepared run:

1. Reset with `make reset`.
2. Activate the incident with `make fault-on`.
3. Wait for the required stabilization window.
4. Launch the selected investigator profile without running `make verify` after activation.

Use a clean, separate `OPENCODE_DATA_DIR` and `INVESTIGATION_OUTPUT_DIR` for every run.

## Per-run metadata

Record:

- run ID;
- profile;
- commit;
- model/provider;
- exact shared `INCIDENT.md` prompt;
- UTC start and end, or duration;
- transcript/artifact path.

Do not use this path as an investigator workspace.
