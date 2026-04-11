#!/usr/bin/env bash
# Oneshot installer
#
# Installs commands, agents, templates, and references into ~/.claude/ so
# /oneshot:* slash commands become available to Claude Code.
#
# Layout after install:
#   ~/.claude/commands/oneshot/<cmd>.md    (slash command definitions)
#   ~/.claude/agents/oneshot-<role>.md     (agent definitions)
#   ~/.claude/oneshot/templates/*          (framework templates)
#   ~/.claude/oneshot/references/*         (framework references)
#   ~/.claude/oneshot/sandbox/*            (sandbox runtime source)
#   ~/.claude/oneshot/VERSION              (installed version marker)
#
# Path rewriting: Claude Code's @-include parser expects absolute paths, so
# any `@~/.claude/...` reference in the source files is expanded to
# `@$HOME/.claude/...` during copy.
#
# Usage:
#   ./install.sh                  install (or reinstall) to ~/.claude/
#   ./install.sh --dry-run        show what would happen, make no changes
#   ./install.sh --uninstall      remove all installed files
#   ./install.sh --help           show this help

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
COMMANDS_DIR="$CLAUDE_DIR/commands/oneshot"
AGENTS_DIR="$CLAUDE_DIR/agents"
ONESHOT_DIR="$CLAUDE_DIR/oneshot"

DRY_RUN=0
UNINSTALL=0

usage() {
  sed -n '2,24p' "$0" | sed 's|^# \{0,1\}||'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=1;    shift ;;
    --uninstall)  UNINSTALL=1;  shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[oneshot] %s\n' "$*"; }

ensure_source_layout() {
  for d in commands agents templates references sandbox; do
    if [[ ! -d "$SOURCE_DIR/$d" ]]; then
      echo "error: source directory missing: $SOURCE_DIR/$d" >&2
      exit 1
    fi
  done
  if [[ ! -f "$SOURCE_DIR/VERSION" ]]; then
    echo "error: VERSION file missing" >&2
    exit 1
  fi
}

ensure_claude_dir() {
  if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "error: ~/.claude not found at $CLAUDE_DIR" >&2
    echo "       Claude Code must be installed first" >&2
    exit 1
  fi
}

do_uninstall() {
  log "uninstalling from $CLAUDE_DIR"
  local removed=0
  if [[ -d "$COMMANDS_DIR" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  would remove: $COMMANDS_DIR"
    else
      rm -rf "$COMMANDS_DIR"
    fi
    removed=1
  fi
  if compgen -G "$AGENTS_DIR/oneshot-*.md" > /dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      for f in "$AGENTS_DIR"/oneshot-*.md; do
        echo "  would remove: $f"
      done
    else
      rm -f "$AGENTS_DIR"/oneshot-*.md
    fi
    removed=1
  fi
  if [[ -d "$ONESHOT_DIR" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  would remove: $ONESHOT_DIR"
    else
      rm -rf "$ONESHOT_DIR"
    fi
    removed=1
  fi
  if [[ $removed -eq 0 ]]; then
    log "nothing to remove — oneshot was not installed"
  else
    log "uninstalled"
  fi
}

# Rewrite `@~/.claude/...` to `@$HOME/.claude/...` and write to destination.
install_with_rewrite() {
  local src="$1" dst="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would install: $src → $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  sed "s|@~/|@$HOME/|g" "$src" > "$dst"
}

install_copy() {
  local src="$1" dst="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would copy: $src → $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
}

do_install() {
  local version
  version="$(cat "$SOURCE_DIR/VERSION")"
  log "installing oneshot v$version → $CLAUDE_DIR"

  log "commands → $COMMANDS_DIR"
  for src in "$SOURCE_DIR"/commands/*.md; do
    [[ -e "$src" ]] || continue
    install_with_rewrite "$src" "$COMMANDS_DIR/$(basename "$src")"
  done

  log "agents → $AGENTS_DIR"
  for src in "$SOURCE_DIR"/agents/*.md; do
    [[ -e "$src" ]] || continue
    install_with_rewrite "$src" "$AGENTS_DIR/$(basename "$src")"
  done

  log "templates → $ONESHOT_DIR/templates"
  for src in "$SOURCE_DIR"/templates/*; do
    [[ -f "$src" ]] || continue
    install_copy "$src" "$ONESHOT_DIR/templates/$(basename "$src")"
  done

  log "references → $ONESHOT_DIR/references"
  for src in "$SOURCE_DIR"/references/*; do
    [[ -f "$src" ]] || continue
    install_copy "$src" "$ONESHOT_DIR/references/$(basename "$src")"
  done

  log "sandbox runtime source → $ONESHOT_DIR/sandbox"
  # recursively copy sandbox/ subdir (includes hooks/, lib/)
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  would recursive-copy: $SOURCE_DIR/sandbox/ → $ONESHOT_DIR/sandbox/"
  else
    mkdir -p "$ONESHOT_DIR/sandbox"
    cp -Rf "$SOURCE_DIR"/sandbox/* "$ONESHOT_DIR/sandbox/"
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    echo "$version" > "$ONESHOT_DIR/VERSION"
  fi

  log "installed oneshot v$version"
  log "commands available: /oneshot:new-project, /oneshot start, /oneshot status, ..."
  log "next: run \`make build-sandbox\` from the repo to build the container image"
}

ensure_source_layout
ensure_claude_dir

if [[ $UNINSTALL -eq 1 ]]; then
  do_uninstall
else
  do_install
fi
