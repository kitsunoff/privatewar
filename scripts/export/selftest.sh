#!/usr/bin/env bash
# Self-test of the export verify step: a clean tree passes, each kind of violation is rejected.
set -o errexit -o nounset -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scratch="$(mktemp --directory)"
trap 'rm -rf "$scratch"' EXIT
failures=0

check() {
    local label="$1"
    shift
    if "$@"; then echo "ok   $label"; else echo "FAIL $label" >&2; failures=$((failures + 1)); fi
}

verify() { bash "$here/verify.sh" "$1" "$here/local-only.txt" >/dev/null 2>&1; }
accepts() { verify "$1"; }
rejects() { ! verify "$1"; }

# fresh <name> [<file> <content>]: a scratch tree with one clean file plus an optional extra file.
fresh() {
    local dir="$scratch/$1"
    mkdir --parents "$dir/docs"
    echo "clean English text" >"$dir/README.md"
    if [[ $# -ge 3 ]]; then
        mkdir --parents "$(dirname "$dir/$2")"
        printf '%s\n' "$3" >"$dir/$2"
    fi
    echo "$dir"
}

check "clean tree passes" accepts "$(fresh clean)"
check "Cyrillic content rejected" rejects "$(fresh cyr docs/a.md "$(printf '\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82')")"
check "Cyrillic file name rejected" rejects "$(fresh cyrname "docs/$(printf '\xd0\x96').md" "x")"
check "scrub term rejected" rejects "$(fresh scrub notes.md "see the home""lab cluster")"
check "scrub term case-insensitive" rejects "$(fresh scrubcase notes.md "AI Slop""match")"
check "absolute home path rejected" rejects "$(fresh homepath notes.md "/Us""ers/someone/x")"
check ".deck.env rejected" rejects "$(fresh deckenv scripts/.deck.env "HOST=x")"
check "private/ rejected" rejects "$(fresh private private/a.txt "x")"
check "local-only path rejected" rejects "$(fresh localonly docs/manual-tests.md "x")"

if ((failures > 0)); then
    echo "[export] selftest: $failures failure(s)" >&2
    exit 1
fi
echo "[export] selftest passed"
