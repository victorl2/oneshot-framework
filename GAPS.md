# GAPS.md — Known gaps, unimplemented features, and untested paths

**Status as of 2026-04-13** — after closing gap blockers #1, #2, #4, #6, #7, #8. See the "Closed" section at the bottom.

This document inventories everything that's **not yet working** or **not yet tested** before we start exercising real-world tasks. Ordered by severity. Each entry has: what's missing, why it matters, and a rough fix approach. When a gap is closed, move it to a `## Closed` section at the bottom (or just delete the entry if trivial).

See [`DESIGN.md`](./DESIGN.md) for the canonical spec — this document tracks the delta from spec to current reality.

---

## 🔴 Blockers for a real repo one-shot task

These must be fixed before the framework can land a PR on a real repo (e.g. iron-lang). Without them, the agent can edit files and commit locally, but cannot push, cannot open a PR, and commits are misattributed.

### 3. No rsync-back mechanism
**What:** Run artifacts (`status.jsonl`, `heartbeats.jsonl`, `agent.log`, worktree with agent changes) live only on the server. The local side has the `dispatched` event and nothing else.
**Why:** DESIGN §"Storage Topology" says local is authoritative — at run end, the server-side artifacts should be rsynced to `~/.claude/oneshot/{project}/runs/{timestamp}/`. Without this, the operator can't review run history from their laptop.
**Fix:** Add a terminal phase to `oneshot-dispatch` (or a new `oneshot-reap` command) that rsyncs the server volume back to the local run dir once the run reaches a terminal state. Could run automatically on `oneshot-status` observing a terminal event.

---

## 🟠 Observability gaps (pipeline works, signal incomplete)

The hook path fires correctly and counters progress over time.

### 5. Token usage not tracked
**What:** `tokens_used_total` always reports 0. Claude Code's `PostToolUse` payload doesn't include token counts. The scorer and calibration would benefit from this data.
**Why:** Budget monitoring (`/oneshot status` showing cost), calibration delta analysis (cost vs quality), and cost caps all need real token numbers.
**Fix:** Check whether `Stop` hook or `--output-format stream-json` exposes token counts. If the former: update `hooks/stop.sh` to parse and emit. If the latter: process the stream in the entrypoint instead of calling `claude --print` naively.

---

## 🟡 Untested command paths

Commands exist as documented-but-stubby markdown files. None have been executed end-to-end yet except the dispatch path (which was tested via `bin/oneshot-dispatch`, not via `/oneshot start` as a slash command).

### 9. `/oneshot:new-project` end-to-end
**What:** The command markdown describes the flow, but no real project has been initialized through it. Does Claude Code correctly create `~/.claude/oneshot/{slug}/` with the right files? Does GSD artifact detection work?
**Fix:** Run it on a fresh project (e.g. iron-lang), verify the directory structure, `project.md` seeding, `config.yml` generation.

### 10. `/oneshot start` with real scorer/discuss subagents
**What:** The command now orchestrates `oneshot-discuss` + `oneshot-scorer` via Task, but this orchestration has never actually run. Does Claude Code spawn them correctly? Does the scorer's JSON output get parsed? Does the score display work? Does plateau detection fire?
**Fix:** Run `/oneshot start` on a real task and walk through the full discuss loop manually.

### 11. `/oneshot status` command
**What:** The markdown describes scanning `~/.claude/oneshot/*/runs/` locally and polling remote runs, but no real implementation exists. Running `/oneshot status` today just opens the markdown in Claude Code — no logic fires.
**Fix:** Implement the actual status-scanning logic (as a shell script in `bin/` that the command invokes, same pattern as `bin/oneshot-dispatch`).

### 12. `/oneshot watch <run_id>` command
**What:** Same as #11 — describes SSH tail + current.json polling, not implemented.
**Fix:** Create `bin/oneshot-watch` that does the SSH tail loop and renders events.

### 13. `/oneshot logs <run_id>` command
**What:** Same — describes `agent.log` streaming, not implemented.
**Fix:** Create `bin/oneshot-logs` wrapping `ssh host tail -f`.

### 14. `/oneshot cancel <run_id>` command
**What:** Same — describes SSH + `docker kill` / `podman kill`, not implemented.
**Fix:** Create `bin/oneshot-cancel` that resolves run_id → container via status.jsonl's `received` event, then kills.

### 15. `/oneshot iterate <PR>` command
**What:** Restart-the-cycle command, entirely unimplemented. Requires: PR context gathering, re-entering discuss with existing requirements as baseline, dispatching against the same branch.
**Fix:** Depends on PR Reviewer existing first. Tackle after #22.

---

## 🟡 CI Gate incomplete

### 16. No real end-to-end test of the CI Gate watch window
**What:** The detach-and-reattach code is in `entrypoint.sh` but has never actually executed against a real PR with real CI. Test repos so far have no `origin` remote.
**Fix:** Need a real repo with CI configured. The iron-lang repo itself has CI — once #1 (GitHub auth) is fixed, a real task will exercise this path.

### 17. Fix sandbox dispatch not implemented
**What:** When required CI checks fail, DESIGN §6 calls for automatic dispatch of a fresh "fix sandbox" with the failing logs as context. Currently the entrypoint just emits `failed` and exits.
**Why:** The "done = PR + CI green" contract can't be enforced without the automatic retry loop.
**Fix:** When CI Gate detects `ci_failed`, have the orchestrator (not the sandbox itself) dispatch a new run with the same bundle + PR diff + failing check logs appended. Tracked under `runs/{parent}/fix-attempts/{N}/`. Hard cap at `ci.max_fix_attempts`. This is a dispatcher change, not an entrypoint change.

### 18. Flaky retry logic not implemented
**What:** `ci.flaky_retry` in config.yml: re-run a failed check once before treating it as real failure. Not implemented.
**Fix:** In the CI Gate polling loop, if a required check fails, call `gh run rerun --failed` once and re-enter the wait, instead of immediately emitting `ci_failed`.

### 19. `ci_blocked` state not implemented
**What:** CI requires human approval (secrets gate, environment approval) → should enter `ci_blocked` state. Currently treated as still-running → eventually fails on timeout.
**Fix:** Parse `gh pr checks` output for approval-pending indicators and emit `ci_blocked` instead of continuing to poll.

---

## 🟡 Discussion Sandbox (entirely unimplemented)

Big chunk of DESIGN §2 has zero implementation. The discuss-agent runs locally and has no remote sandbox to probe during the conversation.

### 20. `sandbox_exec` / `sandbox_fetch` / `sandbox_status` tools
**What:** Three tools the discuss-agent needs for live exploration on the server during discuss. Don't exist.
**Why:** Without them, the operator can't verify capabilities before dispatch ("can the agent reach CloudWatch?"). Requirements are filed blind.
**Fix:** Implement as thin SSH-backed scripts in `bin/` that the discuss-agent can invoke. Lazy-spawn a long-lived container per discuss session.

### 21. Discussion container lifecycle
**What:** Spawn on first exploration call, persist across turns, destroy at seal.
**Fix:** Wrapper command `bin/oneshot-discuss-sandbox start|exec|fetch|status|stop`.

### 22. Exploration artifact capture into bundle
**What:** Summary.md + transcript.jsonl + artifacts/ from the discussion sandbox should ship in the dispatch bundle. Currently the bundle only has `requirements.md` + `project.md`.
**Fix:** At seal time, copy the exploration artifacts from the discussion sandbox into `bundle/exploration/` before tearing it down.

### 23. Capability-gap signal → scorer
**What:** Failed exploration calls should feed into the scorer as evidence of capability gaps. Not wired.
**Fix:** Update `oneshot-scorer` agent prompt to read `bundle/exploration/transcript.jsonl` if present.

---

## 🟡 PR Reviewer + Calibration (entirely unimplemented)

### 24. `oneshot-reviewer` unwired
**What:** Agent definition exists as a stub. No command spawns it, no orchestration.
**Why:** Without the reviewer, no delta between predicted and actual scores, no calibration loop, no feedback question flow. Huge chunk of the framework is inert.
**Fix:** Create a `bin/oneshot-review` script that takes a run_id, reads PR + artifacts, spawns the reviewer agent via `claude -p`, writes `pr-review.md`. Hook it up from `/oneshot status` (when run reaches `completed`, auto-trigger review) or as a separate `/oneshot review <run_id>` command.

### 25. `calibration.md` never written
**What:** Even if the reviewer existed, there's no code that appends `{predicted, actual, delta, root_cause}` tuples to `~/.claude/oneshot/{project}/calibration.md`.
**Fix:** Part of the reviewer's post-processing. After writing `pr-review.md`, also append a calibration entry.

### 26. Scorer reads calibration.md but there's nothing to read
**What:** Scorer agent prompt instructs it to read calibration.md for pattern matching. The file is created empty by `/oneshot:new-project`, so cold-start works, but the learning loop is dead until #25 lands.
**Fix:** Depends on #24 + #25. No code change needed here once those land.

---

## 🟡 Infrastructure gaps

### 27. Rootless Podman cgroup delegation not enabled
**What:** `--cpus` and `--memory` flags cause `crun` errors on rootless Podman without systemd cgroup delegation. Workaround: pass `--cpu none --memory none` to skip. Proper fix: enable delegation.
**Why:** Resource limits (`config.yml` sandbox profiles) are ignored when running rootless. A runaway agent could theoretically exhaust server resources.
**Fix:** Document how to enable delegation in a `README.md` setup section:
```
sudo mkdir -p /etc/systemd/system/user@.service.d
sudo tee /etc/systemd/system/user@.service.d/delegate.conf <<EOF
[Service]
Delegate=cpu cpuset io memory pids
EOF
sudo systemctl daemon-reload
loginctl terminate-user victor
```

### 28. `oneshot server-gc` not implemented
**What:** DESIGN §"Storage Topology" specifies a cleanup command that prunes old run directories from `~/oneshot-data/runs/` once they've been archived locally. Not implemented.
**Why:** Server disk usage grows unbounded as runs accumulate.
**Fix:** Create `bin/oneshot-server-gc` that checks which runs have been successfully rsynced back to local (requires #3 first) and prunes anything beyond the grace period. Conservative defaults.

### 29. Container cleanup on failure
**What:** When a run fails, the container stays around on the server (exited state). Cleanup is manual via `podman rm -f`.
**Why:** Stale containers clutter `podman ps -a` output and consume minor disk.
**Fix:** Dispatcher can run containers with `--rm` flag so they auto-remove on exit. Need to make sure the volume (run dir) survives — `--rm` only removes the container layer, not mounted volumes.

---

## 🟢 Polish items (low priority)

### 30. Commit sha regex may miss some git output formats
**What:** The PostToolUse hook's sha extraction regex assumes git prints `[branch sha] message` on commit. Works for standard commits, may miss edge cases (initial commit on empty branch, merges, etc.).
**Fix:** Swap to running `git rev-parse HEAD` after detecting the commit instead of regex-parsing stdout.

### 31. Default heartbeat interval is 30s, too long for short runs
**What:** Runs under 30s only get the initial e=0 heartbeat. Default could be 10s.
**Fix:** Change `ONESHOT_HEARTBEAT_INTERVAL_S` default in Dockerfile from 30 to 10.

### 32. No version migration on reinstall
**What:** `install.sh` overwrites existing files without warning if versions differ. No migration of `~/.claude/oneshot/*/config.yml` etc.
**Fix:** Compare `$ONESHOT_DIR/VERSION` against `SOURCE_DIR/VERSION` and warn/confirm if different.

### 33. No local status.jsonl mirroring during run
**What:** Only the `dispatched` event is written to the local run dir. The rest of the event stream lives remotely and has to be fetched. `/oneshot status` will need to always SSH.
**Fix:** Optional: have `/oneshot status` cache the last polled `status.jsonl` locally for faster subsequent reads.

### 34. Heartbeat timestamp is unix seconds but status.jsonl uses ISO 8601
**What:** Inconsistent timestamp formats across files.
**Fix:** Pick one (probably ISO 8601 for consistency with status.jsonl) and apply everywhere. Compact heartbeat would still be tiny — ISO adds ~10 chars per line.

---

## What's solid (not gaps — just for completeness)

- ✅ install.sh → copies commands, agents, templates, references to `~/.claude/`, rewrites `@~/` paths correctly, supports `--dry-run` + `--uninstall`
- ✅ Sandbox Dockerfile → Debian + Node + Claude Code CLI + gh + jq + non-root user, builds natively on x86_64 server
- ✅ entrypoint.sh → initializes observability, starts sidecar, runs claude or demo, EXIT trap handles terminal events
- ✅ heartbeat-loop.sh → compact telemetry, atomic current.json writes
- ✅ PostToolUse hook → parses real Claude Code payloads, tracks tool_calls_total, files_touched, subagents_completed_total, detects commit + pr_opened patterns
- ✅ Dispatcher bundle validation, rsync, Podman launch with `--userns=keep-id`, SELinux `:Z` labels, auth mount
- ✅ Subscription auth via `claude setup-token` on server + `~/.claude/` mount
- ✅ CI Gate watch loop (code exists, polling logic correct — just untested end-to-end)
- ✅ Scorer agent spec (JSON contract, cold-start, coach mode) — agent defined, orchestration untested
- ✅ Discuss agent spec (one-question-per-turn, mandatory error-semantics probe, scorer checkpoint-pull) — agent defined, orchestration untested

---

## Priority ordering for closing gaps before real iron-lang test

Minimum to unblock a real iron-lang task landing a PR:
1. ~~**#1 GitHub auth in container**~~ ✅ closed
2. ~~**#2 Git identity**~~ ✅ closed
3. ~~**#4 Phase tracking**~~ ✅ closed
4. ~~**#6 + #7 + #8 Final heartbeat/result.json**~~ ✅ closed

**Remaining blocker**: #3 Rsync-back is nice-to-have but not strictly required for the first real test — runs just live on the server until we add it.

Nice-to-have before real test but not strictly required:
- **#11-14 Status/watch/logs/cancel commands** (convenience during the run)

Defer until after first real task:
- Everything else (#15–34)

---

## Closed

### ✅ #1 GitHub auth in container
**Closed in:** commit `fceedf7` (2026-04-13)
**Resolution:** Dispatcher detects `~/.config/gh/` on the server, mounts it at `/home/oneshot/.config/gh` rw with `:Z` labels. Logs a warning with setup command if absent. Dockerfile creates the mount target. Verified locally via `make test-sandbox`.

### ✅ #2 Git identity
**Closed in:** commit `fceedf7` (2026-04-13)
**Resolution:** Dispatcher resolves operator's local `git config --global user.name/email` (or `GIT_AUTHOR_*` env vars) and passes as `ONESHOT_GIT_NAME` / `ONESHOT_GIT_EMAIL`. Entrypoint sets git global config from those env vars. Falls back to synthetic identity only if both unset. Also adds `/workspace/repo` as a git `safe.directory` to avoid ownership warnings on bind-mounted volumes.

### ✅ #4 Phase tracking via heuristic
**Closed in:** commit `fceedf7` (2026-04-13)
**Resolution:** PostToolUse hook now transitions phase monotonically based on tool patterns: Read/Grep/Glob→exploring, Edit/Write/MultiEdit→implementing, Bash matching test-runners→testing, git commit→reviewing. `advance_phase()` enforces monotonicity — subsequent Reads don't regress the phase back.

### ✅ #6 + #7 Final heartbeat + elapsed_s update
**Closed in:** commit `fceedf7` (2026-04-13)
**Resolution:** Entrypoint cleanup trap calls `emit_final_heartbeat()` after killing the sidecar. Writes one final compact line to `heartbeats.jsonl` and updates `.counters.elapsed_s` to the real post-run elapsed time. Verified locally: demo run now ends with e=15 final tick instead of stopping at the last sidecar iteration.

### ✅ #8 result.json summary
**Closed in:** commit `fceedf7` (2026-04-13)
**Resolution:** Entrypoint cleanup trap calls `write_result_json()` which parses `status.jsonl` for terminal state, PR URL, and commit shas, then writes a compact summary: `{run_id, final_state, pr_url, commits[], tool_calls, files_touched, elapsed_s, written_at}`. Verified locally in the demo run.

---

*This document is a living inventory. Update as gaps close or new ones emerge. Keep entries terse; if a gap needs a deep dive, write it up in `DESIGN.md` and link back.*
