# AGENTS.md

## Project

This repository builds a small, deterministic troubleshooting lab for a recorded workshop.

The authoritative technical contract is [`Especificacion_Lab.md`](Especificacion_Lab.md). Read the relevant sections before changing behavior. Do not duplicate or override that contract in other documents.

## Current status

- Phase 0 is complete: repository scaffold, Make interface, version pins, and test placeholders.
- Phase 1 is complete: healthy pricing, checkout, gateway, and load-generator services; verify with `./tests/healthy.sh`.
- Phase 2 is complete: isolated Toxiproxy fault activation and degraded acceptance pass.
- Phase 3 is in progress: Review 1 provides idempotent `start`, `healthy-check`, and `stop`; transitions, verification, reset, and record-ready remain for later reviews.
- OpenCode CLI is the investigation assistant.
- OpenCode is not a functional dependency of the lab itself.

## Implementation rules

1. Implement one specification phase at a time.
2. Do not advance until that phase's acceptance criteria pass.
3. Prefer the simplest explicit implementation that satisfies the current phase.
4. Do not add components, abstractions, retries, fallbacks, or automation without a concrete requirement.
5. If the specified architecture is blocked, stop and explain the blocker before changing it.
6. Keep the three checkout replicas on exactly the same binary; configuration may differ.
7. Preserve deterministic gateway round-robin behavior.
8. Keep Toxiproxy and physical fault details inaccessible from the investigator environment.
9. Never expose physical upstream addresses or fault details in logs, metrics, debug responses, or investigator files.
10. Keep credentials and tokens out of the repository and container images.

## Development workflow

1. Read the current phase in `Especificacion_Lab.md`.
2. Turn its acceptance requirement into a failing test.
3. Implement only enough behavior to make that test pass.
4. Run focused validation and record the exact command and result.
5. Keep documentation with the behavior it explains.

For controlled distribution tests, pause the load generator and verify exactly 90 requests produce `30/30/30`. Runtime Prometheus and Grafana observations use the tolerances defined in the specification.

## Project interfaces

```bash
make help
```

The primary operations are:

```text
start
healthy-check
fault-on
verify
fault-off
reset
stop
record-ready
```

Phase 0 placeholders intentionally fail until their owning phase is implemented. Do not convert them into false-positive tests.

## Configuration

- `versions.env` is the single source of version pins.
- Never use `latest`.
- Support Docker Compose v2 on Linux and macOS, for `amd64` and `arm64`.
- Authentication for OpenCode must be provided at runtime without preselecting a model provider.

## Git policy

- This is a solo-maintainer repository; keep changes and commits small and direct.
- Commit by working behavior, with tests and related documentation together.
- Do not commit, push, publish, or perform destructive Git operations unless the user explicitly requests it.
