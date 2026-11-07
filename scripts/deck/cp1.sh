#!/usr/bin/env bash
# Checkpoint CP-1 (TASKS.md) on the Steam Deck: every item that runs without a second human.
#
# Usage: nix develop --command bash scripts/deck/cp1.sh [--no-restart]
#   --no-restart  reload the map instead of restarting the game (shadowing test 2 then becomes MANUAL,
#                 because a new legacy addon folder is mounted only at game start)
# Environment: DECK_HOST / DECK_USER (or .deck.env, see common.sh), PW_GLUATEST (set by the devShell; GLuaTest is
# copied to the Deck when it is set).
#
# What it does, in order (each check prints PASS, FAIL <reason> or MANUAL <what to do>):
#   1  deploy, restart on gm_construct, GLuaTest passes, no Lua errors since start
#   2  lobby screen open in LOBBY with its content, base team chooser closed after spawn and after gm_showteam, screenshot
#   3  dummy mode cycle LOBBY -> PREMATCH -> PREMATCH (countdown) -> LIVE -> POSTMATCH -> LOBBY, NW2 seq/end
#      on the server and on the client
#   4  rotation: POSTMATCH -> VOTE -> PREMATCH, then pw_abort -> LOBBY with the reason
#   5  map change to gm_flatgrass reaches PREMATCH; abort; changelevel back to gm_construct reaches LOBBY
#   6  pw_reload as the host: server and client reloaded, no "denied"
#   7  file shadowing tests 1, 2 (temporary GMAs and a temporary legacy addon), 4 is MANUAL
#   8  MANUAL steps for the items that need a second human or an admin mod
# The phase ConVars it changes are restored after step 4 (on exit when it stops earlier) and saved by a map change,
# the temporary shadowing files it created are removed by exact path on exit, and the game is left on gm_construct
# in LOBBY. Evidence (log excerpts, screenshots) goes to
# .deck-shots/cp1-<timestamp>/ (git-ignored). Exit code: 0 when no automated check failed, 1 otherwise.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock # held for the whole checkpoint run; deploy/run/test inside re-enter
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

restart=1
for arg in "$@"; do
    case "$arg" in
        --no-restart) restart=0 ;;
        --help)
            sed --quiet '2,/^source /p' "${BASH_SOURCE[0]}" | grep --invert-match '^source '
            exit 0
            ;;
        *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done

stamp="$(date +%Y%m%d-%H%M%S)"
out="$REPO_ROOT/.deck-shots/cp1-$stamp"
mkdir --parents "$out"
home_map="gm_construct"
other_map="gm_flatgrass"

gmod_dir="$(deck_gmod_dir)"
log="$gmod_dir/console.log"
cmd_file="$gmod_dir/data/privatewar_dev/cmd.txt"

# Temporary shadowing fixtures; only these exact paths are ever removed.
shadow_id="s${stamp//-/}"
shadow_data_rel="data/privatewar_cp1"
shadow_data="$gmod_dir/$shadow_data_rel"
shadow_legacy="$gmod_dir/addons/pw_cp1_legacy"
shadow_gmas=(t1ab_a t1ab_b t1ba_a t1ba_b t2_gma)
shadow_created=0

# ---------------------------------------------------------------------------------------------------------------
# Results

declare -a res_id=() res_status=() res_title=() res_detail=()
failures=0

record() {
    local id="$1" status="$2" title="$3" detail="${4:-}"
    res_id+=("$id")
    res_status+=("$status")
    res_title+=("$title")
    res_detail+=("$detail")
    if [[ -n "$detail" ]]; then
        printf '%-6s %-4s %s: %s\n' "$status" "$id" "$title" "$detail"
    else
        printf '%-6s %-4s %s\n' "$status" "$id" "$title"
    fi
}
pass() { record "$1" PASS "$2" "${3:-}"; }
fail() { failures=$((failures + 1)); record "$1" FAIL "$2" "$3"; }
manual() { record "$1" MANUAL "$2" "$3"; }
step() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

# ---------------------------------------------------------------------------------------------------------------
# Deck access: log, bridge, probes

game_running() {
    deck_run "pgrep --full '$GAME_PROCESS_PATTERN' >/dev/null"
}

log_count() {
    deck_run "if [ -f '$log' ]; then wc --lines < '$log'; else echo 0; fi"
}

# log_since <line count>: the log after that many lines. The game writes CRLF under Proton; drop the CR.
log_since() {
    deck_run "tail --lines=+$(($1 + 1)) '$log' 2>/dev/null || true" | tr --delete '\r'
}

# send <line>...: queue bridge lines (same encoding as cmd.sh, without its extra detection round trip).
send() {
    local encoded
    encoded="$(printf '%s\n' "$@" | base64)"
    deck_run "mkdir --parents '$(dirname "$cmd_file")' && printf '%s' '$encoded' | base64 --decode >> '$cmd_file'"
}

# wait_for <since> <timeout s> <regex> [fail regex]: prints the first matching log line after <since>.
# Returns 0 found, 1 timeout, 2 the fail regex matched first.
wait_for() {
    local since="$1" timeout="$2" regex="$3" fail_regex="${4:-}"
    local deadline=$((SECONDS + timeout)) text line
    while ((SECONDS < deadline)); do
        text="$(log_since "$since")"
        line="$(grep --text --extended-regexp --max-count=1 -- "$regex" <<<"$text" || true)"
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
            return 0
        fi
        if [[ -n "$fail_regex" ]]; then
            line="$(grep --text --extended-regexp --max-count=1 -- "$fail_regex" <<<"$text" || true)"
            if [[ -n "$line" ]]; then
                printf '%s\n' "$line"
                return 2
            fi
        fi
        sleep 2
    done
    return 1
}

new_tag() {
    printf 'q%s%s' "$SECONDS" "$RANDOM"
}

# ask <bridge line> <answer regex> [timeout s]: sends the line until the answer appears. The bridge loses lines
# sent while a map loads, so a lost request is simply sent again.
ask() {
    local request="$1" regex="$2" timeout="${3:-90}" since line
    local deadline=$((SECONDS + timeout))
    since="$(log_count)"
    while ((SECONDS < deadline)); do
        send "$request"
        if line="$(wait_for "$since" 12 "$regex")"; then
            printf '%s\n' "$line"
            return 0
        fi
    done
    return 1
}

# ask_server: "[PW] cp1 state ..." line; ask_client: "[PW] cp1 probe ..." line from the host's client.
ask_server() {
    local tag
    tag="$(new_tag)"
    ask "pw_cp1_state $tag" "\[PW\] cp1 state tag=$tag " "${1:-90}"
}
ask_client() {
    local tag
    tag="$(new_tag)"
    ask "client pw_cp1_probe $tag" "\[PW\] cp1 probe tag=$tag " "${1:-90}"
}

# field <line> <key>: value of key=value (values contain no spaces; abort= runs to the end of the line).
field() {
    if [[ "$2" == "abort" ]]; then
        sed --regexp-extended --quiet 's/.* abort=(.*)$/\1/p' <<<"$1"
        return 0
    fi
    grep --only-matching --extended-regexp -- "(^| )$2=[^ ]*" <<<"$1" | head --lines=1 | cut --delimiter='=' --fields=2-
}

# fcheck <awk condition> <name=value>...: numeric comparison with awk.
fcheck() {
    local cond="$1"
    shift
    local args=()
    for kv in "$@"; do args+=(-v "$kv"); done
    awk "${args[@]}" "BEGIN { exit !($cond) }"
}

# GMod prints a Lua error as "[ERROR] ..." or "[<addon>] <message>" followed by stack lines "  1. fn - file.lua:58".
errors_regex='\[ERROR\]|\.lua:[0-9]+: |^ +1\. .* - .*\.lua:[0-9]+$|stack traceback|devbridge lua error|blocked!|Couldn.t (load|include)'

# errors_since <since>: Lua error lines after <since>.
errors_since() {
    log_since "$1" | grep --text --extended-regexp -- "$errors_regex" || true
}

# tests_result <since> <timeout>: waits for the GLuaTest summary line and checks failed=0.
# Sets tests_line; returns 0 passed, 1 failed, 2 no result.
tests_line=""
tests_result() {
    tests_line="$(wait_for "$1" "$2" '\[PW\] tests finished: passed=[0-9]+ failed=[0-9]+')" || return 2
    local passed failed
    passed="$(sed --regexp-extended 's/.*passed=([0-9]+).*/\1/' <<<"$tests_line")"
    failed="$(sed --regexp-extended 's/.*failed=([0-9]+).*/\1/' <<<"$tests_line")"
    if ((failed == 0 && passed > 0)); then return 0; fi
    return 1
}

# wait_map <map> <since> <timeout>: the server answers on <map> (after a changelevel).
wait_map() {
    local map="$1" since="$2" timeout="$3" deadline state
    deadline=$((SECONDS + timeout))
    wait_for "$since" "$timeout" "\[PW\] Private War .* server loaded" >/dev/null || return 1
    while ((SECONDS < deadline)); do
        if state="$(ask_server 30)" && [[ "$(field "$state" map)" == "$map" ]]; then
            printf '%s\n' "$state"
            return 0
        fi
        sleep 3
    done
    return 1
}

screenshot() {
    local name="$1" path
    if path="$("$here/shot.sh" "$out" 2>/dev/null)"; then
        mv "$path" "$out/$name.jpg"
        note "screenshot: $out/$name.jpg"
        return 0
    fi
    note "screenshot $name: no new screenshot appeared"
    return 1
}

# ---------------------------------------------------------------------------------------------------------------
# ConVars: saved before the first change, restored after step 4 (or on exit when the run stops earlier)

declare -A saved_cvars=()
cvar_names=(pw_countdown pw_postmatch_time pw_vote_time pw_aftermatch)
cvar_defaults=([0]=10 [1]=15 [2]=15 [3]=lobby)

save_cvars() {
    local state="$1" name value
    for name in "${cvar_names[@]}"; do
        value="$(field "$state" "$name")"
        if [[ -z "$value" || "$value" == "?" ]]; then return 1; fi
        saved_cvars[$name]="$value"
    done
    for name in "${cvar_names[@]}"; do note "saved $name=${saved_cvars[$name]}"; done
}

restore_cvars() {
    if ((${#saved_cvars[@]} == 0)); then return 0; fi
    local lines=() name state ok=1 i=0
    for name in "${cvar_names[@]}"; do lines+=("$name ${saved_cvars[$name]}"); done
    send "${lines[@]}"
    if state="$(ask_server 60)"; then
        for name in "${cvar_names[@]}"; do
            if [[ "$(field "$state" "$name")" != "${saved_cvars[$name]}" ]]; then ok=0; fi
        done
    else
        ok=0
    fi
    if ((ok == 1)); then
        note "restored ${lines[*]}"
        for name in "${cvar_names[@]}"; do
            if [[ "${saved_cvars[$name]}" != "${cvar_defaults[$i]}" ]]; then
                note "warning: $name was ${saved_cvars[$name]} before this run (default ${cvar_defaults[$i]})"
            fi
            i=$((i + 1))
        done
        saved_cvars=()
    else
        note "warning: could not confirm the restored ConVars; set them by hand: ${lines[*]}"
    fi
}

# ---------------------------------------------------------------------------------------------------------------
# Shadowing fixtures (notes/09 "To verify in game" tests 1 and 2)

# A GMA (format v3, as gmad writes it) with one Lua file that returns its own name. Built on the Deck with python3.
make_shadow_fixtures() {
    deck_run "set -o errexit; mkdir --parents '$shadow_data' '$shadow_legacy/lua/pw_cp1_shadow/t2_$shadow_id'
printf 'return \"legacy\"\n' > '$shadow_legacy/lua/pw_cp1_shadow/t2_$shadow_id/tdm.lua'
cd '$shadow_data'
python3 - '$shadow_id' <<'PY'
import struct, sys, time, zlib
sid = sys.argv[1]
def gma(out, path, name):
    body = ('return \"%s\"\n' % name).encode()
    head = b'GMAD' + bytes([3]) + struct.pack('<QQ', 0, int(time.time())) + b'\0'
    head += b'pw_cp1 ' + name.encode() + b'\0' + b'{\"description\":\"cp1\",\"type\":\"tool\",\"tags\":[]}\0'
    head += b'cp1\0' + struct.pack('<i', 1)
    head += struct.pack('<I', 1) + path.encode() + b'\0' + struct.pack('<qI', len(body), zlib.crc32(body))
    head += struct.pack('<I', 0)
    data = head + body
    with open(out, 'wb') as f:
        f.write(data + struct.pack('<I', 0))
gma('t1ab_a.gma', 'lua/pw_cp1_shadow/t1ab_%s/tdm.lua' % sid, 'A')
gma('t1ab_b.gma', 'lua/pw_cp1_shadow/t1ab_%s/tdm.lua' % sid, 'B')
gma('t1ba_a.gma', 'lua/pw_cp1_shadow/t1ba_%s/tdm.lua' % sid, 'A')
gma('t1ba_b.gma', 'lua/pw_cp1_shadow/t1ba_%s/tdm.lua' % sid, 'B')
gma('t2_gma.gma', 'lua/pw_cp1_shadow/t2_%s/tdm.lua' % sid, 'gma')
PY"
    shadow_created=1
}

remove_shadow_fixtures() {
    if ((shadow_created == 0)); then return 0; fi
    local paths=() name
    for name in "${shadow_gmas[@]}"; do paths+=("'$shadow_data/$name.gma'"); done
    deck_run "rm --force ${paths[*]}
rm --recursive --force '$shadow_legacy'
rmdir --ignore-fail-on-non-empty '$shadow_data' 2>/dev/null || true" || true
    shadow_created=0
    note "removed the temporary shadowing files (data/privatewar_cp1/*.gma, addons/pw_cp1_legacy)"
}

# ---------------------------------------------------------------------------------------------------------------
# Exit: leave the game on gm_construct in LOBBY with the saved ConVars, save evidence, print the summary

run_since=0

leave_home() {
    game_running || return 0
    local state since
    state="$(ask_server 120)" || { note "warning: the server does not answer; state unknown"; return 0; }
    if [[ "$(field "$state" map)" != "$home_map" ]]; then
        since="$(log_count)"
        send "changelevel $home_map"
        state="$(wait_map "$home_map" "$since" 240)" || { note "warning: could not change back to $home_map"; return 0; }
        # The auto-run GLuaTest drives the live machine (match_rules smoke): read the phase after it.
        tests_result "$since" 180 || true
        state="$(ask_server)" || { note "warning: the server does not answer; state unknown"; return 0; }
    fi
    if [[ "$(field "$state" phase)" != "LOBBY" ]]; then
        send "pw_abort cp1 cleanup"
        sleep 3
    fi
}

summary() {
    local i n="${#res_id[@]}"
    printf '\n== Summary (%s)\n' "$out"
    printf '%-4s | %-6s | %s\n' "ID" "RESULT" "CHECK"
    printf '%s\n' "-----+--------+-------------------------------------------------------------"
    for ((i = 0; i < n; i++)); do
        printf '%-4s | %-6s | %s\n' "${res_id[$i]}" "${res_status[$i]}" "${res_title[$i]}"
    done
    printf '\nPASS %d, FAIL %d, MANUAL %d\n' \
        "$(printf '%s\n' "${res_status[@]}" | grep --count '^PASS$' || true)" "$failures" \
        "$(printf '%s\n' "${res_status[@]}" | grep --count '^MANUAL$' || true)"
}

on_exit() {
    local code=$?
    set +o errexit
    step "Cleanup"
    remove_shadow_fixtures
    leave_home
    if ((${#saved_cvars[@]} > 0)) && game_running; then
        restore_cvars
        # Persist the restored values (see step 4): one more map change writes cfg/server.vdf.
        local since
        since="$(log_count)"
        send "changelevel $home_map"
        if wait_map "$home_map" "$since" 240 >/dev/null; then
            # Leave the game after the auto-run GLuaTest, whose smoke changes the phase ConVars for a moment.
            tests_result "$since" 180 || note "warning: no GLuaTest result after the final map change"
        else
            note "warning: the map change that saves the ConVars failed"
        fi
    fi
    if game_running; then
        log_since "$run_since" >"$out/console.log"
        grep --text --extended-regexp -- '\[PW\]|GLuaTest|'"$errors_regex" "$out/console.log" \
            >"$out/console-filtered.log" || true
        note "log of this run: $out/console.log (filtered: console-filtered.log)"
    fi
    {
        summary
        local i
        printf '\nDetails\n'
        for ((i = 0; i < ${#res_id[@]}; i++)); do
            printf '%s %s %s: %s\n' "${res_status[$i]}" "${res_id[$i]}" "${res_title[$i]}" "${res_detail[$i]}"
        done
    } | tee "$out/summary.txt" | sed --quiet '1,/^Details$/p' | grep --invert-match '^Details$'
    if ((code != 0)); then
        echo "cp1: stopped early (exit $code)" >&2
        exit "$code"
    fi
    if ((failures > 0)); then exit 1; fi
    exit 0
}
trap on_exit EXIT

# ===============================================================================================================
step "1. Deploy, start on $home_map, GLuaTest"

# Stale bridge lines from an earlier session must not run in this one.
deck_run "if [ -f '$cmd_file' ]; then : > '$cmd_file'; fi"
make_shadow_fixtures
"$here/deploy.sh" >"$out/deploy.txt"
if [[ -n "${PW_GLUATEST:-}" ]]; then
    rsync --archive --compress --delete --chmod=u+w --exclude='tests/' --rsh="ssh ${SSH_OPTS[*]}" \
        "$PW_GLUATEST/lua" "$DECK_TARGET:$gmod_dir/addons/gluatest/"
else
    note "PW_GLUATEST is not set: GLuaTest on the Deck is not updated (run through nix develop --command)"
fi
deck_run "rm --force '$gmod_dir/data/privatewar_dev/test_result.txt' '$gmod_dir/data/privatewar_dev/skip_tests.txt'"

legacy_mounted=0
if ! game_running; then
    PW_MAP="$home_map" "$here/run.sh" >/dev/null
    legacy_mounted=1
    run_since=0
elif ((restart == 1)); then
    "$here/stop.sh" >/dev/null
    for _ in $(seq 1 60); do game_running || break; sleep 2; done
    PW_MAP="$home_map" "$here/run.sh" >/dev/null
    legacy_mounted=1
    run_since=0
else
    run_since="$(log_count)"
    send "gamemode privatewar" "map $home_map"
fi
note "waiting for the game, the test gate and GLuaTest (up to 6 min)"

if line="$(wait_for "$run_since" 300 '\[PW\] testgate: starting GLuaTest')"; then
    pass 1.1 "test gate started GLuaTest after the host joined" "${line#*testgate: }"
else
    fail 1.1 "test gate started GLuaTest after the host joined" "no test gate line within 300 s"
fi
if tests_result "$run_since" 180; then
    pass 1.2 "GLuaTest suite passes" "${tests_line#*finished: }"
else
    case $? in
        1) fail 1.2 "GLuaTest suite passes" "${tests_line#*finished: }" ;;
        *) fail 1.2 "GLuaTest suite passes" "no '[PW] tests finished' line within 180 s" ;;
    esac
    exit 1
fi
errors="$(errors_since "$run_since")"
if [[ -z "$errors" ]]; then
    pass 1.3 "no Lua errors in the log since start"
else
    printf '%s\n' "$errors" >"$out/errors-start.txt"
    fail 1.3 "no Lua errors in the log since start" \
        "$(wc --lines <<<"$errors") error lines, first: $(head --lines=1 <<<"$errors") (errors-start.txt)"
fi

# ===============================================================================================================
step "2. Lobby screen and team chooser"

since_client=$run_since
wait_for "$since_client" 90 '\[PW\] cp1 client-phase phase=LOBBY' >/dev/null || true
sleep 2
if probe="$(ask_client)"; then
    note "$probe"
    if [[ "$(field "$probe" teampicker)" == "closed" ]]; then
        pass 2.1 "base team chooser is not open after spawn" "frames=$(field "$probe" frames)"
    else
        fail 2.1 "base team chooser is not open after spawn" "teampicker=open frames=$(field "$probe" frames)"
    fi
    if [[ "$(field "$probe" phase)" == "LOBBY" && "$(field "$probe" lobby)" == "open" && "$(field "$probe" filled)" == "yes" ]]; then
        pass 2.2 "lobby screen is open in LOBBY with its content (server state received)"
    else
        fail 2.2 "lobby screen is open in LOBBY with its content (server state received)" \
            "phase=$(field "$probe" phase) lobby=$(field "$probe" lobby) filled=$(field "$probe" filled)"
    fi
else
    fail 2.1 "base team chooser is not open after spawn" "no answer from the client probe (pw_cp1_probe)"
    fail 2.2 "lobby screen is open in LOBBY with its content (server state received)" \
        "no answer from the client probe (pw_cp1_probe)"
fi
send "client gm_showteam"
sleep 3
if probe="$(ask_client)"; then
    note "$probe"
    if [[ "$(field "$probe" teampicker)" == "closed" ]]; then
        pass 2.3 "base team chooser stays closed after gm_showteam"
    else
        fail 2.3 "base team chooser stays closed after gm_showteam" "teampicker=open frames=$(field "$probe" frames)"
    fi
else
    fail 2.3 "base team chooser stays closed after gm_showteam" "no answer from the client probe"
fi
if screenshot lobby; then
    pass 2.4 "screenshot of the lobby" "lobby.jpg"
else
    fail 2.4 "screenshot of the lobby" "shot.sh found no new screenshot"
fi

# ===============================================================================================================
step "3. Dummy mode: full phase cycle"

# check_cycle <since> <seq before> <id> <expected transitions "FROM>TO:end" ...>
# end: "-" no end (-1), a number = expected duration (seconds of game time, +-0.6), "+" any end in the future.
check_cycle() {
    local since="$1" seq0="$2" id="$3"
    shift 3
    local lines count i expect from to dur line seq nwseq nwphase ends nwend now problems=""
    lines="$(log_since "$since" | grep --text --extended-regexp -- '\[PW\] cp1 phase ' || true)"
    printf '%s\n' "$lines" >"$out/phases-$id.txt"
    count="$(grep --count . <<<"$lines" || true)"
    if ((count < $#)); then
        problems="only $count of $# transitions: $(sed --regexp-extended 's/.*from=([A-Z]+) to=([A-Z]+).*/\1>\2/' <<<"$lines" | paste --serial --delimiters=' ')"
    fi
    i=0
    for expect in "$@"; do
        i=$((i + 1))
        from="${expect%%>*}"
        to="${expect#*>}"
        to="${to%%:*}"
        dur="${expect##*:}"
        line="$(sed --quiet "${i}p" <<<"$lines")"
        [[ -n "$line" ]] || break
        if [[ "$(field "$line" from)" != "$from" || "$(field "$line" to)" != "$to" ]]; then
            problems+=" #$i is $(field "$line" from)>$(field "$line" to), expected $from>$to;"
            continue
        fi
        nwseq="$(field "$line" nwseq)"
        nwphase="$(field "$line" nwphase)"
        ends="$(field "$line" ends)"
        nwend="$(field "$line" nwend)"
        now="$(field "$line" now)"
        seq=$((seq0 + i))
        [[ "$nwseq" == "$seq" ]] || problems+=" $from>$to seq $nwseq, expected $seq;"
        [[ "$nwphase" == "$to" ]] || problems+=" $from>$to NW2 phase $nwphase;"
        fcheck 'a - b < 0.05 && b - a < 0.05' "a=$ends" "b=$nwend" || problems+=" $from>$to NW2 end $nwend != $ends;"
        case "$dur" in
            -) fcheck 'e == -1' "e=$nwend" || problems+=" $from>$to end $nwend, expected none;" ;;
            +) fcheck 'e > n' "e=$nwend" "n=$now" || problems+=" $from>$to end $nwend not after now $now;" ;;
            *) fcheck 'e - n > d - 0.6 && e - n < d + 0.6' "e=$nwend" "n=$now" "d=$dur" \
                || problems+=" $from>$to end-now $(awk -v e="$nwend" -v n="$now" 'BEGIN{print e-n}'), expected $dur;" ;;
        esac
    done
    check_problems="$problems"
    [[ -z "$problems" ]]
}

# check_client <since> <id> <phases...>: the client applied these phases with the server's seq for each.
check_client() {
    local since="$1" id="$2"
    shift 2
    local server client phase cseq sseq problems=""
    server="$(log_since "$since" | grep --text --extended-regexp -- '\[PW\] cp1 phase ' || true)"
    client="$(log_since "$since" | grep --text --extended-regexp -- '\[PW\] cp1 client-phase ' || true)"
    printf '%s\n' "$client" >"$out/client-phases-$id.txt"
    for phase in "$@"; do
        cseq="$(grep --text -- "phase=$phase " <<<"$client" | while read -r l; do field "$l" seq; done | paste --serial --delimiters=' ')"
        if [[ -z "$cseq" ]]; then
            problems+=" client never applied $phase;"
            continue
        fi
        for s in $cseq; do
            sseq="$(grep --text -- " nwseq=$s " <<<"$server" | head --lines=1)"
            if [[ -z "$sseq" || "$(field "$sseq" to)" != "$phase" ]]; then
                problems+=" client $phase seq=$s does not match the server;"
            fi
        done
    done
    check_problems="$problems"
    [[ -z "$problems" ]]
}

state="$(ask_server)" || { fail 3.0 "server state probe answers" "no answer to pw_cp1_state"; exit 1; }
note "$state"
save_cvars "$state" || { fail 3.0 "read the phase ConVars" "missing in: $state"; exit 1; }
if [[ "$(field "$state" phase)" != "LOBBY" ]]; then
    send "pw_abort cp1 start from LOBBY"
    sleep 3
fi
send "pw_countdown 5" "pw_postmatch_time 5" "pw_vote_time 5" "pw_aftermatch lobby"
sleep 2
state="$(ask_server)"
seq0="$(field "$state" nwseq)"
note "phase=$(field "$state" phase) seq=$seq0 countdown=$(field "$state" pw_countdown) postmatch=$(field "$state" pw_postmatch_time)"

since="$(log_count)"
send "pw_dev_start"
live_line="$(wait_for "$since" 120 '\[PW\] cp1 phase from=PREMATCH to=LIVE ' '\[PW\] cp1 phase from=[A-Z]+ to=LOBBY ')" || true
if [[ "$live_line" == *"to=LIVE"* ]]; then
    if probe="$(ask_client 30)"; then
        note "client during LIVE: $probe"
        lseq="$(field "$live_line" nwseq)"
        if [[ "$(field "$probe" phase)" == "LIVE" && "$(field "$probe" seq)" == "$lseq" && "$(field "$probe" end)" == "-1.00" ]]; then
            pass 3.3 "client probe sees LIVE with the server's seq and no end" "seq=$lseq"
        else
            fail 3.3 "client probe sees LIVE with the server's seq and no end" \
                "client phase=$(field "$probe" phase) seq=$(field "$probe" seq) end=$(field "$probe" end), server seq=$lseq"
        fi
    else
        fail 3.3 "client probe sees LIVE with the server's seq and no end" "no answer from the client probe"
    fi
else
    fail 3.3 "client probe sees LIVE with the server's seq and no end" "LIVE not reached within 120 s"
fi
if wait_for "$since" 240 '\[PW\] cp1 phase from=POSTMATCH to=LOBBY ' '\[PW\] cp1 phase from=(PREMATCH|LIVE) to=LOBBY ' >/dev/null; then
    :
fi
sleep 2
if check_cycle "$since" "$seq0" 3 "LOBBY>PREMATCH:+" "PREMATCH>PREMATCH:5" "PREMATCH>LIVE:-" "LIVE>POSTMATCH:5" \
    "POSTMATCH>LOBBY:-"; then
    pass 3.1 "server: LOBBY > PREMATCH > PREMATCH (countdown) > LIVE > POSTMATCH > LOBBY, seq +1 each, ends right" \
        "seq $((seq0 + 1))..$((seq0 + 5)) (phases-3.txt)"
else
    fail 3.1 "server: LOBBY > PREMATCH > PREMATCH (countdown) > LIVE > POSTMATCH > LOBBY, seq +1 each, ends right" \
        "$check_problems (phases-3.txt)"
fi
if check_client "$since" 3 PREMATCH LIVE POSTMATCH LOBBY; then
    pass 3.2 "client applied PREMATCH, LIVE, POSTMATCH, LOBBY with the server's seq"
else
    fail 3.2 "client applied PREMATCH, LIVE, POSTMATCH, LOBBY with the server's seq" "$check_problems"
fi
state="$(ask_server)" || state=""
if [[ "$(field "$state" phase)" == "LOBBY" && "$(field "$state" nwphase)" == "LOBBY" && "$(field "$state" nwend)" == "-1.00" ]]; then
    pass 3.4 "back in LOBBY after the cycle (machine and NW2)"
else
    fail 3.4 "back in LOBBY after the cycle (machine and NW2)" "${state:-no answer}"
fi

# ===============================================================================================================
step "4. Rotation: POSTMATCH > VOTE > PREMATCH, then pw_abort"

state="$(ask_server)" || state=""
seq0="$(field "$state" nwseq)"
send "pw_aftermatch rotation"
sleep 2
since="$(log_count)"
send "pw_dev_start"
if wait_for "$since" 300 '\[PW\] cp1 phase from=VOTE to=PREMATCH ' '\[PW\] cp1 phase from=[A-Z]+ to=LOBBY ' >/dev/null; then
    if check_cycle "$since" "$seq0" 4 "LOBBY>PREMATCH:+" "PREMATCH>PREMATCH:5" "PREMATCH>LIVE:-" "LIVE>POSTMATCH:5" \
        "POSTMATCH>VOTE:5" "VOTE>PREMATCH:+"; then
        pass 4.1 "rotation: POSTMATCH > VOTE > PREMATCH, seq +1 each" "phases-4.txt"
    else
        fail 4.1 "rotation: POSTMATCH > VOTE > PREMATCH, seq +1 each" "$check_problems (phases-4.txt)"
    fi
else
    fail 4.1 "rotation: POSTMATCH > VOTE > PREMATCH, seq +1 each" "VOTE > PREMATCH not seen within 300 s"
fi
since="$(log_count)"
send "pw_abort cp1 rotation check"
if wait_for "$since" 60 '\[PW\] cp1 phase from=[A-Z]+ to=LOBBY ' >/dev/null && state="$(ask_server)" \
    && [[ "$(field "$state" phase)" == "LOBBY" && "$(field "$state" abort)" == "cp1 rotation check" ]]; then
    pass 4.2 "pw_abort returns to LOBBY with the reason" "abort=$(field "$state" abort)"
else
    fail 4.2 "pw_abort returns to LOBBY with the reason" "${state:-no answer}"
fi
# Restore before the map changes of step 5: archived ConVars reach cfg/server.vdf only on a map change (or a
# clean game exit), so a value restored after the last map change would come back at the next game start.
restore_cvars

# ===============================================================================================================
step "5. Map change: $other_map comes up in PREMATCH, back to $home_map in LOBBY"

since="$(log_count)"
send "pw_dev_start $other_map"
if line="$(wait_for "$since" 240 "\[PW\] cp1 phase from=LOBBY to=PREMATCH .*map=$other_map")"; then
    pass 5.1 "$other_map comes up in PREMATCH from the pending file" "nwseq=$(field "$line" nwseq) ends=$(field "$line" ends)"
    since_abort="$(log_count)"
    send "pw_abort cp1 map change check"
    # The first "-> LOBBY" after the abort is the abort's own: the auto-run GLuaTest on this map starts only after
    # the host has loaded, and its match_rules smoke starts a real match from LOBBY. That smoke drives the live
    # machine, so the state is read only after the run has finished (the smoke ends in LOBBY again).
    lobby_line="$(wait_for "$since_abort" 90 "\[PW\] cp1 phase from=[A-Z]+ to=LOBBY .*map=$other_map")" || lobby_line=""
    tests_rc=0
    tests_result "$since" 180 || tests_rc=$?
    state=""
    if [[ -n "$lobby_line" ]] && state="$(ask_server)" && [[ "$(field "$state" phase)" == "LOBBY" ]]; then
        pass 5.2 "pw_abort on $other_map returns to LOBBY" \
            "from=$(field "$lobby_line" from) nwseq=$(field "$lobby_line" nwseq)"
    else
        fail 5.2 "pw_abort on $other_map returns to LOBBY" "lobby line: ${lobby_line:-none}; state: ${state:-no answer}"
    fi
else
    fail 5.1 "$other_map comes up in PREMATCH from the pending file" \
        "no PREMATCH on $other_map within 240 s: $(log_since "$since" | grep --text --extended-regexp 'pending match|changing map|map change' | tail --lines=3 | paste --serial --delimiters='|')"
    tests_rc=0
    tests_result "$since" 180 || tests_rc=$?
fi
if ((tests_rc == 0)); then
    pass 5.3 "GLuaTest passes on $other_map" "${tests_line#*finished: }"
else
    fail 5.3 "GLuaTest passes on $other_map" "${tests_line:-no result within 180 s}"
fi
since="$(log_count)"
send "changelevel $home_map"
if state="$(wait_map "$home_map" "$since" 240)"; then
    tests_result "$since" 180 || true
    state="$(ask_server)" || state=""
    if [[ "$(field "$state" phase)" == "LOBBY" && "$(field "$state" nwphase)" == "LOBBY" ]]; then
        pass 5.4 "changelevel $home_map comes up in LOBBY" "map=$(field "$state" map)"
    else
        fail 5.4 "changelevel $home_map comes up in LOBBY" "${state:-no answer}"
    fi
    if probe="$(ask_client)" && [[ "$(field "$probe" map)" == "$home_map" && "$(field "$probe" phase)" == "LOBBY" \
        && "$(field "$probe" filled)" == "yes" ]]; then
        pass 5.5 "the host's client followed to $home_map and sees the filled lobby"
    else
        fail 5.5 "the host's client followed to $home_map and sees the filled lobby" "${probe:-no answer}"
    fi
else
    fail 5.4 "changelevel $home_map comes up in LOBBY" "the server did not answer on $home_map within 240 s"
fi

# ===============================================================================================================
step "6. pw_reload as the host"

since="$(log_count)"
send "client pw_reload"
sv="$(wait_for "$since" 60 '\[PW\] reloaded \(server, pw_reload by ' '\[PW\] pw_reload denied')" || true
cl="$(wait_for "$since" 60 '\[PW\] reloaded \(client, pw_reload from the server\)')" || true
denied="$(log_since "$since" | grep --text -- 'pw_reload denied' || true)"
if [[ "$sv" == *"reloaded (server"* && -n "$cl" && -z "$denied" ]]; then
    pass 6.1 "pw_reload from the host reloads server and client, no denied" "${sv#*reloaded }"
else
    fail 6.1 "pw_reload from the host reloads server and client, no denied" \
        "server='${sv:-none}' client='${cl:-none}' denied='${denied:-none}'"
fi
errors="$(errors_since "$since")"
if [[ -n "$errors" ]]; then
    fail 6.2 "no Lua errors after pw_reload" "$(head --lines=1 <<<"$errors")"
else
    pass 6.2 "no Lua errors after pw_reload"
fi

# ===============================================================================================================
step "7. File shadowing (notes/09 'To verify in game')"

# shadow_include <tag> <lua path>: prints the winner (what the file returned) or empty.
shadow_include() {
    local line
    line="$(ask "pw_cp1_include $1 $2" "\[PW\] cp1 include tag=$1 " 60)" || return 1
    note "$line" >&2
    field "$line" winner
}
mount_gma() {
    local line
    line="$(ask "pw_cp1_mount $1 $shadow_data_rel/$2.gma" "\[PW\] cp1 mount tag=$1 " 60)" || return 1
    note "$line" >&2
    [[ "$(field "$line" ok)" == "true" ]]
}

t1_ok=1
if ! mount_gma t1ab1 t1ab_a || ! mount_gma t1ab2 t1ab_b; then t1_ok=0; fi
w_ab="$(shadow_include t1ab "pw_cp1_shadow/t1ab_$shadow_id/tdm.lua")" || w_ab=""
if ! mount_gma t1ba1 t1ba_b || ! mount_gma t1ba2 t1ba_a; then t1_ok=0; fi
w_ba="$(shadow_include t1ba "pw_cp1_shadow/t1ba_$shadow_id/tdm.lua")" || w_ba=""
if ((t1_ok == 1)) && [[ "$w_ab" =~ ^[AB]$ && "$w_ba" =~ ^[AB]$ ]]; then
    if [[ "$w_ab" == "A" && "$w_ba" == "B" ]]; then verdict="the first mounted GMA wins"
    elif [[ "$w_ab" == "B" && "$w_ba" == "A" ]]; then verdict="the last mounted GMA wins"
    else verdict="the same GMA wins in both orders (not mount order)"; fi
    pass 7.1 "test 1, GMA vs GMA (game.MountGMA): one file wins" "mount A,B -> $w_ab; mount B,A -> $w_ba: $verdict"
else
    fail 7.1 "test 1, GMA vs GMA (game.MountGMA): one file wins" "mount ok=$t1_ok, winners A,B='$w_ab' B,A='$w_ba'"
fi
manual 7.2 "test 1 with real Workshop items" \
    "publish two private Workshop items with lua/codtest/modes/tdm.lua printing its name, subscribe A then B, start a listen server, run 'lua_run include(\"codtest/modes/tdm.lua\")' and 'whereis lua/codtest/modes/tdm.lua'; unsubscribe both, subscribe B then A, repeat; record the winner each time"

if ((legacy_mounted == 1)); then
    if mount_gma t2 t2_gma; then
        w_t2="$(shadow_include t2 "pw_cp1_shadow/t2_$shadow_id/tdm.lua")" || w_t2=""
        if [[ "$w_t2" == "legacy" || "$w_t2" == "gma" ]]; then
            pass 7.3 "test 2, legacy addon folder vs mounted GMA: one file wins" "winner: $w_t2"
        else
            fail 7.3 "test 2, legacy addon folder vs mounted GMA: one file wins" "include returned '${w_t2:-nothing}'"
        fi
    else
        fail 7.3 "test 2, legacy addon folder vs mounted GMA: one file wins" "could not mount t2_gma.gma"
    fi
else
    manual 7.3 "test 2, legacy addon folder vs mounted GMA" \
        "run this script without --no-restart (a new addons/ folder is mounted only at game start)"
fi
manual 7.4 "test 2 with a real Workshop item" \
    "subscribe to a private Workshop item with lua/codtest/modes/tdm.lua and put the same path in addons/codtest_legacy/ with a different print; restart the game; run 'lua_run include(\"codtest/modes/tdm.lua\")' and 'whereis lua/codtest/modes/tdm.lua'; record the winner"
manual 7.5 "test 4, client consistency (dedicated server)" \
    "on a dedicated server with sv_allowcslua 0 put addons/codtest_sv/lua/codtest/modes/tdm.lua (print 'server') and AddCSLuaFile it from a server autorun; on the client machine put addons/codtest_cl/lua/codtest/modes/tdm.lua (print 'client'); connect; a client autorun sent by the server runs include('codtest/modes/tdm.lua') and prints file.Find('codtest/modes/*', 'LUA'); expect 'server' and only server-sent files; reconnect and check again"

# ===============================================================================================================
step "8. Needs a second human or an admin mod"

manual 8.1 "P2P guest follows changelevel; a new guest joins after it (notes/10 item 2, #6832)" \
    "host: main menu > New Game, Private War, gm_construct, Max Players 12, P2P on; guest joins from the Steam friends list; host runs 'pw_dev_start gm_flatgrass' (or Start in the lobby with another map); guest must load gm_flatgrass without the main menu and without 'invalid sequence ack nr'; repeat 5 times; then a third account joins through Steam 'Join game'. If it fails: apply the fallback of 00-core.md d.9 and tell the orchestrator"
manual 8.2 "guest lobby has no Start and no toggles" \
    "with a guest connected in LOBBY, the guest presses F1: the lobby shows MODE AND MAP and GAME SETUP read-only, no START button, no CONTENT toggles column"
manual 8.3 "late joiner sees the right phase and timer" \
    "host: pw_countdown 30 then pw_dev_start; a guest joins during the PREMATCH countdown and again during LIVE; in the guest console 'pw_cp1_probe late' prints the phase and end; the HUD/console timer must match the host's"
manual 8.4 "guest pw_reload without reconnect" \
    "a connected guest (not superadmin) runs pw_reload in the console: the host log shows 'pw_reload denied for <guest>'; after the host runs pw_reload, the guest console shows '[PW] reloaded (client, pw_reload from the server)' without reconnecting"
manual 8.5 "ULX/SAM privileges; the listen host is superadmin" \
    "install ULX (or SAM), restart; host runs 'lua_run print(Entity(1):IsSuperAdmin(), Entity(1):GetUserGroup())' -> true superadmin; give a guest 'ulx adduser <guest> admin' and check pw_reload/pw_abort are denied; grant 'ulx groupallow admin pw.reload' and check pw_reload works for that guest"

# ===============================================================================================================
step "Whole run"

state="$(ask_server)" || state=""
probe="$(ask_client)" || probe=""
note "$state"
note "$probe"
if [[ "$(field "$state" map)" == "$home_map" && "$(field "$state" phase)" == "LOBBY" \
    && "$(field "$probe" lobby)" == "open" && "$(field "$probe" filled)" == "yes" ]]; then
    pass 9.2 "ends on $home_map in LOBBY with the filled lobby screen"
else
    fail 9.2 "ends on $home_map in LOBBY with the filled lobby screen" \
        "map=$(field "$state" map) phase=$(field "$state" phase) lobby=$(field "$probe" lobby) filled=$(field "$probe" filled)"
fi
screenshot final || true

errors="$(errors_since "$run_since")"
if [[ -z "$errors" ]]; then
    pass 9.1 "no Lua errors in the log during the whole run"
else
    printf '%s\n' "$errors" >"$out/errors-run.txt"
    fail 9.1 "no Lua errors in the log during the whole run" "$(head --lines=1 <<<"$errors") (errors-run.txt)"
fi
