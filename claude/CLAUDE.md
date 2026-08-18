@RTK.md
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Cross-machine setup
- This stack is versioned in `~/dotfiles` (github.com/Cyb3rRon1n/dotfiles, public).
- After any `git -C ~/dotfiles pull`, re-run `~/dotfiles/bootstrap.sh` (idempotent) to pick up plugin pins, the RTK hook, and graphify. Restart opencode + Claude Code after.
- On a brand-new machine: one-liner — `bash <(curl -fsSL https://raw.githubusercontent.com/Cyb3rRon1n/dotfiles/main/install.sh)` — installs opencode + Claude Code + uv and runs the full bootstrap. Restart both after.
- If plugins seem lost: `~/dotfiles/bootstrap.sh` prints a verification (plugin counts, rtk/graphify versions); check that `~/.config/opencode/opencode.jsonc` and `~/.claude/CLAUDE.md` are symlinks into `~/dotfiles/`.
