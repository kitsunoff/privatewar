#!/usr/bin/env bash
# Checks a staged addon tree (T-10.2): fails if anything that must not ship is inside, or a required
# file is missing. Usage: verify.sh <addon-dir> <gamemode|integration>
set -o errexit -o nounset -o pipefail

root="${1:?usage: verify.sh <addon-dir> <gamemode|integration>}"
kind="${2:?usage: verify.sh <addon-dir> <gamemode|integration>}"
failures=0
# The addon name is the staged folder name; its licence files live under data_static/<name>/.
name="$(basename "$root")"

fail() {
    echo "[package] FAIL ${root}: $1" >&2
    failures=$((failures + 1))
}

if [[ ! -d "$root" ]]; then
    echo "[package] FAIL: $root is not a directory" >&2
    exit 1
fi

# Excluded paths (TASKS.md T-10.2): tests, fixtures, the whole dev addon, Deck connection and tooling.
forbidden=(
    'lua/tests'
    'lua/privatewar_fixtures'
    'privatewar_dev'
    'dev'
    'scripts'
    'docs'
    'tests'
    'design'
    'notes'
    'cfg'
    'lua/autorun/server/pw_devbridge.lua'
    'lua/autorun/server/pw_devstart.lua'
    'lua/autorun/server/pw_testgate.lua'
    'lua/autorun/server/pw_testreport.lua'
    'lua/autorun/server/pw_cp1.lua'
    'lua/autorun/client/pw_cp1_probe.lua'
    'lua/autorun/client/pw_lobby_probe.lua'
    'lua/privatewar/modes/pw_dummy.lua'
    'lua/privatewar/screens/dev_kit.lua'
    '.deck.env'
)
for path in "${forbidden[@]}"; do
    if [[ -e "$root/$path" ]]; then fail "excluded path present: $path"; fi
done

# Dotfiles and dot-directories (.deck.env, .DS_Store, .git, .nix ...).
while IFS= read -r found; do
    fail "dotfile or dot-directory present: ${found#"$root"/}"
done < <(find "$root" -name '.*' -not -path "$root")

# Only Lua sources, gamemode manifests and menu images, the addon manifest and licence texts ship.
while IFS= read -r found; do
    rel="${found#"$root"/}"
    case "$rel" in
        addon.json) ;;
        *.lua) ;;
        gamemodes/*/*.txt) ;;
        gamemodes/privatewar/logo.png | gamemodes/privatewar/icon24.png)
            if [[ "$kind" != gamemode ]]; then fail "gamemode menu image in integration: $rel"; fi ;;
        data_static/"$name"/LICENSE.txt | data_static/"$name"/THIRD_PARTY_NOTICES.txt) ;;
        *) fail "file type not allowed: $rel" ;;
    esac
done < <(find "$root" -type f)

# addon.json must exist and describe the addon.
if [[ -f "$root/addon.json" ]]; then
    if ! jq --exit-status '.title and .type and (.tags | type == "array") and (.ignore | type == "array")' \
        "$root/addon.json" >/dev/null 2>&1; then
        fail "addon.json lacks title, type, tags or ignore"
    fi
    if [[ "$kind" == gamemode ]] && [[ "$(jq --raw-output .type "$root/addon.json" 2>/dev/null)" != gamemode ]]; then
        fail "addon.json type is not gamemode"
    fi
else
    fail "addon.json is missing"
fi

# The licence and the third-party notices ship in every addon (T-10.1), under data_static/<addon>/.
for required in LICENSE.txt THIRD_PARTY_NOTICES.txt; do
    if [[ ! -s "$root/data_static/$name/$required" ]]; then fail "licence file is missing: data_static/$name/$required"; fi
done

if [[ "$kind" == gamemode ]]; then
    for required in gamemodes/privatewar/privatewar.txt gamemodes/privatewar/logo.png \
        gamemodes/privatewar/icon24.png gamemodes/privatewar/gamemode/shared.lua \
        gamemodes/privatewar/gamemode/init.lua gamemodes/privatewar/gamemode/cl_init.lua lua/privatewar; do
        if [[ ! -e "$root/$required" ]]; then fail "required path is missing: $required"; fi
    done
fi

if ((failures > 0)); then exit 1; fi
echo "[package] verified ${root}"
