#!/usr/bin/env bash
# Manual full GLuaTest gate on the Steam Deck (scripts/deck/test.sh).
# No pre-push hook is installed; acceptance/merge still require an authorized game run.
exec bash "$(dirname "${BASH_SOURCE[0]}")/../deck/test.sh"
