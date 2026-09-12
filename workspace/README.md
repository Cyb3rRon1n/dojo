# dojo workspace

A browser IDE — [code-server](https://github.com/coder/code-server) (VS Code) —
with the terminal coding agents and dojo's optimizer stack already installed and
wired. Spin it up on a homelab box, put it behind your reverse proxy, and open a
full agent-ready workspace from any browser.

This is the browser-native path — no desktop app anywhere. An optional second
service, `orca-serve`, also lives in this directory for Orca's own remote mode
(parallel worktrees, mobile client) — see below for why that one still needs
the Orca desktop/mobile app as its client, not a browser.

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

By default no port is published — reach it over Tailscale/WireGuard (see
Security below) or by uncommenting the `ports:` block in `docker-compose.yml`
for LAN-only use. Already run Vulcan's Traefik + Authelia? Use the proxy
overlay instead (see Security).

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
  (Authelia/Authentik/oauth2-proxy), plus HTTPS. Two ways to do that here:

  **Tailscale/WireGuard only (default, simplest)** — leave the port
  unpublished, or publish it and rely on the VPN alone to reach it. No proxy
  config needed; `code-server`'s own `WORKSPACE_PASSWORD` is the only login.

  **Already run Vulcan's Traefik + Authelia?** Use the overlay instead of a
  second VPN hop:

  ```bash
  # .env additions:
  #   TRAEFIK_NETWORK=<vulcan's compose project name>_default   # docker network ls | grep -i default
  #   WORKSPACE_DOMAIN=workspace.yourdomain.tld
  #   TRAEFIK_ENTRYPOINTS=websecure,tunnel   # only if Vulcan's Traefik has cloudflared enabled — see below
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d --build
  ```

  Vulcan's Authelia runs `default_policy: one_factor`, so routing through
  Traefik with the `authelia@docker` middleware already requires a login —
  no Authelia config change needed. **Recommended**: add
  `workspace.<domain>` to Vulcan's own `admin_only_services` so this
  service — the one holding your agent API keys and a GitHub token — needs
  the admin group, not just any authenticated user.

  **Behind a Cloudflare Tunnel** (found live, not hypothetical — see the
  overlay file's own comments for the full story): every other tunneled
  router in Vulcan's compose carries `entrypoints=websecure,tunnel`, and
  Traefik's docker provider needs `traefik.docker.network` pinned the
  moment this service sits on more than one network (it does, by design —
  `default` + `proxy`) or it can pick the network it has no route to and
  hang until Cloudflare's edge times out (504/524). Both are already
  handled by the overlay — `TRAEFIK_ENTRYPOINTS` above is the only thing
  you set; `traefik.docker.network` just uses `TRAEFIK_NETWORK` you already set.
- Use a fine-grained GitHub token scoped to just the repos you work on.
- Treat the API keys as rotatable; don't reuse your primary ones if you can help it.

Egress allowlisting, dropped capabilities, and a read-only root FS are sensible
next steps if this box does anything else.

## Managing the host you run on (optional)

`docker-compose.manage.yml` gives the workspace `docker`/`docker compose`
(client-only, no daemon in this image) against **this host's** real Docker
socket, plus your real repo checkouts mounted at `/home/coder/host` — for
using the agents inside to fix or update whatever else runs here (a
co-located Vulcan install included), the exact loop this project's own dojo
repo was debugged through.

```bash
# .env addition:
#   HOST_PROJECTS_DIR=/home/youruser   # wherever your real checkouts live
docker compose -f docker-compose.yml [-f docker-compose.proxy.yml] -f docker-compose.manage.yml up -d --build
```

Mounting `/var/run/docker.sock` is root-equivalent access to the whole host,
not just "containers" — the same caveat as everywhere else this stack
touches a socket. This overlay is opt-in for exactly that reason.

## orca-serve — an always-on Orca agent server (optional)

`orca/` builds a second, separate service: Orca itself (github.com/stablyai/orca),
headless, so its agents keep running while your laptop sleeps. Enable it with:

```bash
docker compose --profile orca up -d --build orca-serve
```

**This is not a browser workspace.** Orca's own browser client can't yet run
terminals or agents against a headless server (open upstream issue,
stablyai/orca#9047) — you pair to this with the **Orca desktop or mobile app**
(Settings → Remote Orca Servers → Add Server, or scan the QR code), not a URL
you click from the dashboard. Reach it over Tailscale only — Orca has no
account system; its `serve` output prints a one-time pairing URL, which is
itself the credential, so keep it out of logs you'd share. Set
`ORCA_PAIRING_ADDRESS` in `.env` to the host's Tailscale IP so the printed
pairing link advertises an address your desktop app can actually reach:

```bash
docker compose --profile orca logs orca-serve | grep "Pairing URL"
```

Verified live: the image builds, `docker run` reaches "Orca server ready"
and a real pairing URL, and the port answers `200`. One thing learned the
hard way — wrapping the launch in `xvfb-run` left it never starting (its own
readiness check never unblocked in this image); Orca launches its own
internal Xvfb correctly as long as `DISPLAY` is left unset, which is what
`entrypoint.sh` now does.

## Homepage dashboard tile

If you run a co-located Vulcan install with Homepage enabled, add a click-through
tile for this workspace instead of remembering the URL:

```bash
pip install --user pyyaml   # if not already present
python3 workspace/homepage_integrate.py --url http://192.168.1.x:8443
```

The tile also gets a live status dot (Homepage's built-in ping check) —
default `--ping` points at the compose-assigned container name:port
directly, bypassing Traefik/Authelia for a true "is the container actually
up" signal. Override if you renamed the compose project/service, or pass
`--ping ''` to omit it.

Auto-detects a sibling `vulcan/stack` (the same layout this workspace repo
itself uses); pass `--vulcan-dir` for any other layout. Safe to re-run — it
only ever touches its own "Workspace (dojo)" group, same write-once respect
for the rest of `services.yaml` as Anvil's Vulcan integration.

## Persistence

One named volume holds all of `/home/coder`: your projects, every agent's auth and
history, shell history, editor settings. Remove it (`docker compose down -v`) to
start clean.
