#!/usr/bin/env bash
#
# bootstrap.sh — idempotent setup of the opencode + Claude Code token
# optimization stack on a (new) machine.
#
# Clone dojo wherever you like — ~/dojo, or alongside your other repos in
# ~/projects/github/repos/dojo — this script finds its own location, so
# either works the same:
#
#   git clone git@github.com:Cyb3rRon1n/dojo.git ~/dojo && ~/dojo/bootstrap.sh
#
# To update later, from wherever you cloned it: git pull && ./bootstrap.sh
#
# Safe to re-run: existing files are backed up to .bak before replacement,
# and every step is a no-op when already in place.
#
set -euo pipefail

DOJO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOCAL_BIN="$HOME/.local/bin"

if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
  export PATH="$LOCAL_BIN:$PATH"
fi

log()  { printf '[dojo] %s\n' "$*"; }
warn() { printf '[dojo][warn] %s\n' "$*" >&2; }
die()  { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# link_file <src> <dst> — symlink, backing up any existing regular file.
# ---------------------------------------------------------------------------
link_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    warn "backing up $dst -> $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -sfn "$src" "$dst"
}

# ---------------------------------------------------------------------------
# 0. Tool binaries (skipped with a warning if the parent package manager is
#    missing). opencode / claude are not auto-installed — install those the
#    way you normally do on each machine.
# ---------------------------------------------------------------------------
if ! command -v opencode >/dev/null 2>&1; then
  warn "opencode not found — install: curl -fsSL https://opencode.ai/install | bash"
fi

if ! command -v claude >/dev/null 2>&1; then
  warn "claude not found — install: npm install -g @anthropic-ai/claude-code"
fi

if ! command -v rtk >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    log "installing rtk (prebuilt binary)"
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  else
    warn "curl missing — rtk install skipped"
  fi
fi
command -v rtk >/dev/null 2>&1 && ln -sf "$LOCAL_BIN/rtk" /usr/local/bin/rtk 2>/dev/null || true

if ! command -v graphify >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    log "installing graphify CLI"
    uv tool install graphifyy
  else
    warn "uv missing — graphify install skipped (install uv: https://docs.astral.sh/uv)"
  fi
fi
command -v graphify >/dev/null 2>&1 && ln -sf "$LOCAL_BIN/graphify" /usr/local/bin/graphify 2>/dev/null || true
command -v graphify >/dev/null 2>&1 && ln -sf "$LOCAL_BIN/graphify-mcp" /usr/local/bin/graphify-mcp 2>/dev/null || true

log "installing dojo command (update/status)"
mkdir -p "$LOCAL_BIN"
ln -sf "$DOJO_DIR/dojo" "$LOCAL_BIN/dojo"

# ---------------------------------------------------------------------------
# 1. opencode global config + plugin dependencies
# ---------------------------------------------------------------------------
log "installing opencode global config"
OCONF="$CONFIG_HOME/opencode"
mkdir -p "$OCONF"
link_file "$DOJO_DIR/opencode/opencode.jsonc" "$OCONF/opencode.jsonc"
cp "$DOJO_DIR/opencode/package.json" "$OCONF/package.json"
cp "$DOJO_DIR/opencode/package-lock.json" "$OCONF/package-lock.json"

if command -v npm >/dev/null 2>&1; then
  log "installing opencode plugin dependencies"
  ( cd "$OCONF" && npm install --legacy-peer-deps )
else
  warn "npm missing — opencode plugins will be auto-installed by opencode at first launch"
fi

# ---------------------------------------------------------------------------
# 2. Claude Code user-level instructions
# ---------------------------------------------------------------------------
log "installing Claude Code user config"
mkdir -p "$CLAUDE_HOME"
link_file "$DOJO_DIR/claude/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
link_file "$DOJO_DIR/claude/RTK.md" "$CLAUDE_HOME/RTK.md"

# ---------------------------------------------------------------------------
# 3. Claude Code plugins (marketplace + install are idempotent)
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  log "registering Claude Code plugins"
  claude plugin marketplace add alexgreensh/token-optimizer 2>&1 | tail -1 || warn "token-optimizer marketplace add failed"
  claude plugin marketplace add DietrichGebert/ponytail     2>&1 | tail -1 || warn "ponytail marketplace add failed"

  # -y/--yes was added to `claude plugin install` in a later CLI release -
  # an already-installed-and-not-upgraded claude (bootstrap.sh never
  # upgrades one that's already present) can predate it, and passing an
  # unknown flag hard-fails the install instead of just being ignored.
  # Detect support once instead of assuming it.
  CLAUDE_INSTALL_YES_FLAG=""
  if claude plugin install --help 2>&1 | grep -qE -- '(^|[ ,])(-y|--yes)([ ,]|$)'; then
    CLAUDE_INSTALL_YES_FLAG="-y"
  fi

  claude plugin install token-optimizer@alexgreensh-token-optimizer $CLAUDE_INSTALL_YES_FLAG 2>&1 | tail -1 || warn "token-optimizer install failed"
  claude plugin install ponytail@ponytail $CLAUDE_INSTALL_YES_FLAG                2>&1 | tail -1 || warn "ponytail install failed"

  log "installing RTK Claude Code hook"
  command -v rtk >/dev/null 2>&1 && rtk init -g --auto-patch || warn "rtk hook install skipped"

  log "installing graphify for Claude Code"
  command -v graphify >/dev/null 2>&1 && graphify install --platform claude || warn "graphify claude install skipped"
else
  warn "claude not found — Claude Code plugin setup skipped"
fi

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
log "verification"
echo "  plugins (opencode):   $(command -v opencode >/dev/null && echo installed || echo MISSING)"
echo "  plugins (claude):     $(command -v claude >/dev/null && claude plugin list 2>/dev/null | grep -ciE 'ponytail|token-optimizer' || echo 0) of 2"
echo "  rtk:                  $(command -v rtk >/dev/null && rtk --version | head -1 || echo MISSING)"
echo "  graphify:             $(command -v graphify >/dev/null && graphify --version | head -1 || echo MISSING)"

log "done. Restart opencode and Claude Code on this machine."
