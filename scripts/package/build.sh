#!/usr/bin/env bash
# Local Workshop build (T-10.2): stages addon trees into a directory (default dist/) and, when gmad is
# on PATH, packs each tree into a .gma. Never uploads anything; publishing is a manual step.
# Usage: build.sh [--output DIR]
set -o errexit -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/scripts/package"
output="$root/dist"

while (($# > 0)); do
    case "$1" in
        --output)
            output="${2:?--output needs a directory}"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

for tool in rsync jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool is not on PATH; run through 'nix develop --command ...'" >&2
        exit 2
    fi
done

# Copies only Lua sources and plain-text gamemode manifests; dotfiles are skipped at copy time.
stage() {
    local from="$1" to="$2"
    mkdir --parents "$to"
    rsync --archive --prune-empty-dirs \
        --exclude='.*' \
        --include='*/' --include='*.lua' --include='*.txt' --exclude='*' \
        "$from/" "$to/"
}

# Licence and notices go into every staged addon. gmad's whitelist rejects files in the addon root and Markdown
# anywhere, so they ship as plain text under data_static/<addon>/ (whitelisted as data_static/*.txt).
notices() {
    local to="$1" name="$2"
    mkdir --parents "$to/data_static/$name"
    cp "$root/LICENSE" "$to/data_static/$name/LICENSE.txt"
    cp "$root/THIRD_PARTY_NOTICES.md" "$to/data_static/$name/THIRD_PARTY_NOTICES.txt"
}

# Each addon directory is rebuilt from scratch below; nothing else in the output is touched.
mkdir --parents "$output"
output="$(cd "$output" && pwd)"
staged=()

# Gamemode addon (addons/privatewar/): its gamemodes/ and lua/privatewar/ plus its addon.json. lua/tests and
# lua/privatewar_fixtures are never copied because only lua/privatewar is a source; the dev addon
# (addons/privatewar-dev/) is not a source at all.
src="$root/addons/privatewar"
gm="$output/privatewar"
rm -rf "$gm"
stage "$src/gamemodes" "$gm/gamemodes"
cp "$src/gamemodes/privatewar/logo.png" "$src/gamemodes/privatewar/icon24.png" "$gm/gamemodes/privatewar/"
stage "$src/lua/privatewar" "$gm/lua/privatewar"
cp "$src/addon.json" "$gm/addon.json"
notices "$gm" privatewar
bash "$here/verify.sh" "$gm" gamemode
staged+=("$gm")

# Integration addons: every other addons/<name>/ except the dev addon, each with its own addon.json, copied under the
# same filter.
integrations=0
for dir in "$root"/addons/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    case "$name" in privatewar | privatewar-dev) continue ;; esac
    integrations=$((integrations + 1))
    if [[ ! -f "$dir/addon.json" ]]; then
        echo "integration $name has no addon.json" >&2
        exit 1
    fi
    rm -rf "${output:?}/$name"
    stage "$dir" "$output/$name"
    cp "$dir/addon.json" "$output/$name/addon.json"
    notices "$output/$name" "$name"
    bash "$here/verify.sh" "$output/$name" integration
    staged+=("$output/$name")
done
if ((integrations == 0)); then
    echo "[package] no integration addons under addons/ to stage"
fi

if command -v gmad >/dev/null 2>&1; then
    for tree in "${staged[@]}"; do
        gmad create -folder "$tree" -out "$tree.gma"
    done
else
    echo "[package] gmad is not available: staged trees only, no .gma files (see docs/packaging.md)"
fi

echo "[package] staged ${#staged[@]} addon(s) in ${output}"
