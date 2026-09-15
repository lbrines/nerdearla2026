# Especificación técnica del Lab de Troubleshooting

**Estado:** listo para implementación
**Propósito:** producir la sesión real grabada que se utilizará en el Bloque 4 del workshop.
**Implementador previsto:** OpenCode.
**Este documento define qué construir. No contiene todavía la implementación.**

---

# 1. Objetivo

Construir un entorno local, pequeño, determinista y reproducible donde pueda ocurrir un incidente real y se pueda investigar utilizando OpenCode desde terminal.

El lab debe hacer visible este proceso:

> **HECHOS → HIPÓTESIS → AMPLIAR → INTENTAR ROMPER → PRUEBA → EVIDENCIA → ACTUALIZAR**

El objetivo **no es que OpenCode encuentre rápidamente la causa**.

El objetivo es conseguir una investigación donde:

> el humano genera hipótesis → el LLM amplía → humano y LLM diseñan pruebas → el sistema devuelve evidencia → cambian las hipótesis.

---

# 2. Objetivos pedagógicos

El lab debe demostrar principalmente dos comportamientos.

### Objetivo primario

> **Intentá demostrar que tu hipótesis es falsa.**

### Objetivo secundario

> **Usá el LLM para ampliar y desafiar tu razonamiento, no para darte la respuesta.**

Y una regla transversal:

> **Una hipótesis puede provenir del humano o del LLM.
> La evidencia debe provenir del sistema observado.**

---

# 3. Fuera de alcance

El lab **no** debe convertirse en una demo de:

* Kubernetes;
* Docker;
* Prometheus;
* Grafana;
* Toxiproxy;
* networking;
* OpenCode;
* prompting;
* agentes;
* skills;
* tracing distribuido.

Esas tecnologías son instrumentos.

Tampoco construiremos:

* service mesh;
* Loki;
* Elasticsearch;
* Jaeger;
* OpenTelemetry Collector;
* multi-agent;
* Pi/Gentel-IA;
* una aplicación empresarial compleja;
* frontend;
* base de datos;
* colas;
* autenticación;
* chaos engineering sofisticado.

---

# 4. Arquitectura lógica

Nombres y roles:

| Nombre | Rol |
| --- | --- |
| `checkout-api` | servicio lógico investigado, compuesto por tres réplicas |
| `checkout-gateway` | punto de entrada y reverse proxy del servicio lógico |
| `checkout-1`, `checkout-2`, `checkout-3` | réplicas de `checkout-api` |
| `pricing-api` | dependencia de pricing |

Arquitectura que puede conocer el investigador:

```text
                      ┌──────────────┐
                      │ load-generator│
                      └───────┬──────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ checkout-gateway │
                    └────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         checkout-1      checkout-2      checkout-3
              │               │               │
              └───────────────┼───────────────┘
                              ▼
                         pricing-api
```

Observabilidad:

```text
services ──metrics──> Prometheus ──> Grafana
services ──logs─────> shared log volume ──> investigator
```

---

# 5. Arquitectura física real

Internamente existe una diferencia que el investigador **no conoce inicialmente**:

```text
checkout-1 ────────────────────────► pricing-api

checkout-2 ────────────────────────► pricing-api

checkout-3 ──► Toxiproxy ─────────► pricing-api
                    │
                    └── +800 ms downstream latency
```

`checkout-3` debe parecer externamente equivalente a las otras dos instancias.

---

# 6. Redes Docker

Usar **dos redes diferentes**.

## `operator_net`

Visible desde el entorno del investigador.

Participan:

* gateway/checkout-api;
* checkout-1;
* checkout-2;
* checkout-3;
* pricing-api;
* Prometheus;
* Grafana;
* investigator.

Toxiproxy **no participa** de esta red.

---

## `fault_net`

Red interna del escenario.

Participan únicamente:

* checkout-3;
* pricing-api;
* Toxiproxy.

Toxiproxy no debe ser:

* resolvible desde `operator_net`;
* visible desde el investigator;
* accesible desde OpenCode;
* documentado en el workspace de investigación.

---

# 7. Servicios

## 7.1 `checkout-gateway`

Punto de entrada del servicio lógico `checkout-api`. Es un reverse proxy mínimo cuya única responsabilidad es repartir tráfico de forma determinista:

```text
request 1 → checkout-1
request 2 → checkout-2
request 3 → checkout-3
request 4 → checkout-1
...
```

### Requisitos

* round-robin estricto;
* contador atómico;
* sin retries;
* sin circuit breaker;
* sin sticky sessions;
* preservar request ID;
* pasar códigos HTTP sin transformaciones;
* `/healthz`;
* `/metrics`.

No debe revelar al cliente qué backend atendió la request.

---

# 8. checkout-api

Tres instancias ejecutando **exactamente el mismo binario**.

Endpoints mínimos:

```text
GET /healthz
GET /checkout
GET /metrics
GET /debug/upstream
```

## `/checkout`

Proceso:

```text
request
  ↓
checkout
  ↓
pricing-api /price
  ↓
respuesta
```

Timeout hacia pricing:

> **500 ms**

Si pricing responde antes:

```http
200 OK
```

Si se supera el timeout:

```http
504 Gateway Timeout
```

El error interno debe ser equivalente a:

```text
context deadline exceeded
```

---

# 9. `pricing-api`

Servicio deliberadamente sano.

Endpoints:

```text
GET /healthz
GET /price
GET /metrics
```

`/price` introduce aproximadamente:

> **40 ms de procesamiento**

de manera determinista.

Debe responder:

```http
200 OK
```

durante todo el incidente.

Nunca debe introducir errores propios.

---

# 10. Fault injection

Usar **Toxiproxy**.

Proxy conceptual:

```text
listen: :8666
upstream: pricing-api:8080
```

Solo `checkout-3` utiliza este path.

## Toxic

Tipo:

> **latency**

Dirección:

> **downstream**

Latencia:

> **800 ms**

Jitter:

> **0**

Toxicity:

> **100 %**

La elección de `downstream` es intencional:

```text
checkout-3
   ↓ request
Toxiproxy
   ↓
pricing-api
   ↓ ~40ms response
Toxiproxy
   ↓ +800ms
checkout-3
```

Así:

* `pricing-api` procesa correctamente;
* las métricas de pricing muestran ~40 ms;
* checkout espera;
* a los ~500 ms vence su timeout;
* checkout genera 504.

Esto produce evidencia especialmente útil:

> **pricing está sano pero checkout observa timeout hacia pricing.**

---

# 11. Estado sano

Con toxic deshabilitado:

```text
checkout-1 → pricing → OK
checkout-2 → pricing → OK
checkout-3 → pricing → OK
```

Requisitos:

* error rate total ≈ 0 %;
* error por instancia ≈ 0 %;
* pricing error rate ≈ 0 %;
* pricing p95 < 100 ms.

---

# 12. Estado degradado

Con toxic habilitado:

```text
checkout-1 → OK
checkout-2 → OK
checkout-3 → TIMEOUT
```

Resultado esperado:

```text
overall error rate ≈ 33.3%

checkout-1 ≈   0% errors
checkout-2 ≈   0% errors
checkout-3 ≈ 100% errors
```

`pricing-api` continúa:

```text
error rate ≈ 0%
p95 ≈ 40 ms
```

---

# 13. Load generator

Debe generar tráfico **constante y reproducible**.

Recomendación:

> ~6 requests/segundo.

Características:

* ticker a intervalo fijo;
* generación independiente del tiempo de respuesta;
* concurrencia limitada;
* request IDs únicos;
* no retries;
* mismo endpoint siempre;
* ejecución continua.

El gateway garantiza el reparto exacto sobre cualquier secuencia consecutiva de requests cuyo tamaño sea múltiplo de tres.

Para una verificación controlada de 90 requests, el load generator debe pausarse temporalmente:

```text
checkout-1 = 30
checkout-2 = 30
checkout-3 = 30
```

Con falla:

```text
success = 60
errors  = 30
```

Durante la operación normal y la grabación, el load generator permanece activo y los dashboards muestran valores temporales aproximados.

---

# 14. IDs y correlación

Cada request debe llevar:

```http
X-Request-ID
```

Debe conservarse:

```text
loadgen
→ gateway
→ checkout
→ pricing
```

Los logs deben contener ese ID.

Esto permite correlacionar evidencia sin introducir tracing distribuido.

---

# 15. Logging

Formato:

> **JSON Lines**

Ejemplo checkout exitoso:

```json
{
  "timestamp": "...",
  "level": "info",
  "service": "checkout",
  "instance": "checkout-1",
  "request_id": "...",
  "event": "pricing_call",
  "upstream": "pricing-api",
  "duration_ms": 43,
  "outcome": "success"
}
```

Timeout:

```json
{
  "timestamp": "...",
  "level": "error",
  "service": "checkout",
  "instance": "checkout-3",
  "request_id": "...",
  "event": "pricing_call",
  "upstream": "pricing-api",
  "duration_ms": 500,
  "outcome": "timeout",
  "error": "context deadline exceeded"
}
```

Pricing:

```json
{
  "timestamp": "...",
  "service": "pricing",
  "request_id": "...",
  "duration_ms": 40,
  "status": 200
}
```

## Restricción crítica

Los logs **nunca** deben incluir:

* URL física real utilizada por checkout-3;
* hostname de Toxiproxy;
* palabras `toxiproxy`, `toxic`, `fault`;
* `800ms injected`;
* información que revele la solución.

Deben decir:

> `pricing-api`

como nombre lógico de la dependencia.

---

# 16. Acceso a logs

Los servicios escriben además de stdout a un volumen compartido:

```text
/logs/
  gateway.jsonl
  checkout-1.jsonl
  checkout-2.jsonl
  checkout-3.jsonl
  pricing.jsonl
  loadgen.jsonl
```

El container `investigator` monta el volumen como:

> **read-only**

Ejemplo:

```bash
tail -n 100 /var/log/lab/checkout-3.jsonl | jq .
```

No es necesario Docker socket para investigar.

---

# 17. Métricas

Scrape interval de Prometheus:

> **5 segundos**

Las ventanas de dashboards y aceptación usan `rate(...[30s])`.

El label de réplica debe llamarse `checkout_instance`; no usar `instance`, porque Prometheus lo reserva para identificar el target de scrape.

Todas las combinaciones declaradas de labels y outcomes deben inicializarse en cero. Así, los dashboards muestran `0` en estado sano en lugar de `No data`.

## Slice aprobada: Phase 4.1 — métricas de checkout

Esta slice implementa solamente las métricas de checkout y permite validar su endpoint `/metrics` directamente. Las métricas de pricing y gateway, los logs, Compose/Prometheus/Grafana y `observability.sh` siguen pendientes; la acceptance completa de Phase 4 y la aceptación real de Prometheus permanecen en Phase 5.

## Checkout

```text
checkout_requests_total{
  checkout_instance,
  outcome="success|error"
}
```

Histograma:

```text
checkout_request_duration_seconds{
  checkout_instance
}
```

Calls hacia pricing:

```text
checkout_pricing_requests_total{
  checkout_instance,
  outcome="success|timeout"
}
```

```text
checkout_pricing_request_duration_seconds{
  checkout_instance
}
```

Los dos histogramas de checkout deben usar estos buckets, en segundos:

```text
0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1
```

---

## Pricing

```text
pricing_requests_total{
  outcome="success|error"
}
```

```text
pricing_request_duration_seconds
```

Buckets, en segundos:

```text
0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5
```

---

## Gateway

Como mínimo:

```text
gateway_requests_total{
  outcome="success|error"
}
```

No es imprescindible mostrar backend en los dashboards iniciales.

---

# 18. Dashboards Grafana

Crear **dos dashboards**. Las siguientes PromQL son parte del contrato y deben quedar versionadas con los dashboards.

## Dashboard 1 — `Lab Overview`

Es el que debe estar abierto inicialmente.

Paneles mínimos:

### Checkout error rate agregado

```promql
sum(rate(checkout_requests_total{outcome="error"}[30s]))
/
sum(rate(checkout_requests_total[30s]))
```

Esperado durante incidente:

> ~33 %

### Checkout p95 latency agregada

```promql
histogram_quantile(0.95,
  sum by (le) (rate(checkout_request_duration_seconds_bucket[30s]))
)
```

Debe mostrar degradación.

### Request rate

```promql
sum(rate(checkout_requests_total[30s]))
```

Confirma que el tráfico no desapareció.

### Pricing error rate

```promql
sum(rate(pricing_requests_total{outcome="error"}[30s]))
/
sum(rate(pricing_requests_total[30s]))
```

Esperado:

> ~0 %

### Pricing p95 latency

```promql
histogram_quantile(0.95,
  sum by (le) (rate(pricing_request_duration_seconds_bucket[30s]))
)
```

Esperado:

> menor a 100 ms y visualmente cercano al bucket de 40–50 ms.

Este dashboard permite formular:

> “checkout está teniendo problemas llamando a pricing, pero pricing parece sano.”

---

## Dashboard 2 — `Checkout by Instance`

No debe mostrarse inicialmente.

Paneles:

### Error rate por instancia

```promql
sum by (checkout_instance) (
  rate(checkout_requests_total{outcome="error"}[30s])
)
/
sum by (checkout_instance) (
  rate(checkout_requests_total[30s])
)
```

```text
checkout-1   ~0%
checkout-2   ~0%
checkout-3 ~100%
```

### Request rate por instancia

```promql
sum by (checkout_instance) (
  rate(checkout_requests_total[30s])
)
```

Debe mostrar reparto aproximadamente igual.

### Pricing-call duration por instancia

```promql
histogram_quantile(0.95,
  sum by (le, checkout_instance) (
    rate(checkout_pricing_request_duration_seconds_bucket[30s])
  )
)
```

Debe hacer visible que checkout-3 observa una duración anormal.

Este dashboard representa el momento:

> **“cambiemos la dimensión.”**

---

# 19. Grafana

Requisitos:

* provisioning automático;
* dashboards versionados;
* datasource Prometheus automático;
* refresh ~5 segundos;
* acceso anonymous viewer para lab local;
* sin configuración manual necesaria.

---

# 20. Investigation workspace

OpenCode trabaja únicamente desde:

```text
/investigator-workspace
```

Contenido:

```text
README.md
INVESTIGATION_PROTOCOL.md
investigation.md
architecture.md
bin/
  promq
```

Opcionalmente:

```text
notes/
```

No contiene:

* Compose;
* source de fault injection;
* Toxiproxy config;
* control scripts;
* implementación del escenario;
* secretos.

---

# 21. `architecture.md`

Debe mostrar únicamente:

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

Información permitida:

* existen 3 réplicas;
* pricing es una dependencia;
* timeout general conocido o descubrible;
* endpoints públicos;
* ubicación de logs;
* Prometheus/Grafana.

No contiene diferencias internas entre réplicas.

---

# 22. Seguridad del escenario frente a OpenCode

OpenCode se debe ejecutar dentro de un container:

> **investigator**

El container:

* pertenece a `operator_net`;
* no pertenece a `fault_net`;
* no monta el repositorio completo;
* no monta `/var/run/docker.sock`;
* no monta directorios padre;
* no puede ejecutar `docker inspect`;
* no puede leer `compose.yaml`;
* no puede resolver `toxiproxy`;
* no puede acceder al admin API de Toxiproxy;
* solo puede leer logs;
* puede consultar servicios, Prometheus y Grafana.

Esto es la **frontera de seguridad principal** del lab.

No depender de decirle al LLM:

> “por favor no mires compose”.

Debe ser técnicamente inaccesible.

---

# 23. OpenCode CLI

El container investigator debe permitir ejecutar OpenCode CLI, instalado desde el paquete npm oficial `opencode-ai`.

Requisitos:

* ni el repositorio ni la imagen contienen credenciales o tokens;
* la autenticación se proporciona en runtime, sin preseleccionar un proveedor de modelos;
* versión del CLI queda fijada durante implementación;
* no usar `latest` sin pinning;
* el container sigue siendo utilizable manualmente aunque OpenCode no esté disponible.

La investigación técnica debe funcionar incluso desde shell.

OpenCode es una **capa sobre el lab**, no una dependencia funcional del escenario.

---

# 24. Protocolo de investigación

Archivo:

```text
INVESTIGATION_PROTOCOL.md
```

Contenido conceptual obligatorio:

### Objetivo

> Reducir incertidumbre mediante evidencia. No adivinar una root cause.

### Reglas

1. Separar hechos de interpretaciones.
2. Mantener un estado de investigación conciso.
3. Generar hipótesis alternativas.
4. Buscar activamente alternativas a la hipótesis dominante.
5. Antes de cada prueba significativa, indicar:

   * hipótesis;
   * predicción si es cierta;
   * prueba propuesta;
   * resultado que la debilitaría.
6. Preferir pruebas:

   * baratas;
   * seguras;
   * de alto valor informativo.
7. No hacer shotgun debugging.
8. No convertir una respuesta del LLM en hecho.
9. Los hechos requieren observación del sistema.
10. Actualizar hipótesis según nueva evidencia.
11. Declarar una hipótesis descartada/depriorizada solo indicando por qué.
12. No declarar root cause solamente porque una explicación sea plausible.
13. Pedir aprobación humana antes de:

* acciones que cambien estado;
* acciones con riesgo;
* pruebas que materialmente cambien la dirección de investigación.

14. Los comandos triviales de lectura pueden ejecutarse una vez explicitada su intención.
15. El objetivo no es certeza absoluta; es reducir suficiente incertidumbre para decidir el próximo paso.

---

# 25. Investigation log

Archivo:

```text
investigation.md
```

Formato obligatorio:

```markdown
# Investigation

## FACTS

## HYPOTHESES

## DISCARDED / DEPRIORITIZED

## NEXT TEST
```

Cada elemento en `DISCARDED / DEPRIORITIZED` debe incluir evidencia.

Ejemplo:

```markdown
- pricing-api globally degraded
  - deprioritized because direct metrics show ~40ms p95 and ~0% errors.
```

El log debe permanecer pequeño.

Objetivo aproximado:

> una pantalla.

---

# 26. Primer estado de investigación esperado

Inicialmente:

```text
FACTS
- checkout-api error rate ≈ 33%
- timeout calling pricing-api

HYPOTHESES — humanas
- pricing-api degradado
- networking
- timeout/configuración
```

Después se pregunta a OpenCode:

> **“¿Qué hipótesis no estamos considerando?”**

Respuestas plausibles:

* una réplica específica;
* routing;
* DNS;
* diferencias de configuración;
* pool/conexiones;
* otros problemas localizados.

No necesitamos forzar una respuesta específica.

---

# 27. Hipótesis esperadas y pruebas disponibles

| Hipótesis                                 | Prueba útil                                   | Resultado esperado                        |
| ----------------------------------------- | --------------------------------------------- | ----------------------------------------- |
| Pricing globalmente degradado             | métricas/health directos                      | debilitada                                |
| Problema global de checkout               | segmentar por instancia                       | debilitada                                |
| Una réplica diferente                     | error rate por instancia                      | gana fuerza                               |
| Timeout/configuración global              | comparar comportamiento entre réplicas        | pierde fuerza                             |
| Problema localizado de networking/routing | comparar llamadas desde cada checkout         | gana fuerza                               |
| DNS                                       | evidencia/logs/pruebas disponibles si aparece | debería perder fuerza o quedar secundaria |

No todas tienen que investigarse durante la grabación.

---

# 28. Secuencia de troubleshooting objetivo

No es un script rígido para OpenCode.

Es la trayectoria pedagógica que el entorno debe permitir.

```text
síntoma agregado
      ↓
hipótesis humanas
      ↓
LLM amplía
      ↓
elegir prueba informativa
      ↓
test pricing
      ↓
pricing sano
      ↓
actualizar hipótesis
      ↓
comparar instancias
      ↓
checkout-3 concentra fallas
      ↓
comparar paths
      ↓
degradación localizada en el path checkout-3 → pricing-api
```

La investigación dentro del sandbox termina cuando la evidencia permite localizar la degradación en ese path. Identificar Toxiproxy o el mecanismo físico exacto de inyección no forma parte del objetivo y debe permanecer inaccesible al investigador.

---

# 29. Endpoints diagnósticos

Para evitar depender de `docker exec`, cada checkout debe ofrecer:

```text
GET /debug/upstream
```

Respuesta conceptual:

```json
{
  "logical_upstream": "pricing-api",
  "outcome": "timeout",
  "elapsed_ms": 500
}
```

En checkout-1:

```json
{
  "logical_upstream": "pricing-api",
  "outcome": "success",
  "elapsed_ms": 42
}
```

## Restricción

Nunca devolver:

* URL real;
* IP del proxy;
* hostname interno;
* Toxiproxy.

Este endpoint representa una prueba diagnóstica desde la perspectiva de la propia instancia.

---

# 30. Scenario control plane

Fuera del workspace del investigador.

Interfaz requerida:

```bash
make start
make healthy-check
make fault-on
make verify
make fault-off
make reset
make stop
make record-ready
```

Los nombres pueden implementarse mediante `labctl`, pero estos comandos deben existir como UX principal.

---

# 31. `make start`

Debe:

1. levantar servicios;
2. esperar healthchecks;
3. configurar Toxiproxy sin toxic;
4. iniciar Prometheus/Grafana;
5. iniciar load generator;
6. validar estado sano.

Resultado:

> HEALTHY.

---

# 32. `make fault-on`

Debe:

1. crear/habilitar toxic downstream latency;
2. esperar suficiente tráfico;
3. validar comportamiento esperado.

Resultado:

> DEGRADED.

---

# 33. `make fault-off`

Elimina/desactiva toxic.

No limpia necesariamente métricas históricas.

Resultado:

> HEALTHY nuevamente.

---

# 34. `make reset`

Reset fuerte y reproducible.

## Implementación actual: Phase 3.3

Para el proyecto fijo del lab, `reset` ejecuta explícitamente `docker compose down --volumes --remove-orphans`, luego usa el `start` existente y su verificación sana. Los contenedores nuevos recrean el proxy con su configuración neutral, sin toxic propiedad del escenario.

Hoy no existen volúmenes de TSDB de Prometheus ni de logs. Esta fase no los declara ni afirma haberlos limpiado.

## Contrato final

Debe:

* detener escenario;
* borrar TSDB de Prometheus;
* limpiar logs;
* resetear toxic;
* reconstruir estado;
* arrancar sano;
* verificar.

Esto sirve para:

* repetir experimentos;
* nuevas grabaciones;
* pruebas automáticas.

---

# 35. `make record-ready`

## Secuenciación aprobada

`record-ready` se difiere intencionalmente hasta que las Phases 4–6 aporten métricas, logs, Grafana e investigator. Mientras tanto, permanece como placeholder explícito que falla; no se implementa una espera temporal como sustituto de evidencia observable.

## Contrato final

Flujo recomendado:

1. reset limpio;
2. levantar sano;
3. mantener ~30 segundos de baseline;
4. habilitar falla;
5. esperar ~45–60 segundos;
6. verificar ~33 % error rate;
7. abrir entorno investigator listo para investigar.

Resultado:

> escenario con evidencia suficiente para comenzar grabación.

---

# 36. `make verify`

Debe pausar temporalmente el load generator, tomar un baseline de contadores, ejecutar exactamente 90 requests consecutivas contra el gateway y comparar los deltas. Debe restaurar el load generator antes de terminar.

### Distribución

```text
checkout-1 = 30
checkout-2 = 30
checkout-3 = 30
```

### Healthy

Si falla deshabilitada:

```text
overall errors = 0
```

### Degraded

Si falla habilitada:

```text
overall errors = 30
checkout-1 errors = 0
checkout-2 errors = 0
checkout-3 errors = 30
```

### Pricing

Siempre:

```text
health = OK
error rate ≈ 0%
p95 < 100ms
```

---

# 37. Acceptance tolerances

El reparto y los outcomes de las 90 requests controladas se validan con conteos exactos. No usar comparaciones exactas sobre métricas temporales de Prometheus o dashboards.

Valores recomendados para observación temporal:

```text
overall degraded error rate:
30% – 36%

checkout-1:
< 2% errors

checkout-2:
< 2% errors

checkout-3:
> 95% errors

pricing:
< 1% errors

pricing p95:
< 100 ms

checkout-3 observed upstream call:
>= 480 ms
```

---

# 38. Health checks

## Gateway

```text
/healthz → 200
```

## Checkout

`/healthz` valida **solo salud local**.

No debe validar pricing.

De otro modo `checkout-3` aparecería unhealthy y revelaría el problema demasiado pronto.

## Pricing

```text
/healthz → 200
```

Prometheus/Grafana:

health estándar.

---

# 39. Estados del escenario

Formalizar:

```text
STOPPED
   ↓ start
HEALTHY
   ↓ fault-on
DEGRADED
   ↓ fault-off
HEALTHY
```

`reset`:

```text
ANY STATE
   ↓
clean HEALTHY
```

---

# 40. Estructura propuesta del repositorio

```text
troubleshooting-lab/
│
├── Makefile
├── README.md
│
├── scenario/
│   ├── compose.yaml
│   │
│   ├── services/
│   │   ├── gateway/
│   │   ├── checkout/
│   │   ├── pricing/
│   │   └── loadgen/
│   │
│   ├── fault/
│   │   ├── toxiproxy/
│   │   └── control/
│   │
│   ├── observability/
│   │   ├── prometheus/
│   │   │   └── prometheus.yml
│   │   └── grafana/
│   │       ├── provisioning/
│   │       └── dashboards/
│   │           ├── overview.json
│   │           └── by-instance.json
│   │
│   └── control/
│       ├── labctl
│       └── verify/
│
├── investigator/
│   ├── Dockerfile
│   ├── README.md
│   ├── architecture.md
│   ├── INVESTIGATION_PROTOCOL.md
│   ├── investigation.md
│   └── bin/
│       └── promq
│
├── docs/
│   ├── acceptance.md
│   ├── recording-runbook.md
│   └── troubleshooting-flow.md
│
└── tests/
    ├── healthy.sh
    ├── degraded.sh
    ├── reset.sh
    ├── isolation.sh
    └── observability.sh
```

---

# 41. Versionado y entorno soportado

No usar:

```text
latest
```

Durante implementación OpenCode debe:

1. seleccionar versiones estables disponibles;
2. fijarlas explícitamente;
3. registrarlas en un archivo equivalente a:

```text
versions.env
```

`versions.env` es la fuente de versiones para imágenes y herramientas. Las dependencias de módulos Go se fijan en `go.mod` y sus checksums generados quedan en `go.sum`; no se duplican en `versions.env`.

Ejemplo conceptual:

```text
GRAFANA_VERSION=x.y.z
PROMETHEUS_VERSION=x.y.z
TOXIPROXY_VERSION=x.y.z
OPENCODE_CLI_VERSION=x.y.z
```

Entorno soportado:

* Docker Engine o Docker Desktop con Docker Compose v2;
* Linux y macOS;
* arquitecturas `amd64` y `arm64`;
* `make`, `curl` y Docker disponibles en el host;
* imágenes con versión concreta y soporte para ambas arquitecturas.

Una vez elegidas, todos los tests deben ejecutarse sobre esas versiones. La implementación debe registrar la combinación de versiones efectivamente validada.

---

# 42. Código de servicios

Recomendación:

> **Go**

Motivos:

* binarios simples;
* concurrencia sencilla;
* `context.WithTimeout`;
* Prometheus client maduro;
* imágenes pequeñas;
* comportamiento determinista;
* poco runtime.

No es una exigencia pedagógica, pero debería ser el default de implementación.

OpenCode solo debería cambiarlo si aparece un impedimento concreto.

---

# 43. Estrategia de grabación

La sesión real puede durar lo necesario.

La grabación final del workshop mostrará solo decisiones relevantes.

## Momento 1 — AMPLIAR

Mostrar:

```text
hipótesis humanas
      +
LLM agrega alternativas
```

Pregunta de audiencia:

> **“¿Qué probarías primero?”**

---

## Momento 2 — INTENTAR ROMPER

Mostrar:

```text
pricing está degradado
       ↓
qué evidencia la haría caer
       ↓
prueba
       ↓
pricing sano
```

---

## Momento 3 — ACTUALIZAR

Mostrar:

```text
evidencia
↓
investigation log cambia
↓
comparar instancias
↓
checkout-3 = 100% errors
```

Pregunta:

> **“¿Qué cambió con esta evidencia?”**

---

# 44. Qué acelerar o cortar

Acelerar/cortar:

* escritura larga del modelo;
* instalación;
* tiempos muertos;
* comandos repetidos;
* queries Prometheus largas;
* navegación mecánica;
* logs sin información.

Mantener a velocidad normal:

* formulación de hipótesis;
* decisión de qué probar;
* predicción;
* evidencia;
* actualización;
* cambio de dimensión;
* resolución.

---

# 45. Diseño de pantalla para grabación

Preferencia:

### Terminal

OpenCode + investigation log.

### Browser

Grafana.

Evitar muchas ventanas.

Una grabación de escritorio completa permite luego editar:

* zoom a terminal;
* zoom a Grafana;
* overlays conceptuales.

Resolución recomendada:

> 1440p o superior.

Texto suficientemente grande para streaming.

---

# 46. Criterios pedagógicos de aceptación

El lab **no está terminado** solo porque produce 33 % de errores.

Está terminado cuando una investigación permite naturalmente:

* empezar con hechos;
* generar 2–3 hipótesis humanas;
* pedir alternativas al LLM;
* obtener hipótesis razonables pero no necesariamente correctas;
* seleccionar pruebas por información;
* debilitar `pricing degradado`;
* actualizar el investigation log;
* cambiar observación de agregado a por instancia;
* descubrir `checkout-3`;
* localizar el problema en su path;
* llegar a una conclusión mediante evidencia.

---

# 47. Criterios de aislamiento

Desde investigator:

Debe fallar:

```bash
docker ps
```

o no existir Docker socket.

Debe fallar:

```bash
cat ../scenario/compose.yaml
```

porque el path no existe/monta.

Debe fallar:

```bash
getent hosts toxiproxy
```

Debe ser imposible acceder:

```text
Toxiproxy admin API
```

No debe existir en environment ninguna variable con:

```text
TOXIPROXY
FAULT
BROKEN_INSTANCE
INJECTED_LATENCY
```

---

# 48. Tests automáticos mínimos

Los tests de distribución pausan el load generator, ejecutan exactamente 90 requests consecutivas y lo restauran al finalizar. Los conteos de esa secuencia son deterministas; las tolerancias de la sección 37 se reservan para Prometheus y dashboards.

## `healthy.sh`

Verifica:

* stack sano;
* 90 requests;
* reparto 30/30/30;
* 0 errores;
* pricing sano.

## `degraded.sh`

Verifica:

* fault activo;
* 90 requests;
* exactamente 30 fallan;
* las 30 fallas corresponden a checkout-3;
* pricing sano.

## `reset.sh`

Secuencia:

```text
healthy
→ fault
→ degraded
→ reset
→ healthy
→ fault
→ degraded
```

Debe reproducirse.

## `isolation.sh`

Ejecutado dentro de investigator:

* no compose;
* no Docker socket;
* no toxiproxy DNS;
* no admin API;
* no fault config.

## `observability.sh`

Valida que Prometheus contiene:

* agregado;
* por instancia;
* pricing;
* latencias;
* errors.

---

# 49. Implementation Plan for OpenCode

## Phase 0 — Scaffold y contrato

### Objetivo

Crear estructura del repo y acceptance tests vacíos.

### Crear

* árbol de directorios;
* Makefile;
* docs;
* test harness;
* version pinning.

### Criterio

```bash
make help
```

muestra todas las operaciones previstas.

---

## Phase 1 — Servicios sanos

### Implementar

* pricing;
* checkout;
* gateway;
* loadgen.

Sin Toxiproxy todavía.

### Validar

```text
90 requests controladas
30/30/30
0 failures
```

### Acceptance

`tests/healthy.sh` pasa.

---

## Phase 2 — Fault injection

### Implementar

* `fault_net`;
* Toxiproxy;
* path checkout-3;
* toxic downstream 800 ms;
* fault-on/fault-off.

### Acceptance

* checkout1 OK;
* checkout2 OK;
* checkout3 timeout;
* pricing sano;
* overall ~33%.

`tests/degraded.sh` pasa.

---

## Phase 3 — Reset y control

Implementar:

```text
start
fault-on
fault-off
verify
reset
stop
record-ready
```

### Secuenciación aprobada

Phase 3.3 implementa `reset`. `record-ready` conserva su contrato final, pero se difiere a las Phases 4–6 porque requiere observabilidad e investigator reales. Esta excepción no completa Phase 3.

### Acceptance de Phase 3.3

`tests/reset.sh` pasa repetidamente.

Mínimo:

> 5 ciclos consecutivos sin comportamiento diferente.

---

## Phase 4 — Metrics y logs

Implementar:

* métricas Prometheus;
* structured JSON logs;
* shared read-only log volume;
* request IDs.

### Slice aprobada: Phase 4.1

Implementar solo las métricas de checkout y validarlas directamente en `/metrics`. Esta slice no completa métricas de pricing o gateway, logs, el suite `observability.sh` ni la acceptance final de Phase 4; Prometheus y su aceptación efectiva siguen en Phase 5.

### Acceptance

Se puede demostrar desde datos:

* pricing sano;
* overall ~33%;
* checkout-3 concentra errores.

---

## Phase 5 — Prometheus + Grafana

Implementar provisioning automático.

Dashboards:

* overview;
* by-instance.

### Acceptance

Después de `make record-ready`:

Overview muestra:

> ~33% errors + pricing sano.

By-instance muestra:

> 0 / 0 / 100.

Sin configuración manual.

---

## Phase 6 — Investigator sandbox

Crear container investigator.

Instalar:

* shell;
* curl;
* jq;
* dig/getent;
* grep/rg;
* herramientas básicas;
* OpenCode CLI (paquete npm `opencode-ai`).

Montar:

* workspace;
* logs read-only.

No montar:

* repo;
* Docker socket;
* scenario.

### Acceptance

`tests/isolation.sh` pasa.

---

## Phase 7 — Investigation protocol

Crear:

```text
INVESTIGATION_PROTOCOL.md
investigation.md
architecture.md
```

Validar manualmente una investigación usando shell antes de usar OpenCode.

### Acceptance

La degradación puede localizarse en el path `checkout-3 → pricing-api` usando únicamente información disponible al investigador. No se exige descubrir el mecanismo físico exacto.

---

## Phase 8 — OpenCode dry run

Ejecutar una investigación real.

No dirigirlo hacia la respuesta.

Evaluar:

* hipótesis generadas;
* pruebas propuestas;
* respeto de evidence boundary;
* mantenimiento del log;
* tendencia a shotgun debugging.

Ajustar solamente el **protocolo**, no darle pistas del escenario.

---

## Phase 9 — Pedagogical acceptance

Realizar múltiples sesiones.

El lab se considera pedagógicamente válido si al menos una sesión produce naturalmente:

> **ampliar → intentar romper → actualizar**

sin que OpenCode lea la solución.

No se exige que todas las ejecuciones sigan exactamente el mismo camino.

---

## Phase 10 — Recording runbook

Crear procedimiento reproducible:

```bash
make record-ready
make investigate
```

Abrir:

* Grafana Overview;
* terminal con OpenCode.

Ejecutar sesión.

Guardar grabación original sin editar.

---

# 50. Riesgos y mitigaciones

| Riesgo                                        | Mitigación                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------ |
| OpenCode encuentra Toxiproxy leyendo archivos | sandbox real, no instrucciones                                           |
| OpenCode llega inmediatamente a checkout-3    | aceptar la hipótesis, exigir evidencia; humano decide prueba informativa |
| Grafana revela checkout-3 demasiado pronto    | Overview agregado como dashboard inicial                                 |
| Pricing parece lento por el proxy             | usar latency downstream; pricing mide solo su procesamiento              |
| Load distribution fluctúa                     | gateway round-robin determinista                                         |
| Reset conserva métricas viejas                | borrar TSDB/logs en reset fuerte                                         |
| OpenCode hace shotgun debugging               | protocolo obliga hypothesis/prediction/test                              |
| Lab parece tutorial de networking             | resolución comprimida                                                    |
| Grabación depende de OpenCode en vivo         | grabar previamente múltiples tomas                                       |
| Versiones cambian                             | pins exactos; nunca latest                                               |
| Logs revelan proxy                            | usar nombres lógicos y tests anti-leak                                   |
| Demasiados componentes                        | rechazar cualquier componente que no cambie una decisión pedagógica      |

---

# 51. Definition of Done

El lab está terminado únicamente cuando todas estas afirmaciones son verdaderas:

```text
[ ] make start produce estado sano
[ ] estado sano tiene ~0% errors
[ ] 90 requests controladas se distribuyen exactamente 30/30/30
[ ] make fault-on produce falla determinista
[ ] error rate agregado ronda 33%
[ ] checkout-1 permanece sano
[ ] checkout-2 permanece sano
[ ] checkout-3 falla de forma consistente
[ ] pricing permanece sano
[ ] checkout-3 timeout ≈ 500ms
[ ] Prometheus refleja correctamente el escenario
[ ] Grafana Overview no revela inmediatamente la instancia
[ ] Grafana by-instance revela claramente checkout-3
[ ] logs aportan evidencia sin revelar Toxiproxy
[ ] investigator no puede acceder a la configuración de falla
[ ] OpenCode puede investigar usando herramientas reales
[ ] investigation log puede mantenerse durante la sesión
[ ] pricing-degraded puede ser debilitada mediante evidencia
[ ] global-checkout-problem puede ser debilitada
[ ] problema puede localizarse en checkout-3
[ ] degradación puede localizarse en el path checkout-3 → pricing-api
[ ] la investigación no requiere revelar Toxiproxy ni el mecanismo físico exacto
[ ] reset reproduce un estado limpio
[ ] cinco ciclos fault/reset consecutivos funcionan
[ ] sesión completa puede grabarse
[ ] grabación contiene ampliar/falsar/actualizar
```

---

# 52. Material para el repositorio público

Una vez grabado el workshop, el mismo repo puede ofrecer:

```text
README
lab
protocol
investigation template
dashboards
runbook
references
```

La audiencia podrá ejecutar el escenario después.

Durante la sesión no hacemos un tour del repo.

---

# 53. Prompt inicial esperado para la sesión de troubleshooting

No debe contener la solución.

Conceptualmente:

> Tenemos un incidente en `checkout-api`.
> El error rate agregado está alrededor del 33 % y vemos timeouts cuando checkout llama a pricing.
> Estos son los hechos conocidos y estas son nuestras hipótesis iniciales.
>
> Quiero que trabajes siguiendo `INVESTIGATION_PROTOCOL.md` y mantengas `investigation.md`.
>
> Primero, buscá hipótesis relevantes que no estemos considerando. No elijas todavía una root cause ni conviertas ninguna hipótesis en un hecho.

Después la investigación sigue con evidencia.

---

# 54. Regla final para el implementador OpenCode

Cuando OpenCode reciba esta especificación para construir el lab:

> **No debe optimizar por “encontrar otra arquitectura mejor”.**

Debe optimizar por:

1. simplicidad;
2. determinismo;
3. aislamiento de la causa;
4. observabilidad;
5. reproducibilidad;
6. valor pedagógico.

Si una alternativa hace el lab técnicamente más sofisticado pero pedagógicamente menos claro:

> **se rechaza.**

---

## READY FOR OPENCODE: **YES**

La arquitectura, comportamiento, fault, observabilidad, frontera de investigación, secuencia pedagógica, tests y criterios de aceptación están suficientemente definidos para pasar a implementación.

El siguiente paso es entregarle esta especificación a OpenCode con una instrucción corta:

> **Implementá este lab por fases siguiendo exactamente la especificación. No avances de fase hasta que pasen sus criterios de aceptación. No modifiques la arquitectura ni agregues componentes salvo que exista un bloqueo técnico; si aparece uno, detenete, explicá el bloqueo y proponé la mínima desviación necesaria.**
