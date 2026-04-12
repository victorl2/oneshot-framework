#!/usr/bin/env bash
# Claude Code Stop hook for Oneshot sandbox.
#
# Fires when the Claude Code session ends. The hook does NOT emit terminal
# events (completed/failed) on its own — the entrypoint's EXIT trap is the
# authoritative source for those, because it sees the real exit code of the
# `claude` command. A clean exit from Claude Code means success; a non-zero
# exit means failure. The Stop hook can't observe either, so it shouldn't
# guess.
#
# Reserved for future per-session bookkeeping that doesn't involve emitting
# terminal events (e.g. counting messages, logging cost, flushing state).

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/lib/oneshot/counters.sh

# Drain stdin — Claude Code sends a JSON payload we don't currently use.
[[ -t 0 ]] || cat >/dev/null

# Intentionally a no-op for now. The entrypoint's EXIT trap handles terminal
# events based on the actual exit code.
exit 0
