#!/usr/bin/env bash
# tests/branch-model.test.sh — assert the branch model's security property:
# the shipped branch carries no development material.
#
# `omarchy plugin add` clones the whole repository into a user's
# ~/.config/omarchy/plugins/<id>. A root AGENTS.md on the shipped branch is
# therefore content a stranger's coding agent can discover and act on inside
# their own installation (DEVIATIONS.md R11). R13 replaced R11's mechanism —
# "never merge dev into master" — with a curated sync, and this suite is the
# assertion that the mechanism actually held: a plain `git merge dev` on the
# shipped branch turns this suite red instead of shipping worknotes/, skills/,
# orchestration/ and every AGENTS.md to every user.
#
# It is a gate suite because a shipped branch carrying agent instructions is a
# broken plugin, not a stale note.
#
# What it inspects, in this order:
#   1. the matcher in tests/lib/shipped-paths.sh (so a mis-edited list is caught)
#   2. the one fact .githooks/pre-commit has to duplicate: the branch name
#   3. the tree of the shipped branch, from $OMAFAN_SHIPPED_REF or the first
#      resolvable of refs/heads/master and refs/remotes/origin/master
#   4. this working tree, when it *is* a shipped tree (HEAD on the shipped
#      branch, or an installed copy with no git metadata at all)
#
# With no shipped ref resolvable — a shallow, single-branch clone of `dev` — the
# tree check is reported as SKIPPED rather than faked green. CI fetches the ref
# explicitly and asserts the "checked" line, so the skip cannot hide there.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1
source "$repo/tests/lib/harness.sh"
# shellcheck source=tests/lib/shipped-paths.sh
. "$repo/tests/lib/shipped-paths.sh"

# assert_not_dev_path / assert_dev_path — matcher probes, quiet on success.
assert_dev_path() {
    local path="$1"
    if omafan_is_dev_path "$path"; then
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    else
        _HARNESS_FAIL=$((_HARNESS_FAIL + 1))
        printf 'FAIL: %s should be development material\n' "$path" >&2
    fi
}

assert_not_dev_path() {
    local path="$1"
    if omafan_is_dev_path "$path"; then
        _HARNESS_FAIL=$((_HARNESS_FAIL + 1))
        printf 'FAIL: %s is shipped runtime, not development material\n' "$path" >&2
    else
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    fi
}

# assert_clean <label> <newline-separated-path-list> — the load-bearing check.
# Every offender is named, because "something is wrong" is not actionable.
assert_clean() {
    local label="$1" listing="$2"
    local offenders
    offenders="$(printf '%s\n' "$listing" | omafan_dev_paths_in)"
    if [ -z "$offenders" ]; then
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    else
        _HARNESS_FAIL=$((_HARNESS_FAIL + 1))
        printf 'FAIL: %s carries development material:\n' "$label" >&2
        printf '%s\n' "$offenders" | sed 's/^/       /' >&2
        printf '       a release is a curated sync, never a merge:\n' >&2
        printf '       skills/publish-a-release/sync-master.sh (DEVIATIONS.md R13)\n' >&2
    fi
}

# --- 1. the matcher -----------------------------------------------------------
# Every denylist entry, through the same function the hook and the sync use.
assert_dev_path "AGENTS.md"
assert_dev_path "bin/AGENTS.md"
assert_dev_path "tests/AGENTS.md"
assert_dev_path "orchestration/AGENTS.md"
assert_dev_path "worknotes/INDEX.md"
assert_dev_path "orchestration/LEDGER.md"
assert_dev_path "skills/README.md"
assert_dev_path ".githooks/pre-commit"
assert_dev_path "PLAN.md"
assert_dev_path "QUESTIONS.md"
assert_dev_path ".recon/screenshot.png"
assert_dev_path "docs/agents/issue-tracker.md"
assert_dev_path ".omc/state/session.json"
assert_dev_path "tests/fixtures/.omc/scratch"
# An AGENTS.md that nobody has added yet is still caught (the basename rule).
assert_dev_path "docs/AGENTS.md"

# Shipped runtime and operator docs must not trip the matcher, or a release
# would copy nothing.
assert_not_dev_path "Panel.qml"
assert_not_dev_path "Model.js"
assert_not_dev_path "manifest.json"
assert_not_dev_path "bin/omafan-ctl"
assert_not_dev_path "tests/run-all.sh"
assert_not_dev_path "tests/lib/shipped-paths.sh"
assert_not_dev_path "docs/SAFETY.md"
assert_not_dev_path "docs/images/bar-widget.png"
assert_not_dev_path ".github/PULL_REQUEST_TEMPLATE.md"
assert_not_dev_path "README.md"
assert_not_dev_path "DEVIATIONS.md"

# The allowlist must actually cover what it claims to ship.
assert_shipped() {
    local path="$1"
    if omafan_is_shipped_path "$path"; then
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    else
        _HARNESS_FAIL=$((_HARNESS_FAIL + 1))
        printf 'FAIL: %s is not in OMAFAN_SHIPPED_PATHS\n' "$path" >&2
    fi
}
assert_shipped "BarWidget.qml"
assert_shipped "Panel.qml"
assert_shipped "KeyboardHelp.qml"
assert_shipped "Model.js"
assert_shipped "manifest.json"
assert_shipped "preview.png"
assert_shipped "LICENSE"
assert_shipped "bin/omafan-keybindings"
assert_shipped "tests/fixtures/fake-afanctl"
assert_shipped "docs/INSTALL.md"
assert_shipped ".github/ISSUE_TEMPLATE/bug_report.md"
# ... and must not claim to ship what nothing needs at runtime.
assert_eq "no" "$(omafan_is_shipped_path "worknotes/INDEX.md" && echo yes || echo no)" \
    "worknotes/ is outside the allowlist"
assert_eq "no" "$(omafan_is_shipped_path "PLAN.md" && echo yes || echo no)" \
    "PLAN.md is outside the allowlist"

# --- 2. the hook's one duplicated fact ----------------------------------------
# .githooks/pre-commit must decide whether it is on the shipped branch before it
# can read this library, so the branch name appears there as a literal too. That
# is the only copy, and this is the assertion that keeps it honest. The hook is
# development material, so on the shipped branch there is nothing to check.
hook=".githooks/pre-commit"
if [ -r "$hook" ]; then
    assert_eq "1" \
        "$(grep -c "^\[ \"\$branch\" = \"$OMAFAN_SHIPPED_BRANCH\" \] || exit 0\$" "$hook")" \
        "$hook keys on the literal branch name $OMAFAN_SHIPPED_BRANCH"
    # And never on "the default branch", which is now the integration branch.
    assert_eq "0" "$(grep -c 'symbolic-ref.*refs/remotes/origin/HEAD' "$hook")" \
        "$hook does not resolve the default branch"
fi

# --- 3. the shipped branch's tree ---------------------------------------------
shipped_ref=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    for candidate in \
        ${OMAFAN_SHIPPED_REF:-} \
        "refs/heads/$OMAFAN_SHIPPED_BRANCH" \
        "refs/remotes/origin/$OMAFAN_SHIPPED_BRANCH"; do
        [ -n "$candidate" ] || continue
        if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
            shipped_ref="$candidate"
            break
        fi
    done
fi

if [ -n "$shipped_ref" ]; then
    tree="$(git ls-tree -r --name-only "$shipped_ref")"
    assert_clean "$shipped_ref" "$tree"
    printf 'branch-model: checked %s (%s paths, %s)\n' \
        "$shipped_ref" "$(printf '%s\n' "$tree" | grep -c .)" \
        "$(git rev-parse --short "$shipped_ref")"
else
    printf 'branch-model: SKIPPED the tree check — no %s ref in this clone.\n' \
        "$OMAFAN_SHIPPED_BRANCH" >&2
    printf '  fetch it:  git fetch origin %s:refs/remotes/origin/%s\n' \
        "$OMAFAN_SHIPPED_BRANCH" "$OMAFAN_SHIPPED_BRANCH" >&2
fi

# --- 4. this working tree, when it is a shipped tree --------------------------
# Two shapes reach a user: a clone with HEAD on the shipped branch, and the
# installed plugin directory, which the shell copies without git metadata.
head_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")"
if [ "$head_branch" = "$OMAFAN_SHIPPED_BRANCH" ]; then
    assert_clean "the working tree (HEAD on $OMAFAN_SHIPPED_BRANCH)" \
        "$(git ls-files)"
    printf 'branch-model: checked the working tree (HEAD on %s)\n' "$head_branch"
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    assert_clean "this installed tree" \
        "$(find . -type f -not -path './.git/*' | sed 's|^\./||')"
    printf 'branch-model: checked this installed tree (no git metadata)\n'
fi

summarize
