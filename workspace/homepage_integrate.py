#!/usr/bin/env python3
"""
Add a "Workspace (dojo)" tile to a co-located Vulcan install's Homepage
dashboard, so the browser IDE shows up as a click-through tile instead of a
URL you have to remember. Optional, one-shot — run it after `docker compose
up`, and again any time the URL changes.

Mirrors anvil/installer/vulcan_integration.py's merge_into_vulcan_homepage()
exactly: same tile shape ({name: {href, icon, description}}), same
write-once respect for Vulcan's own groups (only this script's own named
group is ever touched), same insert-before-"Guides" placement. Kept as a
plain standalone script rather than a dojo CLI subcommand — this is a single
fixed tile, not a per-hardware generated set, so there's no config to drive
an installer flow with.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

GROUP_NAME = "Workspace (dojo)"
TILE_NAME = "Workspace"


def find_vulcan_stack(search_paths: list[Path] | None = None) -> Path | None:
    if search_paths is None:
        cwd = Path.cwd().resolve()
        search_paths = [
            cwd.parent.parent / "vulcan" / "stack",  # run from dojo/workspace/
            cwd.parent / "vulcan" / "stack",
            cwd / "vulcan" / "stack",
        ]
    for path in search_paths:
        if (path / ".vulcan-state.json").exists():
            return path
    return None


def stats_widget(stats_url: str) -> dict:
    # dojo-tokens.py --serve's flat JSON (see its as_json()) - a fixed set of
    # scalars, so "list" display (mappings is an array), not "dynamic-list"
    # (that's for an array of similar-shaped records, like Recently Added).
    return {
        "type": "customapi",
        "url": stats_url,
        "refreshInterval": 60000,
        "display": "list",
        "mappings": [
            {"field": "health", "label": "Health", "format": "number", "suffix": "/100"},
            {"field": "fill_pct", "label": "Ctx Fill", "format": "number", "suffix": "%"},
            {"field": "compactions", "label": "Compactions", "format": "number"},
            {"field": "five_hour_pct", "label": "5h Limit", "format": "number", "suffix": "%"},
            {"field": "five_hour_reset", "label": "5h Resets", "format": "text"},
            {"field": "seven_day_pct", "label": "7d Limit", "format": "number", "suffix": "%"},
        ],
    }


def merge_tile(services_yaml_path: Path, url: str, ping: str | None, stats_url: str | None) -> None:
    groups = yaml.safe_load(services_yaml_path.read_text()) or []
    groups = [g for g in groups if GROUP_NAME not in g]

    tile_body = {"href": url, "icon": "code-server.png", "description": "AI-tooled coding workspace"}
    # Pings the container directly over the docker network rather than the
    # public URL - real container status, no Traefik/Authelia hop in the way.
    if ping:
        tile_body["ping"] = ping
    if stats_url:
        tile_body["widget"] = stats_widget(stats_url)
    tile = {TILE_NAME: tile_body}
    insert_at = next((i for i, g in enumerate(groups) if "Guides" in g), len(groups))
    groups.insert(insert_at, {GROUP_NAME: [tile]})

    services_yaml_path.write_text(yaml.safe_dump(groups, sort_keys=False))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:8443", help="workspace URL (default: http://localhost:8443)")
    parser.add_argument(
        "--ping",
        default="http://dojo-workspace-workspace-1:8080",
        help="internal address Homepage's status dot checks (default: the container's own compose-assigned "
        "name:port — override if you renamed the compose project/service, or pass '' to omit the status check)",
    )
    parser.add_argument(
        "--stats-url",
        default="http://dojo-workspace-workspace-1:8799",
        help="dojo-tokens.py --serve endpoint for the token-usage/quality widget (same container, port 8799 - "
        "see provision.sh); pass --stats-url '' to omit the widget entirely",
    )
    parser.add_argument("--vulcan-dir", type=Path, help="path to Vulcan's stack/ dir (auto-detected if omitted)")
    args = parser.parse_args()

    vulcan_dir = args.vulcan_dir or find_vulcan_stack()
    if vulcan_dir is None:
        print("[dojo-workspace] no co-located Vulcan stack found (looked for a sibling vulcan/stack "
              "with .vulcan-state.json) — pass --vulcan-dir, or add the tile to your dashboard by hand.",
              file=sys.stderr)
        return 1

    services_yaml_path = vulcan_dir / "config" / "homepage" / "services.yaml"
    if not services_yaml_path.exists():
        print(f"[dojo-workspace] Vulcan found at {vulcan_dir} but Homepage isn't enabled there "
              f"({services_yaml_path} doesn't exist) — enable it in Vulcan first.", file=sys.stderr)
        return 1

    merge_tile(services_yaml_path, args.url, args.ping or None, args.stats_url or None)
    print(f"[dojo-workspace] added '{TILE_NAME}' -> {args.url} to {services_yaml_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
