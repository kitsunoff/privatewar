#!/usr/bin/env bash
# Start Garry's Mod on the Deck as a listen server with dev arguments.
# Environment overrides: PW_GAMEMODE (default privatewar), PW_MAP (default gm_construct),
# PW_MAXPLAYERS (default 12), PW_EXTRA_ARGS (appended as is).
# Usage: run.sh [--restart]
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # one user of the Deck at a time (lock.sh); nested calls re-enter

gamemode="${PW_GAMEMODE:-privatewar}"
map="${PW_MAP:-gm_construct}"
maxplayers="${PW_MAXPLAYERS:-12}"
extra="${PW_EXTRA_ARGS:-}"

if deck_run "pgrep --full '$GAME_PROCESS_PATTERN' >/dev/null"; then
    if [[ "${1:-}" == "--restart" ]]; then
        "$(dirname "${BASH_SOURCE[0]}")/stop.sh"
        sleep 5
    else
        echo "[run] Garry's Mod is already running (use --restart)" >&2
        exit 1
    fi
fi

# -condebug appends to console.log across runs; keep one previous log and start each run clean.
log="$(deck_gmod_dir)/console.log"
deck_run "if [ -f '$log' ]; then mv --force '$log' '$log.prev'; fi"

args="-condebug +maxplayers $maxplayers +gamemode $gamemode +map $map $extra"
# "steam -applaunch" forwards the request to the running Steam client and returns. It must run in the
# foreground of the SSH session (a detached background call was lost) with the graphical session env.
deck_run "DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/\$(id --user) timeout 30 steam -applaunch 4000 $args >/dev/null 2>&1"
echo "[run] requested launch: $args"
