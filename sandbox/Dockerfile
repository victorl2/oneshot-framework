# Oneshot sandbox runtime image
#
# Status: STUB — specification per DESIGN.md §4 (Sandbox Runtime).
#
# This image is the container that runs on the server for both discussion
# sandboxes (long-lived, interactive) and implementation sandboxes (ephemeral,
# one-shot). Same image, different lifecycles.
#
# Required capabilities (to be built):
#   - Claude Code CLI installed
#   - git, gh, jq, curl, standard build tooling
#   - A bind-mounted /workspace/run/ volume for status.jsonl + heartbeats.jsonl
#     + current.json + agent.log (server-persistent, survives container death)
#   - Claude Code hooks wired up:
#       * SessionStart → emit 'running' event, init counters file
#       * PostToolUse → increment tool_call counter, detect git commit /
#         gh pr create, emit corresponding events
#       * Stop → emit 'completed' or 'failed' based on exit state
#   - Sidecar heartbeat loop writing compact lines to heartbeats.jsonl and
#     overwriting current.json every 30s
#   - A mount point at /root/.claude/ for the skills+MCP snapshot from the
#     dispatch bundle
#
# See:
#   - DESIGN.md §4 (Sandbox Runtime) for the full spec
#   - DESIGN.md §5 (Progress Tracker) for event/heartbeat details
#   - DESIGN.md §"Storage Topology" for the volume mount contract

# TODO: base image selection — likely debian-slim or ubuntu
# FROM debian:bookworm-slim

# TODO: install Claude Code CLI
# RUN curl -fsSL https://... | sh

# TODO: install standard tooling
# RUN apt-get update && apt-get install -y \
#     git \
#     gh \
#     jq \
#     curl \
#     build-essential \
#     && rm -rf /var/lib/apt/lists/*

# TODO: create volume mount points
# RUN mkdir -p /workspace/run /root/.claude

# TODO: copy sidecar heartbeat loop
# COPY heartbeat-loop.sh /usr/local/bin/heartbeat-loop

# TODO: copy hook scripts
# COPY hooks/ /usr/local/share/oneshot/hooks/

# TODO: entrypoint that starts the heartbeat loop and then the agent
# ENTRYPOINT ["/usr/local/bin/oneshot-entrypoint"]

# Placeholder — not yet buildable.
FROM scratch
