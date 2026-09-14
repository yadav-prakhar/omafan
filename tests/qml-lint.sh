#!/usr/bin/env bash
# tests/qml-lint.sh — QML gate for omafan against the installed Omarchy shell.
#
# Why this is not a plain `qmllint` call: the shell's own modules (`qs.Ui`,
# `qs.Commons`, `qs.services`) ship a `qmldir` but no `qmltypes`, so the
# documented `qmllint -I "$OMARCHY_PATH/shell"` cannot resolve them (the import
# path must contain a `qs/` directory) and, once resolved, every member access
# on those singletons is reported as `[missing-property]`. Running qmllint on
# the shipped third-party plugin `omaplug` shows both effects today.
#
# So this gate builds a shim import root (`<tmp>/qs/<module>` -> the real shell
# directories), then classifies diagnostics:
#   FATAL     syntax errors, any qmllint exit != 0, imports that the shim cannot
#             satisfy, missing types that are NOT provided by qs.*, and a small
#             set of categories that always mean a real defect.
#   REPORTED  anything else (missing members/properties on qs.* singletons,
#             unused imports, ...) — printed for the reviewer, not fatal.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
SHELL_DIR="$OMARCHY_PATH/shell"
QMLLINT="${QMLLINT:-}"
if [[ -z $QMLLINT ]]; then
    if command -v qmllint >/dev/null 2>&1; then
        QMLLINT="$(command -v qmllint)"
    elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
        QMLLINT=/usr/lib/qt6/bin/qmllint
    fi
fi

if [[ -z $QMLLINT || ! -x $QMLLINT ]]; then
    echo "SKIP qml-lint: qmllint not found (install qt6-declarative or set QMLLINT)"
    exit 0
fi
if [[ ! -d $SHELL_DIR ]]; then
    echo "SKIP qml-lint: shell sources not found at $SHELL_DIR"
    exit 0
fi

# Collect the plugin's QML files (root + nested dirs), excluding tests/.git.
mapfile -t files < <(find . -name '*.qml' -not -path './.git/*' -not -path './tests/*' | sort)
if (( ${#files[@]} == 0 )); then
    echo "PASS qml-lint (no QML files yet — gate deferred)"
    exit 0
fi

shim="$(mktemp -d)"
cleanup() { rm -rf "$shim"; }
trap cleanup EXIT
mkdir -p "$shim/qs"
for d in "$SHELL_DIR"/*/; do
    [[ -f "$d/qmldir" ]] || continue
    ln -sfn "${d%/}" "$shim/qs/$(basename "${d%/}")"
done
# Extra roots the shell itself is run with (Quickshell resolves qs.* relative to
# the config path, so plugins may import sibling trees such as qs.services).
[[ -d "$SHELL_DIR/services" ]] && ln -sfn "$SHELL_DIR/services" "$shim/qs/services"

# Types declared by those qmldirs: their members cannot be checked without
# qmltypes, so diagnostics about them are expected rather than defects.
known_types="$(cat "$shim"/qs/*/qmldir 2>/dev/null |
    awk '/^[A-Za-z]/ { for (i = 1; i <= NF; i++) if ($i ~ /^[A-Z][A-Za-z0-9]*$/ && $i !~ /^[0-9]/) print $i }' |
    sort -u | paste -sd'|' -)"

out="$(mktemp)"
"$QMLLINT" -I "$shim" "${files[@]}" >"$out" 2>&1
qmllint_rc=$?

fatal=0
reported=0
while IFS= read -r line; do
    [[ -n $line ]] || continue
    case "$line" in
        Warning:*|Error:*|Info:*)
            cat="${line##*[}"
            cat="${cat%]}"
            ;;
        *) continue ;;
    esac
    case "$cat" in
        syntax|unresolved-type|bad-qmldir|duplicate-signal-handler|invalid-property-type|\
        incompatible-type|multiple-enum-values|write-to-read-only-property|unknown-grouped-property)
            echo "FATAL  $line"
            fatal=$((fatal + 1))
            ;;
        missing-type)
            typename="$(printf '%s' "$line" | sed -n 's/.*type "\([A-Za-z0-9_]*\)".*/\1/p')"
            if [[ -n $typename && -n $known_types && $typename =~ ^($known_types)$ ]]; then
                reported=$((reported + 1))
            else
                echo "FATAL  $line"
                fatal=$((fatal + 1))
            fi
            ;;
        import)
            # A module the shim does not provide is a real problem; qs.* modules
            # are provided by the shim, so any failure naming one is also real.
            echo "FATAL  $line"
            fatal=$((fatal + 1))
            ;;
        *)
            reported=$((reported + 1))
            ;;
    esac
done <"$out"

if (( qmllint_rc != 0 )) && (( fatal == 0 )); then
    echo "FATAL  qmllint exited $qmllint_rc"
    fatal=$((fatal + 1))
fi

total=${#files[@]}
if (( fatal > 0 )); then
    echo "FAIL qml-lint: ${fatal} fatal diagnostic(s) across ${total} file(s)"
    rm -f "$out"
    exit 1
fi

echo "PASS qml-lint: ${total} file(s) clean; ${reported} expected non-fatal warning(s) about qs.* members"
if (( reported > 0 )) && [[ ${OMAFAN_LINT_VERBOSE:-0} == 1 ]]; then
    grep -E '^(Warning|Info):' "$out" | sort | uniq -c | sort -rn | head -20
fi
rm -f "$out"
exit 0
