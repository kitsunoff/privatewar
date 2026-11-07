#!/usr/bin/env bash
# Lint gate: glualint with the strict project config (.glualint.json).
# Usage: lint.sh [file.lua ...]   no arguments = every Lua source of the project
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool glualint

targets=()
if (( $# == 0 )); then
    for dir in "${PW_LUA_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then targets+=("$dir"); fi
    done
else
    for f in "$@"; do
        if [[ "$f" == *.lua && -f "$f" ]]; then targets+=("$f"); fi
    done
fi

if (( ${#targets[@]} == 0 )); then exit 0; fi
glualint --config "$PW_ROOT/.glualint.json" lint "${targets[@]}"
echo "[lint] ok"
