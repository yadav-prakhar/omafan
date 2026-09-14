#!/usr/bin/env bash
# tests/manifest.test.sh — assertions about manifest.json that the plugin
# validator does not make: the marketplace-facing fields, the identity the code
# depends on, and the repository layout the shell will load.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1

pass=0
fail=0
check() { # check <description> <command...>
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL: $desc" >&2
    fi
}
eq() { # eq <description> <actual> <expected>
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL: $desc — got '$actual', want '$expected'" >&2
    fi
}

j() { jq -r "$1" manifest.json; }

# --- identity -----------------------------------------------------------------
eq "id" "$(j .id)" "io.github.yadav-prakhar.omafan"
eq "schemaVersion" "$(j .schemaVersion)" "1"
eq "name" "$(j .name)" "omafan"
eq "version" "$(j .version)" "1.0.0"
eq "author" "$(j .author)" "Prakhar Yadav"
eq "license" "$(j .license)" "GPL-3.0-only"
eq "homepage" "$(j .homepage)" "https://github.com/yadav-prakhar/omafan"

# --- kind / entry point -------------------------------------------------------
eq "kinds[0]" "$(j '.kinds[0]')" "bar-widget"
eq "kinds length" "$(j '.kinds | length')" "1"
eq "entryPoints.barWidget" "$(j .entryPoints.barWidget)" "BarWidget.qml"
eq "barWidget.defaultSection" "$(j .barWidget.defaultSection)" "right"
eq "barWidget.allowMultiple" "$(j .barWidget.allowMultiple)" "false"
eq "barWidget.category" "$(j .barWidget.category)" "Hardware"
check "BarWidget.qml exists" test -f BarWidget.qml
check "Panel.qml exists" test -f Panel.qml
check "Model.js exists" test -f Model.js

# --- description is a real marketplace summary --------------------------------
desc_len=$(jq -r '.description | length' manifest.json)
if (( desc_len >= 40 && desc_len <= 220 )); then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "  FAIL: description length $desc_len outside 40..220" >&2
fi

# --- settings schema the panel reads -----------------------------------------
eq "schema keys" "$(j '.barWidget.schema | map(.key) | join(",")')" "show,poll_seconds,release_after_minutes"
eq "defaults" "$(j '.barWidget.defaults | to_entries | map("\(.key)=\(.value)") | join(",")')" \
    "show=temp,poll_seconds=2,release_after_minutes=0"
eq "poll_seconds bounds" "$(j '.barWidget.schema[] | select(.key=="poll_seconds") | "\(.min)-\(.max)"')" "1-10"

# --- repository hygiene the shell enforces or benefits from -------------------
check "no symlinks in plugin tree" bash -c \
    '! find . -name .git -prune -o -type l -print -quit | grep -q .'
check "LICENSE present" test -f LICENSE
check "LICENSE is GPL-3.0" grep -q "GNU GENERAL PUBLIC LICENSE" LICENSE
check "README present" test -f README.md
check "no secrets committed" bash -c \
    '! grep -rIl -E "(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,})" \
       --exclude-dir=.git . | grep -q .'

echo "manifest: PASS $pass / FAIL $fail"
(( fail == 0 ))
