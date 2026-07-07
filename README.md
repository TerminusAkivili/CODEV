# CO-DEV

CO-DEV is a lightweight Human Accountability Harness for AI-assisted software development.

AI cannot read your mind. A loop engine can keep working, a harness agent can keep dispatching tasks, and a plan can look clean while the product slowly drifts away from what you actually wanted. CO-DEV prevents that drift by making the agent stop at chosen boundaries and ask the human to inspect the product.

## Why

I had documents, architecture notes, trace logs, a roadmap, and a working Android version. Then I spent one day and about $300 trying to migrate the product to Windows with AI.

The failure was slow. Each subsystem looked almost reasonable. By the time the drift was obvious, it was no longer one bug. It was the shape of the system.

CO-DEV exists because better instructions are not enough. Human checkpoints must be cheap enough to use and strict enough to stop drift.

## Quickstart

Start with one file:

```markdown
# CO-DEV

Gate: normal
Ceremony: light
Current gate: none
Decision: pending

## Intent
What the human wants.

## Shape
Coarse roadmap: phase, subsystem, next gate.

## Trace
- Fine trace: one short line per small change.
```

Default file: `.codev.md`.

Roadmap is coarse-grained. Trace is fine-grained. Do not spend tokens restating roadmap in trace, and do not turn roadmap into a task log.

## Gate Frequency

| Level | Stop for human review |
|---|---|
| `ultra` | Every small module |
| `strict` | Every feature module |
| `normal` | A batch of related modules |
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
Done: index.html shell
Evidence: shell test passed
Inspect: open index.html
Decision: approved / redirected / rejected
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
```

The checker reads `.codev.md` by default. It is a guardrail; the skill still owns judgment.
