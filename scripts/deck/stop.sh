#!/usr/bin/env bash
# Stop Garry's Mod on the Deck.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # stopping the game kills another agent's run: take the lock like the others

if deck_run "pkill --signal TERM --full '$GAME_PROCESS_PATTERN'"; then
    echo "[stop] sent TERM to Garry's Mod"
else
    echo "[stop] Garry's Mod is not running"
fi
