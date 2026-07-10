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

Execution skills cannot close this gate. Planning, TDD, debugging, review, build, install, or screenshot skills may strengthen the evidence, but only the human can approve, redirect, or reject the next batch.

Decision gate must be exactly identical to Current gate for an active gate. Gate identity uses ordinal, case-sensitive comparison without Unicode normalization; never reuse or normalize an approval from a different gate identifier. The reserved no-gate sentinel is exactly lowercase `none`.

A gate packet must name the thing the human should experience, not just the files changed or commands passed.

`Gate: normal` is not a gate for every code-level change. Do not block on ordinary functions, helpers, interfaces, or refactors unless they create a human-visible behavior change. In normal mode, the review boundary is a demonstrable batch of related functionality.

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
- Single-letter y means yep/approved and is a valid compact approval.
- `redirected`: update `.codev.md`, then adjust.
- `rejected`: stop and correct.
- Ambiguous response or silence: not approved.

## Friction Check

If the human complains about process weight, use `codev-drift`. The ceremony is probably too heavy.
