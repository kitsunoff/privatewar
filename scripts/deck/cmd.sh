#!/usr/bin/env bash
# Send lines to the running game through the dev bridge (addon privatewar_dev).
# Takes no Deck lock and never waits, but refuses (exit 75, "[deck] cmd.sh refused: the Deck is locked by ...") while
# another agent holds the lock: a command sent in the middle of their test run would break it. Allowed when the lock
# is free or held with this process tree's own token (inside cp1.sh / dev.sh). PW_DECK_LOCK=0 disables the check.
# Usage: cmd.sh "pw_reload" ["map gm_flatgrass" ...]   one line per argument
# Prefixes understood by the bridge:
#   lua <code>     run Lua on the server (GMod blocks lua_run and echo from Lua)
#   client <cmd>   run a console command on the host's client, e.g. "client jpeg" for a screenshot
#   anything else  server console command
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -eq 0 ]]; then
    echo "usage: cmd.sh <command> [command ...]" >&2
    exit 2
fi

deck_lock_guard

dir="$(deck_gmod_dir)/data/privatewar_dev"
# Commands travel base64-encoded so quoting inside them cannot break the remote shell.
encoded="$(printf '%s\n' "$@" | base64)"
deck_run "mkdir --parents '$dir' && printf '%s' '$encoded' | base64 --decode >> '$dir/cmd.txt'"
echo "[cmd] queued: $*"
