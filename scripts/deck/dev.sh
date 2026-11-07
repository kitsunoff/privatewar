#!/usr/bin/env bash
# One-shot dev cycle: deploy changed files, ask the game to reload, then follow filtered logs.
# PW_RELOAD_CMD overrides the reload command (default pw_reload).
# pw_reload refreshes the server only: the host's client keeps running the clientside Lua of the last map load (old
# content of changed files, deleted files; a new file shows up one pw_reload later). To see client code on screen use
# snap.sh, which reloads the map.
# The Deck lock is held for deploy + reload only; following the logs is a read and runs without the lock.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
here="$(dirname "${BASH_SOURCE[0]}")"
deck_lock

"$here/deploy.sh"
"$here/cmd.sh" "${PW_RELOAD_CMD:-pw_reload}"
echo "[dev] the host's client still runs the clientside Lua of the last map load; snap.sh reloads the map" >&2
deck_lock_release
exec "$here/logs.sh"
