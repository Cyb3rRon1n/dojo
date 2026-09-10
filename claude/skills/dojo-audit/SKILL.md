---
name: dojo-audit
description: >-
  Token and performance diagnostics for the dojo stack (Claude Code / opencode /
  Codex). Runs token-optimizer, RTK, and graphify readouts, summarises context
  overhead, cost per session, and quality trends, then proposes ranked
  improvements. Use on "/dojo-audit", "audit my setup", "why is this session
  expensive", "check token usage", or when context feels tight. Read-only
  diagnosis — it proposes, it does not change config.
---

# dojo-audit

One-shot health + token audit of the dojo optimization stack. Diagnose, then
present ranked options. **Never edit config in this skill** — hand the user
decisions and let them (or a follow-up) apply them, ideally as a dojo PR.

## 1. Resolve the runtime

dojo machines often export `OPENCODE_CONFIG_DIR` globally (Orca), which
false-trips token-optimizer's runtime gate. If you are in Claude Code
(`CLAUDECODE=1`, parent process `claude`), prefix its commands with
`TOKEN_OPTIMIZER_RUNTIME=claude`.

Find `measure.py`:

```bash
find -L "$HOME/.claude/plugins/cache" "$HOME/.claude/skills" -type f -name measure.py \
  -path '*token-optimizer*/scripts/measure.py' 2>/dev/null | head -1
```

## 2. Collect (all read-only)

```bash
export TOKEN_OPTIMIZER_RUNTIME=claude   # Claude Code only
python3 "$MEASURE_PY" quick             # overhead, degradation risk, top offenders
python3 "$MEASURE_PY" doctor            # component health
python3 "$MEASURE_PY" coach             # health score, issues, cost/session, subagent spend
python3 "$MEASURE_PY" trends            # 30d: sessions, skill usage, model mix, drift
python3 "$MEASURE_PY" savings           # what the stack has already saved + opportunities
rtk gain                               # RTK command-output savings
```

Then inspect config: `~/.claude/settings.json` (hooks, `respondToBashCommands`,
`permissions.deny`), `~/.claude/CLAUDE.md`, `~/.claude/.contextignore`, local
skills + agents, `~/.config/ponytail/config.json`.

## 3. Summarise

- **Startup overhead** (tokens + % of window) and **real session baseline**.
- **Cost/session** and **quality grade distribution** (from coach).
- **Subagent spend** — flag any research running on Opus.
- **Drift** since last snapshot.
- **Already working** — measured savings, RTK %, progressive disclosure.

## 4. Rank improvements

High value first. Typical levers, roughly in order:

1. `respondToBashCommands: false` if unset (auto-reply after every `!`/`/cmd`).
2. Research subagents on Opus → point them at the `researcher` agent (Sonnet).
3. ponytail `full` → `lite` default (`~/.config/ponytail/config.json`).
4. Missing `.contextignore` / `permissions.deny` → stale re-reads.
5. Verbose CLAUDE.md / skill descriptions loaded every session.
6. Dead daemons / broken hooks from `doctor`.

## 5. Present, don't apply

Give the user the summary and the ranked list. For anything they want changed,
the fix belongs in `~/dojo` (bootstrap patch, shipped config, CLAUDE.md edit)
so it deploys to every machine — offer to open a branch + PR.
