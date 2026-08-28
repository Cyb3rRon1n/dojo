#!/usr/bin/env bash
#
# install.sh — one-shot fresh-machine build-out for the dojo stack: installs
# (optionally) the AI coding tools, clones dojo, and wires up every
# token/context optimization each installed tool supports. Idempotent — safe
# to re-run.
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)
#
# Interactive runs prompt for which tools to install (grouped in the Main
# Menu if you run `dojo`); to skip the prompt for scripted/headless runs:
#     DOJO_TOOLS=opencode,claude DOJO_REPOS_REPO=you/your-workspace \
#       bash <(curl -fsSL .../install.sh)
#
# All the real work lives in lib.sh (run_install / install_selected_tools /
# run_wire_up). This shell is just the bootstrap that gets dojo onto disk —
# it has to clone before it can source lib.sh, since `curl | bash` runs with
# nothing on disk yet.
#
set -euo pipefail

DOJO_DIR="${DOJO_DIR:-$HOME/dojo}"
DOJO_REPO="git@github.com:Cyb3rRon1n/dojo.git"
DOJO_HTTPS="https://github.com/Cyb3rRon1n/dojo.git"

if [[ ! -f "$DOJO_DIR/lib.sh" ]]; then
  if [[ -d "$DOJO_DIR/.git" ]]; then
    git -C "$DOJO_DIR" pull --ff-only >/dev/null 2>&1 || true
  else
    echo "[dojo] cloning dojo -> $DOJO_DIR"
    git clone "$DOJO_REPO" "$DOJO_DIR" 2>/dev/null || git clone "$DOJO_HTTPS" "$DOJO_DIR" || {
      echo "[dojo][error] clone failed" >&2; exit 1; }
  fi
fi

# shellcheck disable=SC1091
source "$DOJO_DIR/lib.sh"

# Translate legacy env vars into run_install flags for scripted/CI use.
args=()
if [[ -n "${DOJO_TOOLS:-}" ]]; then
  args+=(--tools "$DOJO_TOOLS")
fi
if [[ -n "${DOJO_REPOS_REPO:-}" ]]; then
  args+=(--repos "$DOJO_REPOS_REPO")
fi

run_install "${args[@]:-}"

log "done. Restart opencode / Claude Code / Copilot CLI / Codex CLI / Aider / Antigravity (agy) / OpenClaw / Cursor / Cline / Qwen / Goose / Pi — you're ready to launch in any repo."
if ! github_auth_detect; then
  warn "reminder: no GitHub auth was detected, so pushes will fail until you run"
  warn "  ssh-keygen -t ed25519 -C you@example.com  (then add the key on GitHub)"
  warn "or"
  warn "  gh auth login"
fi

# Drop into the repos workspace, if this is an interactive terminal.
if [[ -t 0 && -d "$REPOS_DIR" ]]; then
  echo
  read -r -p "[dojo] enter dojo (cd into $REPOS_DIR) or exit? [enter/exit] " reply || reply="exit"
  case "$reply" in
    exit|Exit|EXIT|n|N|no|No)
      log "staying put — cd $REPOS_DIR whenever you're ready."
      ;;
    *)
      log "entering $REPOS_DIR — type 'exit' to leave."
      set +euo pipefail
      exec "${SHELL:-bash}"
      ;;
  esac
fi
