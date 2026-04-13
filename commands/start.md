---
name: oneshot:start
description: Begin a new Oneshot run — discuss, score requirements, dispatch to the sandbox
argument-hint: "<task> [--profile <name>] [--cpu <n>] [--ram <size>] [--gpu] [--force]"
allowed-tools:
  - Read
  - Bash
  - Write
  - Task
  - AskUserQuestion
---

<context>
**Flags:**
- `--profile <name>` — Use a named sandbox profile from `config.yml` (`small` / `medium` / `large` / `xlarge` / `gpu`).
- `--cpu <n>` — Override CPU allocation (fractional cores allowed). Use `none` to skip limits.
- `--ram <size>` — Override memory limit (e.g. `8g`, `16g`). Use `none` to skip limits.
- `--gpu` — Request GPU passthrough.
- `--force` — Dispatch even if the requirements score is below the soft-gate threshold.

**Server configuration:** reads `server.host` from `~/.claude/oneshot/{project}/config.yml`. If not configured, prompts the operator.
</context>

<objective>
Start a new Oneshot run. In this v0 implementation, the full discuss + scorer loop is deferred — instead, the command gathers requirements through a simplified conversational flow, packages a bundle, dispatches it to the remote server, and polls until the run completes.

**What works now:**
- Project resolution (git remote → slug)
- Requirements gathering via direct conversation (simplified, no scorer yet)
- Bundle creation (`requirements.md`, `project.md` snapshot, git ref)
- Dispatch via `bin/oneshot-dispatch` (SSH + rsync + Podman)
- Status polling via `bin/oneshot-status`
- Run directory creation at `~/.claude/oneshot/{project}/runs/{timestamp}/`

**Future (not yet wired):**
- Silent Requirements Scorer running in parallel
- Discussion Sandbox for remote exploration during discuss
- Exploration artifact capture into the bundle
- Score display and soft-gate threshold
</objective>

<execution_context>
@~/.claude/oneshot/references/scoring-model.md
@~/.claude/oneshot/templates/requirements.md
@~/.claude/oneshot/templates/config.yml
</execution_context>

<process>
Execute the following steps. This is a WORKING command, not a stub.

## Step 1: Resolve project identity

Derive the project slug for state directory lookup:
1. Try `git remote get-url origin` in the current repo — normalize it (strip `.git`, scheme, slashes → slug).
2. Fall back to the basename of the current working directory.
3. Check for `.oneshot-project` file at repo root for a manual override.

Set `PROJECT_DIR=~/.claude/oneshot/{slug}/`.

## Step 2: Load or create project config

If `$PROJECT_DIR/config.yml` exists, read it for `server.host`, `server.volume_root`, sandbox defaults, and scoring thresholds.

If `$PROJECT_DIR` doesn't exist, tell the operator to run `/oneshot:new-project` first. Do NOT silently create it — the project needs to be initialized properly.

## Step 3: Gather requirements (discuss + silent scorer)

Spawn **two subagents** concurrently via the `Task` tool:

1. **`oneshot-discuss`** — the interactive requirements-gathering agent. Pass it:
   - The task description from the operator's CLI argument
   - Path to `$PROJECT_DIR/project.md`
   - Path to the requirements template (`@~/.claude/oneshot/templates/requirements.md`)
   - Path to write the sealed `requirements.md` ($RUN_DIR/bundle/requirements.md)

2. **`oneshot-scorer`** (silent) — called on the *current draft* after each operator answer. Pass it:
   - Current requirements draft text
   - Mode: `score`
   - Paths to `$PROJECT_DIR/project.md` and `$PROJECT_DIR/calibration.md`

The scorer returns a compact JSON object: `{dimensions, overall, rationale, weakest_dimension}`. **Display the scores to the operator after each turn** in this format:

```
correctness 72 (+3) · quality 80 (±0) · completeness 55 (+8)
robustness 61 (+1) · ambiguity 70 (-2) → overall 68 (+2)
```

Track the score history to compute deltas. If the overall score has moved less than 5 points across the last 3 turns, invoke the scorer in `coach` mode and pass the structured guidance to the discuss agent. **Do not show the coaching to the operator** — it goes into `$RUN_DIR/scorer-log.md` for audit.

When the operator is ready to seal (or overall score ≥ `scoring.soft_gate` from config.yml), have the discuss agent write the final `requirements.md`.

If the score is below the soft gate and `--force` was not passed, ask the operator to confirm: "Score is X — below gate of Y. Proceed anyway? (requires --force)".

## Step 4: Package the dispatch bundle

Create a timestamped run directory and bundle:

```bash
RUN_ID="r-$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="$PROJECT_DIR/runs/$RUN_ID"
BUNDLE_DIR="$RUN_DIR/bundle"
mkdir -p "$BUNDLE_DIR"
```

Write into the bundle:
- `requirements.md` — the sealed requirements from step 3
- `project.md` — copy from `$PROJECT_DIR/project.md`
- Git ref: `git rev-parse HEAD` (the base commit the agent should branch from)

## Step 5: Dispatch

Read server config from `config.yml`:
- `server.host` (required — SSH target)
- `server.volume_root` (default: `~/oneshot-data`)

Call the dispatcher:

```bash
~/code/oneshot-framework/bin/oneshot-dispatch \
  --host "$SERVER_HOST" \
  --volume-root "$VOLUME_ROOT" \
  --run-id "$RUN_ID" \
  --cpu "$CPU" --memory "$MEMORY" \
  --local-run-dir "$RUN_DIR" \
  "$BUNDLE_DIR"
```

If dispatch succeeds, report the run_id and how to follow along:
- `/oneshot status $RUN_ID`
- `/oneshot watch $RUN_ID`

## Step 6: Poll status (optional)

Ask the operator if they want to watch the run. If yes, poll `oneshot-status` every 15 seconds until the run reaches a terminal state (`completed` or `failed`).

Report the final outcome: PR URL (if completed), or failure reason.
</process>
