---
name: oneshot:logs
description: Stream a Oneshot run's full agent.log for debugging
argument-hint: "<run_id> [--follow]"
allowed-tools:
  - Read
  - Bash
---

<objective>
Stream a run's `agent.log` — full agent stdout/stderr — for debugging. Used when `/oneshot watch` isn't enough and you need to see every tool call, every message, every error.

**Two modes:**
- Default: cat the log once and exit.
- `--follow`: SSH `tail -f` the log, stream until Ctrl+C.

`agent.log` is classified as human-only in the Storage Topology — never read by agents for context.
</objective>

<execution_context>
@~/.claude/oneshot/references/progress-tracker.md
@~/.claude/oneshot/references/storage-topology.md
</execution_context>

<process>
See DESIGN.md §5 (Progress Tracker) and §"Storage Topology" for file locations.

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Resolve `run_id` to project and host.
2. SSH and cat (or `tail -f`) `{volume_path}/agent.log`.
3. Stream to the operator's terminal unchanged.
</process>
