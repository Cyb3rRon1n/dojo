#!/usr/bin/env bash
#
# dojo SSH agent setup — ensures a running ssh-agent with the GitHub key,
# using a stable socket path so all shells share the same agent.
#
# On first source: starts ssh-agent if needed and loads the key.
# On subsequent sources: no-op if agent already running with key loaded.
#
set -euo pipefail

AGENT_SOCK="$HOME/.ssh/agent-sock"

# If the agent is already running with a key loaded, just ensure env is exported
if [ -S "$AGENT_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
  export SSH_AUTH_SOCK="$AGENT_SOCK"
  exit 0
fi

# Clean stale socket and start fresh agent
rm -f "$AGENT_SOCK"
eval "$(ssh-agent -s -a "$AGENT_SOCK")" >/dev/null 2>&1

# Add the GitHub Ed25519 key if present at the expected location(s).
# Check the sentinel user path first (dojo is typically deployed for sentinel),
# then fall back to the current user's home.
for keypath in "/home/sentinel/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519"; do
  if [ -f "$keypath" ]; then
    ssh-add "$keypath" >/dev/null 2>&1
    break
  fi
done

export SSH_AUTH_SOCK="$AGENT_SOCK"