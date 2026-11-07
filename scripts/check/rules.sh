#!/usr/bin/env bash
# Rule gate (DESIGN.md global rules 3 and 4): cheap checks the linters do not cover.
#   1. No net.WriteTable / net.ReadTable in gamemode or module code (the gamemode addon's lua/tests/ may use them).
#   2. A Lua file stays at or under 500 lines.
#   3. A function stays at or under 60 lines, counted from its `function` line to its `end` line.
#   4. A top-level include in a shared file has a matching AddCSLuaFile in the same file.
# Paths: the gamemode addon is addons/privatewar/; integration addons are the other addons/<name>/ folders except the
# dev addon (addons/privatewar-dev/, never shipped, not checked by 1-4).
# Scope of 4: lua/privatewar and the integration addons (the gamemode folder sends its core files from init.lua).
# Scope of 2 and 3: gamemodes/, lua/privatewar/ and the integration addons. Test files (lua/tests/) are exempt: a
# GLuaTest group is one returned table of cases, so its size follows the number of mandatory cases, not the size of
# the code.
# Function lengths come from LuaJIT's own parser: `luajit -bl` lists every function prototype with its first and
# last source line, so nested functions, strings and comments that contain `function` or `end` cannot fool it.
# A file LuaJIT cannot parse (GLua-only syntax such as `!=` or `continue`) fails the gate: the length is unknown.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool luajit

max_file_lines=500
max_function_lines=60
integration_dirs=()
while IFS= read -r dir; do integration_dirs+=("$dir"); done < <(pw_integration_addons)
size_dirs=("$PW_GM_ADDON/gamemodes" "$PW_GM_ADDON/lua/privatewar" "${integration_dirs[@]}")
failures=0

fail() {
    echo "$1" >&2
    failures=$((failures + 1))
}

# 1. net.WriteTable / net.ReadTable outside the gamemode addon's lua/tests/. Text after `--` on a line is a comment and is ignored
# (a comment may name the rule); block comments are not recognised, so a call quoted in one is reported.
while IFS= read -r hit; do
    fail "$hit: net.WriteTable/net.ReadTable is forbidden (DESIGN.md global rule 4)"
done < <(grep --recursive --line-number --extended-regexp --include='*.lua' \
    'net\.(Write|Read)Table' "$PW_GM_ADDON/gamemodes" "$PW_GM_ADDON/lua" "${integration_dirs[@]}" 2>/dev/null \
    | grep --invert-match "^$PW_GM_ADDON/lua/tests/" \
    | awk '{ path = $0; sub(/:.*/, "", path); rest = substr($0, length(path) + 2); line = rest; sub(/:.*/, "", line)
             code = substr(rest, length(line) + 2); sub(/--.*/, "", code)
             if (code ~ /net\.(Write|Read)Table/) print path ":" line }' || true)

files=()
for dir in "${size_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$dir" -name '*.lua' -print0 | sort --zero-terminated)
    fi
done

for file in "${files[@]}"; do
    # 2. File size.
    lines="$(wc --lines <"$file")"
    if (( lines > max_file_lines )); then
        fail "$file: $lines lines, limit $max_file_lines (DESIGN.md global rule 3)"
    fi

    # 3. Function size. Prototype 0 is the file's main chunk, not a function.
    # With an output file -l writes the listing into it, so the listing goes to stdout (no output file).
    if ! listing="$(luajit -b -l "$file" 2>&1)"; then
        fail "$file: LuaJIT cannot parse it, function lengths unknown: $listing"
        continue
    fi
    while read -r first last; do
        if (( first > 0 && last - first + 1 > max_function_lines )); then
            fail "$file:$first: function of $((last - first + 1)) lines (lines $first-$last), limit $max_function_lines (DESIGN.md global rule 3)"
        fi
    done < <(sed --quiet --regexp-extended 's/^-- BYTECODE -- .*:([0-9]+)-([0-9]+)$/\1 \2/p' <<<"$listing")
done

# 4. A shared file (shared.lua, sh_*.lua) that includes a Lua file at the top level (column 0, so not inside an
# `if SERVER` block or a loop) must send it with AddCSLuaFile of the same argument in the same file, else the client
# logs "Couldn't include file". A server-only include belongs inside `if SERVER then ... end` (indented, skipped here).
while IFS= read -r hit; do
    fail "$hit: top-level include without a matching AddCSLuaFile in the same file (client cannot load it); add 'if SERVER then AddCSLuaFile(...) end' or guard the include"
done < <(for file in "${files[@]}"; do
    case "$file" in
        "$PW_GM_ADDON"/gamemodes/*) continue ;; # the gamemode's init.lua sends its own core files
        */shared.lua | */sh_*.lua) ;;
        *) continue ;;
    esac
    awk -v file="$file" '
        { code = $0; sub(/--.*/, "", code); lines[NR] = code }
        END {
            for (i = 1; i <= NR; i++) {
                if (match(lines[i], /^(local[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*)?include\(/)) {
                    arg = substr(lines[i], RSTART + RLENGTH); sub(/\)[ \t]*$/, "", arg)
                    found = 0
                    for (j = 1; j <= NR; j++) if (index(lines[j], "AddCSLuaFile(" arg ")") > 0) found = 1
                    if (!found) print file ":" i
                }
            }
        }' "$file"
done)

if (( failures > 0 )); then
    echo "[rules] $failures problem(s)" >&2
    exit 1
fi
echo "[rules] ok (${#files[@]} files)"
