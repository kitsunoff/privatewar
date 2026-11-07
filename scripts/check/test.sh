#!/usr/bin/env bash
# Test gate for pre-push: the full GLuaTest suite in the game on the Steam Deck (scripts/deck/test.sh).
# Pushes are rare, so the minutes this takes are acceptable; a failing suite refuses the push.
exec bash "$(dirname "${BASH_SOURCE[0]}")/../deck/test.sh"
