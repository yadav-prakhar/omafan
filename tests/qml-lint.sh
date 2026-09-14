#!/usr/bin/env bash
# tests/qml-lint.sh — lint every *.qml in the repo root with /usr/lib/qt6/bin/qmllint.
# Warnings are reported but not fatal; any error exits non-zero.
# Usable from P1 onward (skips gracefully when no QML files exist yet).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Locate qmllint
if command -v qmllint >/dev/null 2>&1; then
    qmllint_cmd="qmllint"
elif [ -x /usr/lib/qt6/bin/qmllint ]; then
    qmllint_cmd="/usr/lib/qt6/bin/qmllint"
else
    echo "SKIP: qmllint not found — skipping qml-lint gate" >&2
    echo "FAIL qml-lint (qmllint absent)"
    exit 1
fi

# Resolve shell include path
omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
shell_dir="$omarchy_path/shell"

if [ ! -d "$shell_dir" ]; then
    echo "SKIP: Omarchy shell directory not found at $shell_dir — skipping qml-lint gate" >&2
    echo "FAIL qml-lint (shell dir absent)"
    exit 1
fi

# Collect QML files in the repo root (non-recursive)
qml_files=()
for f in "$repo_root"/*.qml; do
    [ -f "$f" ] && qml_files+=("$f")
done

if [ ${#qml_files[@]} -eq 0 ]; then
    echo "SKIP: no *.qml files in $repo_root yet — qml-lint gate deferred" >&2
    echo "PASS qml-lint (no files to lint)"
    exit 0
fi

echo "--- qmllint -I $shell_dir (${#qml_files[@]} files) ---"

had_error=0
for qml_file in "${qml_files[@]}"; do
    echo "  linting $(basename "$qml_file") ..."
    if "$qmllint_cmd" -I "$shell_dir" "$qml_file" 2>&1; then
        echo "    OK"
    else
        echo "    ERROR"
        had_error=1
    fi
done

echo "---"
if [ "$had_error" -ne 0 ]; then
    echo "FAIL qml-lint (errors found)"
    exit 1
else
    echo "PASS qml-lint"
    exit 0
fi
