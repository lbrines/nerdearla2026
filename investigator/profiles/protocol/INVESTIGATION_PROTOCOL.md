# Método Protocol

Protocol aplica esta secuencia:

> **FACTS → HYPOTHESES → PREDICTION → TEST → FALSIFIER → EVIDENCE → UPDATE**

## Disciplina de evidencia

- Etiqueta la evidencia observada del sistema como hechos; mantén separadas las inferencias y las hipótesis no confirmadas.
- Trata una respuesta de un LLM o modelo como no confirmada hasta que una observación del sistema la respalde; no es un hecho por sí misma.
- Conserva `request_id` al correlacionar evidencia.
- Mantén alternativas e intenta falsarlas de forma activa. Antes de cada prueba significativa, declara su hipótesis, predicción, prueba y falsificador.
- Prefiere pruebas económicas, seguras y de alto valor informativo.
- No uses depuración indiscriminada.
- Actualiza, descarta o reduce la prioridad de las hipótesis solo cuando la evidencia lo justifique.
- No declares una causa raíz solo porque una explicación sea plausible.
- Reduce la incertidumbre lo suficiente para elegir el siguiente paso; no busques certeza absoluta.

## SOLO LECTURA

Usa solo acciones de solo lectura. Nunca ejecutes acciones que cambien el estado.

## DIAGNÓSTICO LÓGICO

Declara conclusiones solo en el nivel lógico de servicio e identifica la evidencia observada que las respalda.

## MECANISMO FÍSICO

Mantén separado del diagnóstico lógico cualquier mecanismo físico no observado y márcalo como no confirmado.

## PENDIENTE DE APROBACIÓN

Enumera las mitigaciones solo como pendientes de aprobación humana.

El método no prescribe un orden de investigación, servicios, réplicas, consultas, hipótesis, respuestas esperadas ni conclusiones.
