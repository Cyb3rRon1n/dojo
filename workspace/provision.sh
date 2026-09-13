#!/bin/bash
# Runs at container start (code-server ENTRYPOINTD hook), as the coder user,
# before code-server launches. The /home/coder volume can be empty on first
# boot, so run dojo's idempotent wiring against whatever it currently holds.
set -u

export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

# docker-compose.manage.yml mounts the host's /var/run/docker.sock, whose
# group GID varies per host and almost never matches any group already in
# this image. Must happen before code-server starts below (group membership
# is fixed at process start, not re-read per-command) - a terminal opened
# inside code-server inherits whatever groups coder has *right now*.
if [ -S /var/run/docker.sock ]; then
    SOCK_GID="$(stat -c %g /var/run/docker.sock)"
    if ! getent group "$SOCK_GID" >/dev/null; then
        sudo groupadd -g "$SOCK_GID" dockerhost
    fi
    sudo usermod -aG "$SOCK_GID" coder
fi
mkdir -p "$HOME/projects"

# Seeds a project-parent CLAUDE.md so agents working under ~/projects/<repo>
# know what host/stack this container sits next to - each cloned repo's own
# CLAUDE.md documents that repo's code, not the deployment it's running in,
# and this container's hostname is just a random Docker ID. Written once
# from WORKSPACE_HOST_NOTE (this host's own .env, never this public repo);
# never overwritten once present, so a manual edit (or a blank note this
# host never set) always wins over re-running provisioning.
HOST_NOTE_FILE="$HOME/projects/CLAUDE.md"
if [ -n "${WORKSPACE_HOST_NOTE:-}" ] && [ ! -f "$HOST_NOTE_FILE" ]; then
    printf '# Deployment context\n\n%s\n' "$WORKSPACE_HOST_NOTE" > "$HOST_NOTE_FILE"
fi

VSCODE_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
if [ ! -f "$VSCODE_SETTINGS" ] && [ -f /opt/dojo-defaults/vscode-settings.json ]; then
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    cp /opt/dojo-defaults/vscode-settings.json "$VSCODE_SETTINGS"
fi

# A real GITHUB_TOKEN in the environment means `gh auth status` passes and
# bootstrap never touches auth. Without one, bootstrap would call the
# interactive `gh auth login` device flow, which polls forever with no TTY
# and wedges container start — so shadow `gh` with a shim that only
# short-circuits `gh auth login` (everything else passes through).
export GH_TOKEN="${GITHUB_TOKEN:-}"
SHIM="$HOME/.dojo-shim"
mkdir -p "$SHIM"
cat > "$SHIM/gh" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "login" ]; then
    echo "[dojo-workspace] gh auth login skipped — run it yourself in the terminal" >&2
    exit 1
fi
exec /usr/bin/gh "$@"
EOF
chmod +x "$SHIM/gh"

# Token-usage/quality status for the Homepage tile's widget (see
# homepage_integrate.py --stats-port) - reads whatever token-optimizer data
# exists once bootstrap wires it in below; serves {} until then. Backgrounded,
# not part of code-server's own process tree, so it survives independent of
# any single terminal session.
nohup python3 /opt/dojo/dojo-tokens.py --serve 8799 >"$HOME/.dojo-tokens-server.log" 2>&1 &

MARKER="$HOME/.dojo-provisioned"
run_bootstrap() {
    PATH="$SHIM:$PATH" TOKEN_OPTIMIZE=1 bash /opt/dojo/bootstrap.sh </dev/null
}

if [ ! -x /opt/dojo/bootstrap.sh ]; then
    echo "[dojo-workspace] WARNING: /opt/dojo/bootstrap.sh missing — skipping wiring"
elif [ ! -f "$MARKER" ]; then
    echo "[dojo-workspace] first boot — wiring optimizer stack (this takes a minute)"
    run_bootstrap && touch "$MARKER" || echo "[dojo-workspace] bootstrap had warnings; continuing"
else
    echo "[dojo-workspace] re-wiring in the background"
    ( run_bootstrap >"$HOME/.dojo-provision.log" 2>&1 || true ) &
fi
