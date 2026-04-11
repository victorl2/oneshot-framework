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
- `--cpu <n>` — Override CPU allocation (fractional cores allowed).
- `--ram <size>` — Override memory limit (e.g. `8g`, `16g`).
- `--gpu` — Request GPU passthrough.
- `--force` — Dispatch even if the requirements score is below the soft-gate threshold.
</context>

<objective>
Start a new Oneshot run: enter the discuss loop, score requirements in real time, and dispatch to a sandbox container on the server once the gate is cleared.

**Flow:**
1. Spawn the Discuss Agent (see `agents/oneshot-discuss.md`).
2. Silent Requirements Scorer runs alongside (see `agents/oneshot-scorer.md`).
3. Discuss-agent gets live access to a remote Discussion Sandbox for exploration (see DESIGN §2).
4. When the operator seals requirements (or hits `--force`), package the dispatch bundle.
5. Ship the bundle to the server via the Dispatcher.
6. Sandbox runtime spins up a container, the Implementation Agent runs.
7. Progress tracker streams events back to the orchestrator.
8. CI Gate enforces that "done" requires the PR to be open *and* required CI green.
9. Report the PR URL, run ID, and final status.
</objective>

<execution_context>
@~/.claude/oneshot/references/scoring-model.md
@~/.claude/oneshot/references/discussion-sandbox.md
@~/.claude/oneshot/references/progress-tracker.md
@~/.claude/oneshot/references/ci-gate.md
@~/.claude/oneshot/templates/requirements.md
</execution_context>

<process>
See DESIGN.md §"Usage", §2 (Discuss Agent), §3 (Dispatcher), §5 (Progress Tracker), §6 (CI Gate).

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.

1. Resolve sandbox config: CLI flags > profile > defaults from `config.yml`.
2. Resolve project identity from `git remote get-url origin` or the `.oneshot-project` marker.
3. Create a new run directory `~/.claude/oneshot/{project}/runs/{timestamp}/`.
4. Spawn the discuss-agent with the scorer running in parallel.
5. On seal: package bundle (`requirements.md`, `project.md` snapshot, `exploration/`, git ref, sandbox config).
6. Dispatch via SSH to the configured server host.
7. Watch progress via the event stream; return once the run terminates (`completed` or `failed`).
</process>
