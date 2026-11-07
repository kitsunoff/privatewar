#!/usr/bin/env bash
# Claude Code PostToolUse hook (T-0.7): after an Edit or Write of a .lua file, run the lint gate on that file
# and the type gate on the workspace. Problems are printed to stderr with exit code 2, which Claude Code
# feeds back to the agent as a blocking diagnostic.
# The hook command runs from the main checkout. An agent that edits inside a git worktree (.claude/worktrees/*)
# gets the gates of that worktree: its own scripts, .luarc.json and files, not the main checkout's.
set -o errexit -o nounset -o pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

file_path="$(jq --raw-output '.tool_input.file_path // empty')"
if [[ "$file_path" != *.lua ]]; then exit 0; fi
if file_root="$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null)" \
    && [[ -f "$file_root/scripts/check/claude-hook.sh" ]]; then
    root="$file_root"
fi
case "$file_path" in
    "$root"/tests/gates/fixtures/*) exit 0 ;;
esac

if ! output="$(cd "$root" && bash scripts/check/lint.sh "$file_path" 2>&1 && bash scripts/check/types.sh 2>&1)"; then
    printf 'Quality gate failed for %s:\n%s\n' "$file_path" "$output" >&2
    exit 2
fi
