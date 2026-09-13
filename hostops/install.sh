#!/bin/bash
# Installs the thermal watchdog on a bare-metal host with IPMI (tested on a
# Supermicro X11DPL-i). Run with sudo from this directory:
#   sudo ./install.sh
# Idempotent - safe to re-run after pulling updates.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$(id -u)" -ne 0 ]; then
    echo "run with sudo" >&2
    exit 1
fi

command -v ipmitool >/dev/null 2>&1 || apt-get install -y ipmitool
command -v sensors >/dev/null 2>&1 || apt-get install -y lm-sensors

# Full Speed once at install time - the watchdog itself reasserts this if a
# BMC reset ever reverts it (see thermal-watchdog.sh).
ipmitool raw 0x30 0x45 0x01 0x01 || echo "WARNING: not a Supermicro IPMI board, or fan mode set failed - skipping"

install -m 0755 thermal-watchdog.sh /usr/local/bin/thermal-watchdog.sh
install -m 0644 thermal-watchdog.service /etc/systemd/system/thermal-watchdog.service
install -m 0644 thermal-watchdog.timer /etc/systemd/system/thermal-watchdog.timer
systemctl daemon-reload
systemctl enable --now thermal-watchdog.timer
systemctl status thermal-watchdog.timer --no-pager
