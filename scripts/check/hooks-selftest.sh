#!/usr/bin/env bash
# Git hook self-test (T-0.7 mandatory cases): in a fresh worktree that enters the devShell, the pre-commit
# hook is installed and refuses a commit with a lint error, a type error or a markdown error, and the
# Claude Code PostToolUse hook reports a type error. With --push it also proves that pre-push refuses a push
# when a test fails (runs the suite on the Steam Deck, about a minute).
# Runs outside the Nix sandbox (needs git and nix): bash scripts/check/hooks-selftest.sh
set -o errexit -o nounset -o pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixtures="$root/tests/gates/fixtures"
work="$(mktemp --directory)/worktree"
failures=0

cleanup() { git -C "$root" worktree remove --force "$work" >/dev/null 2>&1 || true; }
trap cleanup EXIT

git -C "$root" worktree add --detach "$work" HEAD >/dev/null
cd "$work"
nix develop --quiet --command true 2>/dev/null

hooks_dir="$(git rev-parse --git-path hooks)"
if [[ ! -x "$hooks_dir/pre-commit" || ! -x "$hooks_dir/pre-push" || ! -e .pre-commit-config.yaml ]]; then
    echo "[hooks-selftest] FAIL: hooks are not installed in a fresh worktree" >&2
    exit 1
fi
echo "[hooks-selftest] ok: fresh worktree has pre-commit and pre-push hooks"

# expect_refused <fixture> <destination>
expect_refused() {
    local fixture="$1" dest="$2"
    mkdir --parents "$(dirname "$dest")"
    cp "$fixtures/$fixture" "$dest"
    git add "$dest"
    if git -c user.name=selftest -c user.email=selftest@invalid commit --quiet --message "selftest" >/dev/null 2>&1; then
        echo "[hooks-selftest] FAIL: commit with $fixture was accepted" >&2
        git reset --quiet --hard HEAD~1
        failures=$((failures + 1))
    else
        echo "[hooks-selftest] ok: commit with $fixture refused"
    fi
    git reset --quiet --hard HEAD
}

expect_refused lint_error.lua addons/privatewar/lua/privatewar/lint_error.lua
expect_refused type_error.lua addons/privatewar/lua/privatewar/type_error.lua
expect_refused markdown_error.md docs/BROKEN.md

# The Claude Code PostToolUse hook reports a type error introduced by an edit (exit code 2 + diagnostic).
mkdir --parents addons/privatewar/lua/privatewar
cp "$fixtures/type_error.lua" addons/privatewar/lua/privatewar/type_error.lua
set +o errexit
printf '{"tool_input":{"file_path":"%s"}}' "$work/lua/privatewar/type_error.lua" \
    | nix develop --quiet --command bash scripts/check/claude-hook.sh >/dev/null 2>"$work.err"
status=$?
set -o errexit
if [[ "$status" == 2 ]] && grep --quiet "param-type-mismatch" "$work.err"; then
    echo "[hooks-selftest] ok: Claude Code hook reports the type error"
else
    echo "[hooks-selftest] FAIL: Claude Code hook exit $status" >&2
    cat "$work.err" >&2
    failures=$((failures + 1))
fi
rm --force "$work.err"
git clean --quiet --force -- addons/privatewar/lua/privatewar

if [[ "${1:-}" == "--push" ]]; then
    remote="$(mktemp --directory)/remote.git"
    git init --quiet --bare "$remote"
    cp "$fixtures/failing_test.lua" addons/privatewar/lua/tests/privatewar/zz_failing_test.lua
    git add addons/privatewar/lua/tests/privatewar/zz_failing_test.lua
    git -c user.name=selftest -c user.email=selftest@invalid commit --quiet --message "selftest: failing test"
    # The Deck connection file is git-ignored, so a fresh worktree needs a copy.
    if [[ -f "$root/.deck.env" ]]; then cp "$root/.deck.env" .deck.env; fi
    # The refusal must come from the failing case, not from an unrelated error (no Deck, no DECK_HOST).
    if git push "$remote" HEAD:refs/heads/selftest >"$work.push" 2>&1; then
        echo "[hooks-selftest] FAIL: push with a failing test was accepted" >&2
        failures=$((failures + 1))
    elif grep --quiet --extended-regexp '\[test\] passed=[0-9]+ failed=[1-9]' "$work.push"; then
        echo "[hooks-selftest] ok: push with a failing test refused"
    else
        echo "[hooks-selftest] FAIL: push was refused for another reason:" >&2
        tail --lines=20 "$work.push" >&2
        failures=$((failures + 1))
    fi
    rm --force "$work.push"
    rm --recursive --force "$(dirname "$remote")"
fi

if ((failures > 0)); then exit 1; fi
echo "[hooks-selftest] ok"
