---
name: oneshot:watch
description: Live tail a Oneshot run's event stream as it arrives
argument-hint: "<run_id>"
allowed-tools:
  - Read
  - Bash
---

<objective>
Open a live tail of a run's event stream and render events as they arrive. The operator sees phase transitions, commits, CI events, and heartbeat-derived activity in real time until the run terminates or the operator interrupts.

**Implementation shape:** SSH session running `tail -f` on `status.jsonl` (semantic events) with occasional reads of `current.json` for the current activity string. Output piped through a local renderer that formats each event as a human-readable line.

**Never** tails `heartbeats.jsonl` directly — that file is compact numeric telemetry for the orchestrator's state computation, not for live display. Live activity comes from `current.json`, which is constant-size and cheap to poll.
</objective>

<execution_context>
@~/.claude/oneshot/references/progress-tracker.md
</execution_context>

<process>
See DESIGN.md §5 (Progress Tracker) for the file layout and event schema.

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Resolve `run_id` to a project and recorded host via the local run directory.
2. Open an SSH session: `ssh {host} tail -f {volume_path}/status.jsonl`
3. In parallel, poll `current.json` every ~2s for the live activity string.
4. Render events through a formatter that handles all event types (`dispatched`, `running`, `phase`, `commit`, `pr_opened`, `ci_*`, `completed`, `failed`).
5. Exit cleanly on a terminal event or operator Ctrl+C.
</process>
