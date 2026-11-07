#!/usr/bin/env bash
# Run the GLuaTest suite in the real game on the Deck (T-0.4) and exit with its verdict.
# Deploys the gamemode, the dev addon and GLuaTest, then reloads the map: GLuaTest runs every test on map
# load and the dev reporter (pw_testreport) writes a summary the script polls for.
# Usage: test.sh [--expect-failure]
#   --expect-failure  also deploy tests/gates/fixtures/failing_test.lua and succeed only if the run fails
#                     (proves a failing case makes this script exit non-zero)
# Environment: PW_GLUATEST (GLuaTest source, set by the devShell), PW_MAP, PW_TEST_TIMEOUT (seconds, default 180).
# Exit codes: 0 all passed, 1 failures (or no tests ran), 124 no result before the timeout.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # one user of the Deck at a time (lock.sh); nested calls re-enter
here="$(dirname "${BASH_SOURCE[0]}")"

expect_failure=0
if [[ "${1:-}" == "--expect-failure" ]]; then expect_failure=1; fi

gluatest="${PW_GLUATEST:?PW_GLUATEST is not set; run through nix develop --command}"
timeout_s="${PW_TEST_TIMEOUT:-180}"
map="${PW_MAP:-gm_construct}"

gmod_dir="$(deck_gmod_dir)"
addons="$gmod_dir/addons"
# GMod mounts addon folders only at startup: a first install needs a game restart, not a map reload.
fresh_install=0
if ! deck_run "[ -d '$addons/privatewar' ] && [ -d '$addons/gluatest' ]"; then fresh_install=1; fi

"$here/deploy.sh" >/dev/null

# GLuaTest itself, without its own test suite. Store files are read-only, so make the copies writable.
rsync --archive --compress --delete --chmod=u+w --exclude='tests/' --rsh="ssh ${SSH_OPTS[*]}" \
    "$gluatest/lua" "$DECK_TARGET:$addons/gluatest/"

fixture_dir="$addons/privatewar/lua/tests/privatewar_failfixture"
if [[ "$expect_failure" == 1 ]]; then
    deck_run "mkdir --parents '$fixture_dir'"
    rsync --compress --rsh="ssh ${SSH_OPTS[*]}" "$REPO_ROOT/tests/gates/fixtures/failing_test.lua" \
        "$DECK_TARGET:$fixture_dir/failing_test.lua"
else
    deck_run "rm --recursive --force '$fixture_dir'"
fi

result="$gmod_dir/data/privatewar_dev/test_result.txt"
# A skip flag left by an interrupted snap.sh would skip this run (pw_testgate.lua).
deck_run "rm --force '$result' '$gmod_dir/data/privatewar_dev/skip_tests.txt'"

if ! deck_run "pgrep --full '$GAME_PROCESS_PATTERN' >/dev/null"; then
    PW_MAP="$map" "$here/run.sh"
elif [[ "$fresh_install" == 1 ]]; then
    PW_MAP="$map" "$here/run.sh" --restart
else
    "$here/cmd.sh" "gamemode privatewar" "map $map" >/dev/null
fi
echo "[test] waiting for GLuaTest (up to ${timeout_s}s)"

summary=""
deadline=$((SECONDS + timeout_s))
while ((SECONDS < deadline)); do
    summary="$(deck_run "cat '$result' 2>/dev/null || true")"
    if [[ -n "$summary" ]]; then break; fi
    sleep 3
done

if [[ "$expect_failure" == 1 ]]; then deck_run "rm --recursive --force '$fixture_dir'"; fi

if [[ -z "$summary" ]]; then
    echo "[test] no result within ${timeout_s}s; last log lines:" >&2
    "$here/logs.sh" --once | tail --lines=40 >&2
    exit 124
fi

echo "[test] $summary"
passed="$(sed --regexp-extended 's/.*passed=([0-9]+).*/\1/' <<<"$summary")"
failed="$(sed --regexp-extended 's/.*failed=([0-9]+).*/\1/' <<<"$summary")"
verdict=0
if ((failed > 0 || passed == 0)); then
    verdict=1
    "$here/logs.sh" --once | grep --extended-regexp --after-context=6 'FAIL|failed|\[ERROR\]' | tail --lines=60 >&2 || true
fi

if [[ "$expect_failure" == 1 ]]; then
    if ((failed > 0)); then
        echo "[test] ok: the failing fixture made the run fail"
        exit 0
    fi
    echo "[test] FAIL: the failing fixture did not make the run fail" >&2
    exit 1
fi
exit "$verdict"
