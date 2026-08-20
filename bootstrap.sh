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

warn() { printf '[dojo][warn] %s\n' "$*" >&2; }
die()  { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Progress: "[dojo] (n/N) step description... ok/skip/FAILED" — one line per
# step, with a tool's normal stdout/stderr (npm install noise, graphify's
# banner, etc.) swallowed unless that step actually fails, in which case the
# tail of its output prints so you can debug it.
# ---------------------------------------------------------------------------
TOTAL_STEPS=20
STEP_N=0
step() {
  STEP_N=$((STEP_N + 1))
  printf '[dojo] (%d/%d) %-38s' "$STEP_N" "$TOTAL_STEPS" "$1..."
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

if ! command -v copilot >/dev/null 2>&1; then
  warn "copilot not found — install: npm install -g @github/copilot"
fi

if ! command -v aider >/dev/null 2>&1; then
  warn "aider not found — install: curl -fsSL https://aider.chat/install.sh | sh"
fi

if ! command -v codex >/dev/null 2>&1; then
  warn "codex not found — install: npm install -g @openai/codex"
fi

if command -v rtk >/dev/null 2>&1; then
  skip_step "rtk binary"
elif command -v curl >/dev/null 2>&1; then
  run_step "rtk binary" bash -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh' \
    || warn "rtk install failed"
else
  skip_step "rtk binary" "curl missing"
fi

if command -v graphify >/dev/null 2>&1; then
  skip_step "graphify binary"
elif command -v uv >/dev/null 2>&1; then
  run_step "graphify binary" uv tool install graphifyy || warn "graphify install failed"
else
  skip_step "graphify binary" "uv missing — see https://docs.astral.sh/uv"
fi

step "dojo command (update/status/install/doctor)"
mkdir -p "$LOCAL_BIN"
ln -sf "$DOJO_DIR/dojo" "$LOCAL_BIN/dojo"
echo "ok"

# ---------------------------------------------------------------------------
# 0b. Shell profile — persist the toolchain PATH so opencode / claude /
#     npm-global / nvm survive a fresh login, not just the current shell.
#     Idempotent via a marked block (repaired on every re-run); bash by
#     default, also zsh if it's present.
# ---------------------------------------------------------------------------
step "shell profile PATH persistence"
PROFILE_MARKER="# >>> dojo >>>"
PROFILE_TAIL="# <<< dojo <<<"
profile_block() {
  cat <<EOF
$PROFILE_MARKER
# Managed by dojo (bootstrap.sh) — do not edit by hand.
export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.npm-global/bin:\$PATH"
[ -s "\$HOME/.nvm/nvm.sh" ] && . "\$HOME/.nvm/nvm.sh"

# Token status in the prompt: live usage / cache refresh / context-fill
# threshold from token-optimizer's state, via 'dojo tokens --one-line'.
# Renders nothing when there's no token data yet.
__dojo_ps1_tokens() {
  command -v dojo >/dev/null 2>&1 || return
  local s
  s="\$(dojo tokens --one-line 2>/dev/null)"
  [[ -n "\$s" ]] && printf ' %s' "\$s"
}
if [[ -n "\$PS1" ]] && [[ "\$PS1" != *"__dojo_ps1_tokens"* ]]; then
  PS1="\${PS1}"' \$(__dojo_ps1_tokens)'
fi
$PROFILE_TAIL
EOF
}
ensure_profile_block() {
  local rc="$1" tmp
  [[ -f "$rc" ]] || : > "$rc"
  # Strip any previous dojo block so the installed version always wins on
  # 'dojo update' (adds/replace the PS1 hook, PATH exports, etc.).
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
if [[ -f "$HOME/.zshrc" ]]; then
  ensure_profile_block "$HOME/.zshrc"
fi
ensure_profile_block "$HOME/.bashrc"
echo "ok"

# ---------------------------------------------------------------------------
# 1. opencode global config + plugin dependencies
# ---------------------------------------------------------------------------
step "opencode global config"
OCONF="$CONFIG_HOME/opencode"
mkdir -p "$OCONF"
link_file "$DOJO_DIR/opencode/opencode.jsonc" "$OCONF/opencode.jsonc"
cp "$DOJO_DIR/opencode/package.json" "$OCONF/package.json"
cp "$DOJO_DIR/opencode/package-lock.json" "$OCONF/package-lock.json"
echo "ok"

if command -v npm >/dev/null 2>&1; then
  run_step "opencode plugin dependencies" bash -c "cd '$OCONF' && npm install --legacy-peer-deps" \
    || warn "opencode plugin install failed"
else
  skip_step "opencode plugin dependencies" "npm missing — opencode installs them at first launch"
fi

# ---------------------------------------------------------------------------
# 2. Claude Code user-level instructions
# ---------------------------------------------------------------------------
step "Claude Code user config"
mkdir -p "$CLAUDE_HOME"
link_file "$DOJO_DIR/claude/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
link_file "$DOJO_DIR/claude/RTK.md" "$CLAUDE_HOME/RTK.md"
echo "ok"

# ---------------------------------------------------------------------------
# 3. Claude Code plugins (marketplace + install are idempotent)
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  run_step "Claude Code plugin marketplaces" bash -c '
    claude plugin marketplace add alexgreensh/token-optimizer
    claude plugin marketplace add DietrichGebert/ponytail
  ' || warn "plugin marketplace registration failed"

  # -y/--yes was added to `claude plugin install` in a later CLI release -
  # an already-installed-and-not-upgraded claude (bootstrap.sh never
  # upgrades one that's already present) can predate it, and passing an
  # unknown flag hard-fails the install instead of just being ignored.
  # Detect support once instead of assuming it.
  CLAUDE_INSTALL_YES_FLAG=""
  if claude plugin install --help 2>&1 | grep -qE -- '(^|[ ,])(-y|--yes)([ ,]|$)'; then
    CLAUDE_INSTALL_YES_FLAG="-y"
  fi

  run_step "Claude Code plugins" bash -c "
    claude plugin install token-optimizer@alexgreensh-token-optimizer $CLAUDE_INSTALL_YES_FLAG
    claude plugin install ponytail@ponytail $CLAUDE_INSTALL_YES_FLAG
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
else
  skip_step "Claude Code plugin marketplaces" "claude missing"
  skip_step "Claude Code plugins" "claude missing"
  skip_step "RTK Claude Code hook" "claude missing"
  skip_step "graphify for Claude Code" "claude missing"
fi

# ---------------------------------------------------------------------------
# 4. GitHub Copilot CLI — RTK + graphify only. ponytail/token-optimizer are
#    Claude Code + opencode plugins with no Copilot CLI build yet.
# ---------------------------------------------------------------------------
if command -v copilot >/dev/null 2>&1; then
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

  # Experimental copilot statusline: token/context readout in the footer.
  # Copilot CLI has no plugin system, so this is a plain stdin-JSON formatter
  # wired via its STATUS_LINE feature flag. Never clobbers an existing
  # statusLine the user configured.
  step "Copilot CLI statusline"
  mkdir -p "$HOME/.copilot"
  ln -sf "$DOJO_DIR/copilot/statusline.sh" "$HOME/.copilot/statusline.sh"
  if python3 - "$HOME/.copilot/settings.json" <<'PY'
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
  then
    :
  fi
else
  skip_step "RTK Copilot CLI hook" "copilot missing"
  skip_step "graphify for Copilot CLI" "copilot missing"
  skip_step "Copilot CLI statusline" "copilot missing"
fi

# ---------------------------------------------------------------------------
# 5. OpenAI Codex CLI — RTK + graphify only, same reason as Copilot above.
# ---------------------------------------------------------------------------
if command -v codex >/dev/null 2>&1; then
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

  # Codex statusline (token/context readout in the TUI footer). Native TOML
  # merge is out of scope: only wire it when there's no [tui] section at all,
  # so we never create a duplicate table or fight a user-managed config.
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
else
  skip_step "RTK Codex CLI instructions" "codex missing"
  skip_step "graphify for Codex CLI" "codex missing"
  skip_step "Codex CLI statusline" "codex missing"
fi

# ---------------------------------------------------------------------------
# 6. Aider — no plugin/hook system, so no RTK hook exists for it. graphify
#    supports it directly; token savings otherwise come from Aider's own
#    native settings, defaulted via the shipped config below.
# ---------------------------------------------------------------------------
if command -v aider >/dev/null 2>&1; then
  if command -v graphify >/dev/null 2>&1; then
    run_step "graphify for Aider" graphify install --platform aider || warn "graphify aider install failed"
  else
    skip_step "graphify for Aider" "graphify missing"
  fi
  step "Aider global config"
  link_file "$DOJO_DIR/aider/aider.conf.yml" "$HOME/.aider.conf.yml"
  echo "ok"
else
  skip_step "graphify for Aider" "aider missing"
  skip_step "Aider global config" "aider missing"
fi

# ---------------------------------------------------------------------------
# 6b. OpenClaw — token-optimizer + ponytail plugins when present.
# ---------------------------------------------------------------------------
if command -v openclaw >/dev/null 2>&1; then
  run_step "OpenClaw plugins" bash -c '
    openclaw plugins install token-optimizer
    openclaw plugins install ponytail
  ' || warn "openclaw plugins install failed"
else
  skip_step "OpenClaw plugins" "openclaw missing"
fi

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
echo "[dojo] verification"
echo "  plugins (opencode):   $(command -v opencode >/dev/null && echo installed || echo MISSING)"
echo "  plugins (claude):     $(command -v claude >/dev/null && claude plugin list 2>/dev/null | grep -ciE 'ponytail|token-optimizer' || echo 0) of 2"
echo "  copilot:              $(command -v copilot >/dev/null && echo installed || echo MISSING)"
echo "  codex:                $(command -v codex >/dev/null && echo installed || echo MISSING)"
echo "  aider:                $(command -v aider >/dev/null && echo installed || echo MISSING)"
echo "  openclaw:             $(command -v openclaw >/dev/null && echo installed || echo MISSING)"
echo "  rtk:                  $(command -v rtk >/dev/null && rtk --version | head -1 || echo MISSING)"
echo "  graphify:              $(command -v graphify >/dev/null && graphify --version | head -1 || echo MISSING)"

echo "[dojo] done. Restart opencode and Claude Code on this machine."
