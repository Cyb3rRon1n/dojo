@RTK.md

# Skills & agents dojo adds
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) — any input → knowledge graph. On `/graphify`, use it before anything else.
- **task-observer** (`~/.claude/skills/task-observer/SKILL.md`, "One Skill to Rule Them All") — watch substantive multi-step work sessions for corrections, workflow patterns, and skill gaps; log structured observations. Invoke at the start of that kind of session (description-only matching isn't reliable). Also trigger on "any observations logged?".
- **dojo-audit** (`~/.claude/skills/dojo-audit/SKILL.md`) — token/perf diagnostics of this stack + ranked improvement options. Trigger: `/dojo-audit`.
- **researcher** agent — dispatch heavy web research here (Sonnet, read-only); it synthesises and keeps raw pages out of this context.

# Ponytail
- Starts every session at **lite** (`~/.config/ponytail/config.json`). Bump per-session with `/ponytail full` for over-engineering-prone work.

# Session hygiene
- Concise output on routine/mechanical tasks (file edits, status checks, git ops); skip explanations unless asked.
- Heavy web research (many searches/fetches) → the `researcher` subagent, or a fork. Synthesize and report back; don't pull raw pages into this context.

# Cross-machine setup
- This stack lives in `~/dojo` (github.com/Cyb3rRon1n/dojo). After `git -C ~/dojo pull`, re-run `~/dojo/bootstrap.sh` (idempotent) and restart opencode + Claude Code. New machine, full setup, and troubleshooting: dojo README.
