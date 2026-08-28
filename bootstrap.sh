#!/usr/bin/env bash
#
# bootstrap.sh — idempotent wire-up of the whole dojo optimization stack on
# a machine that already has the tools installed (does NOT install binary
# tools; use `dojo install` or the menu's Install Tools for that).
#
# Kept as its own entry point so `dojo update` and tests/CI have a stable
# target. All the real work lives in lib.sh's run_wire_up() / wire_up_*().
#
#   git clone git@github.com:Cyb3rRon1n/dojo.git ~/dojo && ~/dojo/bootstrap.sh
#   git pull && ./bootstrap.sh        # later updates
#
# Safe to re-run: existing files are backed up to .bak before replacement,
# and every step is a no-op when already in place.
#
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
DOJO_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# shellcheck disable=SC1091
source "$DOJO_DIR/lib.sh"

run_wire_up
