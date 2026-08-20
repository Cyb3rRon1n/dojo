#!/usr/bin/env bash
#
# install.sh — one-shot fresh-machine build-out for the dojo repo: opencode,
# Claude Code, GitHub Copilot CLI, OpenAI Codex CLI, and Aider, each wired up
# with whatever token-optimization each one supports (RTK hooks, graphify,
# and — for Claude Code + opencode only, for now — ponytail/token-optimizer)
# + the projects/github/repos workspace, cloned and submodule-linked.
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)
#
# Idempotent — safe to re-run on a machine that's already set up. The only
# manual step this doesn't cover is GitHub auth (SSH key or HTTPS login) —
# do that first, or this script will tell you to at the end.
#
set -euo pipefail

log()  { printf '[dojo] %s\n' "$*"; }
warn() { printf '[dojo][warn] %s\n' "$*" >&2; }
die()  { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

DOJO_DIR="${DOJO_DIR:-$HOME/dojo}"
DOJO_REPO="git@github.com:Cyb3rRon1n/dojo.git"
DOJO_HTTPS="https://github.com/Cyb3rRon1n/dojo.git"
REPOS_DIR="${REPOS_DIR:-$HOME/projects/github/repos}"
REPOS_REPO="git@github.com:Cyb3rRon1n/foundry.git"
REPOS_HTTPS="https://github.com/Cyb3rRon1n/foundry.git"
LOCAL_BIN="$HOME/.local/bin"
OPENCODE_BIN="$HOME/.opencode/bin"
NPM_GLOBAL="$HOME/.npm-global"

export PATH="$LOCAL_BIN:$OPENCODE_BIN:$NPM_GLOBAL/bin:$PATH"

# ---------------------------------------------------------------------------
# 0. GitHub auth — the one thing this script can't do for you. Detect it up
#    front so clone/push failures later point back here instead of confusing
#    you.
# ---------------------------------------------------------------------------
GIT_AUTH_OK=0
if command -v ssh >/dev/null 2>&1 && ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  GIT_AUTH_OK=1
  log "GitHub SSH auth OK"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GIT_AUTH_OK=1
  log "GitHub HTTPS auth OK (gh)"
else
  warn "no GitHub auth detected — repo clones below will fall back to HTTPS (read-only)."
  warn "set up one of these before pushing anything:"
  warn "  SSH:   ssh-keygen -t ed25519 -C you@example.com && cat ~/.ssh/id_ed25519.pub"
  warn "         then add it at https://github.com/settings/keys"
  warn "  HTTPS: gh auth login"
fi

# Node.js/npm aren't preinstalled on every fresh machine (e.g. minimal distro
# images) — claude/copilot/codex installs below all need npm. Bootstrap it
# with nvm (user-space, no sudo) if it's missing.
if ! command -v npm >/dev/null 2>&1; then
  log "npm not found — installing Node.js via nvm"
  export NVM_DIR="$HOME/.nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1 || warn "nvm install failed"
  [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
  command -v nvm >/dev/null 2>&1 && nvm install --lts >/dev/null 2>&1
  command -v npm >/dev/null 2>&1 || warn "npm still missing after nvm install — claude/copilot/codex installs below will fail"
fi

# npm's default prefix (often /usr/local) is root-owned on most distros, which
# turns `npm install -g` into a sudo prompt this piped one-liner can't answer.
# Repoint npm at a user-owned prefix instead — no sudo required, ever.
if command -v npm >/dev/null 2>&1; then
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ "$npm_prefix" != "$NPM_GLOBAL" ]] && ! [[ -w "$npm_prefix/lib/node_modules" || -w "$npm_prefix" ]] 2>/dev/null; then
    log "npm global prefix ($npm_prefix) isn't user-writable — switching to $NPM_GLOBAL"
    mkdir -p "$NPM_GLOBAL"
    npm config set prefix "$NPM_GLOBAL"
  fi
fi

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
  npm install -g @anthropic-ai/claude-code || die "claude install failed (no sudo used — check npm prefix with 'npm config get prefix')"
else
  log "claude already installed ($(claude --version))"
fi

if ! command -v copilot >/dev/null 2>&1; then
  log "installing GitHub Copilot CLI"
  npm install -g @github/copilot || warn "copilot install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
else
  log "copilot already installed ($(copilot --version 2>/dev/null || echo unknown))"
fi

if ! command -v codex >/dev/null 2>&1; then
  log "installing OpenAI Codex CLI"
  npm install -g @openai/codex || warn "codex install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
else
  log "codex already installed ($(codex --version 2>/dev/null || echo unknown))"
fi

if ! command -v aider >/dev/null 2>&1; then
  log "installing Aider"
  curl -fsSL https://aider.chat/install.sh | sh >/dev/null || warn "aider install failed"
else
  log "aider already installed ($(aider --version 2>/dev/null || echo unknown))"
fi

# uv is the Python tool manager graphify installs through
if ! command -v uv >/dev/null 2>&1; then
  log "installing uv (needed for graphify)"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed — graphify will be skipped by bootstrap"
else
  log "uv already installed"
fi

# ---------------------------------------------------------------------------
# 2. dojo checkout
# ---------------------------------------------------------------------------
if [[ -d "$DOJO_DIR/.git" ]]; then
  log "updating $DOJO_DIR"
  git -C "$DOJO_DIR" pull --ff-only >/dev/null || warn "dojo pull failed"
else
  log "cloning dojo -> $DOJO_DIR"
  git clone "$DOJO_REPO" "$DOJO_DIR" 2>/dev/null || git clone "$DOJO_HTTPS" "$DOJO_DIR" || die "clone failed"
fi

# ---------------------------------------------------------------------------
# 3. Full stack (plugins, hooks, binaries, configs)
# ---------------------------------------------------------------------------
log "running bootstrap"
"$DOJO_DIR/bootstrap.sh"

# ---------------------------------------------------------------------------
# 4. projects/github/repos — the multi-repo workspace (submodule-linked)
# ---------------------------------------------------------------------------
if [[ -d "$REPOS_DIR/.git" ]]; then
  log "updating $REPOS_DIR"
  git -C "$REPOS_DIR" pull --ff-only >/dev/null || warn "repos pull failed"
else
  log "cloning repos workspace -> $REPOS_DIR"
  mkdir -p "$(dirname "$REPOS_DIR")"
  git clone "$REPOS_REPO" "$REPOS_DIR" 2>/dev/null || git clone "$REPOS_HTTPS" "$REPOS_DIR" || die "repos clone failed"
fi
git -C "$REPOS_DIR" submodule update --init --recursive || warn "submodule update failed"

log "done. Restart opencode / Claude Code / Copilot CLI / Codex CLI / Aider — you're ready to launch in any repo."
if [[ "$GIT_AUTH_OK" -eq 0 ]]; then
  warn "reminder: no GitHub auth was detected, so pushes will fail until you run"
  warn "  ssh-keygen -t ed25519 -C you@example.com  (then add the key on GitHub)"
  warn "or"
  warn "  gh auth login"
fi

# ---------------------------------------------------------------------------
# 5. Drop into the repos workspace, if this is an interactive terminal.
# ---------------------------------------------------------------------------
if [[ -t 0 && -d "$REPOS_DIR" ]]; then
  echo
  read -r -p "[dojo] enter dojo (cd into $REPOS_DIR) or exit? [enter/exit] " reply || reply="exit"
  case "$reply" in
    exit|Exit|EXIT|n|N|no|No)
      log "staying put — cd $REPOS_DIR whenever you're ready."
      ;;
    *)
      log "entering $REPOS_DIR — type 'exit' to leave."
      cd "$REPOS_DIR"
      exec "${SHELL:-bash}"
      ;;
  esac
fi
