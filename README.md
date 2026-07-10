# CO-DEV

CO-DEV is a lightweight Human Accountability Harness for AI-assisted software development.

AI cannot read your mind. A loop engine can keep working, a harness agent can keep dispatching tasks, and a plan can look clean while the product slowly drifts away from what you actually wanted. CO-DEV prevents that drift by making the agent stop at chosen boundaries and ask the human to inspect the product.

## Why

I had documents, architecture notes, trace logs, a roadmap, and a working Android version. Then I spent one day trying to migrate the product to Windows with AI.

The failure was slow. Each subsystem looked almost reasonable. By the time the drift was obvious, it was no longer one bug. It was the shape of the system.

CO-DEV exists because better instructions are not enough. Human checkpoints must be cheap enough to use and strict enough to stop drift.

## Core Position

CodeV is the governance layer for AI-assisted development, not the code-writing executor. It keeps AI work bound to the right project, the right phase, and the right human checkpoint so implementation does not drift away from the human's intent.

- CodeV manages direction: what the human wants, which batch is active, and when work must stop for human review.
- Superpowers / Codex manage execution: TDD, debugging, implementation, verification, builds, and other engineering workflows.
- Humans own approval: tests passing, builds succeeding, installs, screenshots, and agent confidence are evidence only; they cannot replace a human saying the batch is approved.

## Project Architecture

```text
codev/
  README.md
  templates/
    codev.md
  skills/
    using-codev/
      SKILL.md
    codev-shape/
      SKILL.md
    codev-gate/
      SKILL.md
    codev-drift/
      SKILL.md
  scripts/
    codev.ps1
    codev-check-gate.ps1
  tests/
    run-codev-v02-structure-tests.ps1
    run-codev-check-gate-tests.ps1
  .codex-plugin/
    plugin.json
  .claude-plugin/
    plugin.json
    marketplace.json
  .cursor-plugin/
    plugin.json
```

### `.codev.md`: Project State

`.codev.md` is the core runtime state file. It lives at the root of the project being developed, not inside a demo folder or previous workspace.

```text
Gate: normal
Ceremony: light
Execution engine: superpower
Current gate: batch-windows-main-shell
Decision: pending
Decision gate: batch-windows-main-shell
```

The six required metadata fields are:

- `Gate`: how often AI work must stop for human inspection.
- `Ceremony`: how heavy the notes and review packet should be.
- `Execution engine`: the active implementation layer, such as `superpower`.
- `Current gate`: the active human checkpoint.
- `Decision`: whether the human has approved, redirected, rejected, or left the gate pending.
- `Decision gate`: the gate identifier to which the decision belongs.

Decision gate must exactly match Current gate when a gate is active. A new gate starts with `Decision: pending` and the matching `Decision gate`; no active gate requires `Decision: pending` and `Decision gate: none`.

The file has three working sections:

- `Intent`: what the human actually wants.
- `Shape`: the current phase, subsystem, and next checkpoint.
- `Trace`: one short line per implementation batch.

### `skills/`: Behavior Rules

CodeV currently has four skills:

- `using-codev`: entry rule. If the human asks to start, use, enable, or launch CodeV, the agent must load `.codev.md` and `using-codev` before any execution workflow.
- `codev-shape`: maintains the lightweight project shape and `.codev.md` state without turning it into heavy documentation.
- `codev-gate`: enforces human checkpoints. Core rule: no approval, no next module.
- `codev-drift`: corrects product drift, shape drift, test drift, gate drift, ceremony drift, and granularity drift.

### `scripts/`: Mechanical Guardrails

`scripts/codev.ps1` is the canonical cross-platform CLI. It validates `.codev.md` before every command:

```powershell
pwsh -File scripts/codev.ps1 check -ProjectRoot .
pwsh -File scripts/codev.ps1 status -ProjectRoot .
pwsh -File scripts/codev.ps1 approve -ProjectRoot . -GateId gate-id
```

- `check` returns `0` when continuation is allowed, `1` when a valid human gate blocks, and `2` for missing or invalid state.
- `status` prints all six validated fields.
- `approve` requires an exact, case-sensitive gate identifier and updates both decision fields.

Windows PowerShell 5.1 remains supported on Windows. macOS and Linux require PowerShell 7 (`pwsh`); PowerShell 7 is also supported on Windows.

`scripts/codev-check-gate.ps1` remains the compatibility wrapper for the original Windows command. It delegates check and `-Status` operations to `scripts/codev.ps1` and forwards the exit code.

The `approve` command performs a transactional approval write: failure leaves the file unchanged, and success preserves the supported original encoding and BOM, newline style, and non-field content. New unmarked state files and the default template remain UTF-8 without BOM.

The CLI is a mechanical guardrail. The CodeV skills still own judgment about intent, shape, drift, and human review.

### `tests/`: Self-Testing Rules

CodeV is maintained as a testable rule system.

- `run-codev-v02-structure-tests.ps1` checks the skill set, frontmatter, README, manifests, templates, and required rule text. The explicit CodeV activation rule is tested here.
- `run-codev-check-gate-tests.ps1` checks gate checker behavior: pending blocks, approved passes, `y` passes, `free` warns but passes, missing state fails, and `-Status` prints current state.

### `templates/`: Default State

`templates/codev.md` is the default `.codev.md` starter. It keeps CodeV single-file and low-friction:

```text
Intent + Shape + Trace
```

CodeV does not create separate requirements, roadmap, review, and audit files by default. Split documents are reserved for `Ceremony: audit`, high-risk work, large projects, or explicit human request.

### Plugin Shells

`.codex-plugin/`, `.claude-plugin/`, and `.cursor-plugin/` package CodeV for different AI environments. They let CodeV operate as a reusable workflow plugin instead of being tied to a single product repository.

## Typical Workflow

```text
Human says start CodeV
-> read the project root .codev.md
-> read using-codev
-> check whether Intent / Shape match the requested work
-> use the configured Execution engine, such as Superpowers or Codex
-> append one short Trace line after the batch
-> at a gate boundary, present a light gate packet
-> human decides: approved / redirected / rejected
-> continue only if the gate allows it
```

## Relationship To Superpowers

The key separation is:

```text
CodeV = governance layer
Superpowers = execution layer
```

Superpowers can help with TDD, debugging, implementation plans, verification, review, and builds. It cannot satisfy a CodeV gate, bypass `.codev.md`, or replace human approval.

The correct order is:

```text
First CodeV: read .codev.md + using-codev
Then Superpowers: execute under the configured Execution engine
Finally CodeV: write Trace, present the gate packet, and wait for approval when required
```

## Quickstart

Start with one file:

```markdown
# CO-DEV

Gate: normal
Ceremony: light
Execution engine: default
Current gate: none
Decision: pending
Decision gate: none

## Intent
What the human wants.

## Shape
Coarse roadmap: phase, subsystem, next gate.

## Trace
- Fine trace: one short line per small change.
```

Default file: `.codev.md`.

Roadmap is coarse-grained. Trace is fine-grained. Do not spend tokens restating roadmap in trace, and do not turn roadmap into a task log.

## Execution Engine

CO-DEV is the governance layer, not a replacement for engineering skills.

Use `Execution engine:` to record the development skill or tool layer allowed to help implementation:

| Engine | Meaning |
|---|---|
| `default` | Use the agent's normal development workflow. |
| `superpower` | Allow Superpower-style planning, TDD, debugging, review, or execution skills. |
| `codex` | Allow Codex-native engineering workflow support. |
| `cursor` | Allow Cursor-native engineering workflow support. |
| `custom:<name>` | Allow a named project or team execution method. |

Other skills can improve execution, but they cannot bypass CO-DEV gates. They may help design, test, debug, review, or implement; they cannot approve a batch, downgrade a gate, skip human inspection, or replace human validation.

## Real Project Binding

Before editing a real project, CO-DEV must bind to that project's own `.codev.md`. Do not rely on a demo folder, plugin repo, or prior conversation state.

For every implementation batch:

1. Confirm or create `.codev.md` in the active project root.
2. Check that intent/shape match the requested change before editing.
3. After implementation, append one short Trace line with change, evidence, and next gate.
4. If the gate boundary is reached, present a light gate packet and wait for the human decision.

Tests, builds, installs, screenshots, and agent confidence are evidence. They are not the human gate.

Gate boundaries are product validation boundaries, not paperwork boundaries. Do not stop a `normal` gate for an internal function, helper, interface, refactor, or implementation detail unless it changes something the human can meaningfully inspect. A `normal` gate should stop at a demonstrable feature batch: something the human can open, try, compare against intent, and approve or redirect.

## Gate Frequency

| Level | Stop for human review |
|---|---|
| `ultra` | Every small module |
| `strict` | Every feature module |
| `normal` | A demonstrable batch of related functionality |
| `loose` | Completed subsystem |
| `free` | Final acceptance only, low assurance |

## Ceremony Weight

| Weight | Review format |
|---|---|
| `light` | Chat packet: done, evidence, inspect, decision |
| `standard` | Update `.codev.md` with shape, trace, and gate |
| `audit` | Split docs only when risk or project size justifies it |

Recommended default: `ultra + light`. Stop often, write little.

## Skills

- `using-codev`: load CO-DEV state and choose routing.
- `codev-shape`: quickly prefill intent, shape, gate, and trace.
- `codev-gate`: enforce lightweight human checkpoints.
- `codev-drift`: stop and correct when implementation diverges from intent.

## Gate Packet

Most gates should be this small:

```text
Gate: gate-002
Execution engine: superpower
Done: index.html shell
Evidence: shell test passed
Inspect: open index.html
Decision: approved / redirected / rejected
Decision gate: gate-002
```

No approval, no next module.

## Install

Use the plugin shell for your agent environment:

- Codex: `.codex-plugin/plugin.json`
- Claude: `.claude-plugin/plugin.json`
- Cursor: `.cursor-plugin/plugin.json`

## Gate Checker

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codev-check-gate.ps1 -ProjectRoot .
powershell -ExecutionPolicy Bypass -File .\scripts\codev-check-gate.ps1 -ProjectRoot . -Status
```

The compatibility checker reads `.codev.md` by default. It is a guardrail; the skill still owns judgment.

### Pre-v0.3 migration

Pre-v0.3 state files must add `Decision gate`. Use `Decision gate: none` when `Current gate: none`; for an active gate, reset to `Decision: pending` and set `Decision gate` to the exact `Current gate`. CodeV does not infer or reuse an older approval.

## GitHub CI

CO-DEV uses GitHub Actions for lightweight repository checks on every push and pull request:

- `tests/run-codev-v02-structure-tests.ps1`
- `tests/run-codev-check-gate-tests.ps1`

There is no deployment target yet, so CD is intentionally left out. The workflow verifies the skill package before it is merged or released.
