# ponytail config

`config.json` is symlinked to `~/.config/ponytail/config.json` by `bootstrap.sh`.

`defaultMode: lite` makes ponytail start every session at **lite** instead of
`full`. lite still enforces the laziness ladder (stdlib first, shortest correct
diff, no speculative abstractions) but injects far less prompt text on every
turn — measurably cheaper per session, which is the point of this stack.

Bump to `full` or `ultra` for a single session with `/ponytail full` when the
work is over-engineering-prone (new subsystem, framework choice, a big refactor).

Resolution order (from `hooks/ponytail-config.js` upstream):
`PONYTAIL_DEFAULT_MODE` env var → this file's `defaultMode` → `full`.
