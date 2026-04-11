#!/usr/bin/env bash
# Claude Code Stop hook for Oneshot sandbox.
#
# Fires when the Claude Code session ends. Responsibility: emit the
# terminal event (`completed` or `failed`) if the agent itself didn't
# already do so.
#
# Note: the CI Gate requires `completed` to be preceded by `ci_passed`.
# This hook must not emit `completed` unilaterally — the agent is expected
# to emit its own terminal events after driving CI green. If the session
# stops without those events, this hook emits `failed` with reason
# `stopped_without_terminal_event`.
#
# Status: STUB. The entrypoint's cleanup trap currently handles fallback
# terminal events. This hook becomes authoritative once real Claude Code
# is wired in.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

# Drain stdin — Claude Code sends a JSON payload we don't currently use.
[[ -t 0 ]] || cat >/dev/null

# If a terminal event is already present, do nothing.
if grep -q '"type":"completed"' "$STATUS_FILE" 2>/dev/null \
|| grep -q '"type":"failed"' "$STATUS_FILE" 2>/dev/null; then
  exit 0
fi

# Session ended without the agent emitting a terminal event.
# Treat this as a failure — the agent's contract is to drive the run to
# a known terminal state before stopping.
last_phase=$(jq -r '.phase // "unknown"' "$COUNTERS_FILE" 2>/dev/null || echo "unknown")
oneshot_failed "stopped_without_terminal_event" "$last_phase"
