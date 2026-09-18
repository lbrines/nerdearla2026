# Arquitectura lógica

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

## Interfaces observables

| Área | Interfaz disponible |
| --- | --- |
| API de Checkout | Endpoint público de checkout y tres réplicas lógicas. Cada réplica proporciona `/healthz`, `/metrics` y `/debug/upstream`. |
| API de Pricing | Una dependencia de pricing con `/healthz` y `/metrics`. |
| Logs | Archivos JSONL de solo lectura en `/var/log/lab`. |
| Prometheus | Métricas consultables. |
| Grafana | Paneles consultables. |

El diagrama y los nombres describen únicamente la arquitectura lógica.
