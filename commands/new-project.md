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

**After this command:** Run `/oneshot start <task>` to begin a run.
</objective>

<execution_context>
@~/.claude/oneshot/references/scoring-model.md
@~/.claude/oneshot/templates/project.md
@~/.claude/oneshot/templates/config.yml
</execution_context>

<process>
Execute the following steps. This is a WORKING command, not a stub.

## Step 1: Derive the project slug

Run these in order, use the first that succeeds:

```bash
# Option 1: git remote (preferred — stable across clones)
slug=$(git remote get-url origin 2>/dev/null | sed 's|.*[:/]||; s|\.git$||')
# Option 2: .oneshot-project marker file
[[ -z "$slug" ]] && [[ -f .oneshot-project ]] && slug=$(cat .oneshot-project | tr -d '[:space:]')
# Option 3: current directory name
[[ -z "$slug" ]] && slug=$(basename "$PWD")
```

If `--name <slug>` was passed, override with that value.

Set `PROJECT_DIR="$HOME/.claude/oneshot/$slug"`.

Show the derived slug and path to the operator and ask for confirmation before creating.

## Step 2: Check for existing project

If `$PROJECT_DIR` already exists:
- Show its contents
- Ask: "Project already initialized at $PROJECT_DIR. Want to reinitialize (destructive) or just use `/oneshot start`?"
- If they say reinitialize: proceed (overwrite). If not: exit.

## Step 3: Scan for GSD artifacts

Check the current repo for GSD project data:
- `.planning/PROJECT.md` — GSD project context
- `.planning/ROADMAP.md` — phase structure
- `.planning/REQUIREMENTS.md` — scoped requirements
- `.planning/STATE.md` — project memory

If any are present (or `--from-gsd` flag was passed):
1. Read the GSD PROJECT.md
2. Extract: project description, core value, tech stack hints, requirements, out-of-scope items
3. Use this to **seed** the Oneshot `project.md` — pre-filling the tech stack, conventions, and gotchas sections rather than leaving them blank

If no GSD artifacts: use the blank template from `@~/.claude/oneshot/templates/project.md`.

In either case, show the operator the proposed `project.md` content and ask them to confirm or edit before writing.

## Step 4: Ask for server configuration

The operator needs to configure the remote server. Ask:
1. **SSH host** — e.g. `victor@silvaserver.local` (the server that will run sandbox containers)
2. **Volume root** — where to store run artifacts on the server (default: `~/oneshot-data`)
3. **Container runtime** — `podman` or `docker` (default: `podman`)

## Step 5: Create the project directory

```bash
mkdir -p "$PROJECT_DIR/runs"
```

Write these files:

### config.yml
Use the template from `@~/.claude/oneshot/templates/config.yml` but fill in the server host from step 4. Write it to `$PROJECT_DIR/config.yml`.

### project.md
Write the confirmed content from step 3 to `$PROJECT_DIR/project.md`.

### calibration.md
Write an empty ledger with just a header:

```markdown
# Calibration — {slug}

Append-only ledger of predicted (scorer) vs actual (reviewer) scores.
See DESIGN.md §"Calibration Loop" for the format specification.

---
```

Write to `$PROJECT_DIR/calibration.md`.

### index.md
Write an empty run index:

```markdown
# Run Index — {slug}

Chronological index of all Oneshot runs for this project.

---
```

Write to `$PROJECT_DIR/index.md`.

## Step 6: Verify and report

Show the operator:
- Full path to the project directory
- List of created files
- The `server.host` from config.yml
- Next step: `/oneshot start <task>` to begin a run

## Step 7: Verify server connectivity

Run a quick SSH check: `ssh -o ConnectTimeout=5 -o BatchMode=yes $SERVER_HOST "echo ok"`. If it fails, warn the operator that SSH key auth may not be set up and suggest `ssh-copy-id`.
</process>
