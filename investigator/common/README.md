# Investigator Workspace

This one-shot workspace contains the common assets for both investigation profiles.

## Available tools and interfaces

| Area | Available interface |
| --- | --- |
| Shell tools | `bash`, `curl`, `jq`, `getent`, `dig`, `grep`, and `rg` |
| OpenCode | `opencode` CLI, with runtime-provided data at `/home/node/.local/share/opencode` |
| Checkout API | `checkout-gateway`, `checkout-1`, `checkout-2`, and `checkout-3`; each checkout replica provides `/healthz`, `/metrics`, and `/debug/upstream` |
| Pricing API | `pricing-api`, with `/healthz` and `/metrics` |
| Logs | Read-only JSONL files at `/var/log/lab` |
| Prometheus | `http://prometheus:9090` and `bin/promq` |
| Grafana | `http://grafana:3000` |

## Workspace lifetime

`/investigator-workspace` is writable only for the one-shot container. Changes made here are discarded when the container exits with `--rm`.

OpenCode data is separate at `/home/node/.local/share/opencode`. Its runtime-provided directory can retain authentication material and sessions between one-shot containers. Do not place credentials in this workspace.
