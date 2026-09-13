#!/bin/bash
# Alerts (journal + log file) when CPU package temp crosses a danger
# threshold, with a snapshot of top CPU consumers for diagnosis. Also
# reasserts the BMC's Full Speed fan mode if it silently reverted (a BMC
# firmware update/reset reverts to its default "Optimal" mode) - that
# revert is the exact precondition for the 2026-09-13 98C incident this
# watchdog exists to catch.
# Alert-only for temps - no automatic throttling/killing of processes.
set -euo pipefail

WARN_C=90
LOGFILE=/var/log/thermal-watchdog.log
STATEFILE=/run/thermal-watchdog.state
FAN_MODE_FULL_SPEED=01  # Supermicro IPMI: 00=Standard 01=Full Speed 02=Optimal 04=Heavy IO

if command -v ipmitool >/dev/null 2>&1; then
    current_mode=$(ipmitool raw 0x30 0x45 0x00 2>/dev/null | tr -d ' \r\n')
    if [ -n "$current_mode" ] && [ "$current_mode" != "$FAN_MODE_FULL_SPEED" ]; then
        ipmitool raw 0x30 0x45 0x01 "0x$FAN_MODE_FULL_SPEED" >/dev/null 2>&1 || true
        echo "[$(date -Is)] FAN MODE REVERTED (was 0x$current_mode) - reasserted Full Speed" \
            | tee -a "$LOGFILE" | logger -t thermal-watchdog
    fi
fi

max_temp=$(sensors -A 2>/dev/null | grep -oP 'Package id \d+:\s+\+\K[0-9]+' | sort -rn | head -1)
[ -z "$max_temp" ] && exit 0

was_alerted=0
[ -f "$STATEFILE" ] && was_alerted=$(cat "$STATEFILE")

if [ "$max_temp" -ge "$WARN_C" ]; then
    if [ "$was_alerted" -eq 0 ]; then
        {
            echo "[$(date -Is)] THERMAL WARNING: package temp ${max_temp}C >= ${WARN_C}C"
            echo "Top CPU consumers:"
            ps aux --sort=-%cpu | head -6
            echo
        } | tee -a "$LOGFILE" | logger -t thermal-watchdog
        echo 1 > "$STATEFILE"
    fi
else
    if [ "$was_alerted" -eq 1 ]; then
        echo "[$(date -Is)] thermal warning cleared: package temp ${max_temp}C" | tee -a "$LOGFILE" | logger -t thermal-watchdog
    fi
    echo 0 > "$STATEFILE"
fi
