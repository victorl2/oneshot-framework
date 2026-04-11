#!/usr/bin/env bash
# Demo agent — simulates a full Oneshot implementation lifecycle for
# testing the sandbox infrastructure end-to-end without a real Claude Code
# integration.
#
# Emits the same events the real implementation agent would emit (via the
# SessionStart / PostToolUse / Stop hooks), at a compressed timeline so the
# full flow completes in ~30 seconds.
#
# Verifies the pipeline produces:
#   - status.jsonl with semantic events (running, phase, commit, pr_opened,
#     ci_waiting, ci_passed, completed)
#   - heartbeats.jsonl with compact numeric telemetry
#   - current.json with live snapshots
#   - agent.log with the demo's own stdout
#
# When you're ready to swap in real Claude Code, update entrypoint.sh to
# exec the real agent instead of calling this script.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

log() { printf '[demo-agent] %s\n' "$*"; }

log "exploring phase"
oneshot_phase "exploring"
oneshot_counters_set_str "act" "reading files"
sleep 4
oneshot_counters_inc "tool_calls_total" 8
oneshot_counters_inc "files_touched" 3

log "implementing phase"
oneshot_phase "implementing"
oneshot_counters_set_str "act" "editing src/parser.rs"
sleep 5
oneshot_counters_inc "tool_calls_total" 12
oneshot_counters_inc "files_touched" 2

log "testing phase"
oneshot_phase "testing"
oneshot_counters_set_str "act" "running cargo test"
sleep 3
oneshot_counters_inc "tool_calls_total" 4

log "committing"
oneshot_counters_set_str "act" "git commit"
oneshot_commit "a1b2c3d" "feat: demo implementation"
oneshot_counters_inc "tool_calls_total" 2

log "opening PR"
oneshot_counters_set_str "act" "gh pr create"
oneshot_pr_opened "https://example.com/demo/pull/42" "oneshot/demo" 1
oneshot_counters_inc "tool_calls_total" 1

log "waiting for CI (simulated)"
oneshot_counters_set_str "phase" "ci_waiting"
oneshot_counters_set_str "act" "gh pr checks --watch"
oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" \
  '{ts:$ts,type:"ci_waiting",pr_url:"https://example.com/demo/pull/42",required_checks:["demo-lint","demo-test"]}')"
sleep 3

log "CI passed (simulated)"
oneshot_emit_status "$(jq -nc --arg ts "$(oneshot_iso_now)" \
  '{ts:$ts,type:"ci_passed",checks_passed:["demo-lint","demo-test"]}')"

log "completing"
oneshot_completed "demo simulation: 1 commit, 5 files touched, CI green"

log "done"
