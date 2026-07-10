---
name: using-codev
description: Use when starting or continuing AI-assisted development where human intent, lightweight project shape, approval gates, ceremony weight, review friction, or drift may matter
---

# Using CO-DEV

CO-DEV keeps AI-assisted development accountable without turning every step into paperwork.

## Explicit Activation

If the human asks to start, use, enable, or launch CodeV, load `.codev.md` and this `using-codev` skill before any other execution workflow.

Plain rule: load .codev.md and this using-codev skill before any other execution workflow.

Treat CodeV like an active project rule layer, not ambient memory. Do not rely on prior conversation state, project familiarity, or another workflow skill as proof that CO-DEV is active.

When another workflow is also requested, activate CO-DEV first, bind it to the active project root, then run the requested execution workflow under the recorded `Execution engine:`.

## State

Look for `.codev.md`. If missing, use `codev-shape` to prefill one compact file.

Required fields:

- `Gate: ultra|strict|normal|loose|free`
- `Ceremony: light|standard|audit`
- `Execution engine: default|superpower|codex|cursor|custom:<name>`
- `Current gate: none|gate-id`
- `Decision: pending|approved|redirected|rejected`
- `Decision gate: none|gate-id`

Decision gate must exactly match Current gate when a gate is active. State transitions are explicit: a new gate means `Decision: pending` plus the matching `Decision gate`; no gate means `Decision: pending` plus `Decision gate: none`.

Default recommendation: `Gate: normal`, `Ceremony: light`. If the human chooses `ultra`, keep ceremony light unless they request audit detail.

## Real Project Binding

Before any code edit in a real project, bind CO-DEV to the active project root:

1. Look for `.codev.md` in the project being edited, not in a demo, plugin, or previous workspace.
2. If missing, use `codev-shape` to create the compact file before implementation.
3. Evaluate whether current intent/shape matches the requested change.

After implementation work, append one short Trace line: change, evidence, drift if any, next gate.

Do not treat tests, builds, or installs as a replacement for the human gate. They are evidence only.

At the configured boundary, present a light gate packet and stop unless the human approves.

For `Gate: normal`, the boundary is a demonstrable functionality batch, not every internal function, helper, interface, refactor, or implementation detail. Stop only when the human can meaningfully open, try, compare, approve, or redirect the product behavior.

## Multi-Skill Composition

CO-DEV is the governance layer, not the only execution skill.

Other skills may be used for engineering execution: planning, TDD, debugging, review, implementation, refactoring, or platform-specific workflows. Record the active execution layer in `Execution engine:` when it materially affects the work.

They cannot advance, skip, downgrade, or satisfy a CO-DEV gate. They also cannot convert human validation into automated evidence. When another execution skill conflicts with CO-DEV, CO-DEV owns intent, gate frequency, trace, drift handling, and the next-batch decision.

When reporting work, state both layers briefly:

```text
CO-DEV: active, gate normal, ceremony light
Execution engine: superpower
Gate status: pending human review
```

## Routing

- Need initial intent/shape/trace: use `codev-shape`.
- Reached a review boundary: use `codev-gate`.
- Human says the process is heavy, wrong, or drifting: use `codev-drift`.

## Principle

Gate frequency and paperwork weight are separate:

- Frequency: `ultra`, `strict`, `normal`, `loose`, `free`
- Ceremony: `light`, `standard`, `audit`

Stop often when needed. Write little by default.
