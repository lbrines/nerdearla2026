# Logical Architecture

```text
client
  ↓
checkout-api
  ├── checkout-1
  ├── checkout-2
  └── checkout-3
  ↓
pricing-api
```

## Observable interfaces

| Area | Available evidence |
| --- | --- |
| Checkout API | Public checkout endpoint and three logical replicas. Each replica provides `/healthz`, `/metrics`, and `/debug/upstream`. |
| Pricing API | A pricing dependency with `/healthz` and `/metrics`. |
| Logs | Read-only JSONL files at `/var/log/lab`. |
| Prometheus | Queryable metrics for aggregate and per-instance comparisons. |
| Grafana | Queryable dashboards for observability context. |

## Reading the diagram

The diagram supplies logical names, not an explanation for a current symptom. Start from aggregate evidence, test whether pricing is globally healthy, then compare all logical checkout replicas. Treat a different logical outcome as a hypothesis to test with observations.

Use the logical names shown here when recording evidence. This document intentionally describes no replica-specific implementation or routing details.
