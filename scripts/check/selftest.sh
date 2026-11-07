#!/usr/bin/env bash
# Gate self-test (TASKS.md, mandatory cases of T-0.3 and T-0.7): every gate must reject its bad fixture.
# Each fixture is copied into a scratch workspace with the project configs, so the real tree stays clean.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fixtures="$PW_ROOT/tests/gates/fixtures"
gates="$PW_ROOT/scripts/check"
failures=0

# expect <accept|reject[:text]> <gate script> <fixture>:<destination inside the scratch workspace>...
# reject:text also requires the gate output to contain text, so the rejection has the intended reason.
# The type gate also gets the project's type declarations (addons/privatewar/lua/privatewar/types/), so fixtures can use MODE etc.
expect() {
    local verdict="${1%%:*}" reason="" gate="$2" work pair label=""
    if [[ "$1" == *:* ]]; then reason="${1#*:}"; fi
    shift 2
    work="$(mktemp --directory)"
    cp "$PW_ROOT/.glualint.json" "$PW_ROOT/.luarc.json" "$PW_ROOT/.markdownlint-cli2.yaml" "$work/"
    mkdir --parents "$work/.nix"
    for lib in glua-api gluatest; do
        if [[ -e "$PW_ROOT/.nix/$lib" ]]; then
            ln --symbolic "$(cd "$PW_ROOT/.nix/$lib" && pwd -P)" "$work/.nix/$lib"
        fi
    done
    if [[ "$gate" == types.sh ]]; then
        mkdir --parents "$work/addons/privatewar/lua/privatewar"
        cp --recursive "$PW_ROOT/addons/privatewar/lua/privatewar/types" "$work/addons/privatewar/lua/privatewar/types"
    fi
    for pair in "$@"; do
        mkdir --parents "$work/$(dirname "${pair#*:}")"
        cp "$fixtures/${pair%%:*}" "$work/${pair#*:}"
        label+=" ${pair%%:*} as ${pair#*:};"
    done
    local accepted=false
    if PW_ROOT="$work" bash "$gates/$gate" >"$work.out" 2>&1; then accepted=true; fi
    if [[ "$verdict" == accept && "$accepted" == true ]]; then
        echo "[selftest] ok: $gate accepts$label"
    elif [[ "$verdict" == reject && "$accepted" == false ]] && grep --quiet --fixed-strings -- "$reason" "$work.out"; then
        echo "[selftest] ok: $gate rejects$label ${reason:+(}$reason${reason:+)}"
    else
        echo "[selftest] FAIL: $gate did not $verdict$label" >&2
        cat "$work.out" >&2
        failures=$((failures + 1))
    fi
    rm --recursive --force "$work" "$work.out"
}

expect reject lint.sh lint_error.lua:addons/privatewar/lua/privatewar/lint_error.lua
expect reject types.sh type_error.lua:addons/privatewar/lua/privatewar/type_error.lua
expect reject markdown.sh markdown_error.md:BROKEN.md

# duplicate-set-field is relaxed only in entity folders (scripts/check/types.sh).
expect accept types.sh \
    duplicate_mode_a.lua:addons/privatewar/lua/privatewar/modes/gate_a.lua \
    duplicate_mode_b.lua:addons/privatewar/lua/privatewar/modes/gate_b.lua
expect accept types.sh \
    duplicate_mode_a.lua:addons/privatewar/lua/privatewar/modules/gate/shared.lua \
    duplicate_mode_b.lua:addons/privatewar/lua/privatewar_fixtures/examples/modes/gate_b.lua \
    duplicate_mode_b.lua:addons/privatewar-dev/lua/privatewar/modes/gate_c.lua
expect reject:"[duplicate-set-field]" types.sh \
    duplicate_mode_a.lua:addons/privatewar/gamemodes/privatewar/gamemode/core/gate_a.lua \
    duplicate_mode_b.lua:addons/privatewar/gamemodes/privatewar/gamemode/core/gate_b.lua
expect reject:"[duplicate-set-field]" types.sh \
    duplicate_mode_a.lua:addons/privatewar/lua/privatewar/types/gate_a.lua \
    duplicate_mode_b.lua:addons/privatewar/lua/privatewar/types/gate_b.lua
expect reject:"[duplicate-set-field]" types.sh \
    duplicate_mode_a.lua:addons/privatewar/lua/tests/privatewar/gate_a.lua \
    duplicate_mode_b.lua:addons/privatewar/lua/tests/privatewar/gate_b.lua
expect reject:"[duplicate-set-field]" types.sh \
    duplicate_mode_a.lua:addons/privatewar/lua/privatewar/modes/gate_a.lua \
    duplicate_mode_b.lua:addons/privatewar/gamemodes/privatewar/gamemode/core/gate_b.lua

# Rule gate (DESIGN.md global rules 3 and 4): each limit rejects its fixture; test files are exempt.
expect accept rules.sh rules_ok.lua:addons/privatewar/gamemodes/privatewar/gamemode/core/gate_ok.lua
expect reject:"net.WriteTable/net.ReadTable is forbidden" rules.sh \
    rules_write_table.lua:addons/privatewar/lua/privatewar/modules/gate/init.lua
expect reject:"net.WriteTable/net.ReadTable is forbidden" rules.sh \
    rules_write_table.lua:addons/privatewar-example/lua/privatewar/modules/gate/init.lua
expect reject:"limit 500" rules.sh rules_long_file.lua:addons/privatewar/gamemodes/privatewar/gamemode/core/gate_long.lua
expect reject:"function of 61 lines" rules.sh rules_long_function.lua:addons/privatewar/lua/privatewar/modes/gate_long.lua
expect accept rules.sh \
    rules_write_table.lua:addons/privatewar/lua/tests/privatewar/gate_table.lua \
    rules_long_file.lua:addons/privatewar/lua/tests/privatewar/gate_long.lua \
    rules_long_function.lua:addons/privatewar/lua/tests/privatewar/gate_function.lua

# Deck lock (scripts/deck/lock.sh): serialization, re-entrancy, stale takeover, timeout.
if ! bash "$gates/deck-lock-selftest.sh"; then failures=$((failures + 1)); fi

if (( failures > 0 )); then exit 1; fi
echo "[selftest] ok"
