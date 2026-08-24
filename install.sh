#!/usr/bin/env bash
#
# install.sh — one-shot fresh-machine build-out for the dojo repo: opencode,
# Claude Code, GitHub Copilot CLI, OpenAI Codex CLI, Aider, Google Antigravity
# CLI, OpenClaw, and Cursor, each wired up with whatever token-optimization
# each
# one supports (RTK hooks, graphify, and — for Claude Code + opencode only,
# for now — ponytail/token-optimizer) + (optionally) your own multi-repo
# GitHub workspace, cloned and submodule-linked into projects/github/repos.
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)
#
# Idempotent — safe to re-run on a machine that's already set up. The only
# manual step this doesn't cover is GitHub auth (SSH key or HTTPS login) —
# do that first, or this script will tell you to at the end.
#
# Interactive runs prompt for which tools to install, and (on a machine
# that hasn't cloned one yet) for your own owner/repo to use as the
# multi-repo workspace — leave that blank to skip it entirely. To skip
# either prompt (e.g. scripted/headless), set:
#     DOJO_TOOLS=opencode,claude DOJO_REPOS_REPO=you/your-workspace \
#       bash <(curl -fsSL .../install.sh)
#
set -euo pipefail

log()  { printf '[dojo] %s\n' "$*"; }
warn() { printf '[dojo][warn] %s\n' "$*" >&2; }
die()  { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# fix_git_object_perms <dir> — the most common self-inflicted failure we see:
# a past root-run (accidental sudo, a root-owned tool) left some objects
# under <dir>/.git* owned by root, so a normal user's git can no longer
# write new objects there ("insufficient permission ... .git/objects"),
# including inside submodule worktrees under <dir>. Offer to chown it back.
# Returns 0 if it fixed something (caller should retry), 1 otherwise.
# ---------------------------------------------------------------------------
fix_git_object_perms() {
  local dir="$1" bad
  bad="$(find "$dir" -path '*/.git*' ! -user "$(id -u)" 2>/dev/null | head -5)"
  [[ -n "$bad" ]] || return 1
  warn "$dir: files under .git are owned by another user (likely a past 'sudo' run), blocking normal git operations:"
  printf '%s\n' "$bad" | sed 's/^/[dojo][warn]   /' >&2
  if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1; then
    read -r -p "[dojo] fix with 'sudo chown -R $(id -un):$(id -gn) $dir'? [y/N] " fix_reply || fix_reply="n"
    if [[ "$fix_reply" =~ ^[Yy] ]] && sudo chown -R "$(id -u):$(id -g)" "$dir"; then
      return 0
    fi
  fi
  warn "fix manually with: sudo chown -R $(id -un):$(id -gn) $dir"
  return 1
}

# ---------------------------------------------------------------------------
# safe_git_pull <dir> <label> — pull --ff-only, self-healing via
# fix_git_object_perms above, and via `git stash` when a prior interrupted/
# permission-blocked pull left local working-tree diffs blocking --ff-only
# (git stash is the safe, reversible fix here — never reset --hard).
# ---------------------------------------------------------------------------
safe_git_pull() {
  local dir="$1" label="$2" out

  if out="$(git -C "$dir" pull --ff-only 2>&1)"; then
    return 0
  fi

  if printf '%s' "$out" | grep -qi 'insufficient permission\|permission denied'; then
    if fix_git_object_perms "$dir"; then
      out="$(git -C "$dir" pull --ff-only 2>&1)" && { log "$label: ownership fixed, updated"; return 0; }
    fi
  fi

  if printf '%s' "$out" | grep -qi 'overwritten by merge\|commit your changes or stash'; then
    warn "$label: local changes in the working tree conflict with the update:"
    printf '%s\n' "$out" | grep '^\s' | sed 's/^/[dojo][warn]   /' >&2
    if [[ -t 0 ]]; then
      read -r -p "[dojo] stash local changes in $dir and retry? [y/N] " stash_reply || stash_reply="n"
      if [[ "$stash_reply" =~ ^[Yy] ]] && git -C "$dir" stash push -u -m "dojo auto-stash $(date +%s)" >/dev/null; then
        if git -C "$dir" pull --ff-only >/dev/null; then
          log "$label: local changes stashed (see 'git -C $dir stash list'), updated"
          return 0
        fi
      fi
    fi
    warn "fix manually: cd $dir && git stash && git pull --ff-only"
  fi

  warn "$label pull failed"
  printf '%s\n' "$out" | tail -10 >&2
  return 1
}

# ---------------------------------------------------------------------------
# safe_submodule_update <dir> — `submodule update --init --recursive`,
# self-healing via fix_git_object_perms (submodule fetches write into
# <dir>/.git/modules/<name>/objects, which hits the exact same root-owned-
# object failure the top-level pull above does, but is a separate git
# invocation so needs its own guard).
# ---------------------------------------------------------------------------
safe_submodule_update() {
  local dir="$1" out
  if out="$(git -C "$dir" submodule update --init --recursive 2>&1)"; then
    return 0
  fi
  if printf '%s' "$out" | grep -qi 'insufficient permission\|permission denied'; then
    if fix_git_object_perms "$dir"; then
      if out="$(git -C "$dir" submodule update --init --recursive 2>&1)"; then
        log "repos submodules: ownership fixed, updated"
        return 0
      fi
    fi
  fi
  warn "submodule update failed"
  printf '%s\n' "$out" | tail -10 >&2
  return 1
}

DOJO_DIR="${DOJO_DIR:-$HOME/dojo}"
DOJO_REPO="git@github.com:Cyb3rRon1n/dojo.git"
DOJO_HTTPS="https://github.com/Cyb3rRon1n/dojo.git"
REPOS_DIR="${REPOS_DIR:-$HOME/projects/github/repos}"
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
if command -v ssh >/dev/null 2>&1 && ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
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
  # Closest thing to fully-automated single-action auth: gh's device flow.
  # Only offered in an interactive terminal (piped one-liners just warn).
  if [[ -t 0 ]] && command -v gh >/dev/null 2>&1; then
    read -r -p "[dojo] run 'gh auth login' now (device flow)? [y/N] " reply || reply="n"
    case "$reply" in
      y|Y|yes|Yes)
        gh auth login || warn "gh auth login did not complete — pushes will fail until it does"
        if gh auth status >/dev/null 2>&1; then GIT_AUTH_OK=1; fi
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# Tool selection — DOJO_TOOLS=opencode,claude (comma list) skips the prompt
# for scripted/headless runs; otherwise, in an interactive terminal, ask.
# Piped one-liners with no TTY (rare) default to installing everything, same
# as before this option existed.
# ---------------------------------------------------------------------------
ALL_TOOLS=(opencode claude copilot codex aider agy openclaw cursor cline qwen goose pi)
if [[ -n "${DOJO_TOOLS:-}" ]]; then
  IFS=',' read -ra SELECTED_TOOLS <<< "$DOJO_TOOLS"
elif [[ -t 0 ]]; then
  echo "Which tools should dojo install/update?"
  echo "  1) opencode"
  echo "  2) claude   (Claude Code)"
  echo "  3) copilot  (GitHub Copilot CLI)"
  echo "  4) codex    (OpenAI Codex CLI)"
  echo "  5) aider"
  echo "  6) agy      (Google Antigravity CLI)"
  echo "  7) openclaw (agent + plugins, token-optimizer/ponytail)"
  echo "  8) cursor   (IDE — install only, no plugin API)"
  echo "  9) cline    (Cline CLI — headless agent from the VS Code extension)"
  echo " 10) qwen     (Qwen Code — Alibaba's agent, free Qwen OAuth tier)"
  echo " 11) goose    (Block's Goose — MCP-native agent)"
  echo " 12) pi       (Pi — minimal harness, any provider)"
  read -rp "Enter numbers/names (space or comma separated), or blank for all: " reply
  if [[ -z "$reply" ]]; then
    SELECTED_TOOLS=("${ALL_TOOLS[@]}")
  else
    reply="${reply//,/ }"
    SELECTED_TOOLS=()
    for tok in $reply; do
      case "$tok" in
        1|opencode) SELECTED_TOOLS+=(opencode) ;;
        2|claude)   SELECTED_TOOLS+=(claude) ;;
        3|copilot)  SELECTED_TOOLS+=(copilot) ;;
        4|codex)    SELECTED_TOOLS+=(codex) ;;
        5|aider)    SELECTED_TOOLS+=(aider) ;;
        6|agy)      SELECTED_TOOLS+=(agy) ;;
        7|openclaw) SELECTED_TOOLS+=(openclaw) ;;
        8|cursor)   SELECTED_TOOLS+=(cursor) ;;
        9|cline)    SELECTED_TOOLS+=(cline) ;;
        10|qwen)    SELECTED_TOOLS+=(qwen) ;;
        11|goose)   SELECTED_TOOLS+=(goose) ;;
        12|pi)      SELECTED_TOOLS+=(pi) ;;
        *) warn "unknown tool selection '$tok' — ignoring" ;;
      esac
    done
  fi
else
  SELECTED_TOOLS=("${ALL_TOOLS[@]}")
fi
want() { printf '%s\n' "${SELECTED_TOOLS[@]}" | grep -qx "$1"; }

# ---------------------------------------------------------------------------
# Multi-repo workspace — *your* GitHub org/repo, not dojo's. This used to be
# hardcoded to the dojo author's own workspace repo, which meant anyone else
# running this installer got the author's personal projects cloned onto
# their machine. Ask instead. DOJO_REPOS_REPO=owner/repo skips the prompt
# for scripted/headless runs; leaving it blank (prompt or env) skips this
# whole step — no multi-repo workspace is a perfectly fine answer.
# ---------------------------------------------------------------------------
REPOS_SLUG="${DOJO_REPOS_REPO:-}"
if [[ -z "$REPOS_SLUG" && ! -d "$REPOS_DIR/.git" && -t 0 ]]; then
  default_slug=""
  if command -v gh >/dev/null 2>&1; then
    default_owner="$(gh api user --jq .login 2>/dev/null || true)"
    [[ -n "$default_owner" ]] && default_slug="$default_owner/foundry"
  fi
  read -rp "GitHub owner/repo for your multi-repo workspace${default_slug:+ [$default_slug]}, blank to skip: " REPOS_SLUG
  [[ -z "$REPOS_SLUG" ]] && REPOS_SLUG="$default_slug"
fi
if [[ "$REPOS_SLUG" == *"://"* || "$REPOS_SLUG" == git@* ]]; then
  # Already a full URL (someone pasted one instead of owner/repo shorthand)
  # — use it as-is rather than mangling it into git@github.com:https://....
  REPOS_REPO="$REPOS_SLUG"
  REPOS_HTTPS="$REPOS_SLUG"
else
  REPOS_REPO="git@github.com:${REPOS_SLUG}.git"
  REPOS_HTTPS="https://github.com/${REPOS_SLUG}.git"
fi

# Node.js/npm aren't preinstalled on every fresh machine (e.g. minimal distro
# images) — claude/copilot/codex installs below all need npm. Bootstrap
# it with nvm (user-space, no sudo) if it's missing and one of those was picked.
if { want claude || want copilot || want codex || want cline || want qwen || want pi; } && ! command -v npm >/dev/null 2>&1; then
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
if want opencode; then
  if ! command -v opencode >/dev/null 2>&1; then
    log "installing opencode"
    curl -fsSL https://opencode.ai/install | bash >/dev/null || die "opencode install failed"
  else
    log "opencode already installed ($(opencode --version))"
  fi
fi

if want claude; then
  if ! command -v claude >/dev/null 2>&1; then
    log "installing Claude Code"
    # newer npm gates postinstall scripts (allow-scripts) — claude-code's
    # postinstall fetches its native binary, so it must be allowed explicitly
    # or `claude` ends up a broken shim with no binary behind it.
    npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code || die "claude install failed (no sudo used — check npm prefix with 'npm config get prefix')"
    claude --version >/dev/null 2>&1 || die "claude installed but its postinstall (native binary fetch) didn't run — try: npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code"
  else
    log "claude already installed ($(claude --version))"
  fi
fi

if want copilot; then
  if ! command -v copilot >/dev/null 2>&1; then
    log "installing GitHub Copilot CLI"
    npm install -g @github/copilot || warn "copilot install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
  else
    log "copilot already installed ($(copilot --version 2>/dev/null || echo unknown))"
  fi
fi

if want codex; then
  if ! command -v codex >/dev/null 2>&1; then
    log "installing OpenAI Codex CLI"
    npm install -g @openai/codex || warn "codex install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
  else
    log "codex already installed ($(codex --version 2>/dev/null || echo unknown))"
  fi
fi

if want aider; then
  if ! command -v aider >/dev/null 2>&1; then
    log "installing Aider"
    curl -fsSL https://aider.chat/install.sh | sh >/dev/null || warn "aider install failed"
  else
    log "aider already installed ($(aider --version 2>/dev/null || echo unknown))"
  fi
fi

# Gemini CLI stopped serving consumer requests on 2026-06-18 (Google moved
# everyone to Antigravity CLI, a Go binary with its own installer — no npm).
if want agy; then
  if ! command -v agy >/dev/null 2>&1; then
    log "installing Google Antigravity CLI"
    curl -fsSL https://antigravity.google/cli/install.sh | bash >/dev/null || warn "agy install failed"
  else
    log "agy already installed ($(agy --version 2>/dev/null || echo unknown))"
  fi
fi

if want openclaw; then
  if ! command -v openclaw >/dev/null 2>&1; then
    log "installing OpenClaw"
    curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-onboard >/dev/null || warn "openclaw install failed"
  else
    log "openclaw already installed"
  fi
fi

if want cursor; then
  if ! command -v cursor >/dev/null 2>&1; then
    log "installing Cursor (IDE)"
    curl https://cursor.com/install -fsSL | bash >/dev/null || warn "cursor install failed"
  else
    log "cursor already installed"
  fi
fi

if want cline; then
  if ! command -v cline >/dev/null 2>&1; then
    log "installing Cline CLI"
    npm install -g cline || warn "cline install failed (needs Node 22+)"
  else
    log "cline already installed ($(cline --version 2>/dev/null || echo unknown))"
  fi
fi

if want qwen; then
  if ! command -v qwen >/dev/null 2>&1; then
    log "installing Qwen Code"
    npm install -g @qwen-code/qwen-code || warn "qwen install failed"
  else
    log "qwen already installed ($(qwen --version 2>/dev/null || echo unknown))"
  fi
fi

# Prebuilt tarballs from GitHub releases (93MB) — no brew/apt package and the
# binary is self-contained, so just extract it onto ~/.local/bin.
if want goose; then
  if ! command -v goose >/dev/null 2>&1; then
    log "installing Goose (Block)"
    case "$(uname -m)" in
      x86_64)        GOOSE_ARCH=x86_64-unknown-linux-gnu ;;
      aarch64|arm64) GOOSE_ARCH=aarch64-unknown-linux-gnu ;;
      *)             GOOSE_ARCH="" ;;
    esac
    if [[ -z "$GOOSE_ARCH" ]]; then
      warn "goose: no prebuilt binary for $(uname -m) — skipped"
    else
      mkdir -p "$LOCAL_BIN"
      curl -fsSL "https://github.com/block/goose/releases/latest/download/goose-${GOOSE_ARCH}.tar.gz" | tar -xz -C "$LOCAL_BIN" --strip-components=1 goose \
        || warn "goose install failed"
    fi
  else
    log "goose already installed ($(goose --version 2>/dev/null || echo unknown))"
  fi
fi

if want pi; then
  if ! command -v pi >/dev/null 2>&1; then
    log "installing Pi coding agent"
    npm install -g @earendil-works/pi-coding-agent || warn "pi install failed"
  else
    log "pi already installed ($(pi --version 2>/dev/null || echo unknown))"
  fi
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
  safe_git_pull "$DOJO_DIR" "dojo" || true
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
  safe_git_pull "$REPOS_DIR" "repos" || true
  safe_submodule_update "$REPOS_DIR" || true

  # dojo's canonical home is $DOJO_DIR ($HOME/dojo) — a stray `git clone` of
  # it dropped straight into the multi-repo workspace (not registered as one
  # of its submodules) is just confusing clutter, so move it aside rather
  # than leaving two copies of the same repo around.
  if [[ -d "$REPOS_DIR/dojo/.git" ]] \
    && ! grep -qF 'path = dojo' "$REPOS_DIR/.gitmodules" 2>/dev/null \
    && { git -C "$REPOS_DIR/dojo" remote get-url origin 2>/dev/null | grep -qF 'Cyb3rRon1n/dojo'; }; then
    stray_dest="$REPOS_DIR/dojo.stray-$(date +%s)"
    if mv "$REPOS_DIR/dojo" "$stray_dest"; then
      log "moved stray clone $REPOS_DIR/dojo -> $stray_dest (dojo already lives at $DOJO_DIR)"
    else
      warn "found a stray dojo clone at $REPOS_DIR/dojo (dojo already lives at $DOJO_DIR) but couldn't move it"
    fi
  fi
elif [[ -n "$REPOS_SLUG" ]]; then
  log "cloning repos workspace -> $REPOS_DIR"
  mkdir -p "$(dirname "$REPOS_DIR")"
  git clone "$REPOS_REPO" "$REPOS_DIR" 2>/dev/null || git clone "$REPOS_HTTPS" "$REPOS_DIR" || die "repos clone failed"
  safe_submodule_update "$REPOS_DIR" || true
else
  log "no multi-repo workspace configured — skipping (set DOJO_REPOS_REPO=owner/repo to add one later)"
fi

log "done. Restart opencode / Claude Code / Copilot CLI / Codex CLI / Aider / Antigravity (agy) / OpenClaw / Cursor / Cline / Qwen / Goose / Pi — you're ready to launch in any repo."
if want claude; then
  log "one manual step, once per machine: open Claude Code and run '/mcp', pick 'github', authorize — that wires up GitHub Issues/PRs tooling for every session after"
fi
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
      # Drop our -euo pipefail before handing off: bash auto-exports active
      # `set -o` options via $SHELLOPTS, so without this the interactive
      # shell inherits `nounset` and chokes on distro profile scripts that
      # reference not-yet-set vars (e.g. Fedora's bash-color-prompt.sh and
      # $PROMPT_START), which is never a problem in a normal login shell.
      set +euo pipefail
      exec "${SHELL:-bash}"
      ;;
  esac
fi
