# Reproducir el lab localmente

Esta guía levanta y opera el escenario desde un checkout limpio. Sirve para preparar un ejercicio técnico; no prescribe cómo investigar ni qué conclusión obtener.

## Requisitos

Usá Linux o macOS en `amd64` o `arm64`, con:

- Docker Engine o Docker Desktop con Docker Compose v2;
- `make` y `curl` disponibles en el host;
- acceso para descargar las imágenes requeridas.

Las imágenes y herramientas usan versiones verificadas y fijadas en [`versions.env`](versions.env). No copies esos valores a otra configuración: ese archivo es la única fuente de pines. Las dependencias de Go se fijan por separado en `go.mod` y `go.sum`.

## Checkout limpio

Cloná la URL HTTPS pública publicada para el lab y conservá ese origen:

```bash
git clone https://github.com/lbrines/nerdearla2026.git lab-local
cd lab-local
git remote get-url origin
```

El último comando debe mostrar la misma URL HTTPS pública usada para clonar. Si ya tenés un checkout, revisá el origen antes de continuar.

## Levantar el escenario sano

```bash
make start
make healthy-check
```

`make start` construye, inicia y comprueba el escenario sano. `make healthy-check` vuelve a comprobar sus endpoints. No uses una espera fija como señal de disponibilidad: esperá el resultado de los comandos y, para métricas, la evidencia observable descrita más abajo.

### Servicios publicados en el host

| Servicio | URL o puerto |
| --- | --- |
| pricing-api | http://127.0.0.1:18080 |
| checkout-1 | http://127.0.0.1:18081 |
| checkout-2 | http://127.0.0.1:18082 |
| checkout-3 | http://127.0.0.1:18083 |
| checkout-gateway | http://127.0.0.1:18084 |
| Prometheus | http://127.0.0.1:19090 |
| Grafana | http://127.0.0.1:3000 |

Solo `pricing-api`, las tres réplicas de checkout y `checkout-gateway` exponen `/healthz`; `make healthy-check` comprueba esos endpoints de aplicación, no Prometheus ni Grafana. Prometheus usa `/-/healthy` y Grafana `/api/health`; los servicios instrumentados también exponen `/metrics` según el contrato técnico.

## Ejercicio de operación

Usá esta secuencia para comprobar el ciclo del escenario, no para preparar una sesión de investigator:

```bash
make start
make fault-on
make fault-off
make healthy-check
```

`make fault-on` deja el escenario degradado. `make fault-off` desactiva el incidente y vuelve a comprobar salud. La verificación controlada es distinta:

```bash
make verify
```

`make verify` pausa temporalmente el generador de carga, ejecuta 90 solicitudes consecutivas contra el gateway más sondas directas de validación y lo restaura al terminar. Las 90 solicitudes corresponden solo a la ventana del gateway. Esperá conteos de `30/30/30` por réplica; con el incidente activo, de esas 90 solicitudes `60` completan correctamente y `30` fallan. Sus sondas agregan logs y métricas, por lo que no es un paso pasivo ni debe ejecutarse después de preparar el estado de un participante.

## Métricas y dashboards

Prometheus recolecta cada 5 segundos. Las observaciones de tasas y dashboards usan ventanas de 30 segundos, así que dejá que haya muestras suficientes para que la ventana represente el estado actual. No reemplaces esa observación por una demora fija.

Grafana está disponible en http://127.0.0.1:3000. La instancia se aprovisiona sin configuración manual; las validaciones de los dashboards pertenecen a las comprobaciones existentes del proyecto, no a una afirmación nueva de esta guía.

## Abrir un perfil investigator

Los perfiles son shells one-shot opcionales. Ambos reciben los mismos logs de solo lectura, capacidades locales y acceso normal a Internet. El perfil Protocol agrega únicamente su material metodológico; esta guía no indica una ruta de diagnóstico.

Para conducir una investigación del incidente, completá primero la [preparación limpia del incidente](operator/README.md#preparación-limpia-del-incidente); no la sustituyas por `make start`. Luego elegí directorios persistentes del host para los datos de OpenCode y la evidencia:

```bash
mkdir -p "$HOME/.local/share/opencode-lab" "$PWD/investigation-output"
export OPENCODE_DATA_DIR="$HOME/.local/share/opencode-lab"
export INVESTIGATION_OUTPUT_DIR="$PWD/investigation-output"
```

Abrí uno de los perfiles:

```bash
docker compose --env-file versions.env --project-name nerdearla2026 --file scenario/compose.yaml \
  --profile investigator-baseline run --rm --no-deps investigator-baseline

# o
docker compose --env-file versions.env --project-name nerdearla2026 --file scenario/compose.yaml \
  --profile investigator-protocol run --rm --no-deps investigator-protocol
```

Dentro de la shell podés ejecutar `opencode`. La autenticación se entrega en runtime y no se preselecciona un proveedor. `OPENCODE_DATA_DIR` se monta en la ubicación de datos de OpenCode; `INVESTIGATION_OUTPUT_DIR` se monta como salida persistente. El workspace de cada shell es efímero.

El material de operación no se monta en esos perfiles. Para una preparación manual, usá [operator/README.md](operator/README.md).

## Detener, reiniciar y limpiar

```bash
make stop
```

`make stop` detiene el escenario y conserva los logs compartidos.

```bash
make reset
```

**Advertencia:** `make reset` elimina los volúmenes propios del escenario, incluidos logs y datos de Prometheus, luego inicia un estado sano. Usalo para una nueva preparación o cuando la evidencia previa ya no sea útil.

`make record-ready` existe pero hoy falla de forma intencional: todavía no reemplaza la preparación manual ni debe usarse como señal de que el escenario está listo para grabar.

## Si algo falla

1. Confirmá que Docker está disponible y que los puertos publicados no están ocupados.
2. Ejecutá `make help` para revisar la interfaz admitida.
3. Ejecutá `make healthy-check` para separar un problema de disponibilidad del ejercicio de operación.
4. Si necesitás descartar evidencia previa, aplicá `make reset` con la advertencia anterior en mente.

Para los contactos del proyecto, consultá [Contacto en README.md](README.md#contacto).
