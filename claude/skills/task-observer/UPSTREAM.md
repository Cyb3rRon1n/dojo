# Upstream

Vendored from [rebelytics/one-skill-to-rule-them-all](https://github.com/rebelytics/one-skill-to-rule-them-all)
(a.k.a. "task-observer"), commit `281f13466cd3a73e9ebc9d210907748e1941a3dd` (2026-07-17).

Licensed CC BY 4.0 by Eoghan Henn / rebelytics.com — see `LICENSE.txt`. Not a
Claude Code plugin-marketplace package (no `.claude-plugin/marketplace.json`),
so it's vendored here as a plain skill directory instead of registered via
`claude plugin marketplace add`, and symlinked into `~/.claude/skills/` by
`bootstrap.sh`.

To pick up an upstream update: re-clone the repo, diff `SKILL.md`,
`USER-GUIDE.md`, `LICENSE.txt`, and `references/*.md` against this directory,
and bump the commit hash above. `README.md` and the two PNG banners are
deliberately not vendored — decorative, not loaded by the skill itself.

## Local modifications

- **`SKILL.md` frontmatter `description`** — trimmed to ~8 lines (from ~13).
  Full upstream text is belt-and-suspenders for activation; dojo's
  `claude/CLAUDE.md` already carries the hard activation instruction, so the
  long description just costs tokens every session. Re-apply this trim after
  any upstream `SKILL.md` merge. Skill body is unmodified.
