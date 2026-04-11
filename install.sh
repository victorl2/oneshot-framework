#!/usr/bin/env bash
# Oneshot installer
#
# Installs commands, agents, and framework files into ~/.claude/ so they're
# available as /oneshot:* slash commands.
#
# Status: STUB — not yet implemented.
#
# Planned behavior:
#   1. Copy commands/*.md       → ~/.claude/commands/oneshot/*.md
#   2. Copy agents/*.md          → ~/.claude/agents/*.md
#   3. Copy templates/references → ~/.claude/oneshot/{templates,references}/
#   4. Create ~/.claude/oneshot/VERSION marker
#   5. Rewrite any absolute @-path references in commands to point at the
#      installed locations.
#
# See DESIGN.md for the framework specification.

set -euo pipefail

echo "oneshot installer: not yet implemented"
echo "see DESIGN.md for specification"
exit 1
