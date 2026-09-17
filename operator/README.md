# Internal Operator Runbook

This operator-only material is not part of either investigator profile and must never be copied into or mounted by an investigator container.

1. Start the lab with `make start`.
2. Confirm the healthy state with `./tests/healthy.sh`.
3. Activate and verify the workshop scenario with `make fault-on` and `make verify`.
4. Reset the lab with `make reset` before another controlled run.

Do not use this path as an investigator workspace.
