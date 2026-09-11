#!/bin/bash
# Deliberately does NOT set DISPLAY or manage Xvfb itself. Orca's own `serve`
# checks whether DISPLAY points at something "verifiably live" and, if not,
# launches its own internal Xvfb — confirmed live: wrapping this in
# `xvfb-run` instead left AppRun never starting (xvfb-run's own readiness
# poll never unblocked in this image), and manually pointing DISPLAY at a
# separately-started Xvfb got rejected by that same liveness check. Leaving
# DISPLAY unset is what the container's own startup message recommends, and
# it's the one path confirmed to reach "Orca server ready" here.
set -e

ARGS=(serve --port 6768)
[ -n "${ORCA_PAIRING_ADDRESS:-}" ] && ARGS+=(--pairing-address "$ORCA_PAIRING_ADDRESS")

exec /opt/squashfs-root/AppRun "${ARGS[@]}"
