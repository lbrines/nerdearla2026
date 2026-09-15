# Lab de Troubleshooting

**Estado: Phase 3 Review 2 completo. `make start`, `make healthy-check`, `make fault-on`, `make verify`, `make fault-off` y `make stop` están disponibles. `verify` cuenta outcomes HTTP controlados; la verificación de baseline/delta de métricas queda para Phase 4. `reset` y `record-ready` siguen para la próxima revisión.**

La autoridad técnica del lab es [Especificacion_Lab.md](Especificacion_Lab.md).

## Verificación sana

```bash
./tests/healthy.sh
```

## Verificación degradada

```bash
./tests/degraded.sh
```
