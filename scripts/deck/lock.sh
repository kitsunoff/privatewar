#!/usr/bin/env bash
# Deck lock: only one script at a time may use the Steam Deck (one game instance, one addons/ folder), across all
# git worktrees of this repository. Sourced by common.sh; scripts call `deck_lock` once after sourcing it.
#
# How it works (pure bash, no flock; macOS has none):
#   - The lock is a SYMLINK in the git common dir (shared by every worktree). `ln -s` is atomic and fails when the
#     link exists, and the owner info lives in the link target, so there is never a half-written lock.
#     Target format: pid|token|start-epoch|branch|worktree
#   - Re-entrancy: the owner exports PW_DECK_LOCK_TOKEN. A child script that finds the lock held with that token
#     (and a live owner pid) continues without locking, so cp1.sh -> deploy.sh -> run.sh does not deadlock.
#   - Stale lock: the owner pid is dead -> take over with one log line. Takeovers are serialized by a short-lived
#     guard directory so two waiters cannot both delete each other's fresh lock.
#   - Release on EXIT, INT, TERM, HUP (trap), only if the lock still carries our token.
# Environment:
#   PW_DECK_LOCK=0             disable locking entirely
#   PW_DECK_LOCK_TIMEOUT       seconds to wait before giving up (default 1800), exit code 75
#   PW_DECK_LOCK_NOTICE        seconds between "waiting" messages (default 30)
#   PW_DECK_LOCK_POLL          seconds between attempts (default 1)
#   PW_DECK_LOCK_PATH          lock path override (used by the self-test)
# Lock-free on purpose: logs.sh and detect.sh are reads (shot.sh locks: it sends a command to the game). cmd.sh takes no lock either, but it calls
# deck_lock_guard: it refuses (exit 75) while another agent holds the lock, because a console command sent into
# the game in the middle of someone else's test run breaks that run.

_deck_lock_path() {
    if [[ -n "${PW_DECK_LOCK_PATH:-}" ]]; then
        printf '%s\n' "$PW_DECK_LOCK_PATH"
        return
    fi
    local root common
    root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    if common="$(cd "$root" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"; then
        printf '%s\n' "$common/pw-deck.lock"
    else
        printf '%s\n' "$root/.pw-deck.lock"
    fi
}

# Prints the lock target (owner record); fails when there is no lock.
_deck_lock_read() { readlink "$1" 2>/dev/null; }

_deck_lock_pid_alive() { [[ "$1" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null; }

_deck_lock_describe() {
    local pid token since branch tree
    IFS='|' read -r pid token since branch tree <<<"$1"
    local when
    when="$(date --date="@${since:-0}" '+%H:%M:%S' 2>/dev/null || date -r "${since:-0}" '+%H:%M:%S')"
    printf '%s (%s) since %s' "${branch:-?}" "${tree:-?}" "$when"
}

# Remove the lock at $1 if it still holds the stale record $2. Serialized by a guard directory.
_deck_lock_takeover() {
    local path="$1" stale="$2" guard="$1.guard" current
    # A guard older than a minute belongs to a crashed taker (the critical section lasts milliseconds).
    if [[ -d "$guard" ]] && [[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
        rmdir "$guard" 2>/dev/null || true
    fi
    mkdir "$guard" 2>/dev/null || return 1
    current="$(_deck_lock_read "$path" || true)"
    if [[ "$current" == "$stale" ]]; then
        rm --force "$path"
        echo "[deck] took over a stale Deck lock left by $(_deck_lock_describe "$stale") (pid ${stale%%|*} is dead)" >&2
    fi
    rmdir "$guard" 2>/dev/null || true
    return 0
}

deck_lock_release() {
    trap '' INT TERM HUP # a second signal must not interrupt the release
    local path record
    path="$(_deck_lock_path)"
    record="$(_deck_lock_read "$path" || true)"
    if [[ -n "${_DECK_LOCK_OWNED:-}" && "$record" == *"|${PW_DECK_LOCK_TOKEN:-}|"* ]]; then
        rm --force "$path"
    fi
    _DECK_LOCK_OWNED=""
    unset PW_DECK_LOCK_TOKEN
    trap - EXIT INT TERM HUP
}

# For lock-free scripts that act on the game (cmd.sh). Never waits and never takes the lock:
#   free lock, stale lock (dead pid), or our own token -> return 0; held by someone else -> exit 75.
deck_lock_guard() {
    if [[ "${PW_DECK_LOCK:-1}" == 0 ]]; then return 0; fi
    local record pid token
    record="$(_deck_lock_read "$(_deck_lock_path)" || true)"
    if [[ -z "$record" ]]; then return 0; fi
    IFS='|' read -r pid token _ <<<"$record"
    if ! _deck_lock_pid_alive "$pid"; then return 0; fi
    if [[ -n "${PW_DECK_LOCK_TOKEN:-}" && "$token" == "$PW_DECK_LOCK_TOKEN" ]]; then return 0; fi
    echo "[deck] cmd.sh refused: the Deck is locked by $(_deck_lock_describe "$record")" >&2
    exit 75
}

deck_lock() {
    if [[ "${PW_DECK_LOCK:-1}" == 0 ]]; then return 0; fi
    local path record pid token since branch tree holder odd=0
    path="$(_deck_lock_path)"
    mkdir --parents "$(dirname "$path")"

    # Re-entrant call: an ancestor script of this process tree already holds the lock.
    if [[ -n "${PW_DECK_LOCK_TOKEN:-}" ]]; then
        record="$(_deck_lock_read "$path" || true)"
        IFS='|' read -r pid token _ <<<"$record"
        if [[ "$token" == "$PW_DECK_LOCK_TOKEN" ]] && _deck_lock_pid_alive "$pid"; then return 0; fi
        unset PW_DECK_LOCK_TOKEN # leftover from a dead process tree
    fi

    local timeout="${PW_DECK_LOCK_TIMEOUT:-1800}" notice="${PW_DECK_LOCK_NOTICE:-30}" poll="${PW_DECK_LOCK_POLL:-1}"
    local waited_since="$SECONDS" last_notice="$SECONDS" announced=0
    token="$$-$(date +%s)-$RANDOM"
    branch="$(git -C "${REPO_ROOT:-.}" branch --show-current 2>/dev/null || true)"
    tree="${REPO_ROOT:-$PWD}"
    since="$(date +%s)"
    record="$$|$token|$since|${branch:-detached}|$tree"

    while ! ln -s "$record" "$path" 2>/dev/null; do
        holder="$(_deck_lock_read "$path" || true)"
        if [[ -z "$holder" ]]; then
            # Released between ln and readlink: retry. A persistent failure is an environment problem.
            if ((++odd > 50)); then
                echo "[deck] cannot create the Deck lock at $path" >&2
                exit 1
            fi
            sleep 0.1
            continue
        fi
        odd=0
        IFS='|' read -r pid _ <<<"$holder"
        if ! _deck_lock_pid_alive "$pid"; then
            _deck_lock_takeover "$path" "$holder" || sleep 0.1
            continue
        fi
        if ((SECONDS - waited_since >= timeout)); then
            echo "[deck] gave up after ${timeout}s: the Deck lock is still held by $(_deck_lock_describe "$holder") (pid $pid). Raise PW_DECK_LOCK_TIMEOUT or wait." >&2
            exit 75
        fi
        if ((announced == 0 || SECONDS - last_notice >= notice)); then
            echo "[deck] waiting for the Deck lock held by $(_deck_lock_describe "$holder")" >&2
            announced=1
            last_notice="$SECONDS"
        fi
        sleep "$poll"
    done

    export PW_DECK_LOCK_TOKEN="$token"
    _DECK_LOCK_OWNED=1
    trap deck_lock_release EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
}
