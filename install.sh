#!/usr/bin/env bash
#
# install.sh — one-shot fresh-machine setup: opencode + Claude Code + the
# full token-optimization stack (pinned plugins, RTK, graphify, hooks).
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dotfiles/main/install.sh)
#
# Idempotent — safe to re-run on a machine that's already set up.
#
set -euo pipefail

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install][warn] %s\n' "$*" >&2; }
die()  { printf '[install][error] %s\n' "$*" >&2; exit 1; }

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_REPO="git@github.com:Cyb3rRon1n/dotfiles.git"
DOTFILES_HTTPS="https://github.com/Cyb3rRon1n/dotfiles.git"
LOCAL_BIN="$HOME/.local/bin"
OPENCODE_BIN="$HOME/.opencode/bin"

export PATH="$LOCAL_BIN:$OPENCODE_BIN:$PATH"

# ---------------------------------------------------------------------------
# 1. Core tools
# ---------------------------------------------------------------------------
if ! command -v opencode >/dev/null 2>&1; then
  log "installing opencode"
  curl -fsSL https://opencode.ai/install | bash >/dev/null || die "opencode install failed"
else
  log "opencode already installed ($(opencode --version))"
fi

if ! command -v claude >/dev/null 2>&1; then
  log "installing Claude Code"
  npm install -g @anthropic-ai/claude-code || die "claude install failed"
else
  log "claude already installed ($(claude --version))"
fi

# uv is the Python tool manager graphify installs through
if ! command -v uv >/dev/null 2>&1; then
  log "installing uv (needed for graphify)"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed — graphify will be skipped by bootstrap"
else
  log "uv already installed"
fi

# ---------------------------------------------------------------------------
# 2. dotfiles checkout
# ---------------------------------------------------------------------------
if [[ -d "$DOTFILES_DIR/.git" ]]; then
  log "updating $DOTFILES_DIR"
  git -C "$DOTFILES_DIR" pull --ff-only >/dev/null || warn "dotfiles pull failed"
else
  log "cloning dotfiles -> $DOTFILES_DIR"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR" 2>/dev/null || git clone "$DOTFILES_HTTPS" "$DOTFILES_DIR" || die "clone failed"
fi

# ---------------------------------------------------------------------------
# 3. Full stack (plugins, hooks, binaries, configs)
# ---------------------------------------------------------------------------
log "running bootstrap"
"$DOTFILES_DIR/bootstrap.sh"

log "done. Restart opencode and Claude Code — you're ready to launch in any repo."
