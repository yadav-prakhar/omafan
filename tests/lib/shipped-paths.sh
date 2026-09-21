#!/usr/bin/env sh
# tests/lib/shipped-paths.sh — the one home of the two path lists that decide
# what a user's clone of omafan may contain.
#
# `omarchy plugin add` clones the *whole* repository into a user's
# ~/.config/omarchy/plugins/<id>, so every file on the shipped branch is content
# a stranger's machine — and a stranger's coding agent — can read and act on. A
# root AGENTS.md there is a prompt-injection surface, not untidiness. That is the
# guarantee of DEVIATIONS.md R11; R13 kept the guarantee and replaced R11's
# mechanism (never merge `dev`) with a curated sync (copy only SHIPPED_PATHS).
#
# Four consumers read these lists, so the lists have one home and no mirror to
# chase (AGENTS.md: "facts with mirrors must move together"):
#
#   tests/branch-model.test.sh              asserts the shipped branch obeys them
#   skills/publish-a-release/sync-master.sh copies SHIPPED, prunes and refuses DEV
#   .githooks/pre-commit                    refuses DEV paths on the shipped branch
#   .github/workflows/ci.yml                runs the test above on every PR
#
# The lists live under tests/ because the test that asserts them has to run on
# the shipped branch too, where skills/ and .githooks/ do not exist.
#
# Library conventions: POSIX sh (the git hook is /bin/sh), no `set` flags — the
# caller owns those — and no output. Safe under `set -u`.

# The branch users install from. Keyed by *name*, never by "the default branch":
# since R13 the default branch is `dev`, and a guard that fired on the default
# branch would block every normal commit.
OMAFAN_SHIPPED_BRANCH="master"

# What a release copies onto the shipped branch, from DEVIATIONS.md R13 (itself
# derived from AGENTS.md's STRUCTURE section). A trailing slash means "this
# directory and everything under it". Nothing outside this list is ever copied.
OMAFAN_SHIPPED_PATHS="BarWidget.qml
Panel.qml
Model.js
KeyboardHelp.qml
manifest.json
bin/
tests/
docs/
preview.png
README.md
PRD.md
DESIGN.md
DEVIATIONS.md
CHANGELOG.md
CONTRIBUTING.md
SECURITY.md
LICENSE
.github/"

# What must never appear on the shipped branch. Three of these sit *inside*
# allowlisted directories (bin/AGENTS.md, tests/AGENTS.md, docs/agents/), which
# is why the denylist is a filter applied after the copy and not merely a
# complement of the allowlist.
#
# Entries beyond the list R13 quotes, and why:
#   docs/agents/  agent instruction files that arrived in docs/ after R12 ruled
#                 the docs/ tree "100% shipped"; same class as bin/AGENTS.md.
#   .omc/         agent operational state; gitignored, denied as well so a
#                 force-added copy cannot ride along.
OMAFAN_DEV_PATHS="AGENTS.md
bin/AGENTS.md
tests/AGENTS.md
orchestration/AGENTS.md
worknotes/
orchestration/
skills/
.githooks/
PLAN.md
QUESTIONS.md
.recon/
docs/agents/
.omc/"

# omafan_is_dev_path <repo-relative-path> — true when the path is development
# material.
omafan_is_dev_path() {
    _sp_path="$1"
    # Two entries match at any depth rather than only at the repo root, because
    # both have already appeared below it: an AGENTS.md is written per directory
    # (bin/, tests/, orchestration/), and .omc/ has turned up under
    # tests/fixtures/. Matching the basename catches the next one — docs/AGENTS.md,
    # say — before it ships, instead of after someone updates the list.
    case "$_sp_path" in
        AGENTS.md | */AGENTS.md) return 0 ;;
        .omc/* | */.omc/*) return 0 ;;
    esac
    for _sp_deny in $OMAFAN_DEV_PATHS; do
        case "$_sp_deny" in
            */)
                case "$_sp_path" in
                    "$_sp_deny"*) return 0 ;;
                esac
                ;;
            *)
                if [ "$_sp_path" = "$_sp_deny" ]; then
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# omafan_is_shipped_path <repo-relative-path> — true when the path is inside the
# allowlist. A denylisted path is never shipped even when it matches, so callers
# check omafan_is_dev_path first.
omafan_is_shipped_path() {
    _sp_path="$1"
    for _sp_allow in $OMAFAN_SHIPPED_PATHS; do
        case "$_sp_allow" in
            */)
                case "$_sp_path" in
                    "$_sp_allow"*) return 0 ;;
                esac
                ;;
            *)
                if [ "$_sp_path" = "$_sp_allow" ]; then
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# omafan_dev_paths_in — filter a newline-separated path list on stdin down to
# its development-material entries, in input order. Prints nothing when clean.
omafan_dev_paths_in() {
    while IFS= read -r _sp_line; do
        [ -n "$_sp_line" ] || continue
        if omafan_is_dev_path "$_sp_line"; then
            printf '%s\n' "$_sp_line"
        fi
    done
}
