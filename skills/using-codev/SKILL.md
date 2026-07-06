---
name: using-codev
description: Use when starting or continuing AI-assisted development where human intent, lightweight project shape, approval gates, ceremony weight, review friction, or drift may matter
---

# Using CO-DEV

CO-DEV keeps AI-assisted development accountable without turning every step into paperwork.

## State

Look for `.codev.md`. If missing, use `codev-shape` to prefill one compact file.

Required fields:

- `Gate: ultra|strict|normal|loose|free`
- `Ceremony: light|standard|audit`
- `Current gate: none|gate-id`
- `Decision: pending|approved|redirected|rejected`

Default recommendation: `Gate: normal`, `Ceremony: light`. If the human chooses `ultra`, keep ceremony light unless they request audit detail.

## Routing

- Need initial intent/shape/trace: use `codev-shape`.
- Reached a review boundary: use `codev-gate`.
- Human says the process is heavy, wrong, or drifting: use `codev-drift`.

## Principle

Gate frequency and paperwork weight are separate:

- Frequency: `ultra`, `strict`, `normal`, `loose`, `free`
- Ceremony: `light`, `standard`, `audit`

Stop often when needed. Write little by default.
