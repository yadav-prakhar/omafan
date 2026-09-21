#!/usr/bin/env bash
# skills/publish-a-release/sync-master.sh — cut a release by copying the shipped
# path allowlist from the integration branch onto the shipped branch.
#
# A release is a curated sync, never a merge (DEVIATIONS.md R13, issue #2).
# `omarchy plugin add` clones the whole repository into a user's
# ~/.config/omarchy/plugins/<id>, so `git merge dev` on the shipped branch would
# put worknotes/, orchestration/, skills/, PLAN.md and every AGENTS.md inside a
# stranger's installation, where their coding agent can read and act on it. This
# script copies only OMAFAN_SHIPPED_PATHS, prunes OMAFAN_DEV_PATHS from what it
# copied, and refuses outright if any development path survives.
#
# It lives in skills/ rather than bin/ because bin/ is itself on the shipped
# allowlist: a release tool placed there would ship to every user's install,
# which is the thing the allowlist exists to prevent. skills/ is denied, so this
# script stays on the integration branch beside the SKILL.md that documents it.
# (orchestration/ is the frozen build-era record and takes no new tools — R12.)
#
# Usage:
#   sync-master.sh [--from <ref>] [--full-diff]           # review only (default)
#   sync-master.sh [--from <ref>] --commit [--tag vX.Y.Z] # and write it
#
#   --from <ref>    source of the shipped paths (default: dev)
#   --full-diff     print the whole diff instead of the per-file stat
#   --commit        commit the staged sync onto the shipped branch
#   --tag <tag>     annotated tag on that commit; needs --commit
#
# Nothing is written without --commit: the default run stages the sync in a
# throwaway worktree, prints the diff for review, and removes it again. Running
# it twice is safe — a sync that changes nothing reports "already in sync" and
# exits 0.
#
# Exit codes: 0 ok · 1 runtime failure · 2 usage error.
set -euo pipefail

from="dev"
do_commit=0
full_diff=0
tag=""

die() { # die <exit-code> <line...>
    local rc="$1"
    shift
    printf 'sync-master: %s\n' "$1" >&2
    shift || true
    for line in "$@"; do
        printf '  %s\n' "$line" >&2
    done
    exit "$rc"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --from)
            [ $# -ge 2 ] || die 2 "--from needs a ref" "example: --from dev"
            from="$2"
            shift 2
            ;;
        --tag)
            [ $# -ge 2 ] || die 2 "--tag needs a tag name" "example: --tag v1.0.1"
            tag="$2"
            shift 2
            ;;
        --commit)
            do_commit=1
            shift
            ;;
        --full-diff)
            full_diff=1
            shift
            ;;
        -h | --help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            die 2 "unknown argument: $1" "run with --help for the usage"
            ;;
    esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
cd "$repo"
# shellcheck source=tests/lib/shipped-paths.sh
. "$repo/tests/lib/shipped-paths.sh"
shipped="$OMAFAN_SHIPPED_BRANCH"

[ "$do_commit" = 1 ] || [ -z "$tag" ] || die 2 \
    "--tag needs --commit" "there is no commit to tag in a review run"

git rev-parse --verify --quiet "$from" >/dev/null 2>&1 || die 2 \
    "no such ref: $from" "fetch it:  git fetch origin $from"
git rev-parse --verify --quiet "refs/heads/$shipped" >/dev/null 2>&1 || die 1 \
    "no local $shipped branch to sync onto" \
    "create it:  git branch $shipped origin/$shipped"

from_sha="$(git rev-parse --short "$from")"
from_subject="$(git log -1 --format=%s "$from")"

# The sync happens in a throwaway worktree, so the operator's checkout — and
# whatever is half-finished in it — is never touched.
worktree="$(mktemp -d "${TMPDIR:-/tmp}/omafan-release.XXXXXX")"
rmdir "$worktree"
cleanup() {
    git worktree remove --force "$worktree" >/dev/null 2>&1 || true
    rm -rf -- "$worktree"
}
trap cleanup EXIT

git worktree add --quiet "$worktree" "$shipped" || die 1 \
    "cannot check out $shipped in a worktree" \
    "it is probably checked out elsewhere:  git worktree list"

printf 'sync-master: %s  ->  %s\n' "$from" "$shipped"
printf '  source:   %s %s ("%s")\n' "$from" "$from_sha" "$from_subject"
printf '  onto:     %s %s\n' "$shipped" "$(git rev-parse --short "$shipped")"
printf '  worktree: %s\n\n' "$worktree"

# --- copy the allowlist, entry by entry ---------------------------------------
# Each entry is replaced outright rather than merged, so a file deleted on the
# source ref disappears from the shipped branch instead of lingering.
missing=""
for entry in $OMAFAN_SHIPPED_PATHS; do
    case "$entry" in
        "" | . | .. | /* | */../* | *..)
            die 1 "refusing an unsafe allowlist entry: [$entry]" \
                "fix OMAFAN_SHIPPED_PATHS in tests/lib/shipped-paths.sh"
            ;;
    esac
    rm -rf -- "${worktree:?}/${entry%/}"
    if [ -z "$(git ls-tree -r --name-only "$from" -- "$entry")" ]; then
        missing="$missing $entry"
        continue
    fi
    git archive --format=tar "$from" -- "$entry" | tar -x -C "$worktree"
done

if [ -n "$missing" ]; then
    printf 'not on %s, so removed from %s:%s\n\n' "$from" "$shipped" "$missing"
fi

# --- prune development material the allowlist swept up ------------------------
# bin/AGENTS.md, tests/AGENTS.md and docs/agents/ all sit *inside* allowlisted
# directories, so the denylist is a filter over what was copied and not merely
# the complement of the allowlist.
pruned=0
while IFS= read -r file; do
    if omafan_is_dev_path "$file"; then
        rm -rf -- "$worktree/$file"
        printf 'pruned (development material): %s\n' "$file"
        pruned=$((pruned + 1))
    fi
done <<EOF
$(cd "$worktree" && find . -type f -not -path './.git/*' | sed 's|^\./||' | sort)
EOF
[ "$pruned" -eq 0 ] || printf '\n'

git -C "$worktree" add -A

# --- refuse if any development path survived ----------------------------------
# The prune above should make this impossible; it is asserted anyway, because a
# silent hole here ships agent instructions to every user (R11).
offenders="$(git -C "$worktree" diff --cached --name-only | omafan_dev_paths_in)"
if [ -n "$offenders" ]; then
    printf 'sync-master: refusing to write development material to %s\n\n' "$shipped" >&2
    printf '%s\n' "$offenders" | sed 's/^/  /' >&2
    die 1 "the denylist prune did not hold — this is a bug in this script" \
        "lists: tests/lib/shipped-paths.sh" \
        "guard: tests/branch-model.test.sh"
fi

if [ ! -f "$worktree/manifest.json" ]; then
    die 1 "no manifest.json in the synced tree" \
        "$shipped must stay a valid plugin: omarchy plugin validate . reads it" \
        "check that manifest.json exists on $from"
fi

# --- what is carried over untouched -------------------------------------------
# Paths already tracked on the shipped branch that are neither copied nor
# denied. They survive; naming them keeps that an explicit decision rather than
# an accident (`.gitignore` is the one in the tree today).
carried=""
while IFS= read -r file; do
    [ -n "$file" ] || continue
    if ! omafan_is_shipped_path "$file" && ! omafan_is_dev_path "$file"; then
        carried="$carried $file"
    fi
done <<EOF
$(git -C "$worktree" ls-files)
EOF
if [ -n "$carried" ]; then
    printf 'carried over untouched (outside the allowlist, not denied):%s\n\n' "$carried"
fi

# --- review -------------------------------------------------------------------
if git -C "$worktree" diff --cached --quiet; then
    printf '%s is already in sync with %s — nothing to commit.\n' "$shipped" "$from"
    exit 0
fi

printf '%s\n' "--- what this release would change on $shipped ---"
if [ "$full_diff" = 1 ]; then
    git -C "$worktree" --no-pager diff --cached
else
    git -C "$worktree" --no-pager diff --cached --stat
fi
printf '%s\n\n' "--- end of diff ---"

if [ "$do_commit" != 1 ]; then
    cat <<MSG
Review run: nothing was written. $shipped is unchanged.

  re-run with the whole diff:  $0 --from $from --full-diff
  write it:                    $0 --from $from --commit [--tag vX.Y.Z]
MSG
    exit 0
fi

# --- commit and tag -----------------------------------------------------------
git -C "$worktree" commit --quiet -F - <<MSG
release: sync $shipped from $from at $from_sha

A curated sync, not a merge: only the shipped path allowlist in
tests/lib/shipped-paths.sh was copied, and every development path was pruned
and then asserted absent. A plain merge would put worknotes/, orchestration/,
skills/ and every AGENTS.md into every user's ~/.config/omarchy/plugins/<id>
(DEVIATIONS.md R11, mechanism replaced by R13; issue #2).

source: $from $from_sha ("$from_subject")

  skills/publish-a-release/sync-master.sh --from $from --commit
  bash tests/branch-model.test.sh   ->  the guard that keeps this honest
MSG
new_sha="$(git -C "$worktree" rev-parse --short HEAD)"
printf 'committed %s on %s\n' "$new_sha" "$shipped"

if [ -n "$tag" ]; then
    if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null 2>&1; then
        die 1 "tag $tag already exists" \
            "pick the next version, or delete it:  git tag -d $tag"
    fi
    git -C "$worktree" tag -a "$tag" -m "omafan $tag"
    printf 'tagged %s at %s\n' "$tag" "$new_sha"
fi

cat <<MSG

Not pushed. Check it, then push:

  bash tests/branch-model.test.sh          # the shipped tree carries no dev material
  git push origin $shipped${tag:+ --follow-tags}
MSG
