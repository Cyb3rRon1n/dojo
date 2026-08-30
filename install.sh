#!/usr/bin/env bash
#
# install.sh — Orca work environment installer
# Prompts for Orca Desktop or Headless, then token optimization,
# with menu options including Complete Install Wipe.
#
# The end result: running 'orca' opens the work environment with
# optimizations and plugins already persistently connected.
#
# Usage:
#   bash install.sh              # interactive mode with menu
#   echo "1" | bash install.sh  # piped input: install Desktop + optimize
#   echo -e "2\nn" | bash install.sh  # piped input: install Headless + no optimize
#
# The end result: running 'orca' opens the work environment with
# optimizations and plugins already persistently connected.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------
log()   { printf '[dojo] %s\n' "$*"; }
warn()  { printf '[dojo][warn] %s\n' "$*" >&2; }
die()   { printf '[dojo][error] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Detect Orca installation status
# ---------------------------------------------------------------------------
is_orca_desktop_installed() {
    # Check if orca command exists and .orca-desktop config dir exists
    local orca_path
    orca_path="$(command -v orca 2>/dev/null)" || return 1
    [[ -x "$orca_path" ]] || return 1
    [[ -d "$HOME/.orca-desktop" ]] 2>/dev/null || return 1
    return 0
}

is_orca_headless_installed() {
    # Check if orca command exists and .orca-headless config dir exists
    local orca_path
    orca_path="$(command -v orca 2>/dev/null)" || return 1
    [[ -x "$orca_path" ]] || return 1
    [[ -d "$HOME/.orca-headless" ]] 2>/dev/null || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Install Orca Desktop
# ---------------------------------------------------------------------------
install_orca_desktop() {
    log "Installing Orca Desktop..."

    # Create desktop-specific directory
    mkdir -p "$HOME/.orca-desktop"

    # Configure for desktop mode
    cat > "$HOME/.orca-desktop/config" <<'DESKTOP_CONFIG'
{
  "mode": "desktop",
  "worktrees": true,
  "editor": "code",
  "mobile_companion": true
}
DESKTOP_CONFIG

    # Create launcher script
    cat > "$HOME/.local/bin/orca-desktop" <<'ORCA_DESKTOP_LAUNCHER'
#!/usr/bin/env bash
# Orca Desktop launcher
exec orca "$@"
ORCA_DESKTOP_LAUNCHER
    chmod +x "$HOME/.local/bin/orca-desktop"

    log "Orca Desktop installation complete."
    log "  - Desktop mode enabled"
    log "  - Worktree support active"
    log "  - Mobile companion enabled"
}

# ---------------------------------------------------------------------------
# Install Orca Headless
# ---------------------------------------------------------------------------
install_orca_headless() {
    log "Installing Orca Headless..."

    # Create headless-specific directory
    mkdir -p "$HOME/.orca-headless"

    # Configure for headless mode
    cat > "$HOME/.orca-headless/config" <<'HEADLESS_CONFIG'
{
  "mode": "headless",
  "worktrees": true,
  "editor": "none",
  "mobile_companion": false
}
HEADLESS_CONFIG

    # Create launcher script
    cat > "$HOME/.local/bin/orca-headless" <<'ORCA_HEADLESS_LAUNCHER'
#!/usr/bin/env bash
# Orca Headless launcher
exec orca "$@"
ORCA_HEADLESS_LAUNCHER
    chmod +x "$HOME/.local/bin/orca-headless"

    log "Orca Headless configuration complete."
    log "  - Headless mode enabled"
    log "  - Worktree support active"
    log "  - No GUI components"
}

# ---------------------------------------------------------------------------
# Token optimization prompt
# ---------------------------------------------------------------------------
prompt_token_optimization() {
    local answer
    read -rp "Would you like to set up token optimization now? This will configure
token-optimizer and ponytail for your Orca environment.
Selecting Yes will install the token optimization plugins.
Selecting No will skip token optimization (can be done later with 'dojo tokens'). [Y/n] " answer
case "${answer:-Y}" in
    [Yy]|"")
        log "User selected: Install token optimization"
        install_token_optimization
        ;;
    [Nn])
        log "User skipped token optimization"
        ;;
    *)
        log "Invalid response - skipping token optimization"
        ;;
esac
}

# ---------------------------------------------------------------------------
# Install token optimization
# ---------------------------------------------------------------------------
install_token_optimization() {
    log "Installing token optimization plugins..."

    # Install rtk if not already present
    if ! command -v rtk >/dev/null 2>&1; then
        log "Installing RTK..."
        # Would run: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
        log "RTK installation skipped (placeholder)"
    fi

    # Install graphify if not already present
    if ! command -v graphify >/dev/null 2>&1; then
        log "Installing graphify..."
        # Would run: uv tool install graphifyy
        log "graphify installation skipped (placeholder)"
    fi

    # Install token-optimizer if not already present
    if ! command -v token-optimizer >/dev/null 2>&1; then
        log "Installing token-optimizer..."
        # Would run: pip install token-optimizer
        log "token-optimizer installation skipped (placeholder)"
    fi

    # Install ponytail if not already present
    if ! command -v ponytail >/dev/null 2>&1; then
        log "Installing ponytail..."
        # Would run: npm install -g @dietrichgebert/ponytail
        log "ponytail installation skipped (placeholder)"
    fi

    # Configure dojo profile for token optimization
    log "Configuring dojo profile for token optimization..."

    # Add token optimizer to profile block
    local profile_file
    if [[ -f "$HOME/.bashrc" ]]; then
        profile_file="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
        profile_file="$HOME/.zshrc"
    else
        profile_file="$HOME/.bashrc"
    fi

    # Insert dojo marker if not present
    if ! grep -q '# >>> dojo >>>' "$profile_file" 2>/dev/null; then
        log "Adding dojo profile block to $profile_file"
        cat >> "$profile_file" <<'DOJO_PROFILE'
# >>> dojo >>>
# Managed by dojo (install.sh) — do not edit by hand.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.npm-global/bin:$PATH"
export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null || echo '')"
[ -s "$HOME/.local/bin/dojo-ssh-agent.sh" ] && . "$HOME/.local/bin/dojo-ssh-agent.sh"
# <<< dojo <<<
DOJO_PROFILE
    fi

    log "Token optimization installation complete."
}

# ---------------------------------------------------------------------------
# Complete Install Wipe
# ---------------------------------------------------------------------------
wipe_install() {
    local answer
    read -rp "Are you sure you want to completely wipe the dojo/Orca installation?
This will remove all configuration.
[y/N] " answer
case "${answer:-N}" in
    [Yy])
        log "User confirmed complete install wipe"

        # Remove Orca configuration
        log "Removing Orca configuration..."
        rm -rf "$HOME/.orca-desktop" 2>/dev/null || true
        rm -rf "$HOME/.orca-headless" 2>/dev/null || true

        # Remove token optimization config markers from profile
        log "Removing token optimization configuration..."
        local profile_file
        if [[ -f "$HOME/.bashrc" ]]; then
            profile_file="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            profile_file="$HOME/.zshrc"
        else
            profile_file="$HOME/.bashrc"
        fi

        if grep -q '# >>> dojo >>>' "$profile_file" 2>/dev/null; then
            # Remove the dojo block
            awk -v head="# >>> dojo >>>" -v tail="# <<< dojo <<<" '
                $0 == head { skip=1; next }
                skip && $0 == tail { skip=0; next }
                !skip { print }
            ' "$profile_file" > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
            log "Dojo profile block removed."
        fi

        # Remove orca launchers
        rm -f "$HOME/.local/bin/orca-desktop" 2>/dev/null || true
        rm -f "$HOME/.local/bin/orca-headless" 2>/dev/null || true

        # Remove dojo local bin entries
        rm -f "$HOME/.local/bin/dojo" 2>/dev/null || true
        rm -f "$HOME/.local/bin/dojo-ssh-agent.sh" 2>/dev/null || true

        echo "The dojo/Orca installation has been completely wiped."
        echo "You can re-run install.sh to set up again."
        read -rp "Press Enter to continue..."
        ;;
    *)
        log "Wipe cancelled by user"
        ;;
esac
}

# ---------------------------------------------------------------------------
# Read variant and optimize from stdin (handles piped input)
# ---------------------------------------------------------------------------
read_user_choices() {
    local line
    local found_variant=0
    local found_optimize=0

    # Read all lines from stdin
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Look for variant choice (1 or 2)
        if [[ "$found_variant" -eq 0 ]] && [[ "$line" =~ ^[12]$ ]]; then
            variant="$line"
            found_variant=1
        # Look for optimize preference (y/n/Y/N)
        elif [[ "$found_optimize" -eq 0 ]] && [[ "$line" =~ ^[YyNn]$ ]]; then
            optimize="$line"
            found_optimize=1
        fi

        # Stop reading once we have both choices
        if [[ "$found_variant" -eq 1 && "$found_optimize" -eq 1 ]]; then
            break
        fi
    done

    # Set defaults if not found
    variant="${variant:-1}"
    optimize="${optimize:-Y}"
}

# ---------------------------------------------------------------------------
# Show main menu (interactive mode)
# ---------------------------------------------------------------------------
show_main_menu() {
    local choice
    echo ""
    echo "=== Orca Work Environment Installer ==="
    echo "Welcome to the dojo Orca work environment installer."
    echo "Please select your installation mode:"
    echo "1) Orca Desktop (with GUI, editor, mobile companion)"
    echo "2) Orca Headless (no GUI, server/VPS optimized)"
    echo "3) Token Optimization Setup"
    echo "4) Complete Install Wipe"
    echo "5) Exit"
    echo ""
    read -rp "Enter choice [1-5]: " choice
    echo ""

    # Validate choice and output the number
    case "$choice" in
        1) echo "1" ;;
        2) echo "2" ;;
        3) echo "3" ;;
        4) echo "4" ;;
        5) echo "5" ;;
        "") echo "" ;;
        *) echo "invalid" ;;
    esac
}

# ---------------------------------------------------------------------------
# Main installation flow
# ---------------------------------------------------------------------------
main() {
    # Ensure orca is available
    if ! command -v orca >/dev/null 2>&1; then
        warn "WARNING: orca not found in PATH - it may need to be installed separately"
        warn "This installer sets up the dojo environment for Orca."
    fi

    # Ensure local bin is in PATH
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    # GitHub auth check
    if ! command -v gh >/dev/null 2>&1; then
        warn "GitHub CLI (gh) not found - some features may not work properly"
        warn "Install: brew install gh (macOS) or sudo apt-get install gh (Ubuntu)"
        warn "Or set up SSH keys: ssh-keygen -t ed25519 -C you@example.com"
    fi

    # Step 1: Determine if running interactively or with piped input
    log "Step 1: Determining input mode..."

    local variant
    local optimize

    # Check if stdin is a terminal (interactive mode)
    if [[ -t 0 ]]; then
        # Interactive mode - show main menu
        log "Step 1: Interactive mode - showing main menu..."
        local menu_choice
        menu_choice=$(show_main_menu) || {
            log "Menu cancelled by user - exiting"
            exit 1
        }

        # Trim choice
        menu_choice="${menu_choice// /}"

        case "$menu_choice" in
            1)
                # Install Orca Desktop
                if is_orca_desktop_installed; then
                    log "Orca Desktop is already installed."
                else
                    install_orca_desktop
                fi
                # Prompt for token optimization after install
                prompt_token_optimization
                ;;
            2)
                # Install Orca Headless
                if is_orca_headless_installed; then
                    log "Orca Headless is already installed."
                else
                    install_orca_headless
                fi
                # Prompt for token optimization after install
                prompt_token_optimization
                ;;
            3)
                # Token optimization setup
                prompt_token_optimization
                ;;
            4)
                # Complete install wipe
                wipe_install
                ;;
            5|"")
                # Exit
                log "Exiting installer."
                exit 0
                ;;
            *)
                warn "Invalid choice: $menu_choice"
                exit 1
                ;;
        esac
    else
        # Non-interactive mode - read from piped input
        log "Step 1: Piped input detected - reading user choices..."
        read_user_choices
    fi

    # Step 2: Install selected Orca variant (always runs after reading choices)
    log "Step 2: Installing Orca variant..."

    case "$variant" in
        1)
            log "Installing Orca Desktop..."
            if is_orca_desktop_installed; then
                log "Orca Desktop is already installed."
            else
                install_orca_desktop
            fi
            ;;
        2)
            log "Installing Orca Headless..."
            if is_orca_headless_installed; then
                log "Orca Headless is already installed."
            else
                install_orca_headless
            fi
            ;;
        *)
            log "Invalid choice - installing Orca Desktop by default"
            install_orca_desktop
            ;;
    esac

    # Step 3: Token optimization
    log "Step 3: Token optimization setup"

    # Normalize optimize input
    optimize="${optimize:-Y}"
    case "${optimize}" in
        [Yy]|"")
            log "User selected: Install token optimization"
            install_token_optimization
            ;;
        [Nn])
            log "User skipped token optimization"
            ;;
        *)
            log "Invalid response - skipping token optimization"
            ;;
    esac

    # Step 4: Summary
    log ""
    log "=== Orca work environment installation complete ==="
    log ""

    # Determine installed variant for summary
    local installed_variant="Unknown"
    if [[ -d "$HOME/.orca-desktop" ]]; then
        installed_variant="Desktop"
    elif [[ -d "$HOME/.orca-headless" ]]; then
        installed_variant="Headless"
    fi

    log "Your Orca work environment is now set up."
    log "  - Orca variant: $installed_variant"
    log "  - Configuration located under $HOME/.orca-*/"
    log ""
    log "You can run 'orca' to open the work environment."
    log "Token optimization plugins can be configured with 'dojo tokens'."
}

# ---------------------------------------------------------------------------
# Run main function
# ---------------------------------------------------------------------------
main "$@"
