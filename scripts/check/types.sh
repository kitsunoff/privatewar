#!/usr/bin/env bash
# Type gate: lua-language-server --check over the workspace (.luarc.json), every diagnostic is an error.
# The whole workspace is checked even for one changed file: types cross file boundaries, and it takes seconds.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool lua-language-server
require_tool jq
link_type_libraries

# duplicate-set-field is not an error in entity files. Relaxed by the user's decision, approved by the user on
# 2026-11-06: SWEP-style entity files define methods on a shared class table (MODE, MODULE, ...), so every second
# file of a kind triggers duplicate-set-field.
# LuaLS has no per-path diagnostics setting and reads one .luarc.json per --check run (nested configs are not
# honoured), so the gate filters its JSON report instead. Entity files: every folder under lua/privatewar/ (the kind
# folders, kinds/, modules/) of any addon under addons/ (the gamemode, the dev addon and the integration addons share
# the layout), and everything under the gamemode addon's lua/privatewar_fixtures/; a types/ folder is never an entity
# folder. Everywhere else (gamemodes/, lua/privatewar/types/, lua/tests/) a duplicate field stays an error, and so does
# a duplicate whose other definition lies outside the entity folders.
entity_relaxed_code="duplicate-set-field"
entity_paths='^addons/([^/]+/lua/privatewar/[^/]+/|privatewar/lua/privatewar_fixtures/)'
non_entity_paths='(^|/)types/'

log_dir="$(mktemp --directory)"
trap 'rm --recursive --force "$log_dir"' EXIT
root="$(pwd -P)"
# The exit status is not used: the report is filtered below, and a missing report means LuaLS failed.
lua-language-server --check="$root" --checklevel=Information \
    --configpath="$root/.luarc.json" --logpath="$log_dir" --check_format=json >"$log_dir/stdout" 2>&1 || true
if [[ ! -f "$log_dir/check.json" ]]; then
    echo "[types] lua-language-server wrote no report:" >&2
    cat "$log_dir/stdout" >&2
    exit 2
fi

# The other definition of a duplicate is in relatedInformation; it must be an entity file too.
problems="$(jq --raw-output \
    --arg root "file://$(jq --null-input --raw-output --arg path "$root" '$path | split("/") | map(@uri) | join("/")')/" \
    --arg code "$entity_relaxed_code" --arg entity "$entity_paths" --arg excluded "$non_entity_paths" '
    def relative: ltrimstr($root);
    def entity: relative | test($entity) and (test($excluded) | not);
    to_entries[]
    | .key as $uri
    | .value[]
    | select((.code == $code and ($uri | entity)
        and all(.relatedInformation[]?; .location.uri | entity)) | not)
    | "\($uri | relative):\(.range.start.line + 1):\(.range.start.character + 1): [\(.code)] \(.message)"
' "$log_dir/check.json")"
if [[ -n "$problems" ]]; then
    echo "$problems" >&2
    echo "[types] $(wc --lines <<<"$problems") problem(s)" >&2
    exit 1
fi
echo "[types] ok"
