#!/usr/bin/env bash
# Claude Code PostToolUse hook for Oneshot sandbox.
#
# Fires after every tool call. Parses the JSON payload from stdin and:
#   1. Increments tool_calls_total unconditionally
#   2. Counts files_touched on Edit / Write / MultiEdit
#   3. Tracks subagents on Task (sa++ on start, sc++ on completion — but
#      PostToolUse only fires on completion, so we increment both at once)
#   4. Detects `git commit` and emits a commit event with sha + message
#   5. Detects `gh pr create` and emits a pr_opened event with url + branch
#
# Payload shape (from Claude Code, captured on Rocky/2.1.1):
#   {
#     "session_id": "...",
#     "tool_name": "Bash" | "Edit" | "Write" | "Task" | ...,
#     "tool_input":    { "command": "...", "file_path": "...", ... },
#     "tool_response": { "stdout": "...", "stderr": "...", ... }
#   }
#
# Runs as the container's non-root user, reads COUNTERS_FILE and STATUS_FILE
# from env set by entrypoint.sh.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

# Read the payload. If stdin is empty or non-JSON, just bump the counter and bail.
payload=""
if [[ ! -t 0 ]]; then
  payload="$(cat)"
fi

# Always increment tool_calls_total.
oneshot_counters_inc "tool_calls_total"

# Bail if no payload to parse.
if [[ -z "$payload" ]] || ! echo "$payload" | jq . >/dev/null 2>&1; then
  exit 0
fi

tool_name="$(echo "$payload" | jq -r '.tool_name // ""')"

# Current phase for monotonic transitions below (only advances, never goes back).
current_phase="$(jq -r '.phase // "booting"' "$COUNTERS_FILE" 2>/dev/null || echo booting)"

# Heuristic phase transitions based on tool patterns. Rules:
#   booting → exploring   on first Read/Grep/Glob
#   exploring → implementing on first Edit/Write/MultiEdit
#   implementing → testing  on Bash matching test-runner patterns
#   (any) → reviewing    on git commit
#
# Monotonic: once past a phase, never regress (implementing stays
# implementing even if the agent runs more Reads).
advance_phase() {
  local new="$1"
  case "$current_phase:$new" in
    booting:exploring|booting:implementing|booting:testing|booting:reviewing) ;;
    exploring:implementing|exploring:testing|exploring:reviewing) ;;
    implementing:testing|implementing:reviewing) ;;
    testing:reviewing) ;;
    *) return 0 ;;  # no transition allowed
  esac
  oneshot_phase "$new"
  current_phase="$new"
}

case "$tool_name" in
  Read|Grep|Glob)
    advance_phase "exploring"
    ;;

  Edit|Write|MultiEdit)
    # File-touching tools. Bump files_touched (rough count — doesn't dedupe
    # repeat edits of the same file, which is fine for a progress signal).
    oneshot_counters_inc "files_touched"
    advance_phase "implementing"
    ;;

  Task)
    # Subagent dispatched. PostToolUse fires after the subagent completes,
    # so we increment both active and completed in sequence (net active = 0
    # at this point, but cumulative completed increments).
    oneshot_counters_inc "subagents_completed_total"
    # Capture subagent token usage if reported in the result.
    sub_tokens="$(echo "$payload" | jq -r '.tool_response.totalTokens // 0' 2>/dev/null)"
    if [[ -n "$sub_tokens" && "$sub_tokens" != "0" && "$sub_tokens" != "null" ]]; then
      oneshot_counters_update ".tokens_used_by_subagents_total += $sub_tokens"
    fi
    ;;

  Bash)
    # Parse the command string for git commit / gh pr create patterns.
    cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"
    stdout="$(echo "$payload" | jq -r '.tool_response.stdout // ""')"
    stderr="$(echo "$payload" | jq -r '.tool_response.stderr // ""')"

    # Test runner detection → phase transition to testing.
    # Matches: cargo test, npm test, pytest, go test, make test, yarn test, jest, vitest
    if echo "$cmd" | grep -qE '(cargo test|npm test|pytest|go test|make test|yarn test|jest|vitest|pnpm test)'; then
      advance_phase "testing"
    fi

    # git commit — extract sha via git rev-parse (more reliable than
    # parsing the bracketed git output, which varies between versions).
    if [[ "$cmd" == *"git commit"* ]] && [[ "$stderr" != *"nothing to commit"* ]]; then
      sha="$(echo "$stdout" | grep -oE '\[[^]]+\]' | head -1 | sed -E 's/.* ([0-9a-f]{7,40})\]/\1/')"
      # Best-effort message extraction from the commit command itself.
      msg="$(echo "$cmd" | sed -n 's/.*-m *["'\''"]\([^"'\'']*\).*/\1/p' | head -1)"
      if [[ -n "$sha" ]]; then
        oneshot_commit "$sha" "${msg:-"(unknown message)"}"
        advance_phase "reviewing"
      fi
    fi

    # gh pr create — extract the PR URL from stdout.
    if [[ "$cmd" == *"gh pr create"* ]]; then
      url="$(echo "$stdout" | grep -oE 'https://[^ ]+/pull/[0-9]+' | head -1)"
      if [[ -n "$url" ]]; then
        # Branch and commit count are best-effort; leave commits as 1 if unknown.
        branch="$(echo "$cmd" | grep -oE -- '--head [^ ]+' | awk '{print $2}')"
        if [[ -z "$branch" ]]; then
          branch="unknown"
        fi
        oneshot_pr_opened "$url" "$branch" 1
      fi
    fi
    ;;
esac

exit 0
