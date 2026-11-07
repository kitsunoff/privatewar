#!/usr/bin/env bash
# Take a screenshot on the Deck (host client "jpeg") and copy it to the Mac.
# Usage: shot.sh [output dir]   (default: <repo>/.deck-shots, git-ignored). Prints the local file path.
# Takes the Deck lock (re-entrant): another agent's deploy must not land between a caller's deploy and the shot.
# For deploy + reload + console commands + shots in one locked run use snap.sh.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # one user of the Deck at a time (lock.sh); nested calls re-enter

out_dir="${1:-$REPO_ROOT/.deck-shots}"
shots="$(deck_gmod_dir)/screenshots"
before="$(deck_run "ls -t '$shots' 2>/dev/null | head --lines=1")"

"$(dirname "${BASH_SOURCE[0]}")/cmd.sh" "client jpeg" >/dev/null

newest=""
for _ in $(seq 1 30); do
    newest="$(deck_run "ls -t '$shots' 2>/dev/null | head --lines=1")"
    if [[ -n "$newest" && "$newest" != "$before" ]]; then break; fi
    sleep 1
done
if [[ -z "$newest" || "$newest" == "$before" ]]; then
    echo "[shot] no new screenshot appeared (is the game running with the dev bridge?)" >&2
    exit 1
fi

mkdir -p "$out_dir"
scp -q "${SSH_OPTS[@]}" "$DECK_TARGET:$shots/$newest" "$out_dir/$newest"
echo "$out_dir/$newest"
