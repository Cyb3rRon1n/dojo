@RTK.md
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Cross-machine setup
- This stack is versioned in `~/dotfiles` (git@github.com:Cyb3rRon1n/dotfiles.git).
- After any `git -C ~/dotfiles pull`, re-run `~/dotfiles/bootstrap.sh` (idempotent) to pick up plugin pins, the RTK hook, and graphify. Restart opencode + Claude Code after.
- On a brand-new machine: clone the repos, then `git clone git@github.com:Cyb3rRon1n/dotfiles.git ~/dotfiles && ~/dotfiles/bootstrap.sh` before first launch — plugins load at startup, so a missing bootstrap silently means no token optimization.
- If plugins seem lost: `~/dotfiles/bootstrap.sh` prints a verification (plugin counts, rtk/graphify versions); check that `~/.config/opencode/opencode.jsonc` and `~/.claude/CLAUDE.md` are symlinks into `~/dotfiles/`.
