# Reproducir el lab localmente

Esta guía levanta y opera el escenario desde un checkout limpio. Sirve para preparar un ejercicio técnico; no prescribe cómo investigar ni qué conclusión obtener.

## Requisitos

Usar Linux o macOS en `amd64` o `arm64`, con:

- Docker Engine o Docker Desktop con Docker Compose v2;
- `make` y `curl` disponibles en el host;
- acceso para descargar las imágenes requeridas.

Las imágenes y herramientas usan versiones verificadas y fijadas en [`versions.env`](versions.env). No se deben copiar esos valores a otra configuración: ese archivo es la única fuente de pines. Las dependencias de Go se fijan por separado en `go.mod` y `go.sum`.

## Checkout limpio

Clonar la URL HTTPS pública publicada para el lab y conservar ese origen:

```bash
git clone https://github.com/lbrines/nerdearla2026.git lab-local
cd lab-local
git remote get-url origin
```

El último comando debe mostrar la misma URL HTTPS pública usada para clonar. Si ya existe un checkout, revisar el origen antes de continuar.

## Levantar el escenario sano

```bash
make start
make healthy-check
```

`make start` construye, inicia y comprueba el escenario sano. `make healthy-check` vuelve a comprobar sus endpoints. No usar una espera fija como señal de disponibilidad: esperar el resultado de los comandos y, para métricas, la evidencia observable descrita más abajo.

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

Usar esta secuencia para comprobar el ciclo del escenario, no para preparar una sesión de investigator:

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

`make verify` pausa temporalmente el generador de carga, ejecuta 90 solicitudes consecutivas contra el gateway más sondas directas de validación y lo restaura al terminar. Las 90 solicitudes corresponden solo a la ventana del gateway. Se esperan conteos de `30/30/30` por réplica; con el incidente activo, de esas 90 solicitudes `60` completan correctamente y `30` fallan. Sus sondas agregan logs y métricas, por lo que no es un paso pasivo ni debe ejecutarse después de preparar el estado de un participante.

## Métricas y dashboards

Prometheus recolecta cada 5 segundos. Las observaciones de tasas y dashboards usan ventanas de 30 segundos, así que debe haber muestras suficientes para que la ventana represente el estado actual. No se debe reemplazar esa observación por una demora fija.

Grafana está disponible en http://127.0.0.1:3000. La instancia se aprovisiona sin configuración manual; las validaciones de los dashboards pertenecen a las comprobaciones existentes del proyecto, no a una afirmación nueva de esta guía.

## Abrir un perfil investigator

Los perfiles son shells one-shot opcionales. Ambos reciben los mismos logs de solo lectura, capacidades locales y acceso normal a Internet. El perfil Protocol agrega únicamente su material metodológico; esta guía no indica una ruta de diagnóstico.

Para conducir una investigación del incidente, primero se debe completar la [preparación limpia del incidente](operator/README.md#preparación-limpia-del-incidente); no se debe sustituir por `make start`.

### Baseline

```bash
mkdir -p "$PWD/investigator-output/baseline/opencode"
export OPENCODE_DATA_DIR="$PWD/investigator-output/baseline/opencode"
export INVESTIGATION_OUTPUT_DIR="$PWD/investigator-output/baseline"

docker compose --env-file versions.env --project-name nerdearla2026 --file scenario/compose.yaml \
  --profile investigator-baseline run --rm --no-deps investigator-baseline
```

Al final de la sesión Baseline, el Markdown final debe guardarse dentro del perfil en `/investigation-output/investigation.md`. En el host queda como `investigator-output/baseline/investigation.md`.

### Protocol

```bash
mkdir -p "$PWD/investigator-output/protocol/opencode"
export OPENCODE_DATA_DIR="$PWD/investigator-output/protocol/opencode"
export INVESTIGATION_OUTPUT_DIR="$PWD/investigator-output/protocol"

docker compose --env-file versions.env --project-name nerdearla2026 --file scenario/compose.yaml \
  --profile investigator-protocol run --rm --no-deps investigator-protocol
```

Al final de la sesión Protocol, el Markdown final debe guardarse dentro del perfil en `/investigation-output/investigation.md`. En el host queda como `investigator-output/protocol/investigation.md`.

Dentro de la shell se puede ejecutar `opencode`. La autenticación se entrega en runtime y no se preselecciona un proveedor. `OPENCODE_DATA_DIR` se monta en la ubicación de datos de OpenCode; `INVESTIGATION_OUTPUT_DIR` se monta como salida persistente. El workspace de cada shell es efímero.

El material de operación no se monta en esos perfiles. Para una preparación manual, consultar [operator/README.md](operator/README.md).

### Permisos de directorios montados en Linux

En Linux, los directorios del host montados en el contenedor deben ser escribibles por el usuario del contenedor. En macOS esto puede no aparecer por la capa de permisos de Docker Desktop.

Si al abrir un perfil aparecen errores como estos:

```text
EACCES: permission denied, mkdir '/home/node/.local/share/opencode/repos'
cp: cannot create regular file '/investigation-output/investigation.md': Permission denied
```

se debe comprobar que los directorios definidos en los comandos anteriores mediante `OPENCODE_DATA_DIR` e `INVESTIGATION_OUTPUT_DIR` pertenezcan al usuario del host:

```bash
sudo chown -R "$(id -u):$(id -g)" "$OPENCODE_DATA_DIR" "$INVESTIGATION_OUTPUT_DIR"
chmod -R u+rwX "$OPENCODE_DATA_DIR" "$INVESTIGATION_OUTPUT_DIR"
```

También se pueden definir directorios nuevos y escribibles para una corrida limpia y luego abrir nuevamente el perfil Baseline o Protocol con los comandos anteriores.

## Detener, reiniciar y limpiar

```bash
make stop
```

`make stop` detiene el escenario y conserva los logs compartidos.

```bash
make reset
```

**Advertencia:** `make reset` elimina los volúmenes propios del escenario, incluidos logs y datos de Prometheus, luego inicia un estado sano. Usarlo para una nueva preparación o cuando la evidencia previa ya no sea útil.

`make record-ready` existe pero hoy falla de forma intencional: todavía no reemplaza la preparación manual ni debe usarse como señal de que el escenario está listo para grabar.

## Si algo falla

1. Confirmar que Docker está disponible y que los puertos publicados no están ocupados.
2. Ejecutar `make help` para revisar la interfaz admitida.
3. Ejecutar `make healthy-check` para separar un problema de disponibilidad del ejercicio de operación.
4. Si se necesita descartar evidencia previa, aplicar `make reset` con la advertencia anterior en mente.

Para los contactos del proyecto, consultar [Contacto en README.md](README.md#contacto).
