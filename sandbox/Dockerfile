# Oneshot sandbox runtime image
#
# Builds a Debian-slim base with the Oneshot sandbox observability pipeline
# (entrypoint + heartbeat sidecar + hook scripts) and a demo agent for
# end-to-end testing without a real Claude Code integration.
#
# Real agent integration is a future step: swap the demo-agent.sh invocation
# in entrypoint.sh for a real `claude code` call against the dispatch bundle.
#
# See DESIGN.md §4 (Sandbox Runtime) and §5 (Progress Tracker).

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      coreutils \
      curl \
      git \
      gnupg \
      jq \
      procps \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (needed by implementation agent for gh pr create, etc.)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Oneshot sandbox scripts
COPY entrypoint.sh         /usr/local/bin/oneshot-entrypoint
COPY heartbeat-loop.sh     /usr/local/bin/oneshot-heartbeat
COPY hooks/                /usr/local/share/oneshot/hooks/
COPY lib/                  /usr/local/lib/oneshot/

RUN chmod +x /usr/local/bin/oneshot-entrypoint \
             /usr/local/bin/oneshot-heartbeat \
             /usr/local/share/oneshot/hooks/*.sh \
             /usr/local/lib/oneshot/*.sh

# Volume mount points:
#   /workspace/run  — server-persistent volume for status.jsonl, heartbeats.jsonl,
#                     current.json, agent.log, result.json
#   /workspace/repo — git worktree (dispatched bundle)
#   /root/.claude   — skill + MCP snapshot from the dispatch bundle
RUN mkdir -p /workspace/run /workspace/repo /root/.claude

ENV ONESHOT_RUN_DIR=/workspace/run \
    ONESHOT_REPO_DIR=/workspace/repo \
    ONESHOT_CLAUDE_DIR=/root/.claude \
    ONESHOT_HEARTBEAT_INTERVAL_S=30 \
    ONESHOT_MODEL=unknown

WORKDIR /workspace/repo

ENTRYPOINT ["/usr/local/bin/oneshot-entrypoint"]
