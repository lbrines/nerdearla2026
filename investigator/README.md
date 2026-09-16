# Investigator Workspace

Use this workspace to reduce uncertainty from observable evidence. It contains only investigation guidance and a Prometheus query helper; it contains no scenario control material.

## Safe evidence first

1. State the question and its expected falsifier in `investigation.md`.
2. Read metrics, logs, or logical diagnostic responses.
3. Compare all logical replicas before concentrating on one.
4. Update the investigation log with observations, not conclusions.

| Evidence | Read-only location |
| --- | --- |
| Lab logs | `/var/log/lab` |
| Prometheus | `bin/promq '<PromQL expression>'` |
| Logical instance view | `http://checkout-1:8080/debug/upstream`, `checkout-2`, and `checkout-3` |
| Other observability | Prometheus and Grafana services |

## Compare the logical replicas

```bash
for instance in checkout-1 checkout-2 checkout-3; do
  printf '%s\n' "$instance"
  curl --fail --silent --show-error "http://$instance:8080/debug/upstream" | jq .
done
```

Use PromQL to compare an aggregate error rate, pricing errors or latency, then error rates grouped by checkout instance. For example:

```bash
bin/promq 'sum(rate(checkout_requests_total{outcome="error"}[30s])) / sum(rate(checkout_requests_total[30s]))'
bin/promq 'sum by (checkout_instance) (rate(checkout_requests_total{outcome="error"}[30s])) / sum by (checkout_instance) (rate(checkout_requests_total[30s]))'
```

Inspect logs only to correlate observed request evidence; do not turn an unobserved explanation into a fact. A successful command is evidence only for what it returned.

## Workspace lifetime

`/investigator-workspace` is writable only for the one-shot container. Notes or changes made here are discarded when that container exits with `--rm`; copy any note you want to retain before exiting. There is no persistent workspace mount.

OpenCode data is separate at `/home/node/.local/share/opencode`. Its runtime-provided directory can retain both authentication material and sessions between one-shot containers. Do not place credentials in this workspace.
