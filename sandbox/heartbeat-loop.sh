#!/usr/bin/env bash
# Oneshot heartbeat sidecar
#
# Runs as a background process inside the sandbox container. Every
# ONESHOT_HEARTBEAT_INTERVAL_S seconds it:
#
#   1. Reads the shared counters file (.counters)
#   2. Updates elapsed_s based on wall-clock vs started_at
#   3. Appends a compact line to heartbeats.jsonl (numeric telemetry only)
#   4. Overwrites current.json with the full latest snapshot (including
#      free-form phase/act strings used by /oneshot watch for live display)
#
# Design rule (from DESIGN.md §5): heartbeats.jsonl is compact and must
# never contain free-form strings — those live only in current.json, which
# is constant-size regardless of run length.

set -euo pipefail

RUN_DIR="${ONESHOT_RUN_DIR:-/workspace/run}"
COUNTERS_FILE="$RUN_DIR/.counters"
HEARTBEAT_FILE="$RUN_DIR/heartbeats.jsonl"
CURRENT_FILE="$RUN_DIR/current.json"
INTERVAL="${ONESHOT_HEARTBEAT_INTERVAL_S:-30}"

# Don't crash the container if the counters file isn't present — just exit quietly.
[[ -f "$COUNTERS_FILE" ]] || exit 0

started_at="$(jq -r '.started_at' "$COUNTERS_FILE")"

while true; do
  now="$(date +%s)"
  elapsed=$(( now - started_at ))

  # Update elapsed_s in the counters file (atomic-ish via temp + mv).
  tmp="$(mktemp)"
  jq --argjson e "$elapsed" '.elapsed_s = $e' "$COUNTERS_FILE" > "$tmp" \
    && mv "$tmp" "$COUNTERS_FILE"

  # Append compact heartbeat to heartbeats.jsonl.
  # Short keys, numeric only. See DESIGN.md §5 "Heartbeat telemetry".
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

  # Overwrite current.json with the full live snapshot (including free-form strings).
  # Atomic write via temp + mv so readers never see a partial file.
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
  }' "$COUNTERS_FILE" > "$tmp" \
    && mv "$tmp" "$CURRENT_FILE"

  sleep "$INTERVAL"
done
