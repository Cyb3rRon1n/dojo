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
