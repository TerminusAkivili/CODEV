---
name: codev-gate
description: Use when a CO-DEV project reaches a review boundary or before continuing after a pending human approval decision
---

# CO-DEV Gate

Human gates prevent drift. They should be cheap enough that humans keep using them.

## Law

```text
No approval, no next module.
```

Applies to every gate except `Gate: free`.

AI provides evidence and recommendations; the human owns validation. Automated tests, screenshots, and agent confidence can support a gate, but they cannot replace human approval.

A gate packet must name the thing the human should experience, not just the files changed or commands passed.

## Light Gate Packet

Default to chat:

```text
Gate: gate-id
Done: one line
Evidence: command, screenshot, file, or behavior
Inspect: exact thing the human should try
Decision: approved / redirected / rejected
```

Do not create a review file in `Ceremony: light` unless the human asks.

## Decision Rules

- `approved` or clear equivalent: continue.
- `redirected`: update `.codev.md`, then adjust.
- `rejected`: stop and correct.
- Ambiguous response or silence: not approved.

## Friction Check

If the human complains about process weight, use `codev-drift`. The ceremony is probably too heavy.
