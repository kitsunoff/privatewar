#!/usr/bin/env bash
# Self-test of the Deck lock (scripts/deck/lock.sh). Runs without the Deck: workers only source lock.sh.
# Proves: concurrent callers serialize, nested calls do not deadlock, a stale lock is taken over, the wait
# times out (exit 75) with a "waiting" notice, and a killed holder releases the lock. Also covers the cmd.sh
# guard (free lock, foreign lock refused, own token) through a fake ssh on PATH.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

work="$(mktemp --directory)"
trap 'rm --recursive --force "$work"' EXIT
export PW_DECK_LOCK_PATH="$work/pw-deck.lock"
export REPO_ROOT="$PW_ROOT"
export PW_DECK_LOCK_POLL=0.1
lock_lib="$PW_ROOT/scripts/deck/lock.sh"
failures=0

check() { # check <name> <command...>
    local name="$1"
    shift
    if "$@"; then
        echo "[deck-lock] ok: $name"
    else
        echo "[deck-lock] FAIL: $name" >&2
        failures=$((failures + 1))
    fi
}

# worker.sh <id> <hold seconds>: take the lock, log start/end around the hold.
cat >"$work/worker.sh" <<EOF
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
source "$lock_lib"
deck_lock
echo "start \$1" >>"$work/events"
sleep "\$2" &
wait "\$!"
echo "end \$1" >>"$work/events"
EOF

# outer.sh: lock, then run inner.sh twice (nested, one level deeper through another bash).
cat >"$work/outer.sh" <<EOF
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
source "$lock_lib"
deck_lock
echo "outer" >>"$work/nested"
bash "$work/inner.sh"
bash "$work/inner.sh"
EOF
cat >"$work/inner.sh" <<EOF
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
source "$lock_lib"
deck_lock
echo "inner" >>"$work/nested"
bash -c 'source "$lock_lib"; deck_lock; echo "deep" >>"$work/nested"'
EOF

serialize() {
    : >"$work/events"
    local pids=() i
    for i in 1 2 3; do
        bash "$work/worker.sh" "$i" 0.3 &
        pids+=("$!")
    done
    for i in "${pids[@]}"; do wait "$i"; done
    # Every "start N" must be followed directly by "end N": no interleaving.
    local expected="" line n
    while read -r line; do
        case "$line" in
            start*) n="${line#start }"; expected="end $n" ;;
            *) [[ "$line" == "$expected" ]] || return 1; expected="" ;;
        esac
    done <"$work/events"
    [[ -z "$expected" && "$(wc --lines <"$work/events")" == 6 && ! -e "$PW_DECK_LOCK_PATH" ]]
}
check "three concurrent callers serialize and the lock is released" serialize

reentrant() {
    : >"$work/nested"
    PW_DECK_LOCK_TIMEOUT=5 bash "$work/outer.sh" &&
        [[ "$(tr '\n' ' ' <"$work/nested")" == "outer inner deep inner deep " && ! -e "$PW_DECK_LOCK_PATH" ]]
}
check "nested calls re-enter without deadlock" reentrant

stale() {
    local dead
    bash -c 'exit 0' &
    dead="$!"
    wait "$dead"
    ln -s "$dead|old-token|1|stale-branch|/tmp/old-worktree" "$PW_DECK_LOCK_PATH"
    : >"$work/events"
    PW_DECK_LOCK_TIMEOUT=5 bash "$work/worker.sh" stale 0.1 2>"$work/stale.err" &&
        grep --quiet 'took over a stale Deck lock left by stale-branch' "$work/stale.err" &&
        [[ "$(cat "$work/events")" == $'start stale\nend stale' && ! -e "$PW_DECK_LOCK_PATH" ]]
}
check "a stale lock (dead owner pid) is taken over with a log line" stale

timeout_and_release() {
    : >"$work/events"
    bash "$work/worker.sh" holder 5 &
    local holder="$!" code=0 i
    for i in $(seq 50); do
        [[ -L "$PW_DECK_LOCK_PATH" ]] && break
        sleep 0.1
    done
    PW_DECK_LOCK_TIMEOUT=2 PW_DECK_LOCK_NOTICE=1 bash "$work/worker.sh" late 0 2>"$work/late.err" || code=$?
    [[ "$code" == 75 ]] && grep --quiet 'waiting for the Deck lock held by' "$work/late.err" &&
        grep --quiet 'gave up after 2s' "$work/late.err" || { kill "$holder" 2>/dev/null; return 1; }
    # Killing the holder (Ctrl-C / TERM) must release the lock through the trap.
    kill -TERM "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [[ ! -e "$PW_DECK_LOCK_PATH" && ! -L "$PW_DECK_LOCK_PATH" ]]
}
check "the wait times out with exit 75 and a notice; a killed holder releases the lock" timeout_and_release

# cmd.sh guard: a fake ssh on PATH stands in for the Deck (prints a detect line, records that it was called).
mkdir --parents "$work/bin"
cat >"$work/bin/ssh" <<EOF
#!/usr/bin/env bash
echo "ssh" >>"$work/ssh-calls"
echo "native /tmp/fake-gmod/garrysmod"
EOF
chmod +x "$work/bin/ssh"
run_cmd() { PATH="$work/bin:$PATH" DECK_HOST=fake bash "$PW_ROOT/scripts/deck/cmd.sh" "pw_reload" 2>"$work/cmd.err"; }

cmd_guard_free() {
    rm --force "$PW_DECK_LOCK_PATH"
    : >"$work/ssh-calls"
    run_cmd >/dev/null && [[ -s "$work/ssh-calls" && ! -e "$PW_DECK_LOCK_PATH" && ! -L "$PW_DECK_LOCK_PATH" ]]
}
check "cmd.sh with a free lock is allowed and does not take the lock" cmd_guard_free

cmd_guard_refused() {
    bash "$work/worker.sh" holder 5 &
    local holder="$!" code=0 i ok=0
    for i in $(seq 50); do
        [[ -L "$PW_DECK_LOCK_PATH" ]] && break
        sleep 0.1
    done
    : >"$work/ssh-calls"
    run_cmd >/dev/null || code=$?
    if [[ "$code" == 75 && ! -s "$work/ssh-calls" ]] &&
        grep --quiet 'cmd.sh refused: the Deck is locked by ' "$work/cmd.err" &&
        PW_DECK_LOCK=0 run_cmd >/dev/null; then ok=1; fi
    kill -TERM "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [[ "$ok" == 1 ]]
}
check "cmd.sh refuses with exit 75 while another owner holds the lock; PW_DECK_LOCK=0 bypasses" cmd_guard_refused

cat >"$work/own.sh" <<EOF
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
source "$lock_lib"
deck_lock
PATH="$work/bin:\$PATH" DECK_HOST=fake bash "$PW_ROOT/scripts/deck/cmd.sh" pw_reload
EOF
cmd_guard_own() {
    : >"$work/ssh-calls"
    bash "$work/own.sh" >/dev/null 2>"$work/cmd.err" && [[ -s "$work/ssh-calls" && ! -e "$PW_DECK_LOCK_PATH" ]]
}
check "cmd.sh inside the caller's own locked run (same token) is allowed" cmd_guard_own

if ((failures > 0)); then exit 1; fi
echo "[deck-lock] all checks passed"
