# Oneshot sandbox runtime image
#
# Debian-slim base with the Oneshot observability pipeline (entrypoint +
# heartbeat sidecar + hooks) and Claude Code CLI for autonomous agent
# execution.
#
# Two modes:
#   1. Real mode: ANTHROPIC_API_KEY is set → runs Claude Code against the
#      dispatch bundle (requirements.md + project.md + system-prompt.md).
#   2. Demo mode: no API key → runs demo-agent.sh to exercise the full
#      event pipeline without making API calls.
#
# See DESIGN.md §4 (Sandbox Runtime) and §5 (Progress Tracker).

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      coreutils \
      curl \
      git \
      gnupg \
      jq \
      procps \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (agent needs gh pr create, gh pr checks, etc.)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS (required by Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Oneshot sandbox scripts
COPY entrypoint.sh         /usr/local/bin/oneshot-entrypoint
COPY heartbeat-loop.sh     /usr/local/bin/oneshot-heartbeat
COPY hooks/                /usr/local/share/oneshot/hooks/
COPY lib/                  /usr/local/lib/oneshot/
COPY system-prompt.md      /usr/local/share/oneshot/system-prompt.md
COPY oneshot-settings.json /usr/local/share/oneshot/settings.json

RUN chmod +x /usr/local/bin/oneshot-entrypoint \
             /usr/local/bin/oneshot-heartbeat \
             /usr/local/share/oneshot/hooks/*.sh \
             /usr/local/lib/oneshot/*.sh

# Volume mount points:
#   /workspace/run  — server-persistent volume for status.jsonl, heartbeats.jsonl,
#                     current.json, agent.log, result.json
#   /workspace/repo — git worktree (dispatched bundle or actual repo clone)
#   /root/.claude   — skill + MCP snapshot from the dispatch bundle
RUN mkdir -p /workspace/run /workspace/repo /root/.claude

ENV ONESHOT_RUN_DIR=/workspace/run \
    ONESHOT_REPO_DIR=/workspace/repo \
    ONESHOT_CLAUDE_DIR=/root/.claude \
    ONESHOT_HEARTBEAT_INTERVAL_S=30 \
    ONESHOT_MODEL=unknown

WORKDIR /workspace/repo

ENTRYPOINT ["/usr/local/bin/oneshot-entrypoint"]
