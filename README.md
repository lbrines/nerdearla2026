# Lab de Troubleshooting

**Estado: Phase 3.3 agrega `make reset`. Para el proyecto fijo del lab ejecuta `docker compose down --volumes --remove-orphans`, luego `make start` y su verificación sana. `./tests/reset.sh` confirmó el reset desde detenido y cinco ciclos consecutivos degradado → reset → sano. El volumen nombrado de logs de la Phase 4.2 también se elimina con ese reset. `make record-ready` sigue siendo un placeholder que falla intencionalmente hasta que estén las dependencias de observabilidad e investigator de las Phases 4–6; Phase 3 no está completa.**

**Phase 4.1 implementa métricas de checkout, pricing y gateway, verificables directamente en `/metrics` con `./tests/observability.sh`. Phase 4.2 agrega JSONL correlacionado de checkout y pricing; Phase 4.3A completa la instrumentación JSONL de gateway y load generator en stdout y el volumen compartido. Phase 4.3B verifica con `./tests/logging.sh` la cadena runtime por IDs reales y que `stop` conserva el marcador, y con `./tests/reset.sh` que `reset` lo elimina, recrea los seis logs y cambia el boot prefix. La evidencia directa de métricas y logs está completa; la verificación operacional basada en métricas, Prometheus/Grafana y el investigator read-only de Phase 6 siguen pendientes. Phase 4 no está completa y `make record-ready` sigue diferido. Las imágenes y herramientas se fijan en `versions.env`; los módulos Go se fijan en `go.mod` y `go.sum`.**

La autoridad técnica del lab es [Especificacion_Lab.md](Especificacion_Lab.md).

## Verificación de logs

```bash
./tests/logging.sh
```

## Verificación sana

```bash
./tests/healthy.sh
```

## Verificación degradada

```bash
./tests/degraded.sh
```
