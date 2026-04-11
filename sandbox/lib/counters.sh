#!/usr/bin/env bash
# Shared helpers for updating the Oneshot counters file and emitting events.
#
# Sourced by demo-agent.sh and by the Claude Code hook scripts (once wired).
# Not meant to be executed directly.

# shellcheck shell=bash

: "${ONESHOT_RUN_DIR:=/workspace/run}"
COUNTERS_FILE="$ONESHOT_RUN_DIR/.counters"
STATUS_FILE="$ONESHOT_RUN_DIR/status.jsonl"

oneshot_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Append a JSON event line to status.jsonl.
# Usage: oneshot_emit_status '{"ts":"...","type":"phase","phase":"exploring"}'
oneshot_emit_status() {
  printf '%s\n' "$1" >> "$STATUS_FILE"
}

# Atomically mutate the counters file with a jq filter.
# Usage: oneshot_counters_update '.tool_calls_total += 1'
oneshot_counters_update() {
  local filter="$1"
  local tmp
  tmp="$(mktemp)"
  jq "$filter" "$COUNTERS_FILE" > "$tmp" && mv "$tmp" "$COUNTERS_FILE"
}

# Set a scalar field (string) in the counters file.
# Usage: oneshot_counters_set_str phase exploring
oneshot_counters_set_str() {
  local field="$1" value="$2"
  oneshot_counters_update ".$field = \"$value\""
}

# Set a scalar field (number) in the counters file.
# Usage: oneshot_counters_set_num files_touched 12
oneshot_counters_set_num() {
  local field="$1" value="$2"
  oneshot_counters_update ".$field = $value"
}

# Increment a numeric field.
# Usage: oneshot_counters_inc tool_calls_total
#        oneshot_counters_inc tool_calls_total 3
oneshot_counters_inc() {
  local field="$1" delta="${2:-1}"
  oneshot_counters_update ".$field += $delta"
}

# Emit a phase transition: updates counters.phase and appends a phase event.
# Usage: oneshot_phase exploring
oneshot_phase() {
  local phase="$1"
  oneshot_counters_set_str "phase" "$phase"
  oneshot_emit_status "{\"ts\":\"$(oneshot_iso_now)\",\"type\":\"phase\",\"phase\":\"$phase\"}"
}

# Emit a commit event.
# Usage: oneshot_commit <sha> <message>
oneshot_commit() {
  local sha="$1" message="$2"
  oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" --arg sha "$sha" --arg msg "$message" \
    '{ts:$ts,type:"commit",sha:$sha,message:$msg}')"
}

# Emit a pr_opened event.
# Usage: oneshot_pr_opened <url> <branch> <commits>
oneshot_pr_opened() {
  local url="$1" branch="$2" commits="$3"
  oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" --arg url "$url" --arg branch "$branch" --argjson commits "$commits" \
    '{ts:$ts,type:"pr_opened",url:$url,branch:$branch,commits:$commits}')"
}

# Emit a completed event.
# Usage: oneshot_completed <summary>
oneshot_completed() {
  local summary="$1"
  oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" --arg s "$summary" \
    '{ts:$ts,type:"completed",result_summary:$s}')"
}

# Emit a failed event.
# Usage: oneshot_failed <reason> [<last_phase>]
oneshot_failed() {
  local reason="$1" last_phase="${2:-unknown}"
  oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" --arg r "$reason" --arg lp "$last_phase" \
    '{ts:$ts,type:"failed",reason:$r,last_phase:$lp}')"
}
