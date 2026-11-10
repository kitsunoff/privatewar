#!/usr/bin/env bash
# Bounded controlled fixture, explicit invocation only. The measured AI is never overridden.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
deck_lock
here="$(dirname "${BASH_SOURCE[0]}")"
tag="${1:?usage: cover-budget.sh <alphanumeric-tag>}"
[[ "$tag" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
out="${PW_COVER_OUTPUT:?set PW_COVER_OUTPUT to a private evidence directory}/$tag"
mkdir --parents "$out"
git rev-parse HEAD > "$out/revision.txt"
gmod_dir="$(deck_gmod_dir)"
"$here/snap.sh" 'lua rawset(_G,"PWCoverBudgetScene",include("privatewar_dev/cover_budget_scene.lua"))'
for count in 1 2 5 10; do
    success=0
    for attempt in 1 2; do
        label="${tag}_n${count}_try${attempt}"
        "$here/cmd.sh" "lua PWCoverBudgetScene.Run(\"$label\",$count)"
        sleep 45
        if deck_run "cat '$gmod_dir/data/privatewar_dev/cover_budget_$label.json'" > "$out/$label.json"; then
            success=1
            break
        fi
        "$here/logs.sh" --once > "$out/$label.log"
        echo "[coverbudget] no capture for $label; retry only once" >&2
    done
    [[ "$success" == 1 ]] || exit 1
done
"$here/cmd.sh" 'lua PWCoverBudgetScene.Stop(); rawset(_G,"PWCoverBudgetScene",nil)'
"$here/logs.sh" --once > "$out/console.log"
echo "[coverbudget] evidence: $out"
