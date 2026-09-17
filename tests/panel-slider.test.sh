#!/usr/bin/env bash
# tests/panel-slider.test.sh — regression guard for the T2 slider Auto-reset.
#
# The defect: after preset auto, the slider kept showing the last manual rpm
# because a stale hold doc repopulated pendingRpm (applyStatus) and a queued
# debounce could reapply a manual hold after the release (sliderSend).
#
# Why structural: the gate has no QML runtime (qmllint only lints), so the
# behaviour is pinned by asserting the exact guard structure in Panel.qml —
# the Auto expectation flag, the confirmation-only clearing, and the rule that
# no write-exit path ever clears the slider. If the QML is refactored, this
# suite fails loudly and the assertions move with the code (never edited to
# fit). Scenario walkthroughs live in logs/2026-09-17-t2-slider-evidence.md.
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

# assert_file_contains <file> <needle> [message] — quiet fixed-string check for
# whole-file assertions (the harness assert_contains would dump the file).
assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-assert_file_contains}"
    if grep -qF -- "$needle" "$file"; then
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    else
        _harness_fail "$msg: [$file] does not contain [$needle]"
    fi
}

# assert_file_absent <file> <needle> [message] — quiet fixed-string absence.
assert_file_absent() {
    local file="$1" needle="$2" msg="${3:-assert_file_absent}"
    if grep -qF -- "$needle" "$file"; then
        _harness_fail "$msg: [$file] unexpectedly contains [$needle]"
    else
        _HARNESS_PASS=$((_HARNESS_PASS + 1))
    fi
}

# assert_region_absent <body> <needle> [message] — absence inside an extracted
# region, with a short failure line (no haystack dump).
assert_region_absent() {
    local body="$1" needle="$2" msg="${3:-assert_region_absent}"
    case "$body" in
        *"$needle"*)
            _harness_fail "$msg: unexpectedly contains [$needle]" ;;
        *)
            _HARNESS_PASS=$((_HARNESS_PASS + 1)) ;;
    esac
}

send_body="$(section 'function sendCommand(args)' 'function applyPreset(id)')"
status_body="$(section 'function applyStatus(text)' 'Text-key handler')"
exited_body="$(section 'onExited: function(code)' 'id: commandDeadline')"
deadline_body="$(section 'id: commandDeadline' 'id: statusDeadline')"

# --- A. the Auto expectation state exists ------------------------------------
assert_file_contains "$panel" "property bool expectingAuto: false" \
    "Panel declares the expectingAuto guard flag"
assert_file_contains "$panel" "property bool lastWriteWasRelease: false" \
    "Panel records whether the in-flight write is a release"

# --- B. every release path funnels through sendCommand -----------------------
assert_contains "$send_body" 'args[0] === "release"' \
    "sendCommand recognises the release verb"
assert_contains "$send_body" 'args[1] === "auto"' \
    "sendCommand recognises preset auto (covers cycle-to-auto too)"
assert_contains "$send_body" "sliderSend.stop()" \
    "sendCommand cancels the queued debounce on release"
assert_contains "$send_body" "root.expectingAuto = true" \
    "sendCommand arms the Auto expectation on release"
assert_contains "$send_body" "root.expectingAuto = false" \
    "sendCommand disarms on a superseding manual write"
assert_contains "$send_body" "root.lastWriteWasRelease = isRelease" \
    "sendCommand records the write kind for the exit paths"

# --- C. confirmation comes only from a fresh auto status ---------------------
assert_contains "$status_body" "root.expectingAuto && !root.holdActive" \
    "applyStatus confirms Auto only when a fresh status shows hold inactive"
assert_contains "$status_body" "root.pendingRpm = null" \
    "applyStatus clears the slider on confirmed Auto"
assert_contains "$status_body" "sliderSend.stop()" \
    "applyStatus cancels the debounce on confirmed Auto"
assert_contains "$status_body" "root.expectingAuto = false" \
    "applyStatus disarms the expectation on confirmation"
assert_contains "$status_body" "!root.expectingAuto" \
    "applyStatus gates the hold-doc sync so a stale doc cannot resurrect pendingRpm"
assert_contains "$status_body" "root.pendingRpm = root.holdDoc.rpm" \
    "applyStatus still tracks the daemon target while a hold is on"

# --- D. a write exit alone never confirms ------------------------------------
assert_contains "$exited_body" "root.lastWriteWasRelease" \
    "onExited consults the recorded write kind"
assert_contains "$exited_body" "root.expectingAuto = false" \
    "onExited voids the expectation when a release write fails"
assert_region_absent "$exited_body" "pendingRpm = null" \
    "onExited never clears the slider (neither on success nor on failure)"
assert_contains "$exited_body" "Qt.callLater(root.refresh)" \
    "onExited keeps the post-write status re-read"

# --- E. the deadline behaviour stays consistent -------------------------------
assert_contains "$deadline_body" "root.pendingRpm = null" \
    "commandDeadline still nulls pendingRpm on timeout"
assert_contains "$deadline_body" "root.expectingAuto = false" \
    "commandDeadline voids a killed release expectation"

# --- F. base/min inactive rendering is unchanged -------------------------------
assert_file_contains "$panel" '? "—"' \
    "a nulled pendingRpm renders the inactive em-dash label"
assert_file_contains "$panel" "? Number(root.pendingRpm) : root.fanMinRpm" \
    "a nulled pendingRpm parks the knob at the hardware floor"
assert_file_contains "Model.js" 'off: "Floor (hardware floor)"' \
    "the floor preset keeps its honest full label in the ladder"
assert_file_contains "$panel" "not a stopped fan" \
    "the floors footnote denies the stopped-fan reading"
assert_file_absent "$panel" "fan is stopped" \
    "no surface claims the fan is stopped"
assert_file_absent "$panel" "fan stopped" \
    "no surface claims the fan stopped"

summarize
