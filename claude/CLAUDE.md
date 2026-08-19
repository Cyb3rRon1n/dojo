@RTK.md
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Cross-machine setup
- This stack is versioned in `~/dojo` (github.com/Cyb3rRon1n/dojo, public).
- After any `git -C ~/dojo pull`, re-run `~/dojo/bootstrap.sh` (idempotent) to pick up plugin pins, the RTK hook, and graphify. Restart opencode + Claude Code after.
- On a brand-new machine: one-liner — `bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.sh)` — installs opencode + Claude Code + uv, runs the full bootstrap, and clones `~/Projects/github/repos` (submodules included). Only manual step: GitHub auth (SSH key or `gh auth login`) — install.sh warns if it's missing. Restart both after.
- If plugins seem lost: `~/dojo/bootstrap.sh` prints a verification (plugin counts, rtk/graphify versions); check that `~/.config/opencode/opencode.jsonc` and `~/.claude/CLAUDE.md` are symlinks into `~/dojo/`.
