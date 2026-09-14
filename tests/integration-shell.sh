#!/usr/bin/env bash
# tests/integration-shell.sh — opt-in live check that the installed omafan
# plugin is loaded by the running omarchy-shell and that its IPC answers.
#
# This suite is excluded from tests/run-all.sh: it needs a live desktop session.
# Without OMAFAN_LIVE=1 it prints a skip and exits 0 without touching the shell.
# It performs no fan writes: the only write verb it calls is the intentional
# error path `preset bogus`, and toggle/close only move the panel.
#
# Usage: OMAFAN_LIVE=1 tests/integration-shell.sh
# Env:   OMAFAN_PLUGIN_DIR  plugin directory under test (default the DESIGN.md
#                           section 1 install path)
#        OMARCHY_PATH       shell install prefix (default /usr/share/omarchy)
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }

assert_eq() { # assert_eq <description> <expected> <actual>
    local desc="$1" expected="$2" actual="$3"
    if [[ $expected == "$actual" ]]; then
        ok
    else
        bad "$desc: expected [$expected], got [$actual]"
    fi
}

assert_jq() { # assert_jq <description> <json> <jq-filter>
    local desc="$1" json="$2" filter="$3"
    if printf '%s' "$json" | jq -e "$filter" >/dev/null 2>&1; then
        ok
    else
        bad "$desc: jq [$filter] rejected [$(printf '%.200s' "$json")]"
    fi
}

check() { # check <description> <command...>
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        ok
    else
        bad "$desc"
    fi
}

# The suite moves this machine's panel, so it is opt-in and skipped by default.
if [[ ${OMAFAN_LIVE:-0} != 1 ]]; then
    echo "SKIP integration-shell: set OMAFAN_LIVE=1 to exercise the live shell"
    exit 0
fi

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
plugin_id="io.github.yadav-prakhar.omafan"
design_dir="$HOME/.config/omarchy/plugins/$plugin_id"
plugin_dir="${OMAFAN_PLUGIN_DIR:-$design_dir}"

temp_root=""
cleanup() {
    if [[ -n $temp_root && -d $temp_root ]]; then
        rm -rf -- "$temp_root"
    fi
}
trap cleanup EXIT

for tool in omarchy omarchy-shell jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL integration-shell: '$tool' is not on PATH;" >&2
        echo "      this suite needs a live Omarchy shell" >&2
        printf 'PASS 0 / FAIL 1\n'
        exit 1
    fi
done

# ---------------------------------------------------------------- plugin dir
# Never write to ~/.config/omarchy from a test (safety rule): a missing install
# is reported, and a throwaway copy of the repo is validated in its place. The
# running shell cannot load a temp directory, so the live assertions below will
# then fail and print the exact install command.
if [[ ! -f $plugin_dir/manifest.json ]]; then
    temp_root="$(mktemp -d)"
    plugin_dir="$temp_root/$plugin_id"
    mkdir -p -- "$plugin_dir"
    cp -a -- "$repo/." "$plugin_dir/"
    rm -rf -- "$plugin_dir/.git"
    echo "NOTE: no plugin at $design_dir; validating a temp copy at $plugin_dir"
    echo "NOTE: the running shell cannot load a temp copy; install with:"
    echo "      omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable"
fi

echo "--- omarchy plugin validate $plugin_dir ---"
validate_out="$(omarchy plugin validate "$plugin_dir" 2>&1)"
validate_rc=$?
printf '%s\n' "$validate_out"
assert_eq "omarchy plugin validate $plugin_dir exits 0" "0" "$validate_rc"

# --------------------------------------------------------------- live shell
check "omarchy-shell shell rescanPlugins returns" omarchy-shell shell rescanPlugins

# The registry rescans asynchronously; poll until the plugin appears.
list_json=""
for _ in $(seq 1 20); do
    list_json="$(omarchy plugin list --json 2>/dev/null || true)"
    if printf '%s' "$list_json" | jq -e --arg id "$plugin_id" \
        '.[]? | select(.id == $id)' >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

entry="$(printf '%s' "$list_json" | jq -c --arg id "$plugin_id" \
    '.[]? | select(.id == $id)' 2>/dev/null || true)"
if [[ -z $entry ]]; then
    bad "omarchy plugin list --json does not list $plugin_id." \
        "Fix: omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable"
else
    ok
    assert_eq "$plugin_id is enabled" "true" "$(printf '%s' "$entry" | jq -r '.enabled')"
fi

# ------------------------------------------------------------------- IPC
# `state` returns the panel's last status document verbatim; wait for the first
# poll to land after the rescan.
state_json=""
for _ in $(seq 1 40); do
    state_json="$(omarchy-shell omafan state 2>/dev/null || true)"
    if printf '%s' "$state_json" | jq -e '.schema == "omafan.status.v1"' >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
assert_jq "omarchy-shell omafan state returns an omafan.status.v1 document" \
    "$state_json" '.schema == "omafan.status.v1"'

# An unknown preset must come back as an error string, never as an applied one.
preset_out="$(omarchy-shell omafan preset bogus 2>/dev/null || true)"
if [[ $preset_out == error:* ]]; then
    ok
else
    bad "omarchy-shell omafan preset bogus returned [$preset_out]; expected an error string"
fi

check "omarchy-shell omafan toggle returns" omarchy-shell omafan toggle
check "omarchy-shell omafan close returns" omarchy-shell omafan close

# ------------------------------------------------------------------ shell log
if command -v qs >/dev/null 2>&1; then
    log_text="$(qs log -p "$OMARCHY_PATH/shell" --tail 200 2>&1 || true)"
    echo "--- qs log -p $OMARCHY_PATH/shell --tail 200 ---"
    printf '%s\n' "$log_text"
    # Only errors that name the plugin count (its id, its unique file names, or
    # a path into its directory): other plugins share generic names such as
    # Panel.qml, so a bare file name would produce false positives.
    offending="$(printf '%s\n' "$log_text" \
        | grep -iE '(error|exception|is not a|unable to|cannot)' \
        | grep -iE '(omafan|io\.github\.yadav-prakhar|KeyboardHelp\.qml|BarWidget\.qml|Model\.js)' \
        || true)"
    if [[ -z $offending ]]; then
        ok
    else
        bad "qs log has errors naming omafan:"
        printf '%s\n' "$offending" >&2
    fi
else
    bad "qs is not on PATH, so the shell log cannot be checked"
fi

echo
printf 'PASS %d / FAIL %d\n' "$pass" "$fail"
if [[ $fail -ne 0 ]]; then
    exit 1
fi
exit 0
