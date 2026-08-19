<img src="assets/dojo-lockup.svg" alt="dojo" width="420">

A dojo is where you train before you spar. This one sets up AI coding tools
on any machine — laptop, travel setup, wherever — wired with whatever
token-optimization each one supports, plus your GitHub projects cloned and
ready. One command, and you're warmed up and ready to work on whatever repo
you bring them into. Anyone can point this at their own GitHub and train
their own setup the same way.

Supported tools: **opencode**, **Claude Code**, **GitHub Copilot CLI**,
**OpenAI Codex CLI**, **Aider**. Each gets whatever optimizations it's
actually capable of running (see the table below) — dojo never installs a
tool you don't already have or ask for, and skips a tool's setup cleanly if
it's missing.

## Setup

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)
```

That's it. On a machine with none of the five tools installed, it installs
all of them, wires up whichever optimizations each one supports, clones
`~/projects/github/repos` (your projects), and tells you at the end if you
still need to log in to GitHub (SSH key or `gh auth login` — the one thing
it can't do for you). No sudo needed anywhere.

At the end, in an interactive terminal, it asks `enter dojo (cd into
~/projects/github/repos) or exit?` — press enter (or anything but `exit`)
and it drops you straight into that directory in a fresh shell; type `exit`
to stay where you are.

Restart whichever tools it set up once it finishes, and you're working.

Re-running it later (after a `git pull`) is safe — every step is a no-op if
already done, and only prints `ok`/`skip`/`FAILED` per step instead of
replaying each tool's own install chatter.

## The optimizations, and what each tool actually supports

AI coding assistants burn through their context window (their "working
memory," measured in tokens) on command output, file re-reads, and verbose
generated code. Once that fills up, responses get worse and sessions need
restarting. dojo wires up whatever each tool has a real integration for —
it doesn't force a plugin onto a tool that has no plugin system:

- **RTK** (`rtk`) — rewrites shell commands like `git status` or `find` to
  return only the parts an LLM actually needs, instead of raw terminal
  output. Cuts up to 90% of the tokens a typical command dumps into context.
  Runs automatically as a hook — nothing to invoke by hand. Has native
  integrations for Claude Code, opencode, GitHub Copilot CLI, and OpenAI
  Codex CLI.

- **graphify** — turns a codebase into a queryable knowledge graph once, so
  future questions ("where is X defined," "what calls Y") get answered by a
  graph lookup instead of the AI re-reading files across the whole repo
  every time. Supports all five tools dojo manages, including Aider.

- **token-optimizer** — audits the running session itself: how much context
  is used, what's wasting it, and gives a quality score. Claude Code +
  opencode only for now (no Copilot CLI / Codex CLI / Aider build exists
  yet).

- **ponytail** — a coding-style guardrail that pushes toward the smallest
  correct solution: reuse what's already there, stdlib over a new
  dependency, no speculative abstractions. Claude Code + opencode only, same
  reason as above.

- **Aider's own native settings** — Aider has no plugin/hook system, so
  there's no RTK/ponytail/token-optimizer equivalent to install. Instead
  dojo ships a default `~/.aider.conf.yml` that turns on Aider's own
  built-in prompt caching (off by default upstream).

| Tool | RTK | graphify | token-optimizer | ponytail |
|---|---|---|---|---|
| Claude Code | yes | yes | yes | yes |
| opencode | yes | yes | yes | yes |
| GitHub Copilot CLI | yes | yes | — | — |
| OpenAI Codex CLI | yes | yes | — | — |
| Aider | — | yes | — | — |

## Prefer manual setup?

Same result, step by step:

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

Only install the tools you want — `bootstrap.sh` detects what's present and
skips the rest. `bootstrap.sh` also finds its own location, so `~/dojo`
isn't required — cloning dojo alongside your other repos (e.g.
`~/projects/github/repos/dojo`) works identically.

## Reference

Only the opencode side is version-pinned, in `opencode/opencode.jsonc` /
`opencode/package.json` — bump deliberately. Every other install path
(Claude Code plugin marketplace, RTK's and graphify's own install scripts,
Aider's installer) always fetches latest — don't expect versions to match
across tools.

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

Once `install.sh` or `bootstrap.sh` has run once, a `dojo` command is on
your PATH:

```bash
dojo status   # dojo version, whether it's behind origin, tool/plugin versions, GitHub auth
dojo update   # git pull + re-run bootstrap.sh, from wherever you cloned it
```

## Layout

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
bootstrap.sh          # idempotent setup (plugins, hooks, configs, per tool)
install.sh            # one-shot fresh-machine build-out (installs all 5 tools, calls bootstrap.sh, then clones repos/)
dojo                  # day-to-day command: `dojo update` / `dojo status` (symlinked onto PATH by bootstrap.sh)
```

GitHub Copilot CLI and OpenAI Codex CLI have no dojo-owned config files —
RTK and graphify write their integration files directly onto those tools'
own config paths (`~/.copilot/`, `~/.codex/`) when you run `dojo update`, so
there's nothing for this repo to template or track.
