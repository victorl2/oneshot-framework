---
name: oneshot:cancel
description: Abort a running Oneshot run
argument-hint: "<run_id> [--reason <text>]"
allowed-tools:
  - Read
  - Bash
---

<objective>
Abort a running Oneshot agent by killing its sandbox container on the server. The container's `Stop` hook catches the termination signal and emits a `failed` event with `reason: cancelled` (plus any operator-provided reason text) to `status.jsonl` before the volume is archived.

**Resolution chain:**
1. `run_id` → project + recorded host (from local run directory)
2. run → container ID (from the `received` event in `status.jsonl`)
3. `ssh {host} docker kill {container_id}`
4. `Stop` hook inside the container writes the `failed` event before the process exits.

**Behavior:** this is a hard kill, not a graceful wind-down. The run ends wherever it was. Any in-progress commits not yet pushed are lost; already-pushed commits stay on the branch.
</objective>

<execution_context>
@~/.claude/oneshot/references/progress-tracker.md
</execution_context>

<process>
See DESIGN.md §5 (Progress Tracker) and §"Usage" for the command surface.

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Confirm with the operator — this is destructive action.
2. Resolve run → host + container.
3. Execute `docker kill` via SSH.
4. Verify the `failed` event appeared in `status.jsonl` (should be fast — the Stop hook runs synchronously).
5. Report the final state.
</process>
