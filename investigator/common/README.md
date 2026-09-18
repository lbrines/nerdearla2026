# Espacio de trabajo del investigador

Este espacio de trabajo de uso único contiene los recursos comunes para ambos perfiles de investigación.

## Herramientas e interfaces disponibles

| Área | Interfaz disponible |
| --- | --- |
| Herramientas de shell | `bash`, `curl`, `jq`, `getent`, `dig`, `grep` y `rg` |
| OpenCode | CLI `opencode`, con datos proporcionados en tiempo de ejecución en `/home/node/.local/share/opencode` |
| API de Checkout | `checkout-gateway`, `checkout-1`, `checkout-2` y `checkout-3`; cada réplica de checkout proporciona `/healthz`, `/metrics` y `/debug/upstream` |
| API de Pricing | `pricing-api`, con `/healthz` y `/metrics` |
| Logs | Archivos JSONL de solo lectura en `/var/log/lab` |
| Prometheus | `http://prometheus:9090` y `bin/promq` |
| Grafana | `http://grafana:3000` |

## Contrato compartido de evidencia y resultados

- Utiliza nombres lógicos de servicios en los artefactos y conserva `request_id` para las correlaciones.
- Omite IP internas, ID o nombres de contenedores, rutas del host, rutas o mecanismos físicos y detalles innecesarios del entorno.
- Los valores de los paneles son tasas de 30 s obtenidas de scrapes de Prometheus cada 5 s; JSONL contiene registros exactos de eventos. Las muestras más recientes pueden retrasarse hasta un intervalo de scrape, y la extrapolación de tasas y los límites de ventana implican que las tasas de los paneles no son totales exactos de logs. Las comparaciones exactas utilizan deltas de contadores y conteos de logs sobre límites compartidos de forma explícita.

## Duración del espacio de trabajo

`/investigator-workspace` se puede escribir solo desde el contenedor de uso único. Los cambios realizados aquí se descartan cuando el contenedor termina con `--rm`.

Los datos de OpenCode están separados en `/home/node/.local/share/opencode`. Su directorio proporcionado en tiempo de ejecución puede conservar material de autenticación y sesiones entre contenedores de uso único. No coloques credenciales en este espacio de trabajo.
