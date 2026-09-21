# Runbook de operación interna

Este material es exclusivo de operación. No forma parte de ninguno de los perfiles investigator y nunca debe copiarse ni montarse en un contenedor investigator.

La instalación genérica, los puertos y el arranque básico están en [REPRODUCIR.md](../REPRODUCIR.md). Este documento solo cubre la preparación manual y la comprobación operativa.

## Límites de la operación

`make verify` es una validación opcional de operación. Pausa y restaura el generador de carga, ejecuta 90 solicitudes consecutivas contra el gateway y además realiza sondas directas de validación; sus solicitudes agregan evidencia en logs y métricas. Nunca lo ejecutes después de comenzar la preparación limpia de un participante.

## Ensayo de operación (antes de preparar participantes)

1. **Partí de una base limpia.** Ejecutá `make reset`. Es destructivo para los volúmenes propios, incluidos logs y datos de Prometheus, y termina con el escenario sano.
2. **Confirmá operación sana.** Ejecutá `make healthy-check`. En una ventana controlada sana, las 90 solicitudes de gateway de `make verify` deben observar 90 respuestas correctas y distribución exacta `30/30/30`.
3. **Activá el incidente.** Ejecutá `make fault-on`. Confirmá que la observación degradada tenga una tasa global aproximada de 30–36 %, dos réplicas por debajo de 2 % de errores y una por encima de 95 %; pricing debe permanecer por debajo de 1 % de errores y con p95 menor de 100 ms.
4. **Verificá conteos.** Con el incidente activo, las 90 solicitudes de gateway de `make verify` deben producir 60 respuestas correctas y 30 fallidas, con `30/30/30` solicitudes por réplica. Esta comprobación confirma la operación del escenario; no determina una interpretación del incidente.
5. **Restablecé la base limpia.** Ejecutá nuevamente `make reset` para descartar la evidencia sintética del ensayo antes de preparar un participante.

## Preparación limpia del incidente

Usá esta secuencia para una sesión de investigación de participante. **No ejecutes `make verify` entre `make reset` y la apertura del perfil.**

1. Ejecutá `make reset`.
2. Ejecutá `make fault-on`.
3. Dejá estabilizar los observables. Prometheus recolecta cada 5 segundos y las tasas usan ventanas de 30 segundos; esperá evidencia observable suficiente, no una demora fija.
4. Abrí el perfil seleccionado. Usá un `OPENCODE_DATA_DIR` y un `INVESTIGATION_OUTPUT_DIR` limpios y separados para cada corrida.

Si una sonda, una verificación o una prueba previa contaminó la evidencia destinada a la sesión, repetí la preparación desde `make reset`; no intentes corregir manualmente logs o métricas.

## Separar comando e inferencia

Los comandos de esta lista establecen o comprueban el estado operativo del escenario. No reemplazan la investigación del participante ni convierten una observación en una conclusión. Conservá esa separación al registrar la corrida.

## Metadatos por corrida

Registrá:

- identificador de corrida;
- perfil;
- modelo y proveedor;
- prompt compartido exacto de `INCIDENT.md`;
- inicio y fin en UTC, o duración;
- ruta del transcript o artefacto.

No uses este directorio como workspace de un investigator.
