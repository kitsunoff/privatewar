#!/usr/bin/env bash
# Screenshots in one locked run: deploy, map reload, then the steps in order, all while holding the Deck lock, so no
# other agent's deploy or test run can land between the deploy and a screenshot.
# Why a map reload and not pw_reload: the host's client runs clientside Lua from the server's Lua datapack, filled at
# map load. After pw_reload it still runs the old content of changed files and of files deleted since, and it sees a
# new file only one pw_reload later (measured on the Deck, 2026-11-07). pw_reload refreshes the server only; a map
# reload makes the client run exactly the deployed tree.
# Usage: snap.sh [--no-deploy] step [step ...]
#   shot        take a screenshot (shot.sh); its local path is printed
#   wait:<s>    sleep <s> seconds (let a screen open or a reload finish)
#   <line>      any bridge line for cmd.sh, e.g. "client pw_dev_lobby_open", "lua print(1)", "pw_reload"
# In LOBBY the lobby is already open after the reload. "client pw_lobby" toggles it (F1), so it CLOSES the lobby;
# "client pw_dev_lobby_open" only opens a closed lobby and logs its state ("[PW] lobbyprobe ..." in logs.sh).
# Without --no-deploy it first runs deploy.sh, then reloads the current map (changelevel to game.GetMap()) with the
# GLuaTest run skipped (one-shot flag data/privatewar_dev/skip_tests.txt, consumed by the dev addon's pw_testgate.lua)
# and waits until the host's client has loaded ("[PW] testgate: host <name> loaded"; up to PW_SNAP_LOAD_TIMEOUT
# seconds, default 240). The map reload ends a running match: the steps start in LOBBY with the lobby open.
# Example: snap.sh "client pw_dev_lobby_open" wait:3 shot
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # one user of the Deck at a time (lock.sh); nested calls re-enter
here="$(dirname "${BASH_SOURCE[0]}")"

deploy=1
if [[ "${1:-}" == "--no-deploy" ]]; then
    deploy=0
    shift
fi
if [[ $# -eq 0 ]]; then
    echo "usage: snap.sh [--no-deploy] step [step ...]" >&2
    exit 2
fi

# Reloads the current map without the GLuaTest run and waits until the host's client has loaded.
reload_map() {
    local gmod_dir log flag since deadline timeout="${PW_SNAP_LOAD_TIMEOUT:-240}"
    local ready='\[PW\] testgate: host .* loaded'
    gmod_dir="$(deck_gmod_dir)"
    log="$gmod_dir/console.log"
    flag="$gmod_dir/data/privatewar_dev/skip_tests.txt"
    since="$(deck_run "if [ -f '$log' ]; then wc --lines < '$log'; else echo 0; fi")"
    deck_run "mkdir --parents '$(dirname "$flag")' && echo snap > '$flag'"
    "$here/cmd.sh" 'lua game.ConsoleCommand("changelevel " .. game.GetMap() .. "\n")' >/dev/null
    deadline=$((SECONDS + timeout))
    while ((SECONDS < deadline)); do
        sleep 3
        if deck_run "tail --lines=+$((since + 1)) '$log' | grep --quiet --text --extended-regexp '$ready'"; then
            sleep 3 # the lobby opens a moment after the host's first usercmd
            return 0
        fi
    done
    deck_run "rm --force '$flag'"
    echo "[snap] the host's client did not load within ${timeout}s after the map reload (logs.sh --once)" >&2
    exit 1
}

if [[ "$deploy" == 1 ]]; then
    "$here/deploy.sh" >/dev/null
    reload_map
fi

for step in "$@"; do
    case "$step" in
        shot) "$here/shot.sh" ;;
        wait:*) sleep "${step#wait:}" ;;
        *) "$here/cmd.sh" "$step" >/dev/null ;;
    esac
done
