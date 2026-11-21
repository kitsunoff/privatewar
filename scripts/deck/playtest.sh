#!/usr/bin/env bash
# Temporarily unmount only the dev bridge and GLuaTest on the next game start.
# Usage: nix develop --command bash scripts/deck/playtest.sh
# Requires explicit Deck access permission and confirmation that it is free.
# Backups stay in garrysmod/.privatewar-playtest-disabled/run.*/<addon>.
# Legacy backups directly under .privatewar-playtest-disabled remain untouched.
# No game commands, restarts, deployment, deletion or automatic restore.
if [[ "$#" != 0 ]]; then
    echo 'Usage: nix develop --command bash scripts/deck/playtest.sh' >&2
    exit 2
fi
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
if ! deck_lock; then
    echo "[playtest] could not acquire the Deck lock" >&2
    exit 75
fi

# deck_gmod_dir splits on spaces; keep the full path from the detection record.
if ! detected="$(deck_detect)" || [[ "$detected" != native\ /* && "$detected" != proton\ /* ]]; then
    echo "[playtest] could not detect the game directory" >&2
    exit 1
fi
gmod_dir="${detected#* }"
if [[ "$gmod_dir" == *$'\n'* ]]; then
    echo "[playtest] invalid game directory detection output" >&2
    exit 1
fi
printf -v remote_dir '%q' "$gmod_dir"
if ! deck_run "gmod_dir=$remote_dir
$(cat <<'REMOTE'
set -o errexit -o nounset -o pipefail
fail() { echo "[playtest] $*" >&2; exit 1; }
addons="$gmod_dir/addons"
backup="$gmod_dir/.privatewar-playtest-disabled"
[[ -d "$gmod_dir" && ! -L "$gmod_dir" && -d "$addons" && ! -L "$addons" ]] \
    || fail 'unsafe game/addons directory; stopped'
if [[ -e "$backup" || -L "$backup" ]]; then
    [[ -d "$backup" && ! -L "$backup" ]] || fail 'unsafe backup directory; stopped'
fi

# Check both names and legacy backups before making any changes.
needed=0
for name in privatewar_dev gluatest; do
    src="$addons/$name"
    dst="$backup/$name"
    if [[ -e "$dst" || -L "$dst" ]]; then
        [[ -d "$dst" && ! -L "$dst" ]] || fail "unsafe backup: $name; stopped"
    fi
    if [[ -e "$src" || -L "$src" ]]; then
        [[ -d "$src" && ! -L "$src" ]] || fail "unsafe addon: $name; stopped"
        needed=1
    fi
done
if [[ "$needed" == 1 ]]; then
    if [[ ! -d "$backup" ]]; then
        mkdir --mode=700 -- "$backup" || fail 'cannot create backup directory'
    fi
    [[ -d "$backup" && ! -L "$backup" ]] || fail 'unsafe backup directory; stopped'
    # Atomic exclusive creation, never a guessed name or a reused legacy backup.
    # Keep moves relative to this directory rather than traversing its path again.
    cd -- "$backup" || fail 'cannot enter backup directory'
    saved="$(mktemp --directory ./run.XXXXXXXXXX)" || fail 'cannot create unique backup directory'
    [[ -d "$saved" && ! -L "$saved" ]] || fail 'unsafe unique backup directory; stopped'
    echo "[playtest] backup directory: $backup/${saved#./}"
fi
for name in privatewar_dev gluatest; do
    src="$addons/$name"
    if [[ -e "$src" || -L "$src" ]]; then
        [[ -d "$src" && ! -L "$src" ]] || fail "unsafe addon: $name; stopped"
        [[ "$needed" == 1 ]] || fail 'addon appeared after preflight; retry'
        dst="$saved/$name"
        # Never overwrite or nest into an existing backup, including a racing one.
        mv --no-clobber --no-target-directory -- "$src" "$dst" \
            || fail "move failed: $name; stopped"
        [[ ! -e "$src" && ! -L "$src" ]] || fail "move refused: $name; stopped"
        echo "[playtest] backed up: $name"
    else
        echo "[playtest] not installed: $name"
    fi
done
echo '[playtest] done; already loaded Lua is unaffected until the next game start'
REMOTE
)"; then
    echo "[playtest] operation failed; inspect addon/backup state before retrying" >&2
    exit 1
fi
