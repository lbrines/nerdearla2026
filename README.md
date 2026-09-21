# Lab de Troubleshooting

Un escenario local, determinista y reproducible para observar un incidente y practicar investigación técnica con evidencia. El lab separa el ejercicio de operación de la experiencia del investigator: las superficies Baseline y Protocol tienen las mismas capacidades locales y acceso a Internet; solo Protocol aporta un método explícito.

La autoridad técnica es [Especificacion_Lab.md](Especificacion_Lab.md). Para instalarlo y reproducirlo desde un checkout limpio, seguí [REPRODUCIR.md](REPRODUCIR.md).

## Inicio rápido

```bash
make start
make healthy-check
```

`make start` levanta el escenario y comprueba el estado sano. Requiere Docker Compose v2, `make` y `curl`; los requisitos completos y los puertos publicados están en [REPRODUCIR.md](REPRODUCIR.md#requisitos).

## Operación

| Comando | Uso |
| --- | --- |
| `make start` | Inicia el escenario y confirma salud. |
| `make healthy-check` | Comprueba los endpoints del escenario sano. |
| `make fault-on` | Activa el incidente preparado. |
| `make verify` | Ejecuta una ventana controlada de 90 solicitudes; cambia la evidencia observada. |
| `make fault-off` | Desactiva el incidente y vuelve a comprobar salud. |
| `make stop` | Detiene los contenedores y conserva los logs. |
| `make reset` | Elimina los volúmenes propios, reinicia y vuelve al estado sano. |
| `make record-ready` | Placeholder intencional: hoy falla. |

Usá `make help` para ver la interfaz disponible. La guía de reproducción distingue el ejercicio de operación de una sesión de investigator y explica cuándo no corresponde usar `make verify`.

## Documentación

- [REPRODUCIR.md](REPRODUCIR.md): instalación local, operación básica, perfiles y recuperación.
- [operator/README.md](operator/README.md): checklist manual exclusivo de operación y preparación.
- [Especificacion_Lab.md](Especificacion_Lab.md): contrato técnico del escenario.

## Límites actuales

`make record-ready` todavía no prepara una grabación: permanece como placeholder que falla de forma explícita. La aceptación integrada de observabilidad de la Phase 4 sigue pendiente y aún no ocurrió el dry run comparativo de la Phase 8. No infieras validaciones nuevas a partir de esta documentación.

Las imágenes y herramientas usan pines verificados en `versions.env`; las dependencias de Go se fijan en `go.mod` y `go.sum`.

## Contacto

- Autor: Leopoldo Brines
- LinkedIn: https://www.linkedin.com/in/lbrines/
- Telegram: https://t.me/lbrines/ (@lbrines)
