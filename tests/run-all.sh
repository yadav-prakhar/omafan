#!/usr/bin/env bash
# tests/run-all.sh — the hardware-free gate. Every suite here must pass on any
# machine: no fan writes, no /sys, no root, no network. Live suites are separate
# and opt-in (tests/integration-shell.sh, tests/hw-smoke.sh).
#
# Usage: tests/run-all.sh [--list]
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1

pass_suites=0
fail_suites=0
skip_suites=0
failed_names=()

run_suite() {
    local name="$1"
    local present="$2"
    shift 2
    if [[ ! -e "$present" ]]; then
        printf 'SKIP  %-22s (not present yet)\n' "$name"
        skip_suites=$((skip_suites + 1))
        return 0
    fi
    printf 'RUN   %-22s ' "$name"
    local out
    if out="$("$@" 2>&1)"; then
        printf 'PASS\n'
        pass_suites=$((pass_suites + 1))
    else
        printf 'FAIL\n'
        fail_suites=$((fail_suites + 1))
        failed_names+=("$name")
        printf '%s\n' "$out" | tail -25 | sed 's/^/      | /'
    fi
}

if [[ ${1:-} == --list ]]; then
    echo "plugin-validate manifest.test.sh model.test.mjs ctl.test.sh keybindings.test.sh qml-lint.sh"
    exit 0
fi

echo "omafan test suite — $(date -Is)"
echo "repo: $repo"
echo

# 1. manifest + schema + repository layout (omarchy's own validator)
run_suite "plugin-validate" bash tests/plugin-validate.sh tests/plugin-validate.sh
# 2. manifest-level assertions we make ourselves
run_suite "manifest" bash tests/manifest.test.sh tests/manifest.test.sh
# 3. pure logic of Model.js
run_suite "model" node tests/model.test.mjs tests/model.test.mjs
# 4. the privileged CLI against the afanctl fixture
run_suite "ctl" bash tests/ctl.test.sh tests/ctl.test.sh
# 5. the keybinding block installer against a stubbed Hyprland
run_suite "keybindings" bash tests/keybindings.test.sh tests/keybindings.test.sh
# 6. QML lint against the installed shell
run_suite "qml-lint" bash tests/qml-lint.sh tests/qml-lint.sh

echo
echo "PASS suites ${pass_suites} / FAIL suites ${fail_suites} / SKIP ${skip_suites}"
if [[ $fail_suites -gt 0 ]]; then
    printf 'failed: %s\n' "${failed_names[*]}"
    exit 1
fi
exit 0
