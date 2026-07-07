---
name: codev-drift
description: Use when CO-DEV process, implementation, tests, project shape, gate frequency, ceremony weight, or human feedback indicates drift, excess friction, wrong direction, or mismatch with intent
---

# CO-DEV Drift

Drift includes product mismatch and process mismatch.

## Types

| Type | Meaning |
|---|---|
| Product drift | Built behavior misses human intent. |
| Shape drift | Plan/architecture no longer explains the work. |
| Test drift | Evidence proves the wrong thing. |
| Gate drift | Review frequency is wrong. |
| Ceremony drift | Paperwork is too heavy or too weak. |
| Granularity drift | Roadmap became a task log, or trace became a long report. |

## Correction

1. Name the drift.
2. Change the smallest thing that fixes it.
3. Prefer reducing ceremony before reducing human review.
4. Append one `.codev.md` trace line.
5. Resume only after the human's direction is clear.

## Key Rule

`ultra` means frequent human review. It does not mean frequent paperwork.

Roadmap is coarse. Trace is fine but brief.
