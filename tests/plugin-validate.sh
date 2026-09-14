#!/usr/bin/env bash
# tests/plugin-validate.sh — run `omarchy plugin validate` against the repo root
# and report PASS/FAIL.  Read-only; must not mutate anything.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v omarchy >/dev/null 2>&1; then
    echo "SKIP: omarchy not found on PATH — skipping plugin-validate gate" >&2
    echo "FAIL plugin-validate (omarchy absent)"
    exit 1
fi

echo "--- omarchy plugin validate $repo_root ---"
if omarchy plugin validate "$repo_root"; then
    echo "--- plugin-validate: OK ---"
    echo "PASS plugin-validate"
    exit 0
else
    rc=$?
    echo "--- plugin-validate: FAILED (exit $rc) ---"
    echo "FAIL plugin-validate"
    exit "$rc"
fi
