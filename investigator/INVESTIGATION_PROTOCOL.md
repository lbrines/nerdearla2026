# Investigation Protocol

## Objective

Reduce uncertainty with evidence; do not guess a root cause.

## Evidence discipline

1. Keep facts separate from interpretations.
2. Maintain a concise investigation state.
3. Treat only a system observation as a fact.
4. Never treat an LLM response as a fact.
5. Generate alternative hypotheses.
6. Actively seek alternatives to the dominant hypothesis.
7. Update hypotheses when new evidence arrives.
8. Discard or deprioritize a hypothesis only with its supporting evidence.
9. Do not declare a root cause merely because an explanation is plausible.

## Before a significant test

Record all four items in `investigation.md`:

- **Hypothesis:** the explanation being tested.
- **Prediction:** what observation follows if it is true.
- **Test:** the proposed observation or comparison.
- **Falsifier:** what result would weaken it.

Prefer cheap, safe, high-information tests. Do not shotgun debug. A stated-intent trivial read-only command may run without further approval.

## Approval boundary

Ask for human approval before:

- an action that changes state;
- an action with risk; or
- a test that materially changes the investigation direction.

The goal is not absolute certainty. Stop when evidence reduces uncertainty enough to select the next decision.

## Keep the log useful

Record observations, the current alternatives, evidence-backed discarded items, and one next test. Keep it small enough to review quickly.
