#!/usr/bin/env bash
# Shared helpers for the Steam Deck dev loop. Sourced by the other scripts.
# Configuration comes from the environment only; nothing secret lives in the repository.
#   DECK_HOST  required, e.g. steamdeck.local or an IP address
#   DECK_USER  optional, default "deck"
set -o errexit -o nounset -o pipefail

# Deck lock helpers (definitions only; scripts that touch the Deck state call deck_lock).
# shellcheck source=scripts/deck/lock.sh
source "$(dirname "${BASH_SOURCE[0]}")/lock.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
# Optional git-ignored local file with DECK_HOST / DECK_USER, so agent shells without direnv find the Deck.
if [[ -z "${DECK_HOST:-}" && -f "$REPO_ROOT/.deck.env" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/.deck.env"
fi
DECK_USER="${DECK_USER:-deck}"

if [[ -z "${DECK_HOST:-}" ]]; then
    echo "DECK_HOST is not set (example: export DECK_HOST=steamdeck.local)" >&2
    exit 2
fi

DECK_TARGET="${DECK_USER}@${DECK_HOST}"
# The game process itself: Proton shows a Windows path (S:\common\GarrysMod\bin\win64\gmod.exe),
# the native build runs hl2_linux / hl2_linux64. Wrapper processes (proton, steam.exe) do not match.
export GAME_PROCESS_PATTERN='bin.win(32|64).gmod\.exe|hl2_linux'

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)

# Run a shell snippet on the Deck. The snippet travels on stdin, so the remote command line stays constant.
deck_run() {
    ssh "${SSH_OPTS[@]}" "$DECK_TARGET" 'bash -s' <<<"$*"
}

# Prints "<install type> <garrysmod dir>" for the library that holds app 4000.
deck_detect() {
    ssh "${SSH_OPTS[@]}" "$DECK_TARGET" 'bash -s' <<'REMOTE'
set -o errexit -o nounset -o pipefail
steam_root="$HOME/.local/share/Steam"
vdf="$steam_root/steamapps/libraryfolders.vdf"
lib=""
while read -r path; do
    if [[ -f "$path/steamapps/appmanifest_4000.acf" ]]; then lib="$path"; break; fi
done < <(awk '/"path"/ { gsub(/"/, "", $2); print $2 }' "$vdf")
if [[ -z "$lib" ]]; then echo "Garry's Mod (app 4000) is not installed in any Steam library" >&2; exit 3; fi
game="$lib/steamapps/common/GarrysMod"
if [[ -f "$game/gmod.exe" && -d "$lib/steamapps/compatdata/4000" ]] \
    && awk '/"CompatToolMapping"/{f=1} f && /"4000"/{g=1} g && /"name"/{print; exit}' "$steam_root/config/config.vdf" | grep --quiet proton; then
    kind="proton"
else
    kind="native"
fi
echo "$kind $game/garrysmod"
REMOTE
}

deck_gmod_dir() {
    deck_detect | awk '{ print $2 }'
}
