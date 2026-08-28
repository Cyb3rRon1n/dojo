#!/usr/bin/env bash
# lib.sh — the dojo engine, shared by every front end (menu.sh, the `dojo`
# command, install.sh, bootstrap.sh). Source this file; do NOT execute it.
#
# One engine, thin entry points over it:
#   menu.sh      whiptail Main Menu (interactive)
#   dojo         subcommand surface: menu/update/install/status/doctor/repos/tokens
#   install.sh   curl|bash one-shot fresh-machine bootstrap (clone + install)
#   bootstrap.sh idempotent wire-up-only (kept so `dojo update` and tests/CI
#                still have their canonical entry point)
#
# Every step below was lifted verbatim from the original install.sh /
# bootstrap.sh / dojo scripts — the whole point of this file is to hold the
# logic ONCE (the old code had three copies of safe_git_pull /
# fix_git_object_perms / safe_submodule_update) and let each front end just
# pick which function to run.
#
# Library files must NOT enable `set -euo pipefail` themselves — the entry
# point that sources us decides (sourcing with -e set can exit the caller on
# a function's nonzero return).

# Include guard: safe to source from multiple entry points.
if [[ "${DOJO_LIB_LOADED:-}" == "1" ]]; then
  return 0
fi
DOJO_LIB_LOADED=1

# --- Paths / defaults -----------------------------------------------------
DOJO_DIR="${DOJO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOCAL_BIN="$HOME/.local/bin"
OPENCODE_BIN="$HOME/.opencode/bin"
NPM_GLOBAL="$HOME/.npm-global"
REPOS_DIR="${REPOS_DIR:-$HOME/projects/github/repos}"

DOJO_REPO="git@github.com:Cyb3rRon1n/dojo.git"
DOJO_HTTPS="https://github.com/Cyb3rRon1n/dojo.git"

# --- Logging / progress ---------------------------------------------------
log()  { printf '[dojo] %s\n' "$*"; }
warn() { printf '[dojo][warn] %s\n' "$*" >&2; }
die()  { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

# (n/N) step progress, one line per step; output of the wrapped tool is
# swallowed unless it fails, then the tail prints for debugging.
TOTAL_STEPS=0
STEP_N=0
step() {
  STEP_N=$((STEP_N + 1))
  if [[ "$TOTAL_STEPS" -gt 0 ]]; then
    printf '[dojo] (%d/%d) %-38s' "$STEP_N" "$TOTAL_STEPS" "$1..."
  else
    printf '[dojo] (%d) %-38s' "$STEP_N" "$1..."
  fi
}
run_step() {
  local desc="$1"; shift
  step "$desc"
  local out
  if out="$("$@" 2>&1)"; then
    echo "ok"
  else
    echo "FAILED"
    printf '%s\n' "$out" | tail -20 >&2
    return 1
  fi
}
skip_step() {
  step "$1"
  echo "skip (${2:-already present})"
}

# link_file <src> <dst> — symlink (backing up any existing regular file).
link_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    warn "backing up $dst -> $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -sfn "$src" "$dst"
}

# --- Git self-healing helpers (once, no more triplicate copies) ----------
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

safe_git_pull() {
  local dir="$1" label="$2" out
  if out="$(git -C "$dir" pull --ff-only 2>&1)"; then
    return 0
  fi
  if printf '%s' "$out" | grep -qi 'insufficient permission\|permission denied' && ! printf '%s' "$out" | grep -qi 'publickey'; then
    if fix_git_object_perms "$dir"; then
      out="$(git -C "$dir" pull --ff-only 2>&1)" && { echo "[dojo] $label: ownership fixed, updated"; return 0; }
    fi
  fi
  if printf '%s' "$out" | grep -qi 'overwritten by merge\|commit your changes or stash'; then
    warn "$label: local changes in the working tree conflict with the update:"
    printf '%s\n' "$out" | grep '^\s' | sed 's/^/[dojo][warn]   /' >&2
    if [[ -t 0 ]]; then
      read -r -p "[dojo] stash local changes in $dir and retry? [y/N] " stash_reply || stash_reply="n"
      if [[ "$stash_reply" =~ ^[Yy] ]] && git -C "$dir" stash push -u -m "dojo auto-stash $(date +%s)" >/dev/null; then
        if git -C "$dir" pull --ff-only >/dev/null; then
          echo "[dojo] $label: local changes stashed (see 'git -C $dir stash list'), updated"
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

safe_submodule_update() {
  local dir="$1" out
  if out="$(git -C "$dir" submodule update --init --recursive 2>&1)"; then
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'permission denied \(publickey\)|could not read from remote repository'; then
    if [[ -f "$dir/.gitmodules" ]] && grep -q 'git@github\.com:' "$dir/.gitmodules"; then
      warn "submodule SSH auth failed — rewriting .gitmodules to HTTPS and retrying"
      sed -i.bak 's#git@github\.com:#https://github.com/#g' "$dir/.gitmodules"
      git -C "$dir" submodule sync >/dev/null 2>&1
      if out="$(git -C "$dir" submodule update --init --recursive 2>&1)"; then
        echo "[dojo] repos submodules: switched to HTTPS, updated"
        rm -f "$dir/.gitmodules.bak"
        return 0
      fi
    fi
  elif printf '%s' "$out" | grep -qi 'insufficient permission\|permission denied'; then
    if fix_git_object_perms "$dir"; then
      if out="$(git -C "$dir" submodule update --init --recursive 2>&1)"; then
        echo "[dojo] repos submodules: ownership fixed, updated"
        return 0
      fi
    fi
  fi
  warn "submodule update failed"
  printf '%s\n' "$out" | tail -10 >&2
  return 1
}

# Tool lookup that survives non-login shells (cron/CI/hook contexts don't
# get the profile block's PATH additions).
find_tool() {
  local p
  if p="$(command -v "$1" 2>/dev/null)"; then
    echo "$p"
    return 0
  fi
  for p in "$HOME/.local/bin/$1" "$HOME/bin/$1" "/usr/local/bin/$1" "/usr/local/sbin/$1"; do
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

ver_of() {
  local p v
  if p="$(find_tool "$1")" && v="$("$p" --version 2>/dev/null | head -1)" && [[ -n "$v" ]]; then
    echo "$v"
  else
    echo MISSING
  fi
}

git_auth_status() {
  if command -v ssh >/dev/null 2>&1 && ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "GitHub SSH OK"
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "GitHub HTTPS OK (gh)"
  else
    echo "NOT configured — see README"
  fi
}

# is_installed <tool> — does the binary exist (used by the menu's checklist
# to pre-check installed tools).
is_installed() { command -v "$1" >/dev/null 2>&1; }

# --- Shell profile PATH persistence ---------------------------------------
PROFILE_MARKER="# >>> dojo >>>"
PROFILE_TAIL="# <<< dojo <<<"
profile_block() {
  cat <<EOF
$PROFILE_MARKER
# Managed by dojo — do not edit by hand.
export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.npm-global/bin:\$PATH"
export GITHUB_PERSONAL_ACCESS_TOKEN="\$(gh auth token 2>/dev/null || echo '')"
[ -s "\$HOME/.nvm/nvm.sh" ] && . "\$HOME/.nvm/nvm.sh"

# Shared ssh-agent (stable socket) so every shell — and tools launched from
# them — sees the GitHub key. No-op when the agent is already running.
[ -f "\$HOME/.local/bin/dojo-ssh-agent.sh" ] && . "\$HOME/.local/bin/dojo-ssh-agent.sh"

$PROFILE_TAIL
EOF
}
ensure_profile_block() {
  local rc="$1" tmp
  [[ -f "$rc" ]] || : > "$rc"
  if grep -qF "$PROFILE_MARKER" "$rc"; then
    tmp="$(mktemp)"
    awk -v head="$PROFILE_MARKER" -v tail="$PROFILE_TAIL" '
      $0 == head { skip=1; next }
      skip && $0 == tail { skip=0; next }
      !skip { print }
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
  fi
  printf '\n%s\n' "$(profile_block)" >> "$rc"
}

# --- Centrally-sourced include guard --------------------------------------
# (moved to top of file; see above)
# ===========================================================================
# INSTALL ENGINE (from install.sh)
# ===========================================================================
ALL_TOOLS=(opencode claude copilot codex aider agy openclaw cursor cline qwen goose pi)

SELECTED_TOOLS=()
want() {
  local t
  for t in "${SELECTED_TOOLS[@]:-}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}
set_selected_tools() {
  SELECTED_TOOLS=()
  IFS=', ' read -ra SELECTED_TOOLS <<< "$1"
}
# --- per-tool installers --------------------------------------------------
install_tool_opencode() {
  if ! command -v opencode >/dev/null 2>&1; then
    log "installing opencode"
    curl -fsSL https://opencode.ai/install | bash >/dev/null || die "opencode install failed"
  else
    log "opencode already installed ($(opencode --version))"
  fi
}
install_tool_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    log "installing Claude Code"
    npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code || die "claude install failed (no sudo used — check npm prefix with 'npm config get prefix')"
    claude --version >/dev/null 2>&1 || die "claude installed but its postinstall (native binary fetch) didn't run — try: npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code"
  else
    log "claude already installed ($(claude --version))"
  fi
}
install_tool_copilot() {
  if ! command -v copilot >/dev/null 2>&1; then
    log "installing GitHub Copilot CLI"
    npm install -g @github/copilot || warn "copilot install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
  else
    log "copilot already installed ($(copilot --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    log "installing OpenAI Codex CLI"
    npm install -g @openai/codex || warn "codex install failed (needs Node 22+; check npm prefix with 'npm config get prefix')"
  else
    log "codex already installed ($(codex --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_aider() {
  if ! command -v aider >/dev/null 2>&1; then
    log "installing Aider"
    curl -fsSL https://aider.chat/install.sh | sh >/dev/null || warn "aider install failed"
  else
    log "aider already installed ($(aider --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_agy() {
  if ! command -v agy >/dev/null 2>&1; then
    log "installing Google Antigravity CLI"
    curl -fsSL https://antigravity.google/cli/install.sh | bash >/dev/null || warn "agy install failed"
  else
    log "agy already installed ($(agy --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    log "installing OpenClaw"
    curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-onboard >/dev/null || warn "openclaw install failed"
  else
    log "openclaw already installed"
  fi
}
install_tool_cursor() {
  if ! command -v cursor >/dev/null 2>&1; then
    log "installing Cursor (IDE)"
    curl https://cursor.com/install -fsSL | bash >/dev/null || warn "cursor install failed"
  else
    log "cursor already installed"
  fi
}
install_tool_cline() {
  if ! command -v cline >/dev/null 2>&1; then
    log "installing Cline CLI"
    npm install -g cline || warn "cline install failed (needs Node 22+)"
  else
    log "cline already installed ($(cline --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_qwen() {
  if ! command -v qwen >/dev/null 2>&1; then
    log "installing Qwen Code"
    npm install -g @qwen-code/qwen-code || warn "qwen install failed"
  else
    log "qwen already installed ($(qwen --version 2>/dev/null || echo unknown))"
  fi
}
install_tool_goose() {
  if ! command -v goose >/dev/null 2>&1; then
    log "installing Goose (Block)"
    local GOOSE_ARCH=""
    case "$(uname -m)" in
      x86_64)        GOOSE_ARCH=x86_64-unknown-linux-gnu ;;
      aarch64|arm64) GOOSE_ARCH=aarch64-unknown-linux-gnu ;;
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
}
install_tool_pi() {
  if ! command -v pi >/dev/null 2>&1; then
    log "installing Pi coding agent"
    npm install -g @earendil-works/pi-coding-agent || warn "pi install failed"
  else
    log "pi already installed ($(pi --version 2>/dev/null || echo unknown))"
  fi
}

install_selected_tools() {
  local t
  for t in "${SELECTED_TOOLS[@]:-}"; do
    case "$t" in
      opencode) install_tool_opencode ;;
      claude)   install_tool_claude ;;
      copilot)  install_tool_copilot ;;
      codex)    install_tool_codex ;;
      aider)    install_tool_aider ;;
      agy)      install_tool_agy ;;
      openclaw) install_tool_openclaw ;;
      cursor)   install_tool_cursor ;;
      cline)    install_tool_cline ;;
      qwen)     install_tool_qwen ;;
      goose)    install_tool_goose ;;
      pi)       install_tool_pi ;;
      *)        warn "unknown tool '$t' — skipped" ;;
    esac
  done
}

ensure_nvm() {
  if ! command -v npm >/dev/null 2>&1; then
    log "npm not found — installing Node.js via nvm"
    export NVM_DIR="$HOME/.nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1 || warn "nvm install failed"
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
    command -v nvm >/dev/null 2>&1 && nvm install --lts >/dev/null 2>&1
    command -v npm >/dev/null 2>&1 || warn "npm still missing after nvm install — claude/copilot/codex installs below will fail"
  fi
}

ensure_user_npm_prefix() {
  if command -v npm >/dev/null 2>&1; then
    local npm_prefix
    npm_prefix="$(npm config get prefix 2>/dev/null || true)"
    if [[ "$npm_prefix" != "$NPM_GLOBAL" ]] && ! [[ -w "$npm_prefix/lib/node_modules" || -w "$npm_prefix" ]] 2>/dev/null; then
      log "npm global prefix ($npm_prefix) isn't user-writable — switching to $NPM_GLOBAL"
      mkdir -p "$NPM_GLOBAL"
      npm config set prefix "$NPM_GLOBAL"
    fi
  fi
}

ensure_uv() {
  if ! command -v uv >/dev/null 2>&1; then
    log "installing uv (needed for graphify)"
    curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed — graphify will be skipped by wire-up"
  else
    log "uv already installed"
  fi
}

ensure_dojo_checkout() {
  if [[ -d "$DOJO_DIR/.git" ]]; then
    log "updating $DOJO_DIR"
    safe_git_pull "$DOJO_DIR" "dojo" || true
  else
    log "cloning dojo -> $DOJO_DIR"
    git clone "$DOJO_REPO" "$DOJO_DIR" 2>/dev/null || git clone "$DOJO_HTTPS" "$DOJO_DIR" || die "clone failed"
  fi
}

parse_repos_slug() {
  local slug="${1:-}"
  if [[ "$slug" == *"://"* || "$slug" == git@* ]]; then
    REPOS_REPO="$slug"
    REPOS_HTTPS="$slug"
  else
    REPOS_REPO="git@github.com:${slug}.git"
    REPOS_HTTPS="https://github.com/${slug}.git"
  fi
}

import_repos_workspace() {
  local slug="${1:-}" stray_dest
  if [[ -d "$REPOS_DIR/.git" ]]; then
    log "updating $REPOS_DIR"
    safe_git_pull "$REPOS_DIR" "repos" || true
    safe_submodule_update "$REPOS_DIR" || true
    if [[ -d "$REPOS_DIR/dojo/.git" ]] \
      && ! grep -qF 'path = dojo' "$REPOS_DIR/.gitmodules" 2>/dev/null \
      && { git -C "$REPOS_DIR/dojo" remote get-url origin 2>/dev/null | grep -qF 'Cyb3rRon1n/dojo'; }; then
      stray_dest="$REPOS_DIR/dojo.stray-$(date +%s)"
      if mv "$REPOS_DIR/dojo" "$stray_dest"; then
        log "moved stray clone $REPOS_DIR/dojo -> $stray_dest (dojo already lives at $DOJO_DIR)"
      else
        warn "found a stray dojo clone at $REPOS_DIR/dojo but couldn't move it"
      fi
    fi
  elif [[ -n "$slug" ]]; then
    log "cloning repos workspace -> $REPOS_DIR"
    parse_repos_slug "$slug"
    mkdir -p "$(dirname "$REPOS_DIR")"
    git clone "$REPOS_REPO" "$REPOS_DIR" 2>/dev/null || git clone "$REPOS_HTTPS" "$REPOS_DIR" || die "repos clone failed"
    safe_submodule_update "$REPOS_DIR" || true
  else
    log "no multi-repo workspace configured — skipping (add one later from the Workspace menu)"
  fi
}

github_auth_detect() {
  if command -v ssh >/dev/null 2>&1 && ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    return 0
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# run_install — the guided one-shot: auth, (optional) tools, checkout,
# wire-up, workspace. The menu and install.sh both call this.
run_install() {
  local tools_arg="" repos_arg=""
  local t
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tools) tools_arg="$2"; shift 2 ;;
      --repos) repos_arg="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -n "$tools_arg" ]]; then
    set_selected_tools "$tools_arg"
  elif [[ "${#SELECTED_TOOLS[@]}" -eq 0 ]]; then
    warn "run_install: no tools selected (menu always passes --tools; install.sh defaults to ALL_TOOLS)"
    SELECTED_TOOLS=("${ALL_TOOLS[@]}")
  fi
  [[ "${#SELECTED_TOOLS[@]}" -eq 0 ]] && SELECTED_TOOLS=("${ALL_TOOLS[@]}")

  if github_auth_detect; then
    log "GitHub auth OK"
    GIT_AUTH_OK=1
  else
    warn "no GitHub auth detected — repo clones below will fall back to HTTPS (read-only)."
    GIT_AUTH_OK=0
  fi

  local need_npm=0
  for t in claude copilot codex cline qwen pi; do want "$t" && need_npm=1; done
  if [[ "$need_npm" -eq 1 ]]; then ensure_nvm; fi
  ensure_user_npm_prefix

  if [[ "${#SELECTED_TOOLS[@]}" -gt 0 ]]; then
    install_selected_tools
  else
    log "no tools selected — skipping install"
  fi
  ensure_uv
  ensure_dojo_checkout
  run_wire_up
  import_repos_workspace "$repos_arg"
}
# ===========================================================================
# WIRE-UP ENGINE (from bootstrap.sh)
# ===========================================================================

# wire_up_runtime_tools — rtk / gh / graphify / serena binaries + dojo command.
# (bootstrap.sh's step "0" section, minus the pure prompting.)
wire_up_runtime_tools() {
  # rtk
  if command -v rtk >/dev/null 2>&1; then
    skip_step "rtk binary"
  elif command -v curl >/dev/null 2>&1; then
    run_step "rtk binary" bash -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh' \
      || warn "rtk install failed"
  else
    skip_step "rtk binary" "curl missing"
  fi
  # rtk must be reachable from Claude Code's hook subprocess (whose PATH is
  # whatever claude was launched with, not always ~/.local/bin). Mirror the
  # resolved binary into /usr/local/bin whenever writable — copied (not
  # symlinked) so every user on a shared box can stat() it.
  if command -v rtk >/dev/null 2>&1; then
    local RTK_REAL_BIN="$(command -v rtk)"
    if [ -L /usr/local/bin/rtk ] || ! cmp -s "$RTK_REAL_BIN" /usr/local/bin/rtk 2>/dev/null; then
      if [ -w /usr/local/bin ] && cp -f "$RTK_REAL_BIN" /usr/local/bin/rtk 2>/dev/null; then
        chmod 755 /usr/local/bin/rtk
      elif command -v sudo >/dev/null 2>&1 && sudo cp -f "$RTK_REAL_BIN" /usr/local/bin/rtk 2>/dev/null; then
        sudo chmod 755 /usr/local/bin/rtk
      else
        warn "could not copy rtk into /usr/local/bin - Claude Code's hook subprocess may still not find it on PATH"
      fi
    fi
  fi

  # github auth (for the GitHub MCP server)
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      skip_step "gh authentication" "already logged in"
    else
      run_step "gh authentication" bash -c 'gh auth login --hostname github.com' \
        || warn "gh auth login failed - GitHub MCP may not work"
    fi
  else
    skip_step "gh binary" "install: brew install gh (macOS) or sudo apt-get install gh (Ubuntu)"
  fi

  # graphify
  if command -v graphify >/dev/null 2>&1; then
    skip_step "graphify binary"
  elif command -v uv >/dev/null 2>&1; then
    run_step "graphify binary" uv tool install graphifyy || warn "graphify install failed"
  else
    skip_step "graphify binary" "uv missing — see https://docs.astral.sh/uv"
  fi

  # serena
  if command -v serena >/dev/null 2>&1; then
    skip_step "serena binary"
  elif command -v uv >/dev/null 2>&1; then
    run_step "serena binary" bash -c 'uv python install 3.13 && uv tool install -p 3.13 serena-agent' \
      || warn "serena install failed"
  else
    skip_step "serena binary" "uv missing"
  fi

  step "dojo command (update/install/status/doctor/menu)"
  mkdir -p "$LOCAL_BIN"
  ln -sf "$DOJO_DIR/dojo" "$LOCAL_BIN/dojo"
  ln -sf "$DOJO_DIR/ssh-agent.sh" "$LOCAL_BIN/dojo-ssh-agent.sh"
  echo "ok"
}

wire_up_profile() {
  step "shell profile PATH persistence"
  if [[ -f "$HOME/.zshrc" ]]; then
    ensure_profile_block "$HOME/.zshrc"
  fi
  ensure_profile_block "$HOME/.bashrc"
  echo "ok"
}

wire_up_opencode() {
  step "opencode global config"
  local OCONF="$CONFIG_HOME/opencode"
  mkdir -p "$OCONF"
  link_file "$DOJO_DIR/opencode/opencode.jsonc" "$OCONF/opencode.jsonc"
  cp "$DOJO_DIR/opencode/package.json" "$OCONF/package.json"
  cp "$DOJO_DIR/opencode/package-lock.json" "$OCONF/package-lock.json"
  echo "ok"

  if command -v npm >/dev/null 2>&1; then
    run_step "opencode plugin dependencies" bash -c "cd '$OCONF' && npm install --legacy-peer-deps" \
      || warn "opencode plugin install failed"
    local CG_DIR="$OCONF/node_modules/oh-my-openagent/packages/omo-codex/plugin"
    if [ -d "$CG_DIR" ]; then
      run_step "codegraph native dep" bash -c "cd '$CG_DIR' && npm install @colbymchenry/codegraph --no-save" \
        || warn "codegraph install failed — /mcp codegraph will be missing"
    fi
  else
    skip_step "opencode plugin dependencies" "npm missing"
    mkdir -p "$OCONF/plugins"
    ln -sf "$DOJO_DIR/opencode/plugins/token-gauge.js" "$OCONF/plugins/token-gauge.js"
  fi
}

wire_up_claude() {
  step "Claude Code user config"
  mkdir -p "$CLAUDE_HOME"
  link_file "$DOJO_DIR/claude/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
  link_file "$DOJO_DIR/claude/RTK.md" "$CLAUDE_HOME/RTK.md"
  link_file "$DOJO_DIR/claude/skills/task-observer" "$CLAUDE_HOME/skills/task-observer"
  echo "ok"

  if ! command -v claude >/dev/null 2>&1; then
    skip_step "Claude Code plugin marketplaces" "claude missing"
    skip_step "Claude Code plugins" "claude missing"
    skip_step "RTK Claude Code hook" "claude missing"
    skip_step "graphify for Claude Code" "claude missing"
    skip_step "Serena MCP for Claude Code" "claude missing"
    skip_step "MCP servers for Claude Code (github, context7)" "claude missing"
    return 0
  fi

  run_step "Claude Code plugin marketplaces" bash -c '
    claude plugin marketplace add alexgreensh/token-optimizer
    claude plugin marketplace add DietrichGebert/ponytail
    claude plugin marketplace add obra/superpowers
    claude plugin marketplace add anthropics/claude-plugins-official
  ' || warn "plugin marketplace registration failed"

  local CLAUDE_INSTALL_YES_FLAG=""
  if claude plugin install --help 2>&1 | grep -qE -- '(^|[ ,])(-y|--yes)([ ,]|$)'; then
    CLAUDE_INSTALL_YES_FLAG="-y"
  fi

  run_step "Claude Code plugins" bash -c "
    claude plugin install token-optimizer@alexgreensh-token-optimizer $CLAUDE_INSTALL_YES_FLAG
    claude plugin install ponytail@ponytail $CLAUDE_INSTALL_YES_FLAG
    claude plugin install superpowers@superpowers-dev $CLAUDE_INSTALL_YES_FLAG
    claude plugin install code-review@claude-plugins-official $CLAUDE_INSTALL_YES_FLAG
    claude plugin install pr-review-toolkit@claude-plugins-official $CLAUDE_INSTALL_YES_FLAG
  " || warn "plugin install failed"

  if command -v rtk >/dev/null 2>&1; then
    run_step "RTK Claude Code hook" rtk init -g --auto-patch || warn "rtk hook install failed"
  else
    skip_step "RTK Claude Code hook" "rtk missing"
  fi

  if command -v graphify >/dev/null 2>&1; then
    run_step "graphify for Claude Code" graphify install --platform claude || warn "graphify claude install failed"
  else
    skip_step "graphify for Claude Code" "graphify missing"
  fi

  if ! claude mcp get serena >/dev/null 2>&1; then
    if command -v serena >/dev/null 2>&1; then
      run_step "Serena MCP for Claude Code" serena setup claude-code || warn "serena claude setup failed"
    else
      skip_step "Serena MCP for Claude Code" "serena missing"
    fi
  else
    skip_step "Serena MCP for Claude Code" "(already registered)"
  fi
  run_step "MCP servers for Claude Code (github, context7)" bash -c '
    claude mcp remove github -s user >/dev/null 2>&1
    claude mcp add --scope user --transport http github   https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer \${GITHUB_PERSONAL_ACCESS_TOKEN}" >/dev/null
    claude mcp get context7 >/dev/null 2>&1 || claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp/     >/dev/null
  ' || warn "mcp server registration failed"
}

wire_up_copilot() {
  if ! command -v copilot >/dev/null 2>&1; then
    skip_step "RTK Copilot CLI hook" "copilot missing"
    skip_step "graphify for Copilot CLI" "copilot missing"
    skip_step "Copilot CLI statusline" "copilot missing"
    return 0
  fi
  if command -v rtk >/dev/null 2>&1; then
    run_step "RTK Copilot CLI hook" rtk init -g --copilot || warn "rtk copilot install failed"
  else
    skip_step "RTK Copilot CLI hook" "rtk missing"
  fi
  if command -v graphify >/dev/null 2>&1; then
    run_step "graphify for Copilot CLI" graphify install --platform copilot || warn "graphify copilot install failed"
  else
    skip_step "graphify for Copilot CLI" "graphify missing"
  fi
  step "Copilot CLI statusline"
  mkdir -p "$HOME/.copilot"
  ln -sf "$DOJO_DIR/copilot/statusline.sh" "$HOME/.copilot/statusline.sh"
  python3 - "$HOME/.copilot/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
d = {}
if os.path.isfile(path):
    try:
        d = json.load(open(path))
    except ValueError:
        d = {}
if d.get("statusLine"):
    print("skip (statusLine already set)")
    sys.exit(0)
flags = d.setdefault("feature_flags", {}).setdefault("enabled", [])
if "STATUS_LINE" not in flags:
    flags.append("STATUS_LINE")
d["statusLine"] = {"type": "command", "command": "~/.copilot/statusline.sh", "padding": 1}
json.dump(d, open(path, "w"), indent=2)
print("ok")
PY
  echo "ok"
}

wire_up_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    skip_step "RTK Codex CLI instructions" "codex missing"
    skip_step "graphify for Codex CLI" "codex missing"
    skip_step "Codex CLI statusline" "codex missing"
    return 0
  fi
  if command -v rtk >/dev/null 2>&1; then
    run_step "RTK Codex CLI instructions" rtk init -g --codex || warn "rtk codex install failed"
  else
    skip_step "RTK Codex CLI instructions" "rtk missing"
  fi
  if command -v graphify >/dev/null 2>&1; then
    run_step "graphify for Codex CLI" graphify install --platform codex || warn "graphify codex install failed"
  else
    skip_step "graphify for Codex CLI" "graphify missing"
  fi
  if [[ -f "$HOME/.codex/config.toml" ]] && grep -qE '^\s*\[tui\]' "$HOME/.codex/config.toml"; then
    skip_step "Codex CLI statusline" "[tui] already defined — add status_line manually"
  else
    step "Codex CLI statusline"
    mkdir -p "$HOME/.codex"
    {
      [[ -f "$HOME/.codex/config.toml" ]] && cat "$HOME/.codex/config.toml"
      printf '\n[tui]\nstatus_line = ["model", "context-used", "tokens", "git-branch"]\n'
    } > "$HOME/.codex/config.toml.tmp" && mv "$HOME/.codex/config.toml.tmp" "$HOME/.codex/config.toml"
    echo "ok"
  fi
}

wire_up_aider() {
  if ! command -v aider >/dev/null 2>&1; then
    skip_step "graphify for Aider" "aider missing"
    skip_step "Aider global config" "aider missing"
    return 0
  fi
  if command -v graphify >/dev/null 2>&1; then
    run_step "graphify for Aider" graphify install --platform aider || warn "graphify aider install failed"
  else
    skip_step "graphify for Aider" "graphify missing"
  fi
  step "Aider global config"
  link_file "$DOJO_DIR/aider/aider.conf.yml" "$HOME/.aider.conf.yml"
  echo "ok"
}

wire_up_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    run_step "OpenClaw plugins" bash -c '
      openclaw plugins install token-optimizer
      openclaw plugins install ponytail
    ' || warn "openclaw plugins install failed"
  else
    skip_step "OpenClaw plugins" "openclaw missing"
  fi
}

# run_wire_up — the full idempotent config/wiring pipeline (bootstrap.sh).
run_wire_up() {
  local _n
  wire_up_runtime_tools
  wire_up_profile
  wire_up_opencode
  wire_up_claude
  wire_up_copilot
  wire_up_codex
  wire_up_aider
  wire_up_openclaw

  echo "[dojo] verification"
  echo "  plugins (opencode):   $(command -v opencode >/dev/null && echo installed || echo MISSING)"
  echo "  plugins (claude):     $(command -v claude >/dev/null && claude plugin list 2>/dev/null | grep -ciE 'ponytail|token-optimizer|superpowers|code-review|pr-review-toolkit' || echo 0) of 5"
  echo "  task-observer:        $([ -e "$CLAUDE_HOME/skills/task-observer/SKILL.md" ] && echo installed || echo MISSING)"
  echo "  serena (MCP):         $(command -v serena >/dev/null && echo installed || echo MISSING)"
  echo "  copilot:              $(command -v copilot >/dev/null && echo installed || echo MISSING)"
  echo "  codex:                $(command -v codex >/dev/null && echo installed || echo MISSING)"
  echo "  aider:                $(command -v aider >/dev/null && echo installed || echo MISSING)"
  echo "  openclaw:             $(command -v openclaw >/dev/null && echo installed || echo MISSING)"
  echo "  rtk:                  $(command -v rtk >/dev/null && rtk --version | head -1 || echo MISSING)"
  echo "  graphify:             $(command -v graphify >/dev/null && graphify --version | head -1 || echo MISSING)"
}

# run_update — git pull + re-wire (the `dojo update` self-heal).
run_update() {
  safe_git_pull "$DOJO_DIR" "dojo" || true
  run_wire_up
}
# ===========================================================================
# STATUS / DOCTOR / REPOS (from the `dojo` command)
# ===========================================================================

dojo_status() {
  local rev behind
  rev="$(git -C "$DOJO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "dojo:      $DOJO_DIR @ $rev"
  git -C "$DOJO_DIR" fetch -q origin 2>/dev/null || true
  behind="$(git -C "$DOJO_DIR" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo '?')"
  if [[ "$behind" == "0" ]]; then
    echo "           up to date"
  else
    echo "           $behind commit(s) behind — run 'dojo update'"
  fi
  echo "opencode:  $(ver_of opencode)"
  echo "claude:    $(ver_of claude)"
  echo "copilot:   $(ver_of copilot)"
  echo "codex:     $(ver_of codex)"
  echo "aider:     $(ver_of aider)"
  echo "plugins:   $(p="$(find_tool claude)" && "$p" plugin list 2>/dev/null | grep -ciE 'ponytail|token-optimizer|superpowers' || echo 0) of 3 (claude)"
  echo "rtk:       $(ver_of rtk)"
  echo "graphify:  $(ver_of graphify)"
  echo "auth:      $(git_auth_status)"
}

dojo_doctor() {
  local fail=0
  ok()  { printf '  ok      %s\n' "$*"; }
  bad() { printf '  BROKEN  %s\n' "$*"; fail=1; }

  echo "dojo doctor — $DOJO_DIR"

  echo "  shell PATH persistence (survives reboot):"
  if grep -qs '# >>> dojo >>>' "$HOME/.bashrc" 2>/dev/null; then
    ok "PATH block present in ~/.bashrc"
  else
    bad "PATH block missing from ~/.bashrc — run 'dojo update'"
  fi
  if [[ -f "$HOME/.zshrc" ]]; then
    if grep -qs '# >>> dojo >>>' "$HOME/.zshrc" 2>/dev/null; then
      ok "PATH block present in ~/.zshrc"
    else
      bad "PATH block missing from ~/.zshrc — run 'dojo update'"
    fi
  fi

  echo "  tools:"
  local t v p
  for t in opencode claude rtk graphify; do
    if p="$(find_tool "$t")"; then
      v="$("$p" --version 2>/dev/null | head -1)"
      ok "$t ($v)"
    else
      bad "$t not on PATH"
    fi
  done

  echo "  opencode:"
  local oconf="$CONFIG_HOME/opencode"
  if [[ "$(readlink -f "$oconf/opencode.jsonc" 2>/dev/null)" == "$DOJO_DIR/opencode/opencode.jsonc" ]]; then
    ok "global config symlinked to dojo"
  else
    bad "opencode.jsonc not symlinked to dojo — run 'dojo update'"
  fi
  local np=0 p
  for p in \
    "$oconf/node_modules/@dietrichgebert/ponytail" \
    "$oconf/node_modules/token-optimizer-opencode" \
    "$oconf/node_modules/rtk-for-opencode" \
    "$oconf/node_modules/@javargasm/opencode-graphify" \
    "$oconf/node_modules/opencode-token-usage"; do
    [[ -d "$p" ]] && np=$((np + 1))
  done
  if [[ "$np" -eq 5 ]]; then
    ok "plugin deps installed ($np/5)"
  else
    bad "plugin deps missing ($np/5) — run 'dojo update'"
  fi

  echo "  opencode plugin pins (installed == pinned):"
  local pins_bad=0
  while read -r name ver; do
    local inst=""
    inst="$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('version',''))" \
      "$oconf/node_modules/$name/package.json" 2>/dev/null || true)"
    if [[ -n "$inst" ]] && [[ "$inst" == "$ver" ]]; then
      ok "$name $inst"
    else
      bad "$name pinned $ver, installed ${inst:-MISSING} — run 'dojo update'"
      pins_bad=$((pins_bad + 1))
    fi
  done < <(python3 - "$oconf/package.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in d.get("dependencies", {}).items():
    print(n, v.lstrip("^~"))
PY
)

  echo "  claude:"
  if grep -qs 'rtk hook claude' "$HOME/.claude/settings.json" 2>/dev/null; then
    ok "RTK PreToolUse hook present"
  else
    bad "RTK hook missing from settings.json — run 'dojo update'"
  fi
  local cp=0
  if p="$(find_tool claude)"; then
    cp="$("$p" plugin list 2>/dev/null | grep -ciE 'ponytail|token-optimizer|superpowers' || true)"
  fi
  if [[ "$cp" -ge 3 ]]; then
    ok "plugins enabled ($cp/3)"
  else
    bad "plugins missing ($cp/3) — run 'dojo update'"
  fi

  echo "  claude statusline:"
  local sl
  sl="$(python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    sl = d.get("statusLine") or {}
    print("ok" if sl.get("type") == "command" and sl.get("command") else "none")
except (OSError, ValueError):
    print("unreadable")
PY
)"
  case "$sl" in
    ok) ok "statusLine command present" ;;
    none) echo "  note  statusLine slot empty — token-optimizer auto-installs its quality bar here" ;;
    *) bad "settings.json unreadable" ;;
  esac

  echo "  claude docs:"
  local f
  for f in CLAUDE.md RTK.md; do
    if [[ "$(readlink -f "$HOME/.claude/$f" 2>/dev/null)" == "$DOJO_DIR/claude/$f" ]]; then
      ok "$f linked to dojo"
    else
      bad "$f not linked to dojo — run 'dojo update'"
    fi
  done
  if [[ "$(readlink -f "$HOME/.claude/skills/task-observer" 2>/dev/null)" == "$DOJO_DIR/claude/skills/task-observer" ]]; then
    ok "task-observer skill linked to dojo"
  else
    bad "task-observer skill not linked to dojo — run 'dojo update'"
  fi

  if command -v copilot >/dev/null 2>&1; then
    echo "  copilot:"
    if [[ "$(readlink -f "$HOME/.copilot/statusline.sh" 2>/dev/null)" == "$DOJO_DIR/copilot/statusline.sh" ]]; then
      ok "statusline.sh linked to dojo"
    else
      bad "statusline.sh not linked to dojo — run 'dojo update'"
    fi
    local csl
    csl="$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('ok' if d.get('statusLine',{}).get('command') else 'none')" \
      "$HOME/.copilot/settings.json" 2>/dev/null || echo unreadable)"
    case "$csl" in
      ok) ok "statusLine set in ~/.copilot/settings.json" ;;
      none | unreadable) bad "statusLine missing from ~/.copilot/settings.json — run 'dojo update'" ;;
    esac
  fi

  if command -v codex >/dev/null 2>&1; then
    echo "  codex:"
    if grep -qs 'status_line' "$HOME/.codex/config.toml"; then
      ok "status_line in ~/.codex/config.toml"
    else
      echo "  note  status_line absent from ~/.codex/config.toml — add manually or run 'dojo update'"
    fi
  fi

  if command -v aider >/dev/null 2>&1; then
    echo "  aider:"
    if [[ "$(readlink -f "$HOME/.aider.conf.yml" 2>/dev/null)" == "$DOJO_DIR/aider/aider.conf.yml" ]]; then
      ok "aider.conf.yml linked to dojo"
    else
      bad "aider.conf.yml not linked to dojo — run 'dojo update'"
    fi
  fi

  echo "  github auth: $(git_auth_status)"

  if [[ "$fail" -eq 0 ]]; then
    echo "  all checks passed."
  else
    echo "  broken items found — run 'dojo update' to repair." >&2
  fi
  return "$fail"
}

dojo_repos() {
  if [[ ! -d "$REPOS_DIR/.git" ]]; then
    echo "[dojo] no workspace at $REPOS_DIR yet — run 'dojo install' to set one up (it'll ask for your GitHub owner/repo)." >&2
    return 1
  fi
  local ok=0
  safe_git_pull "$REPOS_DIR" "repos" || ok=1
  safe_submodule_update "$REPOS_DIR" || ok=1
  return "$ok"
}
