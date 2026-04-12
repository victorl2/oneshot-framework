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

# Cleanup on exit: stop the heartbeat and emit terminal event if none exists.
cleanup() {
  local exit_code=$?
  if kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi

  if has_event "completed" || has_event "failed"; then
    # Terminal event already written by the agent itself.
    exit "$exit_code"
  fi

  if [[ $exit_code -eq 0 ]]; then
    emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"completed\",\"result_summary\":\"entrypoint exited with code 0 (no explicit terminal event)\"}"
  else
    emit_status "{\"ts\":\"$(iso_now)\",\"type\":\"failed\",\"reason\":\"exit_code_$exit_code\",\"last_phase\":\"$(jq -r '.phase // "unknown"' "$COUNTERS_FILE")\"}"
  fi
  exit "$exit_code"
}
trap cleanup EXIT

# Run the agent. Priority:
#   1. Explicit command passed as arguments → exec that
#   2. ANTHROPIC_API_KEY set + bundle present → run Claude Code against the bundle
#   3. Otherwise → demo-agent simulation
if [[ $# -gt 0 ]]; then
  "$@" 2>&1 | tee -a "$AGENT_LOG"
elif [[ -n "${ANTHROPIC_API_KEY:-}" ]] && [[ -f "$RUN_DIR/bundle/requirements.md" ]]; then
  echo "[oneshot] ANTHROPIC_API_KEY set + bundle found — running Claude Code agent" | tee -a "$AGENT_LOG"

  SYSTEM_PROMPT="/usr/local/share/oneshot/system-prompt.md"
  SETTINGS="/usr/local/share/oneshot/settings.json"
  BUDGET="${ONESHOT_BUDGET_USD:-10}"
  RUN_ID="${ONESHOT_RUN_ID:-unknown}"

  # Build the prompt from the requirements file
  PROMPT="$(cat "$RUN_DIR/bundle/requirements.md")"

  # Configure git for the agent (needed for commits)
  git config --global user.name "oneshot-agent"
  git config --global user.email "oneshot@localhost"
  git config --global init.defaultBranch main

  # Run Claude Code in headless mode
  #   --print            → non-interactive, exits when done
  #   --dangerously-skip-permissions → auto-approve all tool calls (sandbox is isolated)
  #   --system-prompt-file → our implementation agent prompt
  #   --settings         → our hooks for event emission
  #   --max-budget-usd   → cost cap
  claude \
    --print \
    --dangerously-skip-permissions \
    --system-prompt-file "$SYSTEM_PROMPT" \
    --settings "$SETTINGS" \
    --add-dir "$RUN_DIR/bundle" \
    --max-budget-usd "$BUDGET" \
    "$PROMPT" \
    2>&1 | tee -a "$AGENT_LOG"
else
  echo "[oneshot] no API key or no bundle — running demo-agent simulation" | tee -a "$AGENT_LOG"
  /usr/local/lib/oneshot/demo-agent.sh 2>&1 | tee -a "$AGENT_LOG"
fi
