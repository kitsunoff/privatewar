#!/usr/bin/env bash
# Prove the documentation gate fails closed on missing discovery/resources/case names.
set -o errexit -o nounset -o pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp --directory)"
trap 'rm --recursive --force "$work"' EXIT
cd "$root"
mkdir --parents "$work/tests/agent-guides"
cp tests/agent-guides/contracts.json "$work/tests/agent-guides/"
# Copy only explicitly checked documents, reference files, source signatures and mapped suites.
{
    jq --raw-output '.documents[], .references[], .symbols[].file' tests/agent-guides/contracts.json
    for id in $(jq --raw-output '.skills[]' tests/agent-guides/contracts.json); do
        find ".opencode/skills/$id/evals" -type f
    done
    sed --quiet 's/^| T-[^|]*|[^|]*| *\([^|]*\.lua\) *|.*/addons\/privatewar\/lua\/tests\/privatewar\/\1/p' docs/agent-test-map.md
    echo TASKS.md
} | sed 's/ *$//' | sort --unique | while IFS= read -r path; do
    mkdir --parents "$work/$(dirname "$path")"
    cp "$path" "$work/$path"
done
# Copy link targets from the actual documents, not a second manually maintained list.
while IFS= read -r doc; do
    while IFS= read -r target; do
        case "$target" in https:*|http:*|\#*) continue ;; esac
        target="${target%%#*}"
        path="$(dirname "$doc")/$target"
        if [[ -d "$root/$path" ]]; then
            mkdir --parents "$work/$path"
        elif [[ ! -e "$work/$path" ]]; then
            mkdir --parents "$work/$(dirname "$path")"
            cp "$root/$path" "$work/$path"
        fi
    done < <(grep --only-matching --extended-regexp '\]\([^)]*\)' "$root/$doc" | sed 's/^](//; s/)$//' || true)
done < <(jq --raw-output '.documents[]' tests/agent-guides/contracts.json)
check() { PW_GUIDES_ROOT="$work" bash "$root/scripts/check/agent-guides.sh"; }
check
reject() {
    local reason="$1"
    if check >"$work/result" 2>&1; then
        echo "[agent-guides-selftest] FAIL: accepted $reason" >&2
        exit 1
    fi
    grep --fixed-strings --quiet -- "$reason" "$work/result"
    echo "[agent-guides-selftest] ok: rejects $reason"
}
skill="$work/.opencode/skills/privatewar-mode/SKILL.md"
mv "$skill" "$skill.saved"
reject 'missing file: .opencode/skills/privatewar-mode/SKILL.md'
mv "$skill.saved" "$skill"
sed --in-place 's/name: privatewar-mode/name: wrong-id/' "$skill"
reject 'lacks: name: privatewar-mode'
sed --in-place 's/name: wrong-id/name: privatewar-mode/' "$skill"
printf '\n[Missing](missing-resource.md)\n' >>"$skill"
reject 'broken link: missing-resource.md'
sed --in-place '/\[Missing\](missing-resource.md)/d' "$skill"
suite="$work/addons/privatewar/lua/tests/privatewar/modes_tdm_ffa.lua"
sed --in-place 's/Win by score limit: TDM Think/Changed case: TDM Think/' "$suite"
reject 'lacks: name = "Win by score limit: TDM Think'
echo '[agent-guides-selftest] ok: four negative fixtures, no game access'
