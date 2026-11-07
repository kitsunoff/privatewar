#!/usr/bin/env bash
# Copy the addons of the repository (addons/<name>/) to the Deck: the gamemode, the integration addons and the dev-only
# bridge addon. Only changed files are sent; files removed from the repository are removed from our own addon folders
# too (--delete is scoped to one named addon folder at a time and never reaches other addons).
# Deployed folder names: addons/privatewar -> privatewar, addons/<integration> -> <integration>, and the dev addon
# addons/privatewar-dev -> privatewar_dev (the name it had before the repository layout change, so no stale second copy
# of the bridge is left behind on the Deck).
# cfg/*.cfg is copied into the game's cfg folder without --delete.
# Usage: deploy.sh [--no-dev]
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # one user of the Deck at a time (lock.sh); nested calls re-enter

with_dev=1
if [[ "${1:-}" == "--no-dev" ]]; then with_dev=0; fi

gmod_dir="$(deck_gmod_dir)"
addons="$gmod_dir/addons"

rsync_to() {
    local src="$1" dst="$2"
    rsync --archive --compress --delete --itemize-changes --rsh="ssh ${SSH_OPTS[*]}" \
        --exclude='.DS_Store' "$src" "$DECK_TARGET:$dst"
}

# Main addon: the whole gamemode addon folder (gamemodes/, lua/, addon.json, content folders when they exist).
rsync_to "$REPO_ROOT/addons/privatewar" "$addons/"

# Integration addons (addons/<name>/ other than the gamemode and the dev addon, one per weapon base): each is its own
# addon folder, as on the Workshop. GMod mounts addon folders only at startup, so a newly deployed one is loaded after
# the next game start.
for integration in "$REPO_ROOT"/addons/*/; do
    name="$(basename "$integration")"
    case "$name" in privatewar | privatewar-dev) continue ;; esac
    if ! deck_run "[ -d '$addons/$name' ]"; then
        echo "[deploy] new addon $name: GMod loads it after the next game start" >&2
    fi
    rsync_to "${integration%/}" "$addons/"
done

# Our cfg files go into the game's own cfg folder. Only the files of the repository's cfg/ are sent and nothing is
# deleted there (no --delete): the folder holds the game's and the user's files too.
if [[ -d "$REPO_ROOT/cfg" ]]; then
    deck_run "mkdir --parents '$gmod_dir/cfg'"
    for cfg_file in "$REPO_ROOT"/cfg/*.cfg; do
        [[ -f "$cfg_file" ]] || continue
        rsync --archive --compress --itemize-changes --rsh="ssh ${SSH_OPTS[*]}" \
            "$cfg_file" "$DECK_TARGET:$gmod_dir/cfg/"
    done
fi

# Dev-only addon with the command bridge; never shipped to the Workshop.
if [[ "$with_dev" == 1 ]]; then
    rsync_to "$REPO_ROOT/addons/privatewar-dev/" "$addons/privatewar_dev/"
fi

echo "[deploy] done -> $DECK_TARGET:$addons"
