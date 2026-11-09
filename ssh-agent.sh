#!/usr/bin/env bash
#
# dojo SSH agent setup — ensures a running ssh-agent with the GitHub key,
# using a stable socket path so all shells share the same agent.
#
# Designed to be SOURCED from the dojo profile block, not executed:
# first source starts an agent and loads the key; later sources are a
# no-op. Uses return (never exit) so nothing here can kill the calling
# shell, and no shell options are changed.
#

AGENT_SOCK="$HOME/.ssh/agent-sock"

# Minimal environments without ssh: nothing to do.
command -v ssh-add >/dev/null 2>&1 || return 0
mkdir -p "$(dirname "$AGENT_SOCK")"

# Serialise: a burst of parallel shells (agents running ssh in a loop) used to
# race here, each one deleting the socket and starting its own agent — the
# orphans piled up into thousands of ssh-agent processes.
exec {_dojo_agent_lock}>"$AGENT_SOCK.lock"
flock -w 5 "$_dojo_agent_lock" 2>/dev/null

# ssh-add -l exits 2 only when no agent answers; 1 just means "no keys yet".
SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then
  rm -f "$AGENT_SOCK"
  eval "$(ssh-agent -s -a "$AGENT_SOCK")" >/dev/null 2>&1
fi
export SSH_AUTH_SOCK="$AGENT_SOCK"

# Add the GitHub Ed25519 key if the agent has none.
# Check the sentinel user path first (dojo is typically deployed for sentinel),
# then fall back to the current user's home.
if ! ssh-add -l >/dev/null 2>&1; then
  for keypath in "/home/sentinel/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519"; do
    if [ -f "$keypath" ]; then
      ssh-add "$keypath" >/dev/null 2>&1 </dev/null
      break
    fi
  done
fi

exec {_dojo_agent_lock}>&-
unset _dojo_agent_lock
