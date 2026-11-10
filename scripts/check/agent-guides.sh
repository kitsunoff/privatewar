#!/usr/bin/env bash
# Static contracts for agent guidance. No network, model invocation or game access.
set -o errexit -o nounset -o pipefail
root="${PW_GUIDES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
manifest="$root/tests/agent-guides/contracts.json"
fail() { echo "[agent-guides] FAIL: $*" >&2; exit 1; }
file() { [[ -f "$root/$1" ]] || fail "missing file: $1"; }
contains() { grep --fixed-strings --quiet -- "$2" "$root/$1" || fail "$1 lacks: $2"; }

file tests/agent-guides/contracts.json
jq --exit-status '.skills | length == 4' "$manifest" >/dev/null
while IFS= read -r id; do
    path=".opencode/skills/$id/SKILL.md"
    file "$path"
    [[ $(head --lines=1 "$root/$path") == '---' ]] || fail "$path lacks frontmatter"
    contains "$path" "name: $id"
    contains "$path" "description: "
    grep --extended-regexp --quiet '^description: .+' "$root/$path" || fail "$path has empty description"
    if grep --extended-regexp --quiet 'disable-model-invocation: true|opencode/autoinvoke: false' "$root/$path"; then
        fail "$path is hidden from model discovery"
    fi
    contains AGENTS.md "$path"
    contains "$path" "../../../docs/agent-workflow.md"
    for step in 1 2 3 4 5 6; do contains "$path" "$step. "; done
    for heading in "## Ownership" "## Tests first" "## Stop conditions"; do contains "$path" "$heading"; done
    [[ $(wc --lines <"$root/$path") -lt 500 ]] || fail "$path exceeds progressive-disclosure limit"
    for case in implement safety; do
        base=".opencode/skills/$id/evals/$case"
        file "$base/prompt.md"
        contains "$base/case.yaml" 'schema_version: "1.1"'
        contains "$base/case.yaml" "name: $case"
        contains "$base/graders/01-contract.md" 'focus: trace'
    done
done < <(jq --raw-output '.skills[]' "$manifest")

while IFS= read -r path; do file "$path"; done < <(jq --raw-output '.references[]' "$manifest")
while IFS=$'\t' read -r path symbol; do contains "$path" "$symbol"; done \
    < <(jq --raw-output '.symbols[] | [.file, .text] | @tsv' "$manifest")
[[ $(grep --count '^| T-' "$root/docs/agent-test-map.md") -ge 50 ]] || fail 'mandatory case map was truncated'
while IFS='|' read -r _ task mandatory suite name _; do
    task="$(sed 's/^ *//; s/ *$//' <<<"$task")"
    mandatory="$(sed 's/^ *//; s/ *$//' <<<"$mandatory")"
    suite="addons/privatewar/lua/tests/privatewar/$(sed 's/^ *//; s/ *$//' <<<"$suite")"
    name="$(sed 's/^ *//; s/ *$//' <<<"$name")"
    contains TASKS.md "$mandatory"
    contains "$suite" "name = \"$name\""
done < <(grep '^| T-' "$root/docs/agent-test-map.md")

# Check local Markdown links in the new guidance, including resources relative to SKILL.md.
while IFS= read -r doc; do
    while IFS= read -r target; do
        case "$target" in https:*|http:*|\#*) continue ;; esac
        target="${target%%#*}"
        [[ -e "$root/$(dirname "$doc")/$target" ]] || fail "$doc has broken link: $target"
    done < <(grep --only-matching --extended-regexp '\]\([^)]*\)' "$root/$doc" | sed 's/^](//; s/)$//' || true)
done < <(jq --raw-output '.documents[]' "$manifest")
echo '[agent-guides] ok: discovery, structure, links, source signatures and mandatory case references'
