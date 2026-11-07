#!/usr/bin/env bash
# Follow the game console log on the Deck (needs -condebug, set by run.sh).
# Default filter: Lua errors, [PW] lines, GLuaTest output. --all shows everything.
# --from-start prints the existing log first instead of only new lines.
# Lock-free on purpose (read only): it never takes the Deck lock, see lock.sh.
# --once prints the filtered existing log and exits (for agents and scripts).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

filter='\[ERROR\]|\[PW\]|lua/[^ ]+:[0-9]+:|stack traceback|GLuaTest|Couldn.t (load|include)'
lines=0
show_all=0
follow=1
for arg in "$@"; do
    case "$arg" in
        --all) show_all=1 ;;
        --from-start) lines=+1 ;;
        --once) follow=0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

log="$(deck_gmod_dir)/console.log"
if [[ "$follow" == 1 ]]; then
    reader="tail --lines=$lines --follow=name --retry '$log'"
else
    reader="cat '$log'"
fi
if [[ "$show_all" == 1 ]]; then
    deck_run "$reader"
else
    deck_run "$reader" | grep --line-buffered --extended-regexp "$filter" || true
fi
