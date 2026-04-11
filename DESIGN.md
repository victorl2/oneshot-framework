# Oneshot — Design Document

**Status:** Draft — initial design capture from discussion.
**Last updated:** 2026-04-10

---

## Vision

Oneshot is a **standalone framework** that runs **isolated, single-shot implementation agents** in sandboxed containers on a remote server over SSH. It can interoperate with GSD — reusing existing `PROJECT.md`, roadmaps, phases, and artifacts when present — but does not depend on it and is not an extension of it.

The human operator drives requirements gathering locally, with a silent scoring agent measuring requirements quality in real time. Once requirements clear a quality bar, the task is dispatched to a sandboxed container on the server, where an agent attempts a one-shot implementation, opens a PR, and **drives it through CI until all required checks pass**. If CI fails, a fresh sandbox is dispatched automatically with the failure context to fix the failures — that's the agent's responsibility, not the operator's. Throughout execution, the agent streams structured progress events back to the orchestrator so the operator can see at any moment which runs are healthy, thinking, stalled, waiting on CI, or done. Only after CI is green does the reviewer agent run, scoring the PR on the same dimensions and drafting targeted feedback questions for the human. An iterate command re-enters the cycle with the PR, review, and human answers as context.

**The core bet:** requirements quality is the single biggest predictor of one-shot success, and quantifying it with a scorer that learns from past outcomes turns a gut-feel gate into a calibrated, auditable one.

**Success criteria — formally.** A run is considered **done** if and only if:
1. A PR was opened from the run's branch, AND
2. All **required** CI checks on that PR are passing, AND
3. No terminal failure was emitted along the way.

A PR with failing CI is explicitly **not done** — it's in an intermediate state, and getting it to green is the agent's job.

---

## Goals

- Use **any idle Linux/Unix server** reachable over SSH for concurrent isolated agents — no assumptions about specific hardware, distro, or cloud provider baked into the design.
- Resource isolation so multiple agents can run concurrently without stomping on each other (CPU, RAM, and optionally GPU).
- **Interoperate** with GSD projects — when an existing `PROJECT.md`, roadmap, or phase artifacts are detected, seed Oneshot's state from them instead of starting blank.
- Make requirements quality **measurable** before dispatch, not just vibes.
- **Observable in-flight** — the operator can see the state of every dispatched agent (running, thinking, stalled, waiting on CI, crashed, done) without SSHing manually.
- **CI is part of "done"** — the agent is responsible for driving the PR to green, not just opening it. Fix cycles happen automatically without operator intervention.
- Calibrate the scorer against actual PR outcomes over time, per-project.
- Clean review + iterate loop for when the one-shot doesn't land the first time.

## Non-Goals (for v1)

- Multi-user / team sharing of calibration data.
- Remote execution on untrusted networks — LAN or trusted VPN only, single trusted operator.
- Hard real-time scheduling or job priorities.
- Hosted / SaaS mode — Oneshot is self-hosted, operator runs their own server.

---

## Usage

Oneshot exposes its functionality as slash commands. Core surface:

| Command                         | Purpose                                                                                      |
|---------------------------------|----------------------------------------------------------------------------------------------|
| `/oneshot:new-project`          | Initialize a new Oneshot project. Auto-detects GSD artifacts (`PROJECT.md`, roadmaps, phases) in the current repo and seeds `project.md` from them when present. |
| `/oneshot start <task>`         | Begin a new run: enter the discuss loop, score requirements, dispatch to the server on green. Accepts `--profile <name>` or explicit `--cpu <n> --ram <size> [--gpu]` flags to size the sandbox. |
| `/oneshot status`               | Table of all active and recent runs across all projects — state, elapsed, last heartbeat, PR link. |
| `/oneshot status <run_id>`      | Detail view for one run: full event timeline, current phase, metrics, paths to logs.        |
| `/oneshot watch <run_id>`       | Live tail of a run's event stream, rendered as it arrives.                                   |
| `/oneshot logs <run_id>`        | Stream the run's full `agent.log` for debugging.                                              |
| `/oneshot cancel <run_id>`      | Abort a running agent (SSH + kill the container).                                             |
| `/oneshot iterate <PR>`         | Restart the cycle for an existing PR with review + feedback attached as context.             |

`/oneshot:new-project` is intentionally namespaced with a colon to match GSD's convention for project-lifecycle commands; the in-flight commands (`start`, `status`, `watch`, etc.) use a space to match the "verb on an active thing" feel.

---

## High-Level Flow

```
┌─────────────────── LOCAL (operator's machine) ───────────────────┐
│                                                                   │
│  1. /oneshot start <task>                                         │
│                                                                   │
│  2. Discuss loop:                                                 │
│     human ↔ discuss-agent ──(checkpoint pull)──> scorer-agent     │
│                                    ▲                              │
│                                    │ guidance (hidden)            │
│                    score shown to human after every turn          │
│                                                                   │
│  3. Score ≥ threshold → requirements bundle sealed                │
│     (or --force override if operator insists)                     │
│                                                                   │
│  4. Dispatcher packages bundle, ships to server via SSH           │
│                                                                   │
└────────────────────────────┬──────────────────────────────────────┘
                             │
                             ▼
┌──────────────────── SERVER (idle workstation) ────────────────────┐
│                                                                   │
│  5. Sandbox runtime spins up container                            │
│     - git worktree mounted                                        │
│     - cgroup CPU / RAM limits                                     │
│     - GPU passthrough (if requested — one container at a time)    │
│                                                                   │
│  6. Agent attempts one-shot implementation                        │
│                                                                   │
│  7. Agent commits, pushes branch, opens PR                        │
│                                                                   │
│  8. CI Gate — detach-and-reattach loop:                           │
│     • Sandbox watches initial CI briefly (~2 min)                 │
│     • If still running: sandbox exits, orchestrator polls         │
│     • CI passes → run transitions to completed                    │
│     • CI fails  → fresh fix sandbox dispatched automatically      │
│                   (same branch, failure logs attached)            │
│     • Cap at max_fix_attempts; exhausted → failed/ci_unfixable    │
│                                                                   │
│  ─ Throughout steps 5–8, the sandbox appends structured events    │
│    to runs/{timestamp}/status.jsonl (heartbeats, phase changes,   │
│    commits, pr_opened, ci_* events, completed/failed). The        │
│    orchestrator reads this on demand via SSH — no daemon needed.  │
│                                                                   │
└────────────────────────────┬──────────────────────────────────────┘
                             │
                    status.jsonl stream  +  final green PR
                             │
                             ▼
┌──────── LOCAL (operator sees CI-green PR) ────────────────────────┐
│                                                                   │
│  9. Reviewer agent reads PR, emits scores + feedback questions    │
│     (gated on ci_passed — never runs on a red PR)                 │
│                                                                   │
│  10. Human round: operator answers the feedback questions         │
│                                                                   │
│  11. /oneshot iterate <PR> → re-enters step 2 with PR +           │
│       review + feedback as additional context                     │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Requirements Scorer (silent coach)

**Role:** measure requirements quality in real time during discuss; coach the discuss-agent when progress stalls.

**Separation:** MUST be a separate agent from the discuss-agent. Independent judgment → no confirmation bias. This is a non-negotiable architectural constraint.

**Visibility rules:**
- **Scores → always visible** to the human operator, updated after every turn.
- **Scorer ↔ discuss-agent coaching → always hidden** from the human. Logged to an audit trail for later inspection, but not shown in the live conversation.

**Trigger for coaching intervention:** score *plateau*, not question count. If the overall score has moved less than ~5 points across the last 3 turns, the current line of questioning isn't extracting signal → scorer intervenes. A raw count is a worse signal because some requirements legitimately take longer to specify.

**Intervention channel:** **checkpoint pull**, not push. The discuss-agent asks the scorer for coaching when it detects the plateau (or when prompted by the orchestrator). Scorer does not interrupt mid-turn. Keeps the conversational boundary clean — discuss-agent stays in charge of flow.

**What the scorer emits to the discuss-agent:**
- NOT verbatim questions. That would be puppeteering, and the discuss-agent would lose its voice.
- Structured guidance: which dimension is underserved, which framing historically works in *this project*, a rough pointer on what to probe ("probe error contracts, frame around failure modes not happy path").
- The discuss-agent absorbs the guidance and translates into its own voice.

**What the scorer reads:**
- Full discuss transcript so far
- Current requirements draft
- `project.md` (persistent project facts)
- `calibration.md` (historical predicted-vs-actual tuples)
- Selected past `runs/*/scorer-log.md` as few-shot examples

### 2. Discuss Agent

**Role:** interactive requirements gathering with the human.

Extends GSD's existing `/gsd:discuss-phase` pattern. Key changes: adds the scorer checkpoint mechanism (see §1), and has live access to a remote discussion sandbox for exploration during the conversation (see below). On each turn: emit question to the human, receive answer, optionally probe the sandbox to verify or enrich context, update draft, then (if plateau detected) pull coaching from the scorer before composing the next question.

#### Discussion sandbox (exploration environment)

The discuss-agent has **live access to a remote sandbox during the discussion** so it can verify assumptions, probe capabilities, and enrich context with real data — not guesses. This is distinct from the implementation sandbox in lifecycle and purpose, but runs on the same infrastructure.

**Why this exists.** Many requirements assumptions hinge on "can the eventual implementation agent actually do X from its sandbox?" — fetch CloudWatch logs, reach an internal API, run a specific CLI tool, authenticate against a service. Answering these from the operator's laptop is worse than useless: the laptop has different tools, different network posture, different credentials than the sandbox will have. **Exploration must happen in an environment that matches the eventual implementation sandbox.**

The second reason is context enrichment. If the human references "the auth service logs," the discuss-agent can actually go look at them, summarize what it found, and fold that summary into the requirements. This replaces hand-wavey specification ("handle the errors in those logs") with grounded specification ("handle the three error types observed in the sample: A, B, C").

**Non-negotiable constraint: exploration runs remote, never local.** The discussion sandbox is a container on the server, identical in tooling, credentials, network posture, and skill/MCP carryover to an implementation sandbox. Commands the discuss-agent issues for verification go over SSH to that container. **Nothing executes on the operator's laptop.** Local execution would verify a different environment than the one that actually runs the work — a false positive is worse than no check at all.

**Lifecycle.**

- **Lazy spawn.** No container is created for a discussion until the discuss-agent makes its first exploration call. Purely conversational discussions cost nothing — no container is ever started.
- **Persists across turns.** Once spawned, the container lives for the duration of the discussion session. This keeps exploration state warm: installed tools, cached credentials, fetched files, environment variables written to files from earlier commands.
- **Idle and hard timeouts.** Configurable idle timeout (default 30 min) tears the container down if no commands have been issued. Configurable hard cap (default 4 hours) bounds total discussion lifetime regardless of activity.
- **Destroyed at seal.** When requirements are sealed (gate cleared, dispatch about to happen), the discussion sandbox is torn down. The implementation run always gets a fresh container. Artifacts from the discussion are captured into the dispatch bundle *before* teardown — see *Artifact capture* below.

**Profile.** Discussion exploration is usually lighter than implementation. A dedicated `discuss` profile in `config.yml` is the default:

```yaml
sandbox:
  profiles:
    discuss: { cpu: 2, memory: 4g }    # lighter than default implementation profiles
```

Overridable via `--profile` / `--cpu` / `--ram` flags on `/oneshot start`, in case a discussion needs to probe something heavy (e.g. running an integration suite to determine which tests currently pass, before specifying a fix).

**Tools the discuss-agent gets.** Three thin SSH-backed tools, exposed only during the discuss phase:

| Tool                             | Purpose                                                                                                     |
|----------------------------------|-------------------------------------------------------------------------------------------------------------|
| `sandbox_exec(cmd, timeout_s)`   | Run a shell command in the discussion sandbox; return `{stdout, stderr, exit_code}`. Stateless: each call is an independent `docker exec`. Container filesystem and background processes persist between calls. |
| `sandbox_fetch(remote_path)`     | Pull a file from the sandbox back into context. Bounded by size (default 256 KB, refuses larger). Used for schema dumps, log samples, config files. |
| `sandbox_status()`               | Lightweight health check: returns container up/down, remaining idle budget, remaining hard-cap budget.      |

Each call is logged — see *Transparency* below.

**Artifact capture on seal.** Before the discussion sandbox is destroyed, the discuss-agent writes a summary of what exploration discovered into the dispatch bundle:

```
runs/{timestamp}/bundle/
├── requirements.md
├── project.md              (snapshot)
├── exploration/
│   ├── SUMMARY.md          # natural-language summary of what was probed + findings
│   ├── transcript.jsonl    # every sandbox_exec call: cmd, stdout/stderr, exit, timestamp
│   └── artifacts/          # files fetched via sandbox_fetch (schemas, log samples, etc.)
```

`SUMMARY.md` is what the implementation agent actually reads as context when the run starts. It's **pre-digested**, so the implementation agent doesn't re-burn context re-discovering what discuss already found. Specific log samples, schemas, and API response shapes captured during discuss become concrete references the implementation can rely on.

`transcript.jsonl` is preserved for audit and as evidence for the scorer — see *Scorer integration* below.

**Transparency.** Every `sandbox_exec` command is visible to the human operator by default. The live display shows a compact representation of the call (`$ aws logs tail /aws/lambda/auth --since 1h | head -20`) plus a one-line result summary (`→ 23 lines, 3 ERROR entries`). Full output is inspectable on demand. Hiding sandbox activity from the human would be a trust violation — the operator needs to know what the agent is doing on their behalf, with their credentials, on their infrastructure.

**Failure modes and the capability-gap signal.** When an exploration call fails — missing credentials, network blocked, tool not installed, permission denied — the discuss-agent must **not paper over it**. The failure is reported to the human, flagged in `exploration/SUMMARY.md` as a *capability gap*, and becomes input to the scorer.

A run that specifies "fetch CloudWatch logs" but whose exploration showed the sandbox can't reach CloudWatch should score low on completeness, because the specification depends on a capability the implementation sandbox demonstrably won't have.

Capability gaps don't automatically block dispatch — the operator may know a gap will be resolved by the time the run executes (new creds being provisioned, firewall rule approved) and can `--force` through. But gaps are surfaced loudly, not silently assumed away.

**Scorer integration.** The scorer reads `exploration/transcript.jsonl` as part of its scoring input alongside the discussion transcript. Commands that succeeded are evidence of *confirmed capability*; commands that failed are evidence of *capability gaps*. Both are harder signal than prose alone — the scorer can pin down correctness and completeness more precisely when it sees actual probe results, not just statements.

The scorer itself never executes anything in the sandbox — it remains a read-only silent coach. Only the discuss-agent has `sandbox_exec` permissions, and only during the discuss phase.

### 3. Dispatcher

**Role:** package the sealed requirements bundle, ship it to the server, manage job lifecycle.

**v1 approach:** SSH-based job queue backed by a flat file with `flock` for concurrency. Start simple, upgrade only if concurrency pain emerges. `~/.claude/oneshot/{project}/runs/{timestamp}/` on the local side mirrors to a corresponding directory on the server.

**Bundle contents:**
- `requirements.md` (sealed)
- `project.md` snapshot at dispatch time
- `exploration/` directory captured from the discussion sandbox at seal time — `SUMMARY.md`, `transcript.jsonl`, and fetched artifacts (see §2). The implementation agent reads `SUMMARY.md` as pre-digested context.
- Git ref the agent should branch from
- Sandbox config (CPU / RAM / disk / GPU, filtered skill/MCP set, credential pass policy)

### 4. Sandbox Runtime

**Role:** isolated execution environment for agents on the server. Used in **two modes** by different components:

- **Discussion mode** — long-lived, interactive, lightweight (`discuss` profile by default). Spawned lazily when the discuss-agent needs to probe capabilities or enrich context; torn down at requirements-seal. See §2.
- **Implementation mode** — ephemeral, sized per run, hosts the one-shot implementation agent or a fix sandbox. Lifecycle is bounded by the run.

The underlying infrastructure is identical in both modes — same container image, same skill/MCP carryover, same volume mount pattern, same event-stream hooks. Only the lifecycle and default profile differ.

**v1 approach:** **Docker containers** with:
- Git worktree mounted from a bare clone on the server
- **Per-run server-persistent volume** mounted for all output artifacts (`status.jsonl`, `agent.log`, `result.json`, worktree) — the container is disposable, the volume outlives it (see *Storage Topology* below)
- cgroup CPU / RAM / disk limits (see *Resource configuration* below)
- GPU passthrough available to **one container at a time** on single-GPU hosts
- Network egress allowed (agents may need to fetch packages, hit APIs); no inbound
- Host Claude Code skills and MCP servers carried over (see *Skills & MCP carryover* below)

**Rationale:** Docker is sufficient for a single-trusted-operator LAN. VMs or Firecracker would give stronger isolation but the threat model doesn't require it. If we later need stronger isolation for GPU workloads, we can swap the runtime without touching the dispatcher.

#### Resource configuration

CPU, RAM, disk, and GPU per sandbox are configurable via three layers, each overriding the previous:

1. **Global defaults** in `~/.claude/oneshot/{project}/config.yml`.
2. **Named sandbox profiles** — presets for common sizes, referenced by name.
3. **Per-run CLI overrides** on `/oneshot start`.

**Config example:**

```yaml
sandbox:
  defaults:
    cpu: 4.0           # Docker --cpus (fractional cores allowed)
    memory: 8g         # Docker --memory
    disk: 20g          # worktree volume quota
    gpu: false         # request GPU passthrough
  profiles:
    small:  { cpu: 2,  memory: 4g }
    medium: { cpu: 4,  memory: 8g }
    large:  { cpu: 8,  memory: 16g }
    xlarge: { cpu: 12, memory: 32g }
    gpu:    { cpu: 4,  memory: 16g, gpu: true }
```

**CLI override examples:**

```
/oneshot start <task> --profile large
/oneshot start <task> --cpu 6 --ram 12g
/oneshot start <task> --profile gpu --ram 32g    # profile + selective override
```

Resolution order is strict: CLI flags > profile > defaults. The **resolved config** is recorded in the run's `dispatched` event, so every run has an audit trail of exactly what shape its sandbox was — critical for debugging "why did this run behave differently."

#### Skills & MCP carryover

**Default: inherit everything.** The sandbox should feel like the operator's own Claude Code environment — all skills and MCP servers available on the host are present in the sandbox. Divergence between "what I can do locally" and "what the sandboxed agent can do" is a footgun; making them identical is the least surprising default.

**Mechanism: snapshot at dispatch, not live mount.**

At dispatch time, the dispatcher:
1. Enumerates the host's available skills from `~/.claude/skills/` (and project-level `.claude/skills/` if present).
2. Reads the host's MCP server config from `~/.claude/settings.json` (and project-level overrides).
3. Applies exclude lists from `config.yml` to filter out skills/MCPs marked incompatible.
4. Copies the filtered set into the run bundle under `bundle/.claude/`.
5. Ships the bundle to the server; the sandbox runtime mounts it at `/root/.claude/` inside the container.

**Why snapshot, not live mount:**
- **Reproducibility** — a skill update or MCP config change mid-run doesn't mutate agent behavior partway through.
- **Auditability** — the exact skill/MCP set for every run is preserved in `runs/{timestamp}/bundle/.claude/`, so a post-mortem can inspect what the agent actually had.
- **Debuggability** — "I can't reproduce this locally" has a definitive answer: diff the bundle against your current `~/.claude/`.

**Config example:**

```yaml
skills:
  mode: inherit        # inherit | explicit | none
  exclude:             # applies when mode=inherit
    - gmail            # requires interactive OAuth
    - using-git-worktrees   # sandbox has no host git state
  # explicit mode alternative:
  # include:
  #   - test-driven-development
  #   - systematic-debugging

mcp:
  mode: inherit        # inherit | explicit | none
  exclude:
    - notion           # OAuth browser flow, doesn't work in sandbox
  credentials:
    pass: all          # all | none | allowlist
    allow:             # only used when pass=allowlist
      - github
      - context7
```

**Credential handling.** Most MCPs store OAuth tokens or API keys somewhere under `~/.claude/` or the system keychain. Three policies are supported, toggled by `mcp.credentials.pass`:

- **`all`** — mount credentials as-is. Simplest. Acceptable on LAN with a trusted operator, which matches our threat model. **Default.**
- **`none`** — strip credentials before shipping. Safer but breaks any MCP that requires auth.
- **`allowlist`** — only pass credentials for the named MCPs through. Middle ground; recommended once the exclude list has stabilized from empirical use.

**Known-broken categories** (populate the exclude list empirically):
- Skills/MCPs that require interactive prompts (OAuth browser flows) — no browser in the sandbox.
- Anything reaching into host filesystem paths outside the repo — those paths don't exist in the container.
- MCPs that talk to host daemons over Unix sockets — the sockets aren't mounted.

A v1 milestone is a one-time "carryover compatibility pass" that runs the full host skill/MCP set inside a sandbox and flags the ones that break, seeding the initial default exclude list.

#### Subagent usage

The implementation agent runs with a finite context window. As it explores the codebase, reads files, runs tests, and iterates, context fills up — and a full context is the single biggest driver of degraded decision-making, repeated mistakes, and outright failure on long runs. **Oneshot expects the sandbox agent to aggressively use subagents for targeted, context-heavy work** so the main agent's context stays focused on the implementation task itself.

**Rule of thumb:** if the work involves reading many files, digesting large tool output, or producing a summary from voluminous input, delegate it. The parent only pays for the subagent's *return message*, not its full working context.

**Target categories for delegation:**

| Category                      | When                                                                  | Why delegate                                                                 |
|-------------------------------|------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| **Codebase exploration**      | Understanding an unfamiliar subsystem, tracing data flow, mapping callers | Exploration reads many files; only the *mental model* needs to return        |
| **Targeted search**           | Finding all usages of a pattern, symbol, or convention                 | High grep/read volume; only the hit list matters                              |
| **Test execution**            | Running the test suite, interpreting failures                          | Test output is voluminous; only the failure summary needs to reach the parent |
| **Research**                  | Library/API usage patterns, new framework features, external docs     | Web/docs noise; only the actionable answer matters                            |
| **Parallel independent work** | Unrelated edits, simultaneous validations                              | Dispatchable concurrently without context collision                           |
| **Sanity audits**             | "Does this change break invariant Y", lint/style checks                | Read-only, focused, self-contained                                            |

**Anti-patterns, baked into the sandbox agent's system prompt:**

- **Don't spawn for trivial work.** Reading 2–3 files inline is faster than the dispatch overhead. Rough threshold: if the work would fit in < 10% of remaining context, don't delegate.
- **Don't delegate understanding.** The parent must never write "based on your findings, implement the fix" — that shoves synthesis onto the subagent. The parent must actually absorb the return, then decide.
- **Don't re-do subagent work.** If a subagent mapped the data flow, don't re-read the same files to double-check. Trust the return or clarify with a follow-up dispatch.
- **Don't spawn serially when parallel works.** Multiple independent subagent tasks should be dispatched in a single turn.

**Resource budget.** Subagents run **inside the same container** as the parent — they do not get their own sandbox or resource allocation. The CPU / RAM / disk budget for the run is shared across the parent and all its subagents. This matters when sizing a run: an implementation that fans out heavy parallel explorers should use a `large` or `xlarge` profile, because peak memory can stack several subagents' worth at once.

**Cost note.** Delegating to subagents generally **increases total token consumption** — the subagent's working context is overhead the inline version doesn't pay — but **improves the parent's context quality**, which is the bigger lever on run success. Oneshot explicitly trades tokens for quality here; it's the intended design choice, not an accident.

**Integration with the progress tracker.** The heartbeat payload includes `subagents_active`, `subagents_completed_total`, and `tokens_used_by_subagents_total`. This lets the operator see whether the agent is effectively leveraging delegation or plowing through everything inline. Optional: a `subagent` event type emitted by the `PreToolUse` hook on Task tool calls, capturing each subagent's stated purpose — useful for post-mortem of long runs but not required for v1.

**Where the prompt guidance lives.** The subagent rules and anti-patterns above are injected into every sandbox agent's system prompt as part of the container image's default Oneshot agent prompt — not per-run. That means updating the guidance is a framework-level change, not a per-project one, and every run gets the same operating manual.

### 5. Progress Tracker

**Role:** give the orchestrator (and human) a live, accurate view of every dispatched agent — whether it's running, thinking, stalled, or done — without requiring the CLI to be continuously connected or a long-running daemon on either side.

**Core primitive:** an append-only event log per run, `runs/{timestamp}/status.jsonl`, written by the agent's sandbox as it executes. State lives in files, not in process memory, so a CLI restart, network blip, or orchestrator crash never loses observability. The orchestrator is a *viewer* of this state, not a manager of it.

**Durability note:** all of the tracker's output files are written to the **server-persistent volume** mounted into the container, not to the container's ephemeral filesystem. When the container dies — gracefully, on crash, or via `/oneshot cancel` — the logs survive intact on the server. The orchestrator can still fetch them, compute the final state, and archive them to local. See *Storage Topology* for the full picture.

**Four files per run, each with a different audience and cost profile:**
- `status.jsonl` — **semantic events only** (`dispatched`, `running`, `phase`, `commit`, `pr_opened`, `ci_*`, `completed`, `failed`). Low-volume, agent-readable. This is the file other agents should read when they need historical context about a run.
- `heartbeats.jsonl` — compact numeric telemetry, one line per 30s interval. High-volume, **orchestrator-only**. Short field names, unix timestamps, no free-form strings. Explicitly designed to stay cheap in aggregate even on multi-hour runs.
- `current.json` — a single JSON object **overwritten** on every heartbeat tick. Captures the latest "what is it doing right now" snapshot including a short `current_activity` string. Constant-size regardless of run length. Used by `/oneshot watch` and `/oneshot status` for live display.
- `agent.log` — full agent stdout/stderr, for human debugging.

**Design rule (non-negotiable):** heartbeats must never enter an agent's context window. They are operational liveness telemetry for the orchestrator, nothing else. Any agent that needs to understand what happened during a run reads `status.jsonl` (semantic events) — which stays small precisely because heartbeats are separated out. Cost is bounded by construction, not by discipline.

#### Event schema

Append-only JSONL. Each line is a single JSON event with at minimum `ts` (ISO 8601 UTC) and `type`. Core event types for v1:

| Type                | When emitted                                                   | Key payload fields                                                 |
|---------------------|----------------------------------------------------------------|--------------------------------------------------------------------|
| `dispatched`        | orchestrator hands off the job (written locally)               | `run_id`, `host`, `container_spec`                                 |
| `received`          | sandbox runtime accepts the bundle                             | `container_id`                                                     |
| `running`           | agent process is alive and ready                               | `model`, `started_at`                                              |
| `heartbeat`         | periodic liveness ping (every 30s) — **persisted to `heartbeats.jsonl` and `current.json`, NOT `status.jsonl`** | compact numeric telemetry, see *Heartbeat telemetry* below |
| `phase`             | agent transitioned phase                                       | `phase` ∈ {exploring, implementing, testing, reviewing, fixing}    |
| `commit`            | agent made a git commit                                        | `sha`, `message`                                                   |
| `pr_opened`         | branch pushed, PR created                                      | `url`, `branch`, `commits`                                         |
| `ci_waiting`        | sandbox entering initial CI watch window                       | `pr_url`, `required_checks`                                        |
| `ci_pending`        | sandbox exiting with CI still running (detach)                 | `checks_running`                                                   |
| `ci_passed`         | all required checks green                                      | `checks_passed`                                                    |
| `ci_failed`         | one or more required checks red                                | `failing_checks`, `logs_ref`                                       |
| `ci_fix_dispatched` | fresh fix sandbox spawned to address failures                  | `attempt`, `parent_run_id`, `child_run_id`                         |
| `ci_blocked`        | CI blocked on human intervention (approval, secrets gate)      | `blocker`, `description`                                           |
| `completed`         | run finished successfully — **requires** `ci_passed` first     | `result_summary`                                                   |
| `failed`            | run hit a terminal failure                                     | `reason` ∈ {crashed, cancelled, ci_unfixable, ci_timeout, ...}, `last_phase` |

We deliberately do NOT emit an event per tool call — too chatty, would bloat the log and drown out the meaningful events. Heartbeats carry cumulative `tool_calls_total`; the tracker computes activity from deltas between heartbeats.

#### Heartbeat mechanism

- **Interval:** 30 seconds. Fast enough to detect crashes in a reasonable window, slow enough to keep log volume bounded (~120 lines/hour).
- **Generator:** a lightweight background loop inside the container, separate from the agent process. It reads a shared counters file (written by Claude Code hooks, see below) and on each tick: appends a compact line to `heartbeats.jsonl` AND overwrites `current.json` with the latest snapshot. Runs as a supervised sidecar so the agent crashing doesn't silently stop heartbeats mid-run.
- **Unresponsive threshold:** > 90 seconds since last heartbeat → state becomes `unresponsive`. Three missed heartbeats is a more robust signal than a single miss.

#### Heartbeat telemetry (compact format)

Heartbeats are high-volume by necessity (one every 30s → hundreds per run → thousands on multi-hour runs). The format is aggressively compact so that even if the log is ever read by an agent — post-mortem, iteration context, calibration analysis — the token cost stays bounded.

**Compact schema (`heartbeats.jsonl`, one line per interval):**

```jsonl
{"ts":1712760637,"e":30,"tc":8,"tk":4521,"ft":3,"sa":0,"sc":0,"stk":0}
{"ts":1712760667,"e":60,"tc":14,"tk":9842,"ft":6,"sa":1,"sc":0,"stk":241}
{"ts":1712760697,"e":90,"tc":22,"tk":15003,"ft":8,"sa":1,"sc":0,"stk":842}
```

| Field | Meaning                                |
|-------|----------------------------------------|
| `ts`  | unix timestamp (seconds)               |
| `e`   | elapsed seconds since run start        |
| `tc`  | cumulative tool calls                  |
| `tk`  | cumulative tokens used (parent agent)  |
| `ft`  | cumulative files touched               |
| `sa`  | subagents currently active             |
| `sc`  | cumulative subagents completed         |
| `stk` | cumulative tokens used by subagents    |

**Live-snapshot schema (`current.json`, overwritten each tick):**

```json
{"ts":1712760697,"e":90,"tc":22,"tk":15003,"ft":8,"sa":1,"sc":0,"stk":842,"phase":"implementing","act":"editing src/parser.rs"}
```

Same numeric fields as the log, plus `phase` (current agent phase) and `act` (short free-form activity string). The free-form string lives **only** here, never in the append-only log, so it can't accumulate into a large token cost. The file is constant-size regardless of run length.

**Why so aggressive.** A 4-hour run emits ~480 heartbeats. Verbose JSON with long field names and ISO timestamps runs ~250 chars/line → 120KB → roughly 30k tokens if ever inhaled into a context window. The compact format lands around 75 chars/line → 36KB → ~9k tokens for the same run. Dropping the free-form `act` field from the append log is the single biggest saving — everything else is linear scaling on short keys and integer timestamps.

**Why it matters even though agents "don't read heartbeats".** They *shouldn't* read heartbeats, per the design rule. But in practice: a reviewer debugging why a run stalled, an iterate flow pulling parent-run context, or a future calibration analyzer might read them on demand. The cost should be tolerable for those intentional lookups, not a trap.

#### How events are produced (agent stays untouched)

A critical design choice: the agent itself doesn't know it's being observed. No status-reporting skill, no "emit progress" tool, nothing in the prompt asking it to report. Events come from cross-cutting infrastructure, so the agent's cognitive budget stays fully on the implementation task.

Sources:
1. **Claude Code hooks** configured in the sandbox's `settings.json`:
   - `SessionStart` → emit `running` event, initialize counters file.
   - `PostToolUse` → increment tool_call counter; pattern-match the tool invocation to detect `git commit` / `gh pr create` and emit the corresponding `commit` / `pr_opened` events.
   - `Stop` → inspect final state, emit `completed` or `failed` accordingly.
2. **Background heartbeat loop** → emits `heartbeat` events on the 30s interval, reading the counters file populated by the hooks.
3. **Dispatcher** → emits `dispatched` locally and `received` on the server side.

Open question: phase transitions (`exploring` → `implementing` etc.) are harder to detect purely from hooks. Options: (a) let the agent emit phase via a simple file-write convention in its system prompt (minimal cognitive cost), or (b) infer from tool-use patterns (e.g., first Edit call after Reads = "implementing"). (a) is simpler but violates the "agent doesn't know it's observed" principle slightly. Defer to open questions.

#### Liveness vs progress — two distinct signals

This is the single most important distinction in the tracker design. An agent can be *alive but stuck*, and conflating this with "alive and working" is the main failure mode to avoid.

| Signal       | Source                                                                | Answers                          |
|--------------|------------------------------------------------------------------------|----------------------------------|
| **Liveness** | Timestamp of last `heartbeat`                                           | Is the process alive?             |
| **Progress** | Deltas in `tool_calls_total`, `commits`, `files_touched`, `phase`       | Is it *actually doing* something? |

A healthy run has both moving. A crashed agent stops emitting heartbeats entirely. A stuck agent keeps heartbeating but its progress counters flatline — it's burning tokens reasoning in circles, or wedged on a problem it can't solve. These need different human responses, so the tracker surfaces them separately.

#### Run state machine (orchestrator's derived view)

The orchestrator computes each run's state on demand from its event log + the current wall-clock time. No state is stored separately — it's always a pure function of the event log.

```
pending       → dispatched, no `received` event yet
running       → heartbeats flowing, progress counters advancing
thinking      → heartbeats flowing, no progress for 1–5 min
                 (normal pause for planning / long reasoning)
stalled       → heartbeats flowing, no progress for > 5 min
                 (investigate — likely wedged)
unresponsive  → no heartbeat for > 90s
                 (likely crashed; container may need inspection)
ci_waiting    → pr_opened seen; sandbox still inside initial CI watch
ci_pending    → sandbox exited with `ci_pending`; orchestrator is
                 polling CI externally via `gh pr checks`
ci_fixing     → a fresh fix sandbox is running (child run);
                 this parent run's state tracks the child
ci_blocked    → CI requires human intervention (approval/secrets);
                 no automatic progress possible
completed     → `ci_passed` + `completed` events seen
                 (PR open AND required CI green — the only terminal success)
failed        → terminal failure:
                   • `failed` event seen, OR
                   • unresponsive > 10 min, OR
                   • ci_fix_attempts exhausted → reason=ci_unfixable, OR
                   • ci_pending > ci.max_wait_s → reason=ci_timeout
```

**Critical:** `completed` is only reachable through `ci_passed`. A run that opened a PR but never got CI green is **not** completed — it's either `ci_pending`, `ci_fixing`, `ci_blocked`, or `failed`. This is how the success criteria from the Vision section is enforced mechanically.

All thresholds are v1 starting points — calibrate from real runs.

#### Orchestrator-side commands

Implementation is a thin shell over SSH and the event log — no daemon required for v1. See the Usage table above for the command surface (`/oneshot status`, `/oneshot watch`, `/oneshot logs`, `/oneshot cancel`).

- `/oneshot status` discovers runs by scanning `~/.claude/oneshot/*/runs/` locally for any run that hasn't reached a terminal state (`completed`/`failed`), then SSHs to the recorded host and `cat`s the tail of `status.jsonl` for each.
- `/oneshot watch <run_id>` opens an SSH session and runs `tail -f status.jsonl`, piping through a local renderer that formats events as human-readable lines.
- `/oneshot cancel <run_id>` resolves `run_id` → container id via the `received` event, then runs `ssh host docker kill <container>`. The `Stop` hook inside the container catches the termination and writes a `failed` event with `reason: cancelled`.

#### Example status.jsonl

Note: heartbeat events live in `heartbeats.jsonl` (see above), not here. `status.jsonl` contains only semantic events — a typical successful run fits in 10–20 lines regardless of duration.

```jsonl
{"ts":"2026-04-10T14:30:00Z","type":"dispatched","run_id":"r-2026-04-10-143000","host":"workstation.local"}
{"ts":"2026-04-10T14:30:04Z","type":"received","container_id":"c0f1a2b3"}
{"ts":"2026-04-10T14:30:07Z","type":"running","model":"claude-opus-4-6","started_at":"2026-04-10T14:30:07Z"}
{"ts":"2026-04-10T14:30:15Z","type":"phase","phase":"exploring"}
{"ts":"2026-04-10T14:31:22Z","type":"phase","phase":"implementing"}
{"ts":"2026-04-10T14:35:00Z","type":"commit","sha":"a1b2c3d","message":"feat: initial implementation"}
{"ts":"2026-04-10T14:38:11Z","type":"pr_opened","url":"https://github.com/victor/iron-lang/pull/42","branch":"oneshot/r-2026-04-10-143000","commits":3}
{"ts":"2026-04-10T14:38:13Z","type":"ci_waiting","pr_url":"https://github.com/victor/iron-lang/pull/42","required_checks":["lint","test-unit","test-integration"]}
{"ts":"2026-04-10T14:40:02Z","type":"ci_passed","checks_passed":["lint","test-unit","test-integration"]}
{"ts":"2026-04-10T14:40:03Z","type":"completed","result_summary":"PR #42 opened, 3 commits, 12 files touched, all required CI green"}
```

#### Directory layout update

`runs/{timestamp}/` now contains (additions marked `NEW`):

```
runs/{timestamp}/
├── requirements.md
├── discuss-transcript.md
├── scorer-log.md
├── status.jsonl        ← NEW  semantic events — low-volume, agent-readable
├── heartbeats.jsonl    ← NEW  compact numeric telemetry — orchestrator-only
├── current.json        ← NEW  latest live snapshot — overwritten each tick
├── agent.log           ← NEW  full agent stdout/stderr for debugging
├── result.json         ← NEW  written at `completed`: PR url, SHAs, summary
├── pr-review.md
└── human-feedback.md
```

`result.json` is a redundant but convenient summary of the terminal state — it lets the orchestrator answer "did this succeed and what's the PR link" without re-parsing the full event log.

**Cost profile at a glance:**
- `status.jsonl`: 10–20 lines per run, stays small regardless of duration — safe for agents to read.
- `heartbeats.jsonl`: ~120 lines/hour, compact — safe for orchestrator parsing, tolerable for intentional agent lookups.
- `current.json`: constant-size, one object — cheap everywhere.
- `agent.log`: unbounded, human-only — never read by agents for context.

### 6. CI Gate

**Role:** enforce that a run is only "done" when the PR is both opened *and* all required CI checks are passing. If CI fails, dispatch a fresh sandbox automatically to fix the failures — the agent owns the fix loop, not the operator.

**Shape:** the CI Gate is not a standalone service. It's a **protocol** that spans the original sandbox, the orchestrator, and one or more fix sandboxes. The glue is the `ci_*` events in `status.jsonl` and the orchestrator's state machine.

#### What counts as "required"

By default, Oneshot respects the repository's own definition — the checks marked as required in GitHub branch protection rules for the PR's target branch, queried via:

```
gh api repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks
```

Consequences:
- Non-required checks (coverage hints, optional linters) **do not** gate success.
- Repo with no branch protection → no required checks → run is trivially done the moment the PR opens.
- Operators who want stricter behavior override via `ci.required.mode: explicit` in `config.yml` with a named list of required checks.

#### Detach-and-reattach flow

The problem with naively "waiting for CI" inside the sandbox is that CI can take minutes to hours. Holding a container open for that is wasted compute and wastes a concurrent slot. Oneshot sidesteps this with a detach-and-reattach pattern:

```
ORIGINAL SANDBOX                                 ORCHESTRATOR (local)
────────────────                                 ────────────────────

agent opens PR  →  emit pr_opened
│
├─ emit ci_waiting
│
├─ watch `gh pr checks` inside container
│  for up to ci.initial_wait_s (default 120s)
│
├─ CI passes within the wait:
│   emit ci_passed, emit completed
│   sandbox exits cleanly  ───────────────────▶  run terminal: completed
│
├─ CI fails within the wait (required red):
│   emit ci_failed (with failing check list)
│   sandbox exits  ────────────────────────────▶  orchestrator picks up below
│
└─ CI still running at wait expiry:
    emit ci_pending
    sandbox exits cleanly (no wasted compute)
                                                  │
                                                  │  run is now ci_pending
                                                  ▼
                                  on /oneshot status (or background poll):
                                  run `gh pr checks <pr_url>` locally
                                                  │
                              ┌───────────────────┼───────────────────┐
                              │                   │                   │
                        still running        all required green    required failing
                              │                   │                   │
                              │                   ▼                   ▼
                              │         emit ci_passed      emit ci_failed
                              │         emit completed      dispatch fix sandbox
                              │                              (see below)
                              │
                              └── sleep ci.poll_interval_s, repeat
```

The key property: **the original sandbox never sits idle** waiting for CI. It either confirms success quickly, confirms failure quickly, or detaches cleanly and leaves the waiting to the (essentially free) orchestrator poller.

#### Fix sandbox

When required checks fail, the orchestrator dispatches a fresh sandbox with:

- **Same** container image, resource profile, skills/MCPs, and worktree as the original run.
- The original `requirements.md` from the parent run's bundle (so the intent stays anchored).
- **New context layered on top:**
  - The PR URL and its current diff
  - The list of failing check names
  - CI logs fetched via `gh run view --log-failed` for each failing check
  - A focused prompt: *"fix the failing CI checks below while preserving the intent of the original requirements."*

The fix sandbox pushes new commits to the **same branch** as the parent run — no new PR. The push triggers fresh CI, and the CI Gate loop repeats from the top with the fix run now in the `ci_waiting` state.

**Hierarchy:** each fix attempt is a child run logged under the parent:

```
runs/{timestamp}/
├── status.jsonl                  ← parent event log
├── result.json
├── bundle/                        ← parent bundle
├── fix-attempts/
│   ├── 1/
│   │   ├── status.jsonl
│   │   ├── agent.log
│   │   ├── result.json
│   │   └── bundle/
│   ├── 2/
│   │   └── ...
│   └── 3/
│       └── ...
└── ...
```

The parent's `status.jsonl` gets a `ci_fix_dispatched` event referencing the child run id. `/oneshot status <parent>` aggregates across children. `/oneshot status <child>` shows a single fix attempt.

**Attempt cap:** `ci.max_fix_attempts` (default 3). After the cap is reached, the parent run transitions to `failed` with `reason: ci_unfixable` and the operator takes over.

#### Reviewer gating

**The PR Reviewer (component 7) never runs on a red PR.** It is strictly gated on `ci_passed`. Reviewing a PR that still has failing CI would score a non-final state and pollute calibration data with noise. The reviewer kicks off from the orchestrator only after the run reaches `completed`.

#### Edge cases

- **No CI configured.** `gh pr checks` returns an empty list → treat as trivially passing. Run transitions to `completed` immediately after `pr_opened`.
- **Flaky check.** A check failed but re-running it passes. Configurable via `ci.flaky_retry` (default: one automatic retry via `gh run rerun --failed` before counting a check as a real failure).
- **CI blocked on human approval** (secrets gate, deployment environment, required manual review). Run enters `ci_blocked` state. The orchestrator surfaces the blocker in `/oneshot status`. The operator resolves upstream, then runs `/oneshot check-ci <run_id>` to force a re-poll. No agent dispatch — humans must resolve.
- **CI takes longer than the patience ceiling.** `ci.max_wait_s` (default 4 hours) bounds total `ci_pending` time. On expiry, run transitions to `failed` with `reason: ci_timeout`. The operator can manually re-poll later to recover if CI eventually finishes.
- **Agent pushes to the wrong branch** (e.g. the default branch of a fork). Caught at `pr_opened` time — validate the branch matches the expected pattern before emitting the event. Fail the run early rather than chasing CI on a runaway branch.

#### Config

```yaml
ci:
  initial_wait_s: 120          # how long the original sandbox watches CI before detaching
  poll_interval_s: 60          # how often orchestrator re-polls during ci_pending
  max_fix_attempts: 3          # automatic fix cycles before giving up
  max_wait_s: 14400            # 4 hour ceiling on total ci_pending time
  flaky_retry: true            # re-run a failed check once before treating as real
  required:
    mode: from_branch_protection    # from_branch_protection | explicit | none
    # explicit alternative:
    # mode: explicit
    # list:
    #   - lint
    #   - test-unit
    #   - test-integration
```

### 7. PR Reviewer

**Role:** independent review of the PR the agent opens.

**Scoring:** same four dimensions as the requirements scorer (correctness, quality, completeness, robustness). Ambiguity doesn't apply here — it's a pre-implementation concept.

**Outputs:**
- Scores per dimension + overall
- Targeted feedback questions for the human, focused on: decisions the agent made, gaps the reviewer spotted, anything surprising in the diff
- A `pr-review.md` saved to the run directory

**Why same dimensions as the requirements scorer:** so we can compute the delta (`predicted − actual`) and feed it back into `calibration.md`. This delta is the real signal — it's what makes the whole loop more than theater.

### 8. Iterate Loop

**Role:** restart the cycle with an existing PR as context.

`/oneshot iterate <PR>` re-enters the discuss loop, but:
- The current PR diff is attached as context
- The reviewer's scores and questions are attached
- The human's answers to the feedback questions are attached
- The scorer starts with the existing requirements as baseline, not from scratch

On the next pass, the agent updates the same PR branch rather than opening a new one.

---

## Scoring Model

### Dimensions

| Dimension        | Requirements                                     | PR Review                          |
|------------------|--------------------------------------------------|------------------------------------|
| **Correctness**  | Is what's being asked for clearly specified?     | Does the code do what was asked?   |
| **Quality**      | Are standards / conventions / constraints pinned down? | Does the code meet them?     |
| **Completeness** | Are all cases (edge, error, empty) spelled out?  | Are all cases handled?             |
| **Robustness**   | Are failure modes and invariants called out?     | Does it hold up under them?        |
| **Ambiguity** *(requirements only)* | How many unresolved interpretations remain? | N/A                      |

### Display Format (human-facing, per turn)

```
correctness 72 (+3) · quality 80 (±0) · completeness 55 (+8)
robustness 61 (+1) · ambiguity 70 (-2) → overall 68 (+2)
```

The **delta** is essential — it tells the human whether their last answer actually moved the needle. The per-dimension view tells them *where* to aim next.

### Thresholds (v1 starting points, calibrate over time)

- **Soft gate:** overall ≥ 75 to dispatch without friction.
- **Below threshold:** dispatch requires explicit `--force` — not blocked, but requires acknowledgment.
- **Plateau detection:** < 5 points overall movement across last 3 turns → scorer coaches discuss-agent.

---

## Global State Directory

**Location (operator's local machine):** `~/.claude/oneshot/{project_name}/`

This is the authoritative home for persistent project state — scorer inputs, calibration data, run archives. Nothing in this directory is ever written by the sandbox; see *Storage Topology* below for the full durability story.

**Why global, not in-repo:**
- Persists across repo clones, worktrees, and machines
- Doesn't pollute git history or require `.gitignore` entries
- Can be synced to the server sandbox without leaking into PRs
- Multiple operators on the same repo don't collide via git

### Project Identity

Slug derivation order:
1. `git remote get-url origin`, normalized (strip `.git`, scheme, etc.) — **preferred**, stable across clones.
2. Repo root folder name — fallback if no remote.
3. Manual override in a `.oneshot-project` marker file at repo root — escape hatch.

### Layout

```
~/.claude/oneshot/{project}/
├── project.md              # persistent facts the scorer uses
│                           # (stack, patterns, gotchas, conventions)
├── calibration.md          # {predicted, actual, delta, root_cause} tuples
├── config.yml              # thresholds, dimension weights,
│                           # sandbox resource defaults + profiles,
│                           # skills/MCP inheritance rules
├── runs/{timestamp}/       # one directory per oneshot cycle
│   ├── requirements.md     # sealed requirements bundle
│   ├── discuss-transcript.md
│   ├── scorer-log.md       # hidden scorer↔discuss coaching, audit trail
│   ├── pr-review.md        # reviewer agent output
│   └── human-feedback.md   # operator's answers to reviewer questions
└── index.md                # chronological run index
```

### `project.md`

Persistent project knowledge. Seeded once (manually or via an initial probe), updated as patterns emerge. Contains: tech stack, architectural conventions, common gotchas, past failure modes, coding standards, known-difficult areas. The scorer reads this to contextualize its scoring and coaching.

### `calibration.md`

Append-only ledger. Example entry:

```markdown
## run-2026-04-10-143022
- Predicted: correctness 82, quality 78, completeness 80, robustness 75, ambiguity 85 → 80
- Actual:    correctness 64, quality 81, completeness 58, robustness 70           → 68
- Delta:     correctness -18, quality +3, completeness -22, robustness -5 → -12
- Root cause: requirements pinned down the happy path in detail but left error
  semantics vague. Scorer flagged ambiguity at turn 4, discuss asked, human gave
  "handle it sensibly" — shipped anyway.
- Pattern tag: #vague-error-contracts
```

The scorer reads recent entries as few-shot examples. Over time, pattern tags accumulate into the scorer's understanding of *this project's* specific failure modes.

### `runs/{timestamp}/scorer-log.md`

Audit trail of every scorer intervention in that run:

```markdown
## Turn 4
- Score: overall 62 (plateau: +3, +1, +0 over last 3 turns)
- Intervention triggered: yes
- Guidance emitted: "Completeness (55) and ambiguity (60) are dragging the score.
  Discuss has covered happy path and data model, but nothing on error contracts
  or empty states. In this project, #vague-error-contracts has cost an average
  of 18 points on actual correctness. Probe error semantics next, frame around
  'what does the system do when X fails' not 'how should errors be handled'."
- Discuss-agent next question: [logged]
- Human response: [logged]
- Resulting score delta: [logged]
```

This makes the coaching loop auditable and — critically — gives high-quality root-cause data when PRs come back with bad scores.

---

## Storage Topology

Oneshot state lives in three tiers with clearly separated durability guarantees. Getting this separation right is what lets the framework survive the sandbox's normal lifecycle — containers crash, get killed, and are torn down after every run. **The sandbox is disposable by design; persistent state must not depend on it.**

### Three tiers

| Tier                    | Location                                     | Lifetime                                | Authoritative for                                                    |
|-------------------------|-----------------------------------------------|------------------------------------------|-----------------------------------------------------------------------|
| **Local**               | Operator's machine, `~/.claude/oneshot/`      | Persistent                               | `project.md`, `calibration.md`, `config.yml`, `scorer-log.md`, reviewer output, **all archived run history** |
| **Server-persistent**   | Server, e.g. `/var/lib/oneshot/runs/{ts}/`    | Outlives containers, pruned on schedule  | In-flight run artifacts: dispatch bundle, worktree, `status.jsonl`, `agent.log` |
| **Container-ephemeral** | Inside the running container                  | Dies with the container                  | Nothing load-bearing                                                  |

**The non-negotiable rule:** nothing load-bearing lives in the container-ephemeral tier. If a file would hurt to lose when the container dies, it must live in the server-persistent or local tier.

### Why this layering

Containers are torn down after every run, crash during runs, and may be killed manually via `/oneshot cancel`. Any state that depends on the container filesystem surviving beyond the run is state that gets regularly lost.

The **server-persistent** tier exists specifically to decouple run output from container lifetime. The container mounts a per-run volume (e.g. `/var/lib/oneshot/runs/{timestamp}/` on the host → `/workspace/run/` inside the container) and writes all artifacts there. When the container dies — gracefully or not — the volume and its contents remain, and the orchestrator can still read them via SSH.

The **local** tier is the final home for everything. Even the server-persistent tier is treated as transient staging: after a run terminates, its artifacts are rsynced back to local, and the server-side copy becomes eligible for cleanup.

### What lives where

**Always local, never written by the sandbox:**
- `project.md`, `calibration.md`, `config.yml` — the scorer reads these during discuss, which is itself local. Only *snapshots* ship to the sandbox in the dispatch bundle, and those snapshots are read-only to the agent. The live files are never touched by anything remote.
- `scorer-log.md` — written during the discuss phase (local) before dispatch even happens.
- `pr-review.md`, `human-feedback.md` — written after the sandbox has already terminated.
- Historical `runs/*/` archives — the authoritative long-term record for every completed run.

**Written during discussion, to the server-persistent volume of the discussion sandbox:**
- `exploration/transcript.jsonl` — every `sandbox_exec` call made during discuss.
- `exploration/artifacts/*` — files fetched via `sandbox_fetch`.
- `exploration/SUMMARY.md` — written by the discuss-agent at seal time.

These are rsynced back to local and folded into `runs/{timestamp}/bundle/exploration/` before the discussion container is torn down, so they become part of the local run archive regardless of sandbox lifetime.

**Written in the sandbox, to the server-persistent volume:**
- `status.jsonl` — semantic event log (low-volume, agent-readable).
- `heartbeats.jsonl` — compact numeric telemetry, one line per 30s (orchestrator-only).
- `current.json` — constant-size live snapshot, overwritten each heartbeat tick.
- `agent.log` — agent stdout/stderr for debugging.
- The worktree (agent's working copy of the repo).
- `result.json` — written when the run reaches `completed` or `failed`.

**Inside the container only (acceptable to lose):**
- Agent process memory and conversation context.
- `/tmp` files, shell state, package manager caches not explicitly mounted.

### Sync flow

```
DISPATCH                  RUN                             COMPLETION
────────                  ───                             ──────────

local  ──ship bundle──▶  server-persistent volume
                                │
                                │ container mounts volume,
                                │ writes artifacts throughout run
                                ▼
                         container-ephemeral
                                │
 local  ◀─SSH read on demand    │   (/oneshot status, watch, logs)
                                │
                         container dies
                                │
                     volume still has every event
                                │
                                ▼
 local  ◀──rsync volume → local archive──   runs/{timestamp}/
                                                 │
                                                 ▼
                                    local copy is now authoritative
```

### Crash recovery

- **Container crash mid-run:** the server-persistent volume retains every event up to the crash. `status.jsonl` shows the last `heartbeat` before silence; orchestrator marks the run `unresponsive` → `failed`. Operator can still fetch `agent.log` via `/oneshot logs` to diagnose.
- **CLI / orchestrator restart mid-run:** no state lost — the orchestrator holds no in-memory state. On next invocation it rediscovers runs by scanning local `runs/` and the server volume.
- **Network partition between local and server:** the run continues unimpeded; the sandbox doesn't depend on the orchestrator being connected. Events keep accumulating in the server volume. On reconnect, `/oneshot status` catches up.
- **Server reboot:** if the volume lives on persistent disk (not tmpfs), the event log survives — but the run itself is lost (process is dead). Operator can inspect what happened up to the reboot, then re-dispatch.
- **Local machine loss:** historical archives are lost unless separately backed up — same as any other local-only tool. In-flight state is recoverable from the server volume.

### Server-side cleanup

Server-persistent run directories are retained until both conditions hold:
1. The run has been successfully rsynced back to local and verified, **and**
2. A grace period (default 7 days, configurable via `config.yml`) has elapsed.

A `/oneshot server-gc` command walks the server and prunes anything meeting both criteria. **Never** prunes in-flight runs. **Never** prunes runs not yet archived locally. The conservative default keeps the blast radius of a bad gc invocation at zero.

---

## Calibration Loop

```
requirements scored → dispatch → agent implements → PR opened
                                                         │
                                                         ▼
                                          reviewer scores PR
                                                         │
                                                         ▼
                             delta = predicted − actual  ◄── THE SIGNAL
                                                         │
                                                         ▼
                  append to calibration.md with root cause
                                                         │
                                                         ▼
              next run's scorer reads this as few-shot context
                                                         │
                                                         ▼
                             scorer coaching gets sharper
```

The delta is what makes this more than theater. Without it, scoring is vibes with extra steps. With it, the scorer becomes calibrated against *this project's* actual failure modes.

### Cold Start

Early in project life, `calibration.md` is empty. The scorer coaches from general principles only. This degrades gracefully — less sharp but not broken. It sharpens automatically as runs accumulate, with no bootstrap dataset required.

---

## Open Questions

### Architecture
- **Sandbox tech:** Docker is the v1 pick, but do we need stronger isolation for GPU workloads? Docker's GPU story works, but cgroup limits on GPU memory are weaker than VRAM partitioning.
- **Dispatcher:** flat file + `flock` for v1. At what concurrency does it become insufficient? (Probably fine up to single-digit concurrent jobs on one server.)
- **GPU allocation:** single RTX 4080 means one GPU-using agent at a time. Queue? First-come-first-serve? Explicit reservation flag in the job bundle?

### Scorer mechanics
- **Plateau threshold:** starting at "< 5 points over 3 turns." Calibrate from real runs.
- **Soft-gate threshold:** starting at 75. Calibrate.
- **Dimension weights:** equal for v1. Do some dimensions predict outcomes better than others? The answer will emerge from `calibration.md` over time — don't hand-tune now.

### Discussion sandbox
- **Idle timeout default (30 min):** long enough for a distracted operator to come back from lunch, short enough to reclaim resources on abandoned sessions. Calibrate.
- **Hard cap (4 hours):** bounds pathological cases (laptop lid closed, network partition, human left for the day). Should this be a soft timeout with a `keep-alive` ping, or hard-kill?
- **What counts as an "exploration call"?** Just `sandbox_exec` / `sandbox_fetch`, or also MCP calls that happen to route through the sandbox? If an MCP call fails, does that trigger the capability-gap signal too? Probably yes — any remote capability check that fails is signal.
- **Multi-discussion concurrency:** can an operator run two discussions at once (two different `/oneshot start` sessions)? Each would need its own discussion sandbox. Probably yes, but worth naming explicitly.

### Implementation agent behavior
- **Subagent guidance: encouragement vs enforcement.** v1 uses system-prompt guidance (patterns + anti-patterns) rather than hard rules. Is that enough, or do we need enforcement — e.g. a hook that flags the agent when it's read > N files inline without delegating? Enforcement is more reliable but more intrusive; guidance is lighter but easier to ignore.
- **Subagent-heavy runs may need bigger profiles.** Peak memory stacks subagents. Should `/oneshot start` auto-bump the profile if the requirements look exploration-heavy, or leave sizing to the operator? Auto-bump is convenient but hides the cost.
- **Observing subagent efficiency.** Should `calibration.md` capture `subagents_spawned` and `tokens_used_by_subagents_total` per run? Over time, the ratio of subagent tokens to total tokens is likely a signal of implementation quality — runs with healthy delegation probably land better.

### Reviewer
- **Does the human also score alongside the reviewer agent?** Having a human ground-truth column in `calibration.md` would be valuable but adds operator friction. Optional for v1?
- **Draft vs ready PR:** does the agent always open as draft and let the human promote? Probably yes.

### CI Gate
- **Initial wait duration:** 120s is a guess. For fast CI (<2 min) it lets the sandbox resolve inline; for slow CI it's a wasted wait. Should the sandbox peek at historical CI timing for this repo to pick a smarter wait? Probably over-engineering for v1.
- **Background poller vs on-demand poll:** v1 polls CI only when the operator runs `/oneshot status` or when a fresh poll is triggered explicitly. That means a run sitting in `ci_pending` overnight doesn't advance until the operator checks in. Is this acceptable, or do we need a lightweight background cron? First option is simpler; second is more autonomous.
- **Fix-attempt scope creep:** the fix sandbox has the failing checks + logs, but should it also be allowed to *refactor* or only to *patch*? If CI fails because of a fundamental design flaw, narrow patching may not be enough. Hard call — lean toward "patching only, escalate if fix sandbox would need > N files changed" but that needs a mechanism.
- **Fix attempts and calibration:** should the number of fix attempts feed into `calibration.md` as a signal of initial-attempt quality? Arguably yes — a run needing 3 fix cycles is a different outcome than one passing CI first try, even if both end at `completed`. Likely a new "fix_attempts" column in the calibration tuple.
- **Non-GitHub forges:** `gh` CLI is GitHub-specific. GitLab, Forgejo, Gitea all have different CI query APIs. v1 is GitHub-only; multi-forge is a v2 concern. Worth an explicit non-goal?

### State management
- **`project.md` seeding:** manual write, or auto-probe on first run? Auto-probe is nicer UX but risks generating stale or wrong seed content. Hybrid: auto-probe then require human sign-off before first run?
- **`config.yml` generation:** should `/oneshot:new-project` auto-generate a starter `config.yml` with sensible default profiles (`small` / `medium` / `large` / `gpu`), default scoring thresholds, and an empty exclude list — rather than making the operator write one from scratch? Strong argument for yes: the configuration surface area is now large enough that a blank file is hostile on first use. Open sub-questions: (a) should the generated file be heavily commented to expose the knobs, or terse to stay out of the way? (b) does the initial exclude list ship empty, or pre-seeded from a "known-broken on first pass" starter list shared across projects?
- **`calibration.md` pruning:** does it grow unbounded? When do old entries stop being relevant? Probably fine forever at expected run volumes.
- **Run retention:** keep all runs forever? Prune old ones?

### Iterate loop
- **Re-entry point:** does iterate re-enter discuss or plan? Probably discuss — but if the PR review reveals a planning-level issue rather than a requirements issue, should there be a way to skip discuss and go straight to re-planning?
- **Branch strategy:** iterate updates the same PR branch, or opens a new PR that supersedes? Same-branch is simpler but loses the iteration history. Separate branches preserve history but fragment review.

### Scope
- **Multi-project calibration sharing:** should similar projects share calibration data? Probably not v1.
- **What does "task" mean as an input?** Freeform text? A linked issue? A phase from an existing GSD roadmap? All three, with different adapters?

---

## Next Steps

Before writing any code:

1. **Resolve top-blocker open questions** — especially: task input format, iterate re-entry point, `project.md` seeding strategy.
2. **Mock the display format** with a fake discuss loop to make sure the score display feels right at the terminal.
3. **Sketch the full state machine** (discuss → dispatch → implement → review → iterate) as a diagram before implementation.
4. **Pick concrete v1 numbers** for the soft-gate and plateau detection thresholds.
5. **Decide on the v1 scope cut** — what's the smallest version that tests the core bet (requirements scoring predicts PR quality)?

---

This is a living document. Everything above is the current shape of the design — not yet committed. Layer more in, mark up what's wrong, and we iterate against this doc instead of against chat scrollback.
