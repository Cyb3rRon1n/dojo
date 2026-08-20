#!/usr/bin/env bash
# Copilot CLI statusline — reads the JSON Copilot sends on stdin and prints a
# one-line context-window readout for the footer. Prints nothing on garbage
# input so a mangled pipe never breaks the UI.
python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)


def fmt(n):
    n = int(n or 0)
    return f"{n / 1e6:.2f}M" if n >= 1_000_000 else f"{n / 1e3:.1f}k" if n >= 1_000 else str(n)


cw = d.get("context_window") or {}
used = cw.get("used_percentage")
inp = cw.get("total_input_tokens") or 0
out = cw.get("total_output_tokens") or 0
if used is not None:
    print(f"ctx {used:.0f}% · {fmt(inp)}/{fmt(out)}")
' "$@"