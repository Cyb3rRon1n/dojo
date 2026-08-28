#!/usr/bin/env bash
#
# menu.sh — dojo's whiptail-driven Main Menu (DockSTARTer-style), the same
# idea as vulcan's installer/menu.sh. It is a THIN front end: every choice
# gathered here just calls an engine function from lib.sh (run_install,
# run_wire_up, run_update, dojo_status, dojo_doctor, ...). No detection,
# install, or wiring logic lives here — only dialog plumbing and argv
# building.
#
# Entry point: `dojo` with no arguments (or `dojo menu`). Can also run
# directly for development: ./menu.sh
set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
DOJO_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# shellcheck disable=SC1091
source "$DOJO_DIR/lib.sh"

BACKTITLE="dojo - AI Workstation Setup"

# --------------------------------------------------------------------------
# Theme — dojo's brand (warm ink/paper/brass/seal-red) mapped onto whiptail's
# named-color set (whiptail/newt exposes names only, no arbitrary hex):
#   ink #1a1613 -> black · paper #f3ece0 -> white
#   brass #a9905f -> yellow · seal red #c23b28 -> red
# --------------------------------------------------------------------------
export NEWT_COLORS='
root=white,black
border=white,black
window=white,black
shadow=black,black
title=yellow,black
button=black,yellow
actbutton=white,red
checkbox=white,black
actcheckbox=black,red
entry=black,black
label=white,black
listbox=white,black
actlistbox=black,red
sellistbox=white,black
actsellistbox=white,red
textbox=white,black
helpline=yellow,black
roottext=yellow,black
'

if ! declare -F whiptail >/dev/null; then
  whiptail() {
    command whiptail --fullbuttons "$@"
  }
fi

# --- Auto-sizing ----------------------------------------------------------
_dlg_rows() {
  local total
  total=$(tput lines 2>/dev/null || echo 24)
  local rows=$(( total * 60 / 100 ))
  [ "$rows" -lt 10 ] && rows=10
  echo "$rows"
}
_dlg_cols() {
  local total
  total=$(tput cols 2>/dev/null || echo 80)
  local cols=$(( total * 60 / 100 ))
  [ "$cols" -lt 60 ] && cols=60
  echo "$cols"
}
_dlg_items() {
  local total
  total=$(tput lines 2>/dev/null || echo 24)
  local items=$(( total * 45 / 100 ))
  [ "$items" -lt 5 ] && items=5
  echo "$items"
}
DLG_ROWS=$(_dlg_rows)
DLG_COLS=$(_dlg_cols)
DLG_ITEMS=$(_dlg_items)

# --- Small helpers ---------------------------------------------------------
# run_action <title> <cmd...> — confirm, then run with LIVE output on screen
# (install/wire runs can be long and verbose; never buffer them into a
# msgbox). Returns the command's exit status.
run_action() {
  local title="$1"; shift
  if ! whiptail --backtitle "$BACKTITLE" --title "$title" \
    --yesno "Run: $* ?" "$DLG_ROWS" "$DLG_COLS"; then
    return 130
  fi
  clear
  echo "=== $title ==="
  echo
  "$@"
  local status=$?
  echo
  [ "$status" -eq 0 ] && echo "Done." || echo "Failed (exit $status) - see output above."
  read -r -p "Press Enter to return to the menu..." _dummy
  return "$status"
}

installed_mark() {
  if is_installed "$1"; then echo "[x]"; else echo "[ ]"; fi
}

# --------------------------------------------------------------------------
# Tool groups for the Install Tools flow.
# --------------------------------------------------------------------------
TOOL_GROUPS=(
  "Essentials"  "opencode,claude"
  "GitHub"      "copilot"
  "OpenAI"      "codex"
  "Google"      "agy"
  "Python"      "aider"
  "Agent/IDE"   "openclaw,cursor,cline,qwen,goose,pi"
)
GROUP_LABEL() {
  case "$1" in
    Essentials) echo "Everyday: opencode, claude" ;;
    GitHub)     echo "copilot" ;;
    OpenAI)     echo "codex" ;;
    Google)     echo "agy (Antigravity)" ;;
    Python)     echo "aider (+ uv)" ;;
    Agent/IDE)  echo "openclaw, cursor, cline, qwen, goose, pi" ;;
  esac
}

# tool_checklist <group> <csv> — whiptail --checklist (installed pre-checked);
# echoes selected tools as a comma list.
tool_checklist() {
  local group="$1" csv="$2" i t
  local items=()
  IFS=',' read -ra tools <<< "$csv"
  for t in "${tools[@]}"; do
    local state=off
    is_installed "$t" && state=on
    items+=("$t" "$(installed_mark "$t") $t" "$state")
  done
  local sel
  sel=$(whiptail --backtitle "$BACKTITLE" --title "$group tools" \
    --checklist "$(GROUP_LABEL "$group")" \
    "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" "${items[@]}" 3>&1 1>&2 2>&3)
  echo "${sel//\"}"
}
# --------------------------------------------------------------------------
# Install Tools — grouped submenus feeding a single run_install.
# --------------------------------------------------------------------------
install_menu() {
  while true; do
    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" --title "Install Tools" \
      --menu "Pick a group, then tick which tools to install.\n[ ] = not installed  [x] = installed" \
      "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" \
      "guided"   "Guided Setup - Essentials + prompt for the rest" \
      "Essentials" "$(GROUP_LABEL Essentials)" \
      "GitHub"   "$(GROUP_LABEL GitHub)" \
      "OpenAI"   "$(GROUP_LABEL OpenAI)" \
      "Google"   "$(GROUP_LABEL Google)" \
      "Python"   "$(GROUP_LABEL Python)" \
      "AgentIDE" "$(GROUP_LABEL Agent/IDE)" \
      "all"      "Install everything" \
      "back"     "Return to Main Menu" \
      3>&1 1>&2 2>&3) || return

    case "$sel" in
      back) return ;;
      guided)
        run_install --tools "opencode,claude"
        ;;
      all)
        run_install --tools "${ALL_TOOLS[*]}"
        ;;
      *)
        local group="$sel" csv=""
        for ((i=0; i<${#TOOL_GROUPS[@]}; i+=2)); do
          if [[ "${TOOL_GROUPS[i]}" == "$group" ]]; then csv="${TOOL_GROUPS[i+1]}"; break; fi
        done
        # Essentials/AgentIDE in the menu map to the same group slug.
        [[ -z "$csv" && "$sel" == "AgentIDE" ]] && csv="openclaw,cursor,cline,qwen,goose,pi"
        local picked
        picked=$(tool_checklist "$group" "$csv")
        if [[ -n "$picked" ]]; then
          run_action "Install: $picked" run_install --tools "$picked"
        else
          whiptail --backtitle "$BACKTITLE" --title "$group" \
            --msgbox "Nothing selected." "$DLG_ROWS" "$DLG_COLS"
        fi
        ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Login
# --------------------------------------------------------------------------
login_menu() {
  while true; do
    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" --title "Login" \
      --menu "Authenticate your tools. Skip what you don't use." \
      "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" \
      "github"   "GitHub - SSH keygen + gh auth login" \
      "claude"   "$(installed_mark claude) Claude Code login" \
      "codex"    "$(installed_mark codex) OpenAI Codex login" \
      "copilot"  "$(installed_mark copilot) GitHub Copilot CLI login" \
      "aider"    "$(installed_mark aider) Aider login" \
      "back"     "Return to Main Menu" \
      3>&1 1>&2 2>&3) || return
    case "$sel" in
      back) return ;;
      github)
        run_action "GitHub auth" bash -c '
          ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N "" 2>/dev/null || true
          gh auth login
        '
        ;;
      claude) if is_installed claude; then run_action "Claude login" claude login; else _not_installed claude; fi ;;
      codex)  if is_installed codex;  then run_action "Codex login" codex login;  else _not_installed codex; fi ;;
      copilot) if is_installed copilot; then run_action "Copilot login" copilot login; else _not_installed copilot; fi ;;
      aider)  if is_installed aider;  then run_action "Aider login" aider --auth; else _not_installed aider; fi ;;
    esac
  done
}

_not_installed() {
  whiptail --backtitle "$BACKTITLE" --title "$1" \
    --msgbox "$1 is not installed yet — use Install Tools first." "$DLG_ROWS" "$DLG_COLS"
}

# --------------------------------------------------------------------------
# Services (shared runtime / wiring)
# --------------------------------------------------------------------------
services_menu() {
  while true; do
    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" --title "Services" \
      --menu "Shared tooling and wiring for everything the tools use." \
      "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" \
      "wire"    "Re-run full wiring (bootstrap: plugins/hooks/MCP/PATH)" \
      "rtk"     "$(installed_mark rtk) Install/update RTK (context filter)" \
      "graphify" "$(installed_mark graphify) Install graphify (knowledge graph)" \
      "serena"  "$(installed_mark serena) Install Serena (LSP MCP)" \
      "uv"      "$(installed_mark uv) Install uv (python tool manager)" \
      "gh"      "Install gh CLI (GitHub)" \
      "sshagent" "Re-link shared ssh-agent helper" \
      "back"    "Return to Main Menu" \
      3>&1 1>&2 2>&3) || return
    case "$sel" in
      back) return ;;
      wire) run_action "Full wiring (bootstrap)" run_wire_up ;;
      rtk) if is_installed rtk; then run_action "Re-run RTK" true; else
             run_action "Install RTK" bash -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'; fi ;;
      graphify) if is_installed graphify; then run_action "graphify already present" true; else
             run_action "Install graphify" uv tool install graphifyy; fi ;;
      serena) if is_installed serena; then run_action "serena already present" true; else
             run_action "Install serena" bash -c 'uv python install 3.13 && uv tool install -p 3.13 serena-agent'; fi ;;
      uv) if is_installed uv; then run_action "uv already present" true; else
            run_action "Install uv" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'; fi ;;
      gh) if is_installed gh; then run_action "gh already present" true; else
            run_action "Install gh" bash -c 'curl -fsSL https://cli.github.com/install.sh | sh'; fi ;;
      sshagent) run_action "Re-link ssh-agent" bash -c "mkdir -p '$LOCAL_BIN' && ln -sf '$DOJO_DIR/ssh-agent.sh' '$LOCAL_BIN/dojo-ssh-agent.sh'" ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Workspace (multi-repo)
# --------------------------------------------------------------------------
workspace_menu() {
  while true; do
    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" --title "Workspace" \
      --menu "Your projects/github/repos multi-repo workspace." \
      "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" \
      "update" "Update repos + submodules" \
      "clone"  "Clone a new workspace (asks for owner/repo)" \
      "add"    "Add a repo to the workspace" \
      "back"   "Return to Main Menu" \
      3>&1 1>&2 2>&3) || return
    case "$sel" in
      back) return ;;
      update) dojo_repos || whiptail --backtitle "$BACKTITLE" --title "Workspace" \
                --msgbox "See error above. No workspace yet? Pick 'Clone a new workspace'." "$DLG_ROWS" "$DLG_COLS" ;;
      clone)
        local slug
        slug=$(whiptail --backtitle "$BACKTITLE" --title "Clone workspace" \
          --inputbox "GitHub owner/repo (e.g. Cyb3rRon1n/myrepos), blank to skip:" "$DLG_ROWS" "$DLG_COLS" 3>&1 1>&2 2>&3)
        if [[ -n "$slug" ]]; then
          run_action "Clone workspace" import_repos_workspace "$slug"
        fi
        ;;
      add)
        local repo
        repo=$(whiptail --backtitle "$BACKTITLE" --title "Add repo" \
          --inputbox "Full repo URL or owner/repo to add:" "$DLG_ROWS" "$DLG_COLS" 3>&1 1>&2 2>&3)
        if [[ -n "$repo" ]]; then
          pushd "$REPOS_DIR" >/dev/null 2>&1 && {
            git submodule add "$repo" || whiptail --backtitle "$BACKTITLE" --title "Add repo" \
              --msgbox "git submodule add failed (see output above)." "$DLG_ROWS" "$DLG_COLS"
            popd >/dev/null 2>&1
          } || whiptail --backtitle "$BACKTITLE" --title "Add repo" \
              --msgbox "No workspace yet — clone one first." "$DLG_ROWS" "$DLG_COLS"
        fi
        ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Main Menu
# --------------------------------------------------------------------------
main_menu() {
  while true; do
    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" --title "dojo - AI Workstation Setup" \
      --menu "What would you like to do?" \
      "$DLG_ROWS" "$DLG_COLS" "$DLG_ITEMS" \
      "guided"   "1. Guided Setup - install + wire everything (new install)" \
      "install"  "2. Install Tools - pick which AI coding tools to install" \
      "update"   "3. Update - pull latest dojo + re-wire the stack" \
      "login"    "4. Login - GitHub / Claude / Codex / Copilot / Aider" \
      "services" "5. Services - RTK, graphify, serena, uv, gh, ssh-agent" \
      "workspace" "6. Workspace - multi-repo clone / update / add" \
      "doctor"   "7. Status / Doctor - health check" \
      "tokens"   "8. Token usage readout" \
      "quit"     "Exit" \
      3>&1 1>&2 2>&3) || break

    case "$sel" in
      guided)   run_install --tools "opencode,claude" ;;
      install)  install_menu ;;
      update)   run_action "Update dojo" run_update ;;
      login)    login_menu ;;
      services) services_menu ;;
      workspace) workspace_menu ;;
      doctor)
        clear
        dojo_doctor || true
        echo
        read -r -p "Press Enter to return to the menu..." _dummy
        ;;
      tokens)
        "$DOJO_DIR/dojo-tokens.py" || true
        echo
        read -r -p "Press Enter to return to the menu..." _dummy
        ;;
      quit) break ;;
    esac
  done
  clear
}

# --------------------------------------------------------------------------
# Fallback when whiptail isn't available (headless/CI) — print the menu
# choices and let them run via `dojo <command>`.
# --------------------------------------------------------------------------
if ! command -v whiptail >/dev/null 2>&1; then
  echo "[dojo] whiptail not found — using the non-interactive command surface instead."
  echo "[dojo]   dojo install | update | status | doctor | repos | tokens"
  echo "[dojo]   (no-dojo-arg opens this menu when whiptail is installed)"
  exit 0
fi

main_menu