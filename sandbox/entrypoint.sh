#!/usr/bin/env bash
# Oneshot sandbox entrypoint
#
# Initializes the observability pipeline, starts the heartbeat sidecar,
# and runs the agent (or a demo simulation if no command was provided).
#
# Responsibilities:
#   1. Lay down the run directory structure on the mounted volume
#   2. Initialize the shared counters file
#   3. Emit the `running` event to status.jsonl
#   4. Start heartbeat-loop in the background
#   5. Exec the agent command (or demo-agent.sh if none provided)
#   6. On exit, stop the heartbeat and emit completed/failed (if not already)
#
# See DESIGN.md §5 (Progress Tracker).

set -euo pipefail

RUN_DIR="${ONESHOT_RUN_DIR:-/workspace/run}"
STATUS_FILE="$RUN_DIR/status.jsonl"
HEARTBEAT_FILE="$RUN_DIR/heartbeats.jsonl"
CURRENT_FILE="$RUN_DIR/current.json"
AGENT_LOG="$RUN_DIR/agent.log"
COUNTERS_FILE="$RUN_DIR/.counters"
MODEL="${ONESHOT_MODEL:-unknown}"

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

emit_status() {
  # Append a single JSON event to status.jsonl.
  # $1 is the fully-formed JSON object (no trailing newline).
  printf '%s\n' "$1" >> "$STATUS_FILE"
}

has_event() {
  # True if status.jsonl already contains an event of the given type.
  [[ -f "$STATUS_FILE" ]] && grep -q "\"type\":\"$1\"" "$STATUS_FILE"
}

# Lay down run directory structure and zero-out files.
mkdir -p "$RUN_DIR"
touch "$STATUS_FILE" "$HEARTBEAT_FILE" "$AGENT_LOG"

# Initialize the shared counters file. Heartbeat loop reads from here;
# hooks (or the demo agent) write to here.
started_epoch="$(date +%s)"
cat > "$COUNTERS_FILE" <<EOF
{
  "elapsed_s": 0,
  "tool_calls_total": 0,
  "tokens_used_total": 0,
  "files_touched": 0,
  "subagents_active": 0,
  "subagents_completed_total": 0,
  "tokens_used_by_subagents_total": 0,
  "phase": "booting",
  "act": "entrypoint",
  "started_at": $started_epoch
}
EOF

# Initial current.json snapshot so /oneshot watch has something to read immediately.
jq -c '.' "$COUNTERS_FILE" > "$CURRENT_FILE"

# Emit `running` event.
emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"running\",\"model\":\"$MODEL\",\"started_at\":\"$(iso_now)\"}"

# Start heartbeat sidecar in background.
/usr/local/bin/oneshot-heartbeat &
HEARTBEAT_PID=$!

# Emit a single compact heartbeat line using current counter values.
# Used both by the sidecar and by the cleanup trap's final tick.
emit_final_heartbeat() {
  local now elapsed
  now=$(date +%s)
  elapsed=$(( now - started_epoch ))

  # Update elapsed_s in counters so the final state isn't stale.
  local tmp
  tmp="$(mktemp)"
  jq --argjson e "$elapsed" '.elapsed_s = $e' "$COUNTERS_FILE" > "$tmp" && mv "$tmp" "$COUNTERS_FILE"

  # Append compact heartbeat.
  jq -c --argjson now "$now" '{
    ts: $now,
    e: .elapsed_s,
    tc: .tool_calls_total,
    tk: .tokens_used_total,
    ft: .files_touched,
    sa: .subagents_active,
    sc: .subagents_completed_total,
    stk: .tokens_used_by_subagents_total
  }' "$COUNTERS_FILE" >> "$HEARTBEAT_FILE"

  # Overwrite current.json with the full snapshot.
  tmp="$(mktemp)"
  jq -c --argjson now "$now" '{
    ts: $now,
    e: .elapsed_s,
    tc: .tool_calls_total,
    tk: .tokens_used_total,
    ft: .files_touched,
    sa: .subagents_active,
    sc: .subagents_completed_total,
    stk: .tokens_used_by_subagents_total,
    phase: .phase,
    act: .act
  }' "$COUNTERS_FILE" > "$tmp" && mv "$tmp" "$CURRENT_FILE"
}

# Write a result.json summary by parsing status.jsonl for terminal state.
# Extracts: pr_url, commit shas, final state, elapsed, tool_calls_total.
write_result_json() {
  local result_file="$RUN_DIR/result.json"
  local final_state pr_url commits_json shas_json tc ft

  final_state="$(jq -r -s 'map(select(.type == "completed" or .type == "failed")) | last | .type // "unknown"' "$STATUS_FILE" 2>/dev/null || echo unknown)"
  pr_url="$(jq -r -s 'map(select(.type == "pr_opened")) | last | .url // ""' "$STATUS_FILE" 2>/dev/null || echo "")"
  shas_json="$(jq -s '[.[] | select(.type == "commit") | .sha]' "$STATUS_FILE" 2>/dev/null || echo '[]')"
  tc="$(jq -r '.tool_calls_total // 0' "$COUNTERS_FILE" 2>/dev/null || echo 0)"
  ft="$(jq -r '.files_touched // 0' "$COUNTERS_FILE" 2>/dev/null || echo 0)"
  local elapsed
  elapsed="$(jq -r '.elapsed_s // 0' "$COUNTERS_FILE" 2>/dev/null || echo 0)"

  jq -n \
    --arg run_id "${ONESHOT_RUN_ID:-unknown}" \
    --arg state "$final_state" \
    --arg pr "$pr_url" \
    --argjson shas "$shas_json" \
    --argjson tc "$tc" \
    --argjson ft "$ft" \
    --argjson elapsed "$elapsed" \
    '{
      run_id: $run_id,
      final_state: $state,
      pr_url: (if $pr == "" then null else $pr end),
      commits: $shas,
      tool_calls: $tc,
      files_touched: $ft,
      elapsed_s: $elapsed,
      written_at: (now | todate)
    }' > "$result_file" 2>/dev/null || true
}

# Cleanup on exit: stop the heartbeat and emit terminal event if none exists.
cleanup() {
  local exit_code=$?
  if kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi

  # Final heartbeat tick — captures the real elapsed_s and post-run
  # counter values after the sidecar was killed mid-sleep.
  emit_final_heartbeat

  if has_event "completed" || has_event "failed"; then
    # Terminal event already written by the agent itself or by the CI Gate.
    write_result_json
    exit "$exit_code"
  fi

  if [[ $exit_code -eq 0 ]]; then
    emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"completed\",\"result_summary\":\"entrypoint exited with code 0 (no explicit terminal event)\"}"
  else
    emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"failed\",\"reason\":\"exit_code_$exit_code\",\"last_phase\":\"$(jq -r '.phase // "unknown"' "$COUNTERS_FILE")\"}"
  fi

  write_result_json
  exit "$exit_code"
}
trap cleanup EXIT

# Run the agent. Priority:
#   1. Explicit command passed as arguments → exec that
#   2. ANTHROPIC_API_KEY set + bundle present → run Claude Code against the bundle
#   3. Otherwise → demo-agent simulation
if [[ $# -gt 0 ]]; then
  "$@" 2>&1 | tee -a "$AGENT_LOG"
elif [[ -f "$RUN_DIR/bundle/requirements.md" ]]; then
  echo "[oneshot] bundle found — running Claude Code agent with subscription auth" | tee -a "$AGENT_LOG"

  SYSTEM_PROMPT="/usr/local/share/oneshot/system-prompt.md"
  SETTINGS="/usr/local/share/oneshot/settings.json"
  BUDGET="${ONESHOT_BUDGET_USD:-10}"
  RUN_ID="${ONESHOT_RUN_ID:-unknown}"

  # Build the prompt from the requirements file
  PROMPT="$(cat "$RUN_DIR/bundle/requirements.md")"

  # Configure git for the agent. Identity comes from the operator via env
  # vars (ONESHOT_GIT_NAME / ONESHOT_GIT_EMAIL) set by the dispatcher from
  # the operator's local git config. Falls back to a clearly-synthetic
  # identity if none provided (smoke tests, missing config).
  git config --global user.name "${ONESHOT_GIT_NAME:-oneshot-agent}"
  git config --global user.email "${ONESHOT_GIT_EMAIL:-oneshot@localhost}"
  git config --global init.defaultBranch main

  # Safe directory for the mounted repo (rootless Podman with keep-id maps
  # the volume owner correctly, but git can still complain about ownership
  # differences when paths are bind-mounted).
  git config --global --add safe.directory /workspace/repo

  claude \
    --print \
    --dangerously-skip-permissions \
    --system-prompt-file "$SYSTEM_PROMPT" \
    --settings "$SETTINGS" \
    --add-dir "$RUN_DIR/bundle" \
    --max-budget-usd "$BUDGET" \
    "$PROMPT" \
    2>&1 | tee -a "$AGENT_LOG"

  claude_exit=$?
  echo "[oneshot] claude exited with code $claude_exit" | tee -a "$AGENT_LOG"

  # CI Gate — detach-and-reattach watch window.
  #
  # If the agent opened a PR (we can detect this via `gh pr view` in the repo),
  # watch CI for up to CI_INITIAL_WAIT_S seconds. The three outcomes map
  # to terminal events:
  #   - All required checks green within window → emit ci_passed + completed
  #   - Any required check fails within window  → emit ci_failed + failed
  #   - Still running at window expiry          → emit ci_pending, exit clean
  #                                                (orchestrator polls externally)
  #
  # This is v0 — no fix-sandbox dispatching yet. See DESIGN.md §6.
  CI_INITIAL_WAIT_S="${CI_INITIAL_WAIT_S:-120}"

  if [[ $claude_exit -eq 0 ]] && [[ -d /workspace/repo ]] && command -v gh >/dev/null 2>&1; then
    cd /workspace/repo 2>/dev/null || cd "$RUN_DIR"

    # Check if a PR is associated with the current branch.
    pr_json="$(gh pr view --json url,state,headRefName,commits 2>/dev/null || echo '')"

    if [[ -n "$pr_json" ]]; then
      pr_url="$(echo "$pr_json" | jq -r '.url // ""')"
      pr_branch="$(echo "$pr_json" | jq -r '.headRefName // ""')"
      pr_commits="$(echo "$pr_json" | jq -r '(.commits // []) | length')"

      if [[ -n "$pr_url" ]]; then
        echo "[oneshot] PR detected: $pr_url — entering CI Gate watch window (${CI_INITIAL_WAIT_S}s)" | tee -a "$AGENT_LOG"

        # Emit pr_opened if the hook didn't already
        if ! grep -q '"type":"pr_opened"' "$STATUS_FILE"; then
          emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"pr_opened\",\"url\":\"$pr_url\",\"branch\":\"$pr_branch\",\"commits\":${pr_commits:-1}}"
        fi

        # Enumerate required checks (from branch protection).
        # If none configured, treat as trivially passing.
        required_checks="$(gh pr checks --required 2>/dev/null || echo '')"
        if [[ -z "$required_checks" ]]; then
          echo "[oneshot] no required CI checks configured — treating as passed" | tee -a "$AGENT_LOG"
          emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"ci_passed\",\"checks_passed\":[]}"
          emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"completed\",\"result_summary\":\"PR $pr_url opened; no required CI checks\"}"
        else
          emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"ci_waiting\",\"pr_url\":\"$pr_url\"}"

          # Poll gh pr checks until terminal or timeout.
          start=$(date +%s)
          while true; do
            now=$(date +%s)
            elapsed=$(( now - start ))
            if (( elapsed >= CI_INITIAL_WAIT_S )); then
              echo "[oneshot] CI still running at watch expiry — detaching (ci_pending)" | tee -a "$AGENT_LOG"
              emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"ci_pending\",\"elapsed_s\":$elapsed}"
              break
            fi

            status="$(gh pr checks --required 2>&1 || true)"
            # gh pr checks exits 0 if all pass, 8 if pending, non-zero + 8 otherwise.
            rc=$?

            if [[ $rc -eq 0 ]]; then
              echo "[oneshot] CI passed — all required checks green" | tee -a "$AGENT_LOG"
              emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"ci_passed\",\"elapsed_s\":$elapsed}"
              emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"completed\",\"result_summary\":\"PR $pr_url CI green\"}"
              break
            fi

            # Any failing check means ci_failed, even if others are pending.
            if echo "$status" | grep -qE '(fail|FAIL|error|ERROR)'; then
              failing="$(echo "$status" | grep -E '(fail|FAIL|error|ERROR)' | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')"
              echo "[oneshot] CI failed — failing checks: $failing" | tee -a "$AGENT_LOG"
              emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"ci_failed\",\"failing_checks\":[\"$failing\"],\"elapsed_s\":$elapsed}"
              emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"failed\",\"reason\":\"ci_failed\",\"last_phase\":\"ci_waiting\"}"
              break
            fi

            sleep 10
          done
        fi
      fi
    fi
  fi
else
  echo "[oneshot] no bundle — running demo-agent simulation" | tee -a "$AGENT_LOG"
  /usr/local/lib/oneshot/demo-agent.sh 2>&1 | tee -a "$AGENT_LOG"
fi
