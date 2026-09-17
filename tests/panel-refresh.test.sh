#!/usr/bin/env bash
# tests/panel-refresh.test.sh — regression guard for the T5 panel refresh row.
#
# The feature: the panel itself can set poll_mode (Auto/Custom chips) and
# poll_seconds (a ±1 s stepper), writing through `omarchy bar set` — the
# shell's own settings write path. The gate has no QML runtime, so the
# behaviour is pinned by asserting the exact guard structure in Panel.qml:
# the dedicated settings process (no pkexec, fan-neutral), the skip-if-
# unchanged guards, the clamp through Model.effectivePollSeconds, and the
# rule that the control stays OUTSIDE the keyboard cursor sections (whose
# two-section contract DESIGN.md 6.2 freezes). If the QML is refactored,
# this suite fails loudly and the assertions move with the code (never
# edited to fit).
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo" || exit 1
source "$repo/tests/lib/harness.sh"

panel="Panel.qml"

# section <start-literal> <end-literal> — QML lines from the first line
# containing <start> (inclusive) up to the first later line containing <end>
# (exclusive). Literal matching (index, not regex) so QML punctuation is safe.
section() {
    local start="$1" end="$2"
    awk -v s="$start" -v e="$end" '
        !inside && index($0, s) { inside = 1 }
        inside && index($0, e) && !index($0, s) { exit }
        inside { print }
    ' "$panel"
}

# assert_file_contains / assert_file_absent / assert_region_absent — quiet
# fixed-string checks (same helpers as panel-slider.test.sh).
assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-assert_file_contains}"
    if grep -qF -- "$needle" "$file"; then
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    else
        _harness_fail "$msg: [$file] does not contain [$needle]"
    fi
}

assert_file_absent() {
    local file="$1" needle="$2" msg="${3:-assert_file_absent}"
    if grep -qF -- "$needle" "$file"; then
        _harness_fail "$msg: [$file] unexpectedly contains [$needle]"
    else
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    fi
}

assert_region_absent() {
    local body="$1" needle="$2" msg="${3:-assert_region_absent}"
    case "$body" in
        *"$needle"*)
            _harness_fail "$msg: unexpectedly contains [$needle]" ;;
        *)
            _HARNESS_PASS=$((_HARNESS_PASS + 1)) ;;
    esac
}

mode_fn="$(section 'function setPollMode(mode)' 'function stepPollSeconds')"
step_fn="$(section 'function stepPollSeconds' 'function refresh()')"
proc_body="$(section 'id: settingsProc' 'id: settingsDeadline')"
deadline_body="$(section 'id: settingsDeadline' 'id: commandDeadline')"
ui_body="$(section '// ---------- refresh ----------' '// ---------- footer ----------')"

# --- A. the dedicated state exists -------------------------------------------
assert_file_contains "$panel" "property bool settingsBusy: false" \
    "Panel declares the settings-write in-flight flag"
assert_file_contains "$panel" 'property string settingsError: ""' \
    "Panel declares a settings error line separate from the fan banner"
assert_file_contains "$panel" "id: settingsProc" \
    "Panel owns a dedicated settings-write Process"

# --- B. writes go through the shell's own settings path ----------------------
assert_contains "$mode_fn" 'settingsProc.omarchyBin, "bar", "set"' \
    "setPollMode writes through omarchy bar set"
assert_contains "$mode_fn" '"poll_mode", next]' \
    "setPollMode writes the poll_mode key"
assert_contains "$step_fn" '"poll_seconds", String(next), "--json"' \
    "stepPollSeconds writes poll_seconds via omarchy bar set with --json (integer stays typed)"
assert_region_absent "$proc_body" "pkexec" \
    "the settings write path never uses the privileged runner"
assert_region_absent "$proc_body" "/sys" \
    "the settings write path never touches /sys"
assert_contains "$mode_fn" 'next === root.pollMode) return' \
    "setPollMode skips the write when the mode is unchanged"
assert_contains "$step_fn" "next === root.pollSeconds) return" \
    "stepPollSeconds skips the write at a clamp boundary"

# --- C. the stepper clamps through the tested mode math ----------------------
assert_contains "$step_fn" 'Model.effectivePollSeconds("custom", root.pollSeconds + delta)' \
    "stepPollSeconds clamps through Model.effectivePollSeconds (whole seconds 1-10)"

# --- D. the settings lock is independent of the fan lock ---------------------
assert_region_absent "$mode_fn" "root.busy = true" \
    "setPollMode never takes the fan-write lock"
assert_region_absent "$step_fn" "root.busy = true" \
    "stepPollSeconds never takes the fan-write lock"
assert_contains "$mode_fn" "root.settingsBusy = true" \
    "setPollMode sets its own in-flight flag"
assert_contains "$deadline_body" "root.settingsBusy = false" \
    "the settings deadline releases the lock and names the symptom"

# --- E. failure surfaces in the refresh row, not the fan banner --------------
assert_contains "$proc_body" "root.settingsError =" \
    "a failed settings write reports in the refresh row's own error line"
assert_region_absent "$proc_body" "root.lastError =" \
    "a settings failure never overwrites the fan banner"

# --- F. the keyboard cursor contract is untouched ----------------------------
assert_file_contains "$panel" 'readonly property var visibleSections: ["presets", "slider"]' \
    "the cursor model keeps exactly the two frozen sections"
assert_contains "$ui_body" '"REFRESH"' \
    "the refresh row renders with its section header"
assert_contains "$ui_body" 'root.setPollMode("auto")' \
    "the Auto chip writes mode auto"
assert_contains "$ui_body" 'root.setPollMode("custom")' \
    "the Custom chip writes mode custom"
assert_contains "$ui_body" "root.stepPollSeconds(-1)" \
    "the stepper has a −1 s control"
assert_contains "$ui_body" "root.stepPollSeconds(1)" \
    "the stepper has a +1 s control"
assert_contains "$ui_body" 'visible: root.pollMode === "custom"' \
    "the stepper only appears in custom mode (auto is pinned to 2 s)"

summarize
