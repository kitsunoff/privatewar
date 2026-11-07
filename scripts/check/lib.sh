#!/usr/bin/env bash
# Shared setup for the quality gates. Sourced by the gate scripts.
# PW_ROOT overrides the project root (the self-test runs the gates in a scratch workspace).
set -o errexit -o nounset -o pipefail

PW_ROOT="${PW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export PW_ROOT
cd "$PW_ROOT"

# Lua sources that ship or run in GMod: every addon folder under addons/ (the gamemode, the integration addons and
# the dev addon). Gate fixtures (tests/gates/fixtures) are not linted.
PW_LUA_DIRS=(addons)

# Repository paths of the gamemode addon (GMod mounts addons/<name>/ as if it were the game folder).
PW_GM_ADDON=addons/privatewar
PW_DEV_ADDON=addons/privatewar-dev

# Integration addons: every addon folder except the gamemode and the dev addon. Prints one path per line.
pw_integration_addons() {
    local dir
    for dir in addons/*/; do
        dir="${dir%/}"
        [[ -d "$dir" && "$dir" != "$PW_GM_ADDON" && "$dir" != "$PW_DEV_ADDON" ]] || continue
        echo "$dir"
    done
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 is not on PATH; run the gates through 'nix develop --command ...'" >&2
        exit 2
    fi
}

# LuaLS reads the GMod annotations and the GLuaTest types from .nix/ (named in .luarc.json); the flake
# exports their store paths as PW_GLUA_API and PW_GLUATEST.
link_type_libraries() {
    mkdir --parents .nix
    if [[ -n "${PW_GLUA_API:-}" ]]; then
        ln --symbolic --force --no-target-directory "$PW_GLUA_API" .nix/glua-api
    fi
    if [[ -n "${PW_GLUATEST:-}" ]]; then
        ln --symbolic --force --no-target-directory "$PW_GLUATEST" .nix/gluatest
    fi
    if [[ ! -d .nix/glua-api/library || ! -d .nix/gluatest/lua/gluatest ]]; then
        echo "type libraries missing under .nix/; enter the devShell (nix develop)" >&2
        exit 2
    fi
}
