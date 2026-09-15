# Lab de Troubleshooting

**Estado: Phase 3.3 agrega `make reset`. Para el proyecto fijo del lab ejecuta `docker compose down --volumes --remove-orphans`, luego `make start` y su verificación sana. `./tests/reset.sh` confirmó el reset desde detenido y cinco ciclos consecutivos degradado → reset → sano. Hoy no existen volúmenes de TSDB ni logs. `make record-ready` sigue siendo un placeholder que falla intencionalmente hasta que estén las dependencias de observabilidad e investigator de las Phases 4–6; Phase 3 no está completa.**

**Phase 4.1 implementa métricas de checkout, pricing y gateway, verificables directamente en `/metrics` con `./tests/observability.sh`. Los logs y Prometheus/Grafana siguen pendientes; Phase 4 no está completa y `make record-ready` sigue diferido. Las imágenes y herramientas se fijan en `versions.env`; los módulos Go se fijan en `go.mod` y `go.sum`.**

La autoridad técnica del lab es [Especificacion_Lab.md](Especificacion_Lab.md).

## Verificación sana

```bash
./tests/healthy.sh
```

## Verificación degradada

```bash
./tests/degraded.sh
```
