# Lab de Troubleshooting

**Estado: Phase 3.3 agrega `make reset`. Para el proyecto fijo del lab ejecuta `docker compose down --volumes --remove-orphans`, luego `make start` y su verificación sana. `./tests/reset.sh` confirmó el reset desde detenido y cinco ciclos consecutivos degradado → reset → sano. El volumen nombrado de logs de la Phase 4.2 también se elimina con ese reset. `make record-ready` sigue siendo un placeholder que falla intencionalmente; Phase 3 no está completa.**

**Phase 4.1 implementa métricas de checkout, pricing y gateway, verificables directamente en `/metrics` con `./tests/observability.sh`. Phase 4.2 agrega JSONL correlacionado de checkout y pricing; Phase 4.3A completa la instrumentación JSONL de gateway y load generator en stdout y el volumen compartido. Phase 4.3B verifica con `./tests/logging.sh` la cadena runtime por IDs reales y que `stop` conserva el marcador, y con `./tests/reset.sh` que `reset` lo elimina, recrea los seis logs y cambia el boot prefix. Phase 5.1 agrega Prometheus con scrape explícito cada 5 segundos y `./tests/prometheus.sh` consulta su API para validar los estados sano y degradado. Phase 5.2 agrega Grafana provisionado en `http://127.0.0.1:3000`; `./tests/grafana.sh` verifica su API anónima, datasource y dashboards. Phase 6.1 agrega el sandbox investigator con logs read-only y `./tests/isolation.sh` valida su aislamiento técnico. Phase 7 entrega el workspace saneado y el protocolo; la acceptance manual por shell está validada. Phase 8, el dry run con OpenCode, sigue pendiente. La acceptance integrada de Phase 4 sigue pendiente; Phase 4 no está completa y `make record-ready` sigue diferido. Las imágenes y herramientas se fijan en `versions.env`; los módulos Go se fijan en `go.mod` y `go.sum`.**

La autoridad técnica del lab es [Especificacion_Lab.md](Especificacion_Lab.md).

## Sandbox investigator

El sandbox es una shell one-shot opt-in: no agrega un proceso residente ni cambia los comandos existentes del lab.

1. Levantá el lab con `make start`.
2. Creá el directorio persistente aprobado: `mkdir -p "$HOME/.local/share/nerdearla2026/opencode"`.
3. Abrí la shell con:

   ```bash
   docker compose --env-file versions.env --project-name nerdearla2026 --file scenario/compose.yaml \
     --profile investigator run --rm --no-deps investigator
   ```

4. Ejecutá `opencode` y completá el primer login con el proveedor que elijas en runtime.

| Tema | Decisión |
| --- | --- |
| Datos de OpenCode | La única ruta persistente es `OPENCODE_DATA_DIR`; por defecto es `$HOME/.local/share/nerdearla2026/opencode` en el host y se monta en `/home/node/.local/share/opencode`. Conserva credenciales y sesiones provistas en runtime. |
| Workspace | `/investigator-workspace` incluye guía, protocolo, template y `bin/promq`; es escribible pero efímero y se descarta con el container. No existe un bind persistente para notas: exportalas antes de salir si querés conservarlas. |
| Acceso al lab | Solo `operator_net` y `/var/log/lab` read-only; no se montan el repositorio, `scenario` ni el socket de Docker. |

`OPENCODE_DATA_DIR` solo permite una ruta conocida alternativa, por ejemplo para una prueba hermética; no hay descubrimiento ni creación automática de directorios. La autenticación no se incluye en la imagen ni selecciona un proveedor.

## Verificación de aislamiento

```bash
./tests/isolation.sh
```

## Verificación de Grafana

```bash
./tests/grafana.sh
```

Grafana se publica solo en `http://127.0.0.1:3000`.

## Verificación de Prometheus

```bash
./tests/prometheus.sh
```

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
