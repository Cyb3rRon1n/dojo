#!/usr/bin/env python3
#
# dojo tokens — read token-optimizer's live sqlite state and print real token
# usage, cache "refresh", and context-fill threshold status. Powers both
# `dojo tokens` and the PS1 status line (--one-line). Never errors: no data or
# a locked db prints nothing.
#
import glob
import os
import sqlite3
import sys

DATA_DIRS = [
    os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "token-optimizer"),
]

GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"


def fmt(n):
    n = int(n or 0)
    if n >= 1_000_000:
        return f"{n / 1e6:.2f}M"
    if n >= 1_000:
        return f"{n / 1e3:.1f}k"
    return str(n)


def grade(health):
    if health >= 90:
        return "S"
    if health >= 80:
        return "A"
    if health >= 70:
        return "B"
    if health >= 55:
        return "C"
    if health >= 40:
        return "D"
    return "F"


def band(health):
    if health >= 80:
        return "Good"
    if health >= 60:
        return "Fair"
    if health >= 40:
        return "Needs Work"
    return "Poor"


def band_color(health):
    return GREEN if health >= 80 else YELLOW if health >= 60 else RED


def degradation(fill):
    if fill < 0.5:
        return "Safe"
    if fill < 0.7:
        return "Moderate"
    if fill < 0.8:
        return "Warning"
    return "Danger"


def find_data_root():
    for d in DATA_DIRS:
        if os.path.isdir(d):
            return d
    return None


def find_live(root):
    best = None
    for db in glob.glob(os.path.join(root, "sessions", "*", "ses_*.db")):
        try:
            c = sqlite3.connect(db, timeout=0.25)
            row = c.execute(
                "SELECT updated_at, resource_health, session_efficiency, fill_pct, tool_calls, compactions "
                "FROM quality_cache ORDER BY updated_at DESC LIMIT 1"
            ).fetchone()
            mode = c.execute("SELECT value FROM session_meta WHERE key='current_mode'").fetchone()
            c.close()
        except sqlite3.Error:
            continue
        if not row:
            continue
        entry = {
            "db": db,
            "health": row[1],
            "efficiency": row[2],
            "fill_pct": row[3],
            "tool_calls": row[4],
            "compactions": row[5],
            "mode": mode[0] if mode else None,
        }
        if best is None or row[0] > best[0]:
            best = (row[0], entry)
    return best[1] if best else None


def latest_log(root):
    db = os.path.join(root, "trends.db")
    if not os.path.isfile(db):
        return None
    try:
        c = sqlite3.connect(db, timeout=0.25)
        row = c.execute(
            "SELECT model, tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, cost_usd, "
            "duration_seconds FROM session_log ORDER BY created_at DESC, id DESC LIMIT 1"
        ).fetchone()
        c.close()
    except sqlite3.Error:
        return None
    if not row:
        return None
    return {
        "model": row[0],
        "in": row[1],
        "out": row[2],
        "cache_read": row[3],
        "cache_write": row[4],
        "cost": row[5],
        "duration": row[6],
    }


def one_line(q, log):
    parts = []
    if log and (log["in"] or log["out"]):
        parts.append(f"{fmt(log['in'])}/{fmt(log['out'])}")
        if log["cache_read"] or log["cache_write"]:
            parts.append(f"↻{fmt(log['cache_read'])}")
    if q:
        if q["fill_pct"] > 0:
            parts.append(f"fill {q['fill_pct'] * 100:.0f}% ({degradation(q['fill_pct'])})")
        else:
            parts.append(f"health {q['health']:.0f}/100")
        parts.append(grade(q["health"]))
    if not parts:
        return ""
    health = q["health"] if q else 80
    return f"{band_color(health)}{' · '.join(parts)}{RESET}"


def report(q, log):
    lines = []
    if log:
        lines.append(f"usage:    {log['in']:,} in · {log['out']:,} out · ${log['cost']:.4f}")
        lines.append(
            f"refresh:  ↻{log['cache_read']:,} cache read · {log['cache_write']:,} cache write"
        )
    if q:
        f = q["fill_pct"]
        fill = f"{f * 100:.0f}% ({degradation(f)})" if f > 0 else "unknown (no window for model)"
        lines.append(
            f"threshold: context fill {fill} · health {q['health']:.0f}/100 ({grade(q['health'])}, {band(q['health'])})"
            f" · efficiency {q['efficiency']:.0f}/100"
        )
        meta = []
        if q["mode"]:
            meta.append(q["mode"])
        meta.append(f"{q['tool_calls']} tool calls")
        if q["compactions"]:
            meta.append(f"{q['compactions']} compactions")
        lines.append("session:   " + ", ".join(meta))
    if log and log["model"]:
        lines.append(f"model:     {log['model']}")
    return "\n".join(lines)


def main():
    root = find_data_root()
    if not root:
        return 0
    q = find_live(root)
    log = latest_log(root)
    if not q and not log:
        return 0
    if "--one-line" in sys.argv[1:]:
        sys.stdout.write(one_line(q, log))
        return 0
    print(report(q, log))
    return 0


if __name__ == "__main__":
    sys.exit(main())