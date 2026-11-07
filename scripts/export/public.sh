#!/usr/bin/env bash
# Builds the public source tree from HEAD (docs/publishing.md). Usage: public.sh <target-dir>
# Only committed content is exported (git archive). Paths in local-only.txt are left out. The tree is verified
# in a scratch directory first; only then is it written into the target. Nothing outside the target is deleted.
set -o errexit -o nounset -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
target_arg="${1:?usage: public.sh <target-dir>}"
list="$here/local-only.txt"

die() {
    echo "[export] $1" >&2
    exit 1
}

mkdir --parents "$target_arg"
target="$(cd "$target_arg" && pwd -P)"
root_real="$(cd "$root" && pwd -P)"

# Refuse targets that are, contain or sit inside the source repository, and system roots.
case "$target" in
    / | "$HOME" | "$root_real" | "$root_real"/*) die "refusing target: $target" ;;
esac
case "$root_real" in
    "$target"/*) die "refusing target that contains the source repository: $target" ;;
esac

# The target must be empty, or a repository root with a clean working tree.
if [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -not -name .DS_Store)" ]]; then
    top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$target" ]] || die "target is not empty and not a repository root: $target"
    [[ -z "$(git -C "$target" status --porcelain)" ]] || die "target repository has uncommitted changes: $target"
fi

scratch="$(mktemp --directory)"
trap 'rm -rf "$scratch"' EXIT
tree="$scratch/tree"
mkdir "$tree"

excludes=()
while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    excludes+=(":(exclude)$path")
done <"$list"

git -C "$root" archive --format=tar HEAD -- . "${excludes[@]}" | tar --extract --directory "$tree"

bash "$here/verify.sh" "$tree" "$list"

if [[ -d "$target/.git" ]]; then
    rsync --archive --delete --exclude=/.git/ "$tree"/ "$target"/
else
    rsync --archive "$tree"/ "$target"/
fi
echo "[export] wrote $(find "$tree" -type f | wc --lines) files into $target"
