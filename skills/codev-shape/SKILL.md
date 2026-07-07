---
name: codev-shape
description: Use when quickly prefilling or updating lightweight CO-DEV state, intent, project shape, gate level, ceremony weight, next slice, or trace in a single .codev.md file
---

# CO-DEV Shape

Shape is the smallest useful project state, not a document farm.

## Default File

Use `.codev.md` unless the human asks for split docs.

```markdown
# CO-DEV

Gate: normal
Ceremony: light
Execution engine: default
Current gate: none
Decision: pending

## Intent
What the human wants.

## Shape
Coarse roadmap only: phase, subsystem, next gate.

## Trace
- Fine trace: one short line per small change.
```

## Rules

- Prefill fast; do not interrogate the human unless a choice blocks progress.
- Evaluate intent/shape fit before implementation: state whether the proposed shape actually satisfies the human intent, then ask for correction if the fit is uncertain.
- Execution engine records which development skill or tool layer is allowed to help implementation; it does not own approval, gate frequency, or validation.
- In `Gate: normal`, set the next gate at a demonstrable functionality batch, not at an ordinary function, helper, interface, refactor, or implementation detail.
- Split into multiple docs only for `Ceremony: audit`, high risk, or explicit request.
- Update intent/shape only when they actually change.
- For normal module progress, append one trace line.
- Roadmap/shape is big-picture and coarse-grained. Do not log every task there.
- Trace is small and fine-grained, but still brief. One line is usually enough: change, evidence, drift, next.
- Do not duplicate the same status across shape and trace.
