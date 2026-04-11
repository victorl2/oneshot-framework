---
name: oneshot:new-project
description: Initialize a new Oneshot project, auto-detecting GSD artifacts to seed project.md
argument-hint: "[--from-gsd] [--name <slug>]"
allowed-tools:
  - Read
  - Bash
  - Write
  - Task
  - AskUserQuestion
---

<context>
**Flags:**
- `--from-gsd` — Force GSD-artifact detection and seeding (`.planning/PROJECT.md`, roadmaps, phases).
- `--name <slug>` — Manual project name override (default: derived from `git remote get-url origin`).
</context>

<objective>
Initialize a new Oneshot project in the global state directory `~/.claude/oneshot/{project_name}/`.

**Creates:**
- `~/.claude/oneshot/{project_name}/project.md` — persistent project facts the scorer uses
- `~/.claude/oneshot/{project_name}/calibration.md` — empty calibration ledger
- `~/.claude/oneshot/{project_name}/config.yml` — starter config with default sandbox profiles and scoring thresholds
- `~/.claude/oneshot/{project_name}/runs/` — empty runs directory

**GSD interoperability:** If `.planning/PROJECT.md` or other GSD artifacts are present in the current repo, seed `project.md` from them rather than starting blank.

**Project identity:** derive `{project_name}` from `git remote get-url origin` (stable across clones), fall back to repo folder name, allow override via `--name` or a `.oneshot-project` marker file.

**After this command:** Run `/oneshot start <task>` to begin a run.
</objective>

<execution_context>
@~/.claude/oneshot/references/scoring-model.md
@~/.claude/oneshot/templates/project.md
@~/.claude/oneshot/templates/config.yml
</execution_context>

<process>
See DESIGN.md §"Global State Directory" and §"Open Questions → State management" for details on `project.md` seeding strategy and `config.yml` generation.

1. Derive the project slug (git remote → folder name → `.oneshot-project` override).
2. Check if `~/.claude/oneshot/{slug}/` already exists; if so, abort with instructions to use `/oneshot start` instead.
3. Scan the current repo for GSD artifacts (`.planning/PROJECT.md`, roadmaps, phases). If present, propose a seeded `project.md`; otherwise create a blank template.
4. Generate a starter `config.yml` from the template (see `templates/config.yml`), with default sandbox profiles, scoring thresholds, and empty exclude lists.
5. Initialize an empty `calibration.md` with header only.
6. Report the created directory and the path for manual review.

**NOT YET IMPLEMENTED** — this stub documents the intended behavior.
</process>
