# dojo workspace

A browser IDE — [code-server](https://github.com/coder/code-server) (VS Code) —
with the terminal coding agents and dojo's optimizer stack already installed and
wired. Spin it up on a homelab box, put it behind your reverse proxy, and open a
full agent-ready workspace from any browser.

This is the browser-native alternative to running Orca on the desktop. Orca's own
`orca serve` remote mode is the higher-fidelity option (parallel worktrees, mobile
client) — see the dojo README — but this needs no desktop app anywhere.

## What's in the image

| | |
|---|---|
| Editor | code-server (VS Code in the browser) + integrated terminal |
| Agents | Claude Code, opencode, Codex CLI, Copilot CLI, Qwen Code, Aider |
| Optimizers | RTK, graphify, token-optimizer, ponytail, Serena — wired by `dojo/bootstrap.sh` at every start |
| Runtime | Node 22, Python 3, uv, pipx, gh, git |

Agent CLIs and uv tools install to system paths, so the persisted home volume
never shadows them. `bootstrap.sh` re-runs on every container start (idempotent),
so a fresh volume is provisioned on first boot and re-verified after.

## Run it

```bash
cd workspace
cat > .env <<'EOF'
WORKSPACE_PASSWORD=change-me
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GITHUB_TOKEN=
EOF
docker compose up -d --build
```

First build is slow (full toolchain). First start runs `bootstrap.sh` against the
empty volume — a minute or two — then subsequent starts are fast.

By default no port is published: attach the `workspace` service to your
reverse-proxy network. For a first run or LAN-only use, uncomment the `ports:`
block in `docker-compose.yml` (`8443:8080`).

### Environment

| Variable | Purpose |
|---|---|
| `WORKSPACE_PASSWORD` | code-server login password (required) |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | passed to the agents; or log in interactively in the terminal |
| `GITHUB_TOKEN` | for `gh` and the GitHub MCP server — use a fine-grained, short-lived token |

## Security

Do **not** expose this straight to the internet. The agents hold your API keys and
a GitHub token, and a container is not a hard isolation boundary — indirect prompt
injection through a repo or dependency can run code with your permissions.

- Put it behind a VPN (Tailscale/WireGuard) or an authenticating proxy
  (Authelia/Authentik/oauth2-proxy), plus HTTPS.
- Use a fine-grained GitHub token scoped to just the repos you work on.
- Treat the API keys as rotatable; don't reuse your primary ones if you can help it.

Egress allowlisting, dropped capabilities, and a read-only root FS are sensible
next steps if this box does anything else.

## Persistence

One named volume holds all of `/home/coder`: your projects, every agent's auth and
history, shell history, editor settings. Remove it (`docker compose down -v`) to
start clean.
