#!/usr/bin/env bash
# Verifies a public export tree (docs/publishing.md). Usage: verify.sh <tree-dir> [<local-only-list>]
# Fails (exit 1) on: Cyrillic in any file content or file name, a scrub term, a local-only path, .deck.env, private/.
# The scrub terms are written in pieces so that this file does not match its own check.
set -o errexit -o nounset -o pipefail

tree="${1:?usage: verify.sh <tree-dir> [<local-only-list>]}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
list="${2:-$here/local-only.txt}"
failures=0

fail() {
    echo "[export] FAIL: $1" >&2
    failures=$((failures + 1))
}

[[ -d "$tree" ]] || { echo "[export] not a directory: $tree" >&2; exit 2; }

terms=(
    'slop''match'
    'garry.?s warf''are'
    '3801''998124'
    'smart.?b''ots'
    'infinity w''ard'
    'at''e47'
    'weapon-b''ases'
    'reverse.?engi''neer'
    'gma_ext''ract'
    '/Us''ers/'
    'home''lab'
)
scrub="$(IFS='|'; echo "${terms[*]}")"

# UTF-8 lead bytes D0-D3 followed by a continuation byte: Cyrillic (U+0400-U+04FF) and its neighbours.
cyrillic=$'[\xd0-\xd3][\x80-\xbf]'

hits="$(LC_ALL=C grep --recursive --binary-files=without-match --line-number --extended-regexp --exclude-dir=.git "$cyrillic" "$tree" || true)"
if [[ -n "$hits" ]]; then fail "Cyrillic in file content:"; echo "$hits" | head --lines=20 >&2; fi

names="$(cd "$tree" && find . -path ./.git -prune -o -print | LC_ALL=C grep --extended-regexp "$cyrillic" || true)"
if [[ -n "$names" ]]; then fail "Cyrillic in file names:"; echo "$names" >&2; fi

hits="$(LC_ALL=C grep --recursive --binary-files=without-match --line-number --ignore-case --extended-regexp --exclude-dir=.git "$scrub" "$tree" || true)"
if [[ -n "$hits" ]]; then fail "scrub term in file content:"; echo "$hits" | head --lines=20 >&2; fi

names="$(cd "$tree" && find . -path ./.git -prune -o -print | LC_ALL=C grep --ignore-case --extended-regexp "$scrub" || true)"
if [[ -n "$names" ]]; then fail "scrub term in file names:"; echo "$names" >&2; fi

if [[ -n "$(find "$tree" -name .deck.env -not -path "$tree/.git/*")" ]]; then fail ".deck.env present"; fi
if [[ -e "$tree/private" ]]; then fail "private/ present"; fi

if [[ -f "$list" ]]; then
    while IFS= read -r path; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        if [[ -e "$tree/$path" ]]; then fail "local-only path present: $path"; fi
    done <"$list"
fi

if ((failures > 0)); then
    echo "[export] verification failed: $failures problem(s)" >&2
    exit 1
fi
echo "[export] verification passed: $tree"
