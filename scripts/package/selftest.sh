#!/usr/bin/env bash
# Packaging self-test (T-10.2): builds into a temp dir, asserts the exclusions hold, then proves
# that verify.sh rejects each kind of forbidden file.
set -o errexit -o nounset -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp --directory)"
trap 'rm -rf "$tmp"' EXIT
failures=0

check() {
    local label="$1"
    shift
    if "$@"; then echo "ok   $label"; else echo "FAIL $label" >&2; failures=$((failures + 1)); fi
}

bash "$here/build.sh" --output "$tmp/dist" >/dev/null
gm="$tmp/dist/privatewar"

absent() { [[ ! -e "$gm/$1" ]]; }
present() { [[ -e "$gm/$1" ]]; }
no_dotfiles() { [[ -z "$(find "$gm" -name '.*' -not -path "$gm")" ]]; }
check "lua/tests excluded" absent lua/tests
check "lua/privatewar_fixtures excluded" absent lua/privatewar_fixtures
check "dev addon excluded" absent lua/autorun/server/pw_devbridge.lua
check "dummy mode excluded" absent lua/privatewar/modes/pw_dummy.lua
check "dev kit screen excluded" absent lua/privatewar/screens/dev_kit.lua
check "no dotfiles" no_dotfiles
check "addon.json present" present addon.json
check "gamemode manifest present" present gamemodes/privatewar/privatewar.txt
check "types shipped" present lua/privatewar/types
check "licence shipped" present data_static/privatewar/LICENSE.txt
check "third-party notices shipped" present data_static/privatewar/THIRD_PARTY_NOTICES.txt
licence_is_gpl() { grep --quiet 'GNU GENERAL PUBLIC LICENSE' "$gm/data_static/privatewar/LICENSE.txt"; }
check "licence is the GPL text" licence_is_gpl

# Every integration addon (addons/<name>/ except the gamemode and the dev addon) is staged as its own addon with its
# Lua, addon.json and licence files only; the dev addon is never staged.
root="$(cd "$here/../.." && pwd)"
check "dev addon not staged" test ! -e "$tmp/dist/privatewar-dev"
for dir in "$root"/addons/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    case "$name" in privatewar | privatewar-dev) continue ;; esac
    staged_dir="$tmp/dist/$name"
    integration_lua() { [[ -n "$(find "$staged_dir/lua" -name '*.lua' 2>/dev/null)" ]]; }
    integration_tests_absent() { [[ ! -e "$staged_dir/lua/tests" ]]; }
    check "integration $name staged" test -d "$staged_dir"
    check "integration $name addon.json present" test -f "$staged_dir/addon.json"
    check "integration $name ships Lua" integration_lua
    check "integration $name lua/tests excluded" integration_tests_absent
    check "integration $name licence shipped" test -s "$staged_dir/data_static/$name/LICENSE.txt"
    check "integration $name third-party notices shipped" test -s "$staged_dir/data_static/$name/THIRD_PARTY_NOTICES.txt"
done

# verify.sh must reject each planted violation.
rejects() {
    local plant="$1" copy="$tmp/copy/privatewar"
    rm -rf "$tmp/copy"
    mkdir --parents "$tmp/copy"
    cp -R "$gm" "$copy"
    eval "$plant"
    ! bash "$here/verify.sh" "$copy" gamemode >/dev/null 2>&1
}
check "rejects lua/tests" rejects 'mkdir -p "$copy/lua/tests" && touch "$copy/lua/tests/a.lua"'
check "rejects fixtures" rejects 'mkdir -p "$copy/lua/privatewar_fixtures" && touch "$copy/lua/privatewar_fixtures/a.lua"'
check "rejects devbridge" rejects 'mkdir -p "$copy/lua/autorun/server" && touch "$copy/lua/autorun/server/pw_devbridge.lua"'
check "rejects .deck.env" rejects 'touch "$copy/.deck.env"'
check "rejects .DS_Store" rejects 'touch "$copy/lua/.DS_Store"'
check "rejects markdown" rejects 'touch "$copy/README.md"'
check "rejects missing addon.json" rejects 'rm "$copy/addon.json"'
check "rejects missing licence" rejects 'rm "$copy/data_static/privatewar/LICENSE.txt"'
check "rejects missing notices" rejects 'rm "$copy/data_static/privatewar/THIRD_PARTY_NOTICES.txt"'
check "rejects licence in the addon root" rejects 'touch "$copy/LICENSE.txt"'
check "rejects other data_static files" rejects 'touch "$copy/data_static/privatewar/notes.txt"'

if ((failures > 0)); then
    echo "[package-selftest] $failures failed" >&2
    exit 1
fi
echo "[package-selftest] ok"
