#!/bin/sh
# .githooks/guard.sh — the body shared by pre-commit and pre-merge-commit.
#
# Refuse to put development material on the shipped branch. `omarchy plugin add`
# clones the whole repository into a user's shell config, so the shipped branch
# carries the plugin, its tests and the operator documentation only
# (DEVIATIONS.md R11, R13).
#
# Sourced by the hooks from their own directory, so a copy in .git/hooks/ finds
# it there and a core.hooksPath install finds it in .githooks/. Never `set`
# anything: the caller owns its own shell options.
#
# omafan_guard <hook-name> <mode>
#   staged  what this commit adds or changes (pre-commit). Deliberately not the
#           whole tree: on a `master` that a merge already poisoned, checking
#           the tree would refuse every subsequent commit, including the ones
#           that repair it.
#   tree    what the resulting commit will contain (pre-merge-commit). A merge's
#           whole purpose is bulk import, so the tree is the question — a merge
#           of `dev` adds no "staged change" the ACMR filter would attribute to
#           it in the way a normal commit does.
omafan_guard() {
    _g_hook="$1"
    _g_mode="$2"
    _g_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")

    _g_repo=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    _g_lists="$_g_repo/tests/lib/shipped-paths.sh"
    if [ ! -r "$_g_lists" ]; then
        # Fail closed: on the shipped branch, without the lists, this hook
        # cannot tell shipped from development material, and guessing is the one
        # mistake it exists to prevent. Callers reach here only on `master`.
        printf '%s: cannot read %s — refusing to guess on %s.\n' \
            "$_g_hook" "$_g_lists" "$_g_branch" >&2
        printf '  restore the file, or: OMAFAN_ALLOW_DEV_PATHS=1 git ...\n' >&2
        return 1
    fi
    # shellcheck source=tests/lib/shipped-paths.sh
    . "$_g_lists"

    [ "$_g_branch" = "$OMAFAN_SHIPPED_BRANCH" ] || return 0

    case "$_g_mode" in
        staged) _g_paths=$(git diff --cached --name-only --diff-filter=ACMR) ;;
        tree) _g_paths=$(git ls-files) ;;
        *)
            printf '%s: internal error: unknown guard mode [%s]\n' "$_g_hook" "$_g_mode" >&2
            return 1
            ;;
    esac

    _g_offenders=$(printf '%s\n' "$_g_paths" | omafan_dev_paths_in)
    [ -n "$_g_offenders" ] || return 0

    printf '%s: refusing to put development material on %s\n\n' "$_g_hook" "$_g_branch" >&2
    printf '%s\n' "$_g_offenders" | sed 's/^/  /' >&2
    cat >&2 <<'MSG'

These paths exist to develop omafan and must never reach the shipped branch:
users clone it into ~/.config/omarchy/plugins/<id> (DEVIATIONS.md R11, R13).

    git switch dev      # land the change there instead

A release does not merge dev; it copies the shipped path allowlist:

    skills/publish-a-release/sync-master.sh --from dev

Deliberate override: OMAFAN_ALLOW_DEV_PATHS=1 git ...
MSG
    return 1
}
