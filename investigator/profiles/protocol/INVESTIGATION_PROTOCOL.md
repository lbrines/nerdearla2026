# Protocol Method

Protocol applies this sequence:

> **FACTS → HYPOTHESES → PREDICTION → TEST → FALSIFIER → EVIDENCE → UPDATE**

## Evidence discipline

- Label observed system evidence as facts; keep inferences and unconfirmed hypotheses distinct.
- Treat an LLM or model response as unconfirmed until a system observation supports it; it is not a fact on its own.
- Retain `request_id` when correlating evidence.
- Maintain alternatives and actively try to falsify them. Before each significant test, state its hypothesis, prediction, test, and falsifier.
- Prefer cheap, safe, high-information tests.
- Do not use shotgun debugging.
- Update, discard, or deprioritize hypotheses only when the evidence supports it.
- Do not declare root cause merely because an explanation is plausible.
- Reduce uncertainty enough to choose the next step; do not seek absolute certainty.

## READ-ONLY

Use only read-only actions. Never execute state-changing actions.

## LOGICAL DIAGNOSIS

State conclusions only at the logical service level and identify the supporting observed evidence.

## PHYSICAL MECHANISM

Keep any unobserved physical mechanism separate from the logical diagnosis and mark it as unconfirmed.

## PENDING APPROVAL

List mitigations only as pending human approval.

The method does not prescribe an investigation order, services, replicas, queries, hypotheses, expected answers, or conclusions.
