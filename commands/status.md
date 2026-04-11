---
name: oneshot:status
description: Show status of active and recent Oneshot runs
argument-hint: "[run_id]"
allowed-tools:
  - Read
  - Bash
---

<objective>
Show the state of Oneshot runs. Without arguments, displays a table of all active and recent runs across all projects. With a `run_id`, shows the detail view for a single run.

**Table view** (no arguments): one row per run, with columns:
- `PROJECT` — project slug
- `RUN_ID` — timestamped run identifier
- `STATE` — computed from the event log (`pending` / `running` / `thinking` / `stalled` / `unresponsive` / `ci_waiting` / `ci_pending` / `ci_fixing` / `ci_blocked` / `completed` / `failed`)
- `PHASE` — current phase from the latest `phase` event
- `ELAPSED` — wall time since dispatch
- `HB` — seconds since last heartbeat (from `heartbeats.jsonl`)
- `PR` — PR URL or `—` if not yet open
- `FIX_ATTEMPTS` — number of CI fix cycles triggered

**Detail view** (`status <run_id>`): full event timeline, metrics from the latest heartbeat, paths to `agent.log` and bundle, current phase and activity.

**Data sources:**
- `~/.claude/oneshot/*/runs/*/status.jsonl` — semantic events (agent-readable)
- Server-side `heartbeats.jsonl` — pulled via SSH for liveness
- Server-side `current.json` — for current activity string

No long-running daemon: state is derived on demand from files.
</objective>

<execution_context>
@~/.claude/oneshot/references/progress-tracker.md
</execution_context>

<process>
See DESIGN.md §5 (Progress Tracker) for the event schema, heartbeat telemetry format, and state machine.

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Scan `~/.claude/oneshot/*/runs/` locally for any run that hasn't reached a terminal state.
2. For each non-terminal run, SSH to the recorded host and read the tail of `heartbeats.jsonl` + `current.json`.
3. Compute state from event log + current wall-clock time (pure function — no stored state).
4. Render the table (or detail view for single-run mode).
</process>
