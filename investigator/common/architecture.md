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

| Area | Available interface |
| --- | --- |
| Checkout API | Public checkout endpoint and three logical replicas. Each replica provides `/healthz`, `/metrics`, and `/debug/upstream`. |
| Pricing API | A pricing dependency with `/healthz` and `/metrics`. |
| Logs | Read-only JSONL files at `/var/log/lab`. |
| Prometheus | Queryable metrics. |
| Grafana | Queryable dashboards. |

The diagram and names describe the logical architecture only.
