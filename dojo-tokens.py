#!/usr/bin/env python3
#
# dojo tokens — read token-optimizer's live state and print real token usage,
# cache "refresh", and context-fill threshold status. --one-line emits a
# compact single line. Never errors: no data or a locked db prints nothing.
#
# Data sources, all read defensively (any may be absent):
#   * opencode plugin (sqlite):  $TOKEN_OPTIMIZER_DATA_DIR or
#     ~/.local/share/{,opencode/}token-optimizer/{trends.db,sessions/*/ses_*.db}
#   * claude/codex plugins (json): ~/.claude/token-optimizer/ and
#     ~/.codex/token-optimizer/ (quality-cache-*.json, live-fill.json)
#
import glob
import json
import os
import sqlite3
import sys

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


def norm_fill(f):
    if f is None:
        return None
    f = float(f)
    return f / 100.0 if f > 1 else f


def candidate_roots():
    # Explicit override wins verbatim, matching the plugin's own precedence.
    env = os.environ.get("TOKEN_OPTIMIZER_DATA_DIR")
    if env:
        return [env] if os.path.isdir(env) else []
    home = os.path.expanduser("~")
    xdg = os.environ.get("XDG_DATA_HOME", os.path.join(home, ".local", "share"))
    roots = [
        os.path.join(xdg, "token-optimizer"),
        os.path.join(home, ".local", "share", "opencode", "token-optimizer"),
        os.path.join(home, ".claude", "token-optimizer"),
        os.path.join(home, ".codex", "token-optimizer"),
    ]
    return [r for r in dict.fromkeys(roots) if os.path.isdir(r)]


def collect_sqlite(root):
    q = None
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
            "stamp": row[0],
            "health": row[1],
            "efficiency": row[2],
            "fill_pct": norm_fill(row[3]),
            "tool_calls": row[4],
            "compactions": row[5],
            "mode": mode[0] if mode else None,
        }
        if q is None or entry["stamp"] > q["stamp"]:
            q = entry
    log = None
    db = os.path.join(root, "trends.db")
    if os.path.isfile(db):
        try:
            c = sqlite3.connect(db, timeout=0.25)
            row = c.execute(
                "SELECT model, tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, "
                "cost_usd, duration_seconds, created_at "
                "FROM session_log ORDER BY created_at DESC, id DESC LIMIT 1"
            ).fetchone()
            c.close()
            if row:
                log = {
                    "model": row[0],
                    "in": row[1],
                    "out": row[2],
                    "cache_read": row[3],
                    "cache_write": row[4],
                    "cost": row[5],
                    "duration": row[6],
                    "stamp": row[7] or 0,
                }
        except sqlite3.Error:
            pass
    return q, log


def collect_json(root):
    q = None
    for f in glob.glob(os.path.join(root, "quality-cache-*.json")):
        try:
            d = json.load(open(f))
            stamp = os.path.getmtime(f)
        except (OSError, ValueError):
            continue
        entry = {
            "stamp": stamp,
            "health": d.get("resource_health") or d.get("score"),
            "efficiency": d.get("session_efficiency"),
            "fill_pct": norm_fill(d.get("fill_pct") or (d.get("fill_warning") or {}).get("fill_pct")),
            "tool_calls": d.get("tool_calls"),
            "compactions": d.get("compactions"),
            "mode": None,
        }
        if q is None or stamp > q["stamp"]:
            q = entry
    if q:
        try:
            lf = json.load(open(os.path.join(root, "live-fill.json")))
            used = lf.get("used_percentage")
            if isinstance(used, (int, float)):
                q["fill_pct"] = norm_fill(used)
                ts = lf.get("timestamp") or 0
                if ts > 1e12:  # JS Date.now() is milliseconds; everything else is seconds
                    ts /= 1000
                q["stamp"] = max(q["stamp"], ts)
        except (OSError, ValueError):
            pass
    return q, None


def gather():
    q_best, log_best = None, None
    for root in candidate_roots():
        qs, ls = collect_sqlite(root)
        qj, _ = collect_json(root)
        for cand in (qs, qj):
            if cand and (q_best is None or cand["stamp"] > q_best["stamp"]):
                q_best = cand
        if ls and (log_best is None or ls["stamp"] > log_best["stamp"]):
            log_best = ls
    return q_best, log_best


def one_line(q, log):
    parts = []
    if log and (log["in"] or log["out"]):
        parts.append(f"{fmt(log['in'])}/{fmt(log['out'])}")
        if log["cache_read"] or log["cache_write"]:
            parts.append(f"↻{fmt(log['cache_read'])}")
    if q:
        if q["fill_pct"]:
            parts.append(f"fill {q['fill_pct'] * 100:.0f}% ({degradation(q['fill_pct'])})")
        elif q["health"]:
            parts.append(f"health {q['health']:.0f}/100")
        if q["health"]:
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
        if q["health"]:
            fill = f"{f * 100:.0f}% ({degradation(f)})" if f else "unknown (no window for model)"
            lines.append(
                f"threshold: context fill {fill} · health {q['health']:.0f}/100 ({grade(q['health'])}, {band(q['health'])})"
                + (f" · efficiency {q['efficiency']:.0f}/100" if q["efficiency"] else "")
            )
        elif f:
            lines.append(f"threshold: context fill {f * 100:.0f}% ({degradation(f)})")
        meta = []
        if q["mode"]:
            meta.append(q["mode"])
        if q["tool_calls"]:
            meta.append(f"{q['tool_calls']} tool calls")
        if q["compactions"]:
            meta.append(f"{q['compactions']} compactions")
        if meta:
            lines.append("session:   " + ", ".join(meta))
    if log and log["model"]:
        lines.append(f"model:     {log['model']}")
    return "\n".join(lines)


def main():
    q, log = gather()
    if not q and not log:
        return 0
    if "--one-line" in sys.argv[1:]:
        sys.stdout.write(one_line(q, log))
        return 0
    print(report(q, log))
    return 0


if __name__ == "__main__":
    sys.exit(main())