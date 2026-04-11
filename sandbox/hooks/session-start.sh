#!/usr/bin/env bash
# Claude Code SessionStart hook for Oneshot sandbox.
#
# Fires once when the Claude Code session starts inside the container.
# Responsibility: ensure counters are initialized and emit a `running`
# event if one hasn't already been emitted by the entrypoint.
#
# Hook contract: receives JSON on stdin per Claude Code's hook protocol.
# For v0 we ignore the payload — initialization is the same regardless.
#
# Status: STUB. The entrypoint script currently handles initialization
# directly; this hook becomes active when real Claude Code is wired in.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

# Drain stdin (Claude Code sends a JSON payload we don't currently use).
[[ -t 0 ]] || cat >/dev/null

# Ensure counters exist — no-op if entrypoint already initialized them.
if [[ ! -f "$COUNTERS_FILE" ]]; then
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
  "act": "session_start",
  "started_at": $(date +%s)
}
EOF
fi

# Emit running event if not already present.
if ! grep -q '"type":"running"' "$STATUS_FILE" 2>/dev/null; then
  oneshot_emit_status "{\"ts\":\"$(oneshot_iso_now)\",\"type\":\"running\",\"model\":\"${ONESHOT_MODEL:-unknown}\",\"started_at\":\"$(oneshot_iso_now)\"}"
fi
