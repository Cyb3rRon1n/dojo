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
