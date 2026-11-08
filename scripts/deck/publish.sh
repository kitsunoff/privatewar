#!/usr/bin/env bash
# Stage the current working tree and publish one addon using tools installed on the Deck.
set -o errexit -o nounset -o pipefail
usage() {
    echo 'Usage: publish.sh create --addon NAME --icon FILE.jpg' >&2
    echo '       publish.sh update --addon NAME --id ID --changes TEXT [--icon FILE.jpg]' >&2
}
mode="${1:-}"
case "$mode" in create | update) shift ;; *) usage; exit 2 ;; esac
addon=privatewar id= changes= icon=
while (($#)); do
    case "$1" in
        --addon | --id | --changes | --icon)
            [[ $# -ge 2 && -n "$2" ]] || { usage; exit 2; }
            case "$1" in
                --addon) addon="$2" ;; --id) id="$2" ;;
                --changes) changes="$2" ;; --icon) icon="$2" ;;
            esac
            shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[[ "$addon" =~ ^privatewar(-[a-z0-9]+)*$ && "$addon" != privatewar-dev ]] || { echo 'Invalid addon name' >&2; exit 2; }
if [[ "$mode" == create ]]; then
    [[ -n "$icon" && -z "$id" && -z "$changes" ]] || { usage; exit 2; }
else
    [[ "$id" =~ ^[0-9]+$ && -n "$changes" ]] || { usage; exit 2; }
    [[ "$changes" != *$'\n'* && "$changes" != *$'\r'* ]] || { echo 'Changes must be a single line' >&2; exit 2; }
    LC_ALL=C grep -q '^[ -~]*$' <<<"$changes" || { echo 'Changes must use ASCII characters' >&2; exit 2; }
fi
[[ -z "$icon" || -f "$icon" ]] || { echo 'Icon file not found' >&2; exit 2; }

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -f "$REPO_ROOT/addons/$addon/addon.json" ]] || { echo 'Addon not found' >&2; exit 2; }
deck_lock
tmp="$(mktemp -d)"
remote_tmp=
cleanup() {
    if [[ -n "$remote_tmp" ]]; then
        ssh "${SSH_OPTS[@]}" "$DECK_TARGET" 'bash -s' -- "$remote_tmp" <<'REMOTE' || true
case "$1" in /tmp/pw-publish.*) rm -rf -- "$1" ;; esac
REMOTE
    fi
    rm -rf -- "$tmp"
    deck_lock_release
}
trap cleanup EXIT
bash "$REPO_ROOT/scripts/package/build.sh" --output "$tmp/stage"
[[ -d "$tmp/stage/$addon" ]] || { echo 'Addon was not staged' >&2; exit 1; }
if [[ -n "$icon" ]]; then cp "$icon" "$tmp/icon.jpg"; fi
remote_tmp="$(ssh "${SSH_OPTS[@]}" "$DECK_TARGET" 'mktemp -d /tmp/pw-publish.XXXXXXXX')"
[[ "$remote_tmp" =~ ^/tmp/pw-publish\.[a-zA-Z0-9]+$ ]] || { echo 'Invalid remote temporary path' >&2; remote_tmp=; exit 1; }
tar -C "$tmp/stage" -cf "$tmp/addon.tar" "$addon"
rsync --archive --compress --rsh="ssh ${SSH_OPTS[*]}" "$tmp/addon.tar" "$DECK_TARGET:$remote_tmp/"
if [[ -n "$icon" ]]; then
    rsync --archive --rsh="ssh ${SSH_OPTS[*]}" "$tmp/icon.jpg" "$DECK_TARGET:$remote_tmp/"
fi
detected="$(deck_detect)"
game_dir="${detected#* }"
game_dir="${game_dir%/garrysmod}"
# Encode arguments to keep change notes and paths out of remote shell syntax.
encode() { printf 'x'; printf '%s' "$1" | base64 | tr -d '\n'; }
ssh "${SSH_OPTS[@]}" "$DECK_TARGET" 'bash -s' -- "$(encode "$remote_tmp")" "$(encode "$game_dir")" \
    "$(encode "$addon")" "$(encode "$mode")" "$(encode "$id")" "$(encode "$changes")" "$(encode "$icon")" <<'REMOTE'
set -o errexit -o nounset -o pipefail
decode() { printf '%s' "${1#x}" | base64 --decode; }
tmp="$(decode "$1")" game="$(decode "$2")" addon="$(decode "$3")" mode="$(decode "$4")"
id="$(decode "$5")" changes="$(decode "$6")" icon="$(decode "$7")"
tar -xf "$tmp/addon.tar" -C "$tmp"
bin=
for dir in "$game/bin/linux64" "$game/bin/linux32" "$game/bin"; do
    if [[ -x "$dir/gmad" && -x "$dir/gmpublish" ]]; then bin="$dir"; break; fi
done
if [[ -z "$bin" && -x "$game/bin/gmad_linux" && -x "$game/bin/gmpublish_linux" ]]; then
    gmad="$game/bin/gmad_linux" publish="$game/bin/gmpublish_linux" bin="$game/bin"
elif [[ -n "$bin" ]]; then
    gmad="$bin/gmad" publish="$bin/gmpublish"
else
    steam="$HOME/.local/share/Steam"
    proton_name="$(awk '/"CompatToolMapping"/{f=1} f && /"4000"/{g=1} g && /"name"/{sub(/^[^"]*"name"[[:space:]]*"/, ""); sub(/".*/, ""); print; exit}' "$steam/config/config.vdf")"
    if [[ "$proton_name" =~ ^proton_([0-9]+)$ ]]; then proton_name="Proton ${BASH_REMATCH[1]}.0"; fi
    proton="$steam/steamapps/common/$proton_name/proton"
    compat="${game%/common/GarrysMod}/compatdata/4000"
    if [[ ! -f "$proton" || ! -d "$compat" || ! -f "$game/bin/gmad.exe" || ! -f "$game/bin/gmpublish.exe" ]]; then
        echo 'No usable Linux tools or configured Proton tools found.' >&2
        exit 1
    fi
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam" STEAM_COMPAT_DATA_PATH="$compat" SteamAppId=4000
    winpath() { printf 'Z:%s' "${1//\//\\}"; }
    "$proton" run "$game/bin/gmad.exe" create -folder "$(winpath "$tmp/$addon")" -out "$(winpath "$tmp/addon.gma")"
    [[ -s "$tmp/addon.gma" ]] || { echo 'gmad exited without creating an archive; nothing was uploaded.' >&2; exit 1; }
    args=("$mode" -addon "$(winpath "$tmp/addon.gma")")
    if [[ "$mode" == update ]]; then args+=(-id "$id" -changes "$changes"); fi
    if [[ -n "$icon" ]]; then args+=(-icon "$(winpath "$tmp/icon.jpg")"); fi
    "$proton" run "$game/bin/gmpublish.exe" "${args[@]}"
    exit
fi
export LD_LIBRARY_PATH="$bin:$game/bin:${LD_LIBRARY_PATH:-}"
"$gmad" create -folder "$tmp/$addon" -out "$tmp/addon.gma"
[[ -s "$tmp/addon.gma" ]] || { echo 'gmad exited without creating an archive; nothing was uploaded.' >&2; exit 1; }
args=("$mode" -addon "$tmp/addon.gma")
if [[ "$mode" == update ]]; then args+=(-id "$id" -changes "$changes"); fi
if [[ -n "$icon" ]]; then args+=(-icon "$tmp/icon.jpg"); fi
"$publish" "${args[@]}"
REMOTE
