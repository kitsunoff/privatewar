#!/usr/bin/env bash
# Argument validation must fail before any connection or publication.
set -o errexit -o nounset -o pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reject() {
    if DECK_HOST=unused bash "$here/publish.sh" "$@" >/dev/null 2>&1; then
        echo "unexpected success: $*" >&2
        exit 1
    fi
}
reject
reject update --id invalid --changes test
reject update --id 123
reject create
reject update --id 123 --changes test --unknown
echo '[publish-selftest] argument validation ok'
