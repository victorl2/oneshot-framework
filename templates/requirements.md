# Requirements — {run_id}

Sealed requirements bundle for a Oneshot run. Written by the Discuss Agent at the end of the discuss phase, after the Requirements Scorer clears the soft-gate (or the operator forces with `--force`).

This file ships in the dispatch bundle and is read by the Implementation Agent as its primary input. The agent is expected to implement **exactly** what is specified here, no more, no less.

---

## Goal

<!--
One or two sentences. The core outcome this run must deliver.
-->

## Scope

### In scope

<!--
Concrete items that must be done. Bullet list.
-->

### Out of scope

<!--
Explicit exclusions. Things the agent should NOT do even if they seem adjacent.
-->

## Acceptance criteria

<!--
Testable conditions that define "done." Each should be verifiable by either
a test or a CI check.
-->

- [ ] ...
- [ ] ...

## Error semantics

<!--
What happens when things go wrong. This section is mandatory — vague error
contracts are the #1 predictor of one-shot failure.

For each error condition:
- What triggers it
- What the system does in response
- What the caller observes
-->

## Interfaces

<!--
Any public APIs, file formats, CLI flags, or wire protocols the run will
introduce or modify. Specify shapes, not just names.
-->

## Dependencies and capabilities

<!--
External services, libraries, credentials, or tooling the implementation
needs. If any of these were probed during discuss, cross-reference the
exploration summary for capability confirmation.
-->

- [ ] ...

## Exploration findings (cross-reference)

<!--
Pointer to `exploration/SUMMARY.md` in the bundle. If the discuss-agent
probed capabilities or fetched real samples, they're summarized there and
the implementation agent reads that directly.
-->

See `exploration/SUMMARY.md` if present.

## Implementation hints

<!--
Optional. Anything the discuss phase surfaced about HOW this should be
implemented. Keep this light — the agent is expected to think — but
non-obvious constraints belong here.
-->

## Non-functional requirements

<!--
Performance, memory, concurrency, security constraints. Testable where possible.
-->
