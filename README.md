<img src="assets/dojo-lockup.svg" alt="dojo" width="420">

# dojo

A training ground for AI coding tools. Clone once, run one command, and
**opencode**, **Claude Code**, **GitHub Copilot CLI**, **OpenAI Codex CLI**,
and **Aider** are all set up with whatever token-saving optimizations each
one actually supports — plus your GitHub projects, cloned and ready.

Anyone can point this at their own GitHub and train their own setup the
same way.

## Quickstart

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)
```

Installs whichever of the five tools you don't already have, wires up
whatever optimizations each one supports, clones `~/projects/github/repos`,
and prompts for GitHub auth (SSH key or `gh auth login`) if it's missing.
No sudo, anywhere. Safe to re-run later — every step is a no-op if already
done.

## Catalog

### Tools dojo sets up

| Tool | What it is |
|---|---|
| [opencode](https://opencode.ai) | Open-source terminal coding agent |
| [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) | Anthropic's terminal coding agent |
| [GitHub Copilot CLI](https://www.npmjs.com/package/@github/copilot) | GitHub's terminal coding agent |
| [OpenAI Codex CLI](https://www.npmjs.com/package/@openai/codex) | OpenAI's terminal coding agent |
| [Aider](https://aider.chat) | Open-source, git-native AI pair programmer |

dojo never force-installs a tool you didn't ask for — `bootstrap.sh` only
configures what's already present on the machine (`install.sh` is the one
that offers to install all five fresh).

### Optimizations dojo wires up

| Plugin | What it does | Works with |
|---|---|---|
| [RTK](https://github.com/rtk-ai/rtk) | Filters command output before it hits context — up to 90% fewer tokens per command | Claude Code, opencode, Copilot CLI, Codex CLI |
| [graphify](https://www.npmjs.com/package/@javargasm/opencode-graphify) | Builds a queryable knowledge graph of the codebase, once, instead of re-reading files every question | Claude Code, opencode, Copilot CLI, Codex CLI, Aider |
| [token-optimizer](https://github.com/alexgreensh/token-optimizer) | Audits the running session for context waste and gives a quality score | Claude Code, opencode |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Coding-style guardrail against over-engineering — smallest correct solution, stdlib first | Claude Code, opencode |
| Aider's native settings | Turns on Aider's own built-in prompt caching (off by default upstream) — no plugin exists because Aider has no plugin system | Aider only |

Nothing here is faked: token-optimizer and ponytail simply don't have a
Copilot CLI / Codex CLI / Aider build yet, so dojo doesn't claim one.

## Commands

Once installed, a `dojo` command is on your `PATH`:

```bash
dojo status   # versions, GitHub auth, whether you're behind origin
dojo doctor   # verify every wiring point (PATH, symlinks, hooks, plugins); exit 1 if broken
dojo update   # git pull + re-run bootstrap.sh, from wherever you cloned it
dojo install  # re-run install.sh (idempotent) — same one-shot as a fresh machine
dojo tokens   # live token usage / cache refresh / context-fill thresholds
```

`dojo update` is the self-heal: any wiring that rotted (deleted symlink, lost
plugin, missing hook) is re-created. `dojo doctor` tells you *when* to run it.

### Token status

While opencode or Claude Code is running, token-optimizer writes live session
state (per-session SQLite + a global trends DB) under
`~/.local/share/token-optimizer/`. `dojo tokens` reads that real data and
prints current **token usage** (input/output), **token refresh** (context-cache
read/write), and **context-fill threshold** percentage vs the model's context
window, colored by the same Good/Fair/Needs-Work/Poor bands the plugin itself
uses. `dojo tokens --one-line` emits a compact colored line for prompts.

### Persistence

The toolchain PATH and the token-status prompt hook are written into your
shell profile (`~/.bashrc`, plus `~/.zshrc` if present) as a marked,
dojo-managed block — so `opencode`, `claude`, `rtk`, `graphify`, and `nvm` are
on `PATH` after a fresh login, and every interactive prompt appends a live
token status line (usage / refresh / fill %) whenever token data exists. The
block is rewritten from the installed dojo version on every `dojo update`;
don't hand-edit it.

<details>
<summary><b>Prefer manual setup?</b></summary>

Same result, step by step — install only the tools you want:

```bash
curl -fsSL https://opencode.ai/install | bash
npm install -g @anthropic-ai/claude-code
npm install -g @github/copilot
npm install -g @openai/codex
curl -fsSL https://aider.chat/install.sh | sh
curl -LsSf https://astral.sh/uv/install.sh | sh
git clone git@github.com:Cyb3rRon1n/dojo.git ~/dojo
~/dojo/bootstrap.sh
```

`bootstrap.sh` detects what's present and skips the rest. It also finds its
own location, so `~/dojo` isn't required — cloning dojo alongside your
other repos (e.g. `~/projects/github/repos/dojo`) works identically.

</details>

<details>
<summary><b>Reference</b></summary>

Only the opencode side is version-pinned, in `opencode/opencode.jsonc` /
`opencode/package.json` — bump deliberately. Every other install path
(Claude Code's plugin marketplace, RTK's and graphify's own install
scripts, Aider's installer) always fetches latest, so don't expect versions
to match across tools.

| Component | opencode version (pinned) |
|---|---|
| RTK | 0.1.5 |
| token-optimizer | 1.1.0 |
| ponytail | 4.7.3 |
| graphify | 0.2.0 |

Files this repo does **not** touch on your machine:
- `~/.claude/settings.json` — hooks/settings stay machine-local. Only the
  RTK `PreToolUse` hook is added, via `rtk init -g`.
- `~/.config/opencode/package-lock.json` — regenerated by `npm install`.

GitHub Copilot CLI and OpenAI Codex CLI have no dojo-owned config files —
RTK and graphify write their integration files directly onto those tools'
own config paths (`~/.copilot/`, `~/.codex/`) when you run `dojo update`,
so there's nothing for this repo to template or track.

</details>

<details>
<summary><b>Layout</b></summary>

```
opencode/
  opencode.jsonc     # pinned plugin list (symlinked into ~/.config/opencode/)
  package.json       # pinned npm deps (copied; npm install fills node_modules)
  package-lock.json
claude/
  CLAUDE.md          # user instructions (symlinked into ~/.claude/)
  RTK.md             # RTK reference (symlinked into ~/.claude/)
aider/
  aider.conf.yml     # default Aider settings (symlinked to ~/.aider.conf.yml)
assets/               # dojo's own logo/banner (mark, lockup, social preview)
bootstrap.sh          # idempotent setup (plugins, hooks, configs, per tool)
install.sh            # one-shot fresh-machine build-out (installs all 5 tools, calls bootstrap.sh, then clones repos/)
dojo                  # day-to-day command: `dojo update` / `dojo install` / `dojo status` / `dojo doctor` / `dojo tokens` (symlinked onto PATH by bootstrap.sh)
dojo-tokens.py        # reads token-optimizer's live SQLite state (used by `dojo tokens` and the PS1 hook)
```

</details>
