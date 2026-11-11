#!/usr/bin/env bash
# Local fixtures only: the copied script sources fake helpers, never common.sh/SSH.
set -o errexit -o nounset -o pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temp="$(mktemp --directory "${TMPDIR:-/tmp}/pw-playtest.XXXXXXXX")"
trap 'rm --recursive --force -- "$temp"' EXIT
cp -- "$here/playtest.sh" "$temp/playtest.sh"
cat >"$temp/common.sh" <<'STUB'
set -o errexit -o nounset -o pipefail
deck_lock() { return "${MOCK_LOCK_STATUS:-0}"; }
deck_detect() {
    if [[ "${MOCK_DETECT_FAIL:-0}" == 1 ]]; then
        echo 'mock detection failure' >&2
        return 3
    fi
    printf '%s %s\n' "${MOCK_KIND:-native}" "$MOCK_GAME"
}
deck_gmod_dir() { deck_detect | awk '{ print $2 }'; }
deck_run() {
    mv() {
        local dst="${!#}"
        if [[ "${MOCK_RACE:-0}" == 1 ]]; then
            mkdir --parents -- "$dst"
            echo preserved >"$dst/existing"
        elif [[ "${MOCK_RACE:-0}" == symlink ]]; then
            ln --symbolic -- "$MOCK_GAME/data" "$dst"
        fi
        if [[ "${MOCK_FAIL_SECOND:-0}" == 1 && "$dst" == */gluatest ]]; then
            echo 'mock move failure' >&2
            return 1
        fi
        command mv "$@"
    }
    mktemp() {
        if [[ "${MOCK_MKTEMP_FAIL:-0}" == 1 ]]; then
            echo 'mock unique directory failure' >&2
            return 1
        fi
        command mktemp "$@"
    }
    export -f mv mktemp
    bash -c "$1"
}
STUB
count=0
fixture() {
    count=$((count + 1))
    export MOCK_GAME="$temp/case-$count/Game's directory/garrysmod"
    unset MOCK_LOCK_STATUS MOCK_RACE MOCK_FAIL_SECOND MOCK_DETECT_FAIL MOCK_KIND MOCK_MKTEMP_FAIL
    mkdir --parents -- "$MOCK_GAME/addons/privatewar_dev" "$MOCK_GAME/addons/gluatest" \
        "$MOCK_GAME/addons/privatewar" "$MOCK_GAME/data"
    echo bridge >"$MOCK_GAME/addons/privatewar_dev/marker"
    echo tests >"$MOCK_GAME/addons/gluatest/marker"
    echo gameplay >"$MOCK_GAME/addons/privatewar/marker"
    echo user-data >"$MOCK_GAME/data/marker"
    backup="$MOCK_GAME/.privatewar-playtest-disabled"
}
run() { bash "$temp/playtest.sh" "$@" >"$temp/output" 2>&1; }
fail() { cat "$temp/output" >&2; echo "[playtest-selftest] $*" >&2; exit 1; }
reject() { if run "$@"; then fail 'unexpected success'; fi; }
contains() { grep --fixed-strings --quiet -- "$1" "$temp/output" || fail "missing diagnostic: $1"; }
untouched() {
    [[ "$(cat "$MOCK_GAME/addons/privatewar/marker")" == gameplay && \
        "$(cat "$MOCK_GAME/data/marker")" == user-data ]] || fail 'unrelated files changed'
}
sources_present() {
    [[ "$(cat "$MOCK_GAME/addons/privatewar_dev/marker")" == bridge && \
        "$(cat "$MOCK_GAME/addons/gluatest/marker")" == tests ]] || fail 'source changed'
    untouched
}
latest_backup() {
    local matches=("$backup"/run.*)
    saved="${matches[${#matches[@]}-1]}"
    [[ -d "$saved" && ! -L "$saved" ]] || fail 'missing unique backup'
}

fixture
run || fail 'initial backup failed (quoted/spaced path)'
latest_backup
[[ ! -e "$MOCK_GAME/addons/privatewar_dev" && ! -e "$MOCK_GAME/addons/gluatest" ]] || fail 'still mounted'
[[ "$(cat "$saved/privatewar_dev/marker")" == bridge && "$(cat "$saved/gluatest/marker")" == tests ]] || fail 'backup content'
[[ "$(stat --format=%a "$backup")" == 700 ]] || fail 'backup permissions'
[[ "$(stat --format=%a "$saved")" == 700 ]] || fail 'unique backup permissions'
untouched
before="$(find "$backup" -print | sort)"
run || fail 'repeat failed'
contains 'not installed: privatewar_dev'
[[ "$(find "$backup" -print | sort)" == "$before" ]] || fail 'repeat changed backup tree'

fixture
mkdir --parents -- "$backup/gluatest"
echo preserved >"$backup/gluatest/existing"
mkdir -- "$backup/privatewar_dev"
echo old-bridge >"$backup/privatewar_dev/marker"
run || fail 'legacy backup prevented a new backup'
latest_backup
[[ "$(cat "$backup/gluatest/existing")" == preserved && "$(cat "$backup/privatewar_dev/marker")" == old-bridge ]] || fail 'legacy backup changed'
[[ "$(cat "$saved/privatewar_dev/marker")" == bridge && "$(cat "$saved/gluatest/marker")" == tests ]] || fail 'new backup content'
old_saved="$saved"
mkdir -- "$MOCK_GAME/addons/gluatest"
echo replacement >"$MOCK_GAME/addons/gluatest/marker"
run || fail 'reinstalled addon backup failed'
matches=("$backup"/run.*/gluatest/marker)
[[ "${#matches[@]}" == 2 && "$(cat "$old_saved/gluatest/marker")" == tests ]] || fail 'unique backup overwritten'
grep --recursive --quiet --fixed-strings replacement "$backup"/run.* || fail 'replacement lost'
before="$(find "$backup" -print | sort)"
run || fail 'repeat with legacy and unique backups failed'
[[ "$(find "$backup" -print | sort)" == "$before" ]] || fail 'repeat created a backup'
untouched

fixture
mv -- "$MOCK_GAME/addons/privatewar_dev" "$backup-missing"
mv -- "$MOCK_GAME/addons/gluatest" "$backup-missing-tests"
run || fail 'absent addons failed'
contains 'not installed: privatewar_dev'
[[ ! -e "$backup" ]] || fail 'created unnecessary backup'
untouched

fixture
export MOCK_LOCK_STATUS=75
if run; then fail 'lock failure succeeded'; else [[ "$?" == 75 ]] || fail 'wrong lock exit status'; fi
contains 'could not acquire'
sources_present

fixture
reject --unknown
contains 'Usage:'
sources_present

fixture
export MOCK_DETECT_FAIL=1
reject
contains 'mock detection failure'
contains 'could not detect'
sources_present

fixture
export MOCK_KIND=invalid
reject
contains 'could not detect'
sources_present

fixture
export MOCK_KIND=proton
run || fail 'Proton detection failed'
latest_backup
[[ "$(cat "$saved/privatewar_dev/marker")" == bridge ]] || fail 'Proton backup content'
untouched

fixture
mv -- "$MOCK_GAME/addons/gluatest" "$temp/file-addon-$count"
echo invalid >"$MOCK_GAME/addons/gluatest"
reject
contains 'unsafe addon: gluatest'
[[ -d "$MOCK_GAME/addons/privatewar_dev" && ! -e "$backup" ]] || fail 'file source changed bridge'
untouched

fixture
mv -- "$MOCK_GAME/addons/privatewar_dev" "$temp/link-target-$count"
ln --symbolic -- "$temp/link-target-$count" "$MOCK_GAME/addons/privatewar_dev"
reject
contains 'unsafe addon'
[[ -L "$MOCK_GAME/addons/privatewar_dev" && ! -e "$backup" ]] || fail 'source symlink changed'
untouched

fixture
ln --symbolic -- "$temp/nonexistent" "$backup"
reject
contains 'unsafe backup directory'
sources_present

fixture
mkdir -- "$backup"
ln --symbolic -- "$temp/nonexistent" "$backup/gluatest"
reject
contains 'unsafe backup: gluatest'
sources_present

fixture
mv -- "$MOCK_GAME/addons/gluatest" "$temp/absent-$count"
mkdir -- "$backup"
ln --symbolic -- "$temp/nonexistent" "$backup/gluatest"
reject
contains 'unsafe backup: gluatest'
[[ -d "$MOCK_GAME/addons/privatewar_dev" && ! -e "$backup/privatewar_dev" ]] || fail 'unsafe backup changed source'

fixture
echo invalid >"$backup"
reject
contains 'unsafe backup directory'
sources_present

fixture
mv -- "$MOCK_GAME/addons" "$temp/addons-$count"
ln --symbolic -- "$temp/addons-$count" "$MOCK_GAME/addons"
reject
contains 'unsafe game/addons directory'
sources_present

fixture
export MOCK_RACE=1
reject
contains 'move refused: privatewar_dev'
sources_present
latest_backup
[[ "$(cat "$saved/privatewar_dev/existing")" == preserved && ! -e "$saved/privatewar_dev/privatewar_dev" ]] || fail 'racing backup overwritten/nested'

fixture
export MOCK_RACE=symlink
reject
contains 'move refused: privatewar_dev'
sources_present
latest_backup
[[ -L "$saved/privatewar_dev" && ! -e "$MOCK_GAME/data/privatewar_dev" ]] || fail 'racing symlink followed'

fixture
export MOCK_MKTEMP_FAIL=1
reject
contains 'cannot create unique backup directory'
sources_present
[[ -z "$(find "$backup" -mindepth 1 -print)" ]] || fail 'failed reservation changed backup'

fixture
export MOCK_FAIL_SECOND=1
reject
contains 'mock move failure'
contains 'move failed: gluatest'
latest_backup
partial="$saved"
[[ -d "$partial/privatewar_dev" && ! -e "$MOCK_GAME/addons/privatewar_dev" && -d "$MOCK_GAME/addons/gluatest" ]] || fail 'partial state lost'
unset MOCK_FAIL_SECOND
run || fail 'partial retry failed'
contains 'not installed: privatewar_dev'
matches=("$backup"/run.*/gluatest/marker)
[[ "${#matches[@]}" == 1 && "$(cat "${matches[0]}")" == tests && "$(cat "$partial/privatewar_dev/marker")" == bridge ]] || fail 'retry lost data'
untouched

echo "[playtest-selftest] $count local scenarios passed (including repeat and partial retry)"
