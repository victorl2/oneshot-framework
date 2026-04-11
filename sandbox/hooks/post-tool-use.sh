#!/usr/bin/env bash
# Claude Code PostToolUse hook for Oneshot sandbox.
#
# Fires after every tool call the agent makes. Responsibilities:
#   1. Increment the `tool_calls_total` counter
#   2. Inspect the tool call for git commits / PR opens and emit the
#      corresponding `commit` / `pr_opened` events
#   3. (Future) Track files_touched by watching Edit/Write invocations
#   4. (Future) Track subagents_active when Task tool is invoked
#
# Hook contract: receives JSON on stdin with the tool name, arguments, and
# result. Shape per Claude Code docs.
#
# Status: STUB. Pattern-matching on stdin payload is not yet implemented.
# The counters file is updated by demo-agent.sh directly for v0 testing.
# This file documents the shape the real hook will take.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

# Read the hook payload from stdin. Claude Code sends a JSON object like:
#   {"tool_name":"Bash","tool_args":{"command":"git commit -m ..."}, "tool_result":{...}}
payload=""
if [[ ! -t 0 ]]; then
  payload="$(cat)"
fi

# Always increment the tool call counter.
oneshot_counters_inc "tool_calls_total"

# TODO: pattern-match the payload for interesting tool invocations.
#
# Example logic (once we finalize the Claude Code hook payload schema):
#
#   tool_name=$(jq -r '.tool_name // ""' <<<"$payload")
#   case "$tool_name" in
#     Bash)
#       cmd=$(jq -r '.tool_args.command // ""' <<<"$payload")
#       if [[ "$cmd" == *"git commit"* ]]; then
#         # extract commit sha from result, emit `commit` event
#         sha=$(jq -r '.tool_result.stdout // ""' <<<"$payload" | grep -oE '\b[0-9a-f]{7,40}\b' | head -1)
#         msg=$(echo "$cmd" | sed -n 's/.*-m *["'\'']\([^"'\'']*\).*/\1/p')
#         oneshot_commit "$sha" "$msg"
#       elif [[ "$cmd" == *"gh pr create"* ]]; then
#         url=$(jq -r '.tool_result.stdout // ""' <<<"$payload" | grep -oE 'https://[^ ]+/pull/[0-9]+' | head -1)
#         oneshot_pr_opened "$url" "$(git rev-parse --abbrev-ref HEAD)" 1
#       fi
#       ;;
#     Edit|Write)
#       oneshot_counters_inc "files_touched"
#       ;;
#     Task)
#       # Subagent spawned — increment active count
#       oneshot_counters_inc "subagents_active"
#       ;;
#   esac
