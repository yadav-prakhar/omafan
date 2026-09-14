#!/usr/bin/env bash
# tests/hw-smoke.sh — opt-in, supervised smoke test that commands the real fan
# through bin/omafan-ctl and always returns the machine to firmware auto.
#
# Without OMAFAN_HW=1 it prints a skip and exits 0 without running afanctl.
# With OMAFAN_HW=1 it requires an interactive "yes"; anything else (including a
# non-interactive stdin) skips with exit 0. It then refuses (exit 1) unless
# afanctl is present and its daemon is running.
#
# Policy — never reduce airflow the firmware already established:
#   t_eff_c < 60   -> exercise the full ladder off/low/med/high/full;
#   t_eff_c >= 60  -> only holds at or above the live rpm, printing the presets
#                     it skipped. `full` is the hardware maximum, so it always
#                     qualifies; `high` qualifies only while the firmware is
#                     below it. This covers the ticket's t_eff_c >= 75 case and
#                     the 60..74 band with the same safe rule.
# `full` is held for at most 2 s and the fan is released immediately after.
# An EXIT trap calls `release` and verifies mode=observe/manual=false on every
# failure or interrupt, so an aborted run still hands the fan back.
#
# Nothing here touches /sys: every read and write goes through bin/omafan-ctl,
# and the final cross-check reads `afanctl status --json`.
#
# OMAFAN_AFANCTL / OMAFAN_RUNTIME_DIR / OMAFAN_PKEXEC are honoured so this flow
# can be exercised against tests/fixtures/fake-afanctl instead of hardware.
#
# Usage: OMAFAN_HW=1 tests/hw-smoke.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl_bin="$repo/bin/omafan-ctl"

if [[ ${OMAFAN_HW:-0} != 1 ]]; then
    echo "SKIP hw-smoke: set OMAFAN_HW=1 to run the supervised hardware smoke test"
    echo "             (it moves the fan; run it attended, never unattended on a hot machine)"
    exit 0
fi

# ------------------------------------------------------- interactive consent
# Read the confirmation from the controlling terminal, not stdin, so a piped
# "yes" cannot arm a fan write. Returns non-zero when there is no usable
# terminal (headless or CI), and the caller then skips.
prompt_yes() {
    if [[ -t 0 ]]; then
        printf '%s' "$1"
        read -r REPLY || return 1
        return 0
    fi
    { printf '%s' "$1" >/dev/tty; } 2>/dev/null || return 1
    { read -r REPLY </dev/tty; } 2>/dev/null || return 1
    return 0
}

if ! prompt_yes '
omafan hw-smoke will hold the fan at several presets and then return it
to firmware auto. Do not leave it unattended. Type "yes" to continue: '; then
    echo "SKIP hw-smoke: no interactive terminal; nothing was written."
    exit 0
fi
if [[ ${REPLY:-} != yes ]]; then
    echo "SKIP hw-smoke: not confirmed ('yes'); nothing was written."
    exit 0
fi

# ------------------------------------------------------------ CLI invocation
# The same globals the panel passes, so a fixture run never reaches hardware.
ctl=("$ctl_bin")
if [[ -n ${OMAFAN_AFANCTL:-} ]]; then ctl+=(--afanctl "$OMAFAN_AFANCTL"); fi
if [[ -n ${OMAFAN_RUNTIME_DIR:-} ]]; then ctl+=(--runtime-dir "$OMAFAN_RUNTIME_DIR"); fi
if [[ -n ${OMAFAN_PKEXEC:-} ]]; then ctl+=(--pkexec "$OMAFAN_PKEXEC"); fi

# afanctl takes its runtime dir from the environment (ruling R2), so the direct
# cross-check below must export it too.
afanctl_bin="${OMAFAN_AFANCTL:-afanctl}"
runtime_dir="${OMAFAN_RUNTIME_DIR:-/run/afanctl}"

status_doc() {
    # Read-only. A daemon that just went down still renders a document with
    # running:false, so the exit code is ignored here and fields are checked.
    "${ctl[@]}" status --json 2>/dev/null || true
}

jfield() { # jfield <json> <jq-filter> -> the value, or empty
    printf '%s' "$1" | jq -r "$2" 2>/dev/null || true
}

firmware_auto() { # true when the daemon reports observe and manual=false
    local doc mode manual
    doc="$(status_doc)"
    # No `// empty` on the boolean: jq's alternative operator treats false as
    # absent, which would hide an honest manual=false behind an empty string.
    mode="$(jfield "$doc" '.daemon.mode')"
    manual="$(jfield "$doc" '.fan.manual')"
    [[ $mode == observe && $manual == false ]]
}

release_and_verify() {
    local attempt
    "${ctl[@]}" release --json >/dev/null 2>&1 || true
    for attempt in $(seq 1 20); do
        if firmware_auto; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# The trap must not "release" a fan this run never touched, so the precondition
# refusals set cleanup_done first.
cleanup_done=0
on_exit() {
    local rc=$?
    if [[ $cleanup_done -eq 0 ]]; then
        if release_and_verify; then
            echo "hw-smoke: fan returned to firmware auto (mode=observe, manual=false)"
        else
            echo "hw-smoke: WARNING: could not confirm firmware auto;" >&2
            echo "           run: omafan-ctl release   (then: systemctl restart afanctl)" >&2
        fi
    fi
    exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

refuse() { # refuse <message> [fix]
    cleanup_done=1
    printf 'FAIL hw-smoke: %s\n' "$1" >&2
    if [[ -n ${2:-} ]]; then
        printf '              %s\n' "$2" >&2
    fi
    exit 1
}

# --------------------------------------------------------------- preconditions
# `command -v` resolves both a bare name and a path, and fails for a path that
# is not executable.
if ! command -v "$afanctl_bin" >/dev/null 2>&1; then
    refuse "afanctl '$afanctl_bin' is missing or not executable." \
        "Fix: install afanctl (see its packaging/ directory)"
fi

status_json="$(status_doc)"
if ! printf '%s' "$status_json" | jq -e '.daemon.running == true' >/dev/null 2>&1; then
    refuse "the afanctl daemon is not running (no fresh state.json)." \
        "Fix: systemctl restart afanctl, then retry"
fi

presets_json="$("${ctl[@]}" presets --json 2>/dev/null || true)"
if ! printf '%s' "$presets_json" | jq -e '.schema == "omafan.presets.v1"' >/dev/null 2>&1; then
    refuse "cannot read the preset ladder from bin/omafan-ctl presets --json." \
        "Fix: run bin/omafan-ctl doctor --json"
fi

preset_rpm_of() { # preset_rpm_of <id> -> rpm literal
    printf '%s' "$presets_json" | jq -r --arg id "$1" \
        '.presets[] | select(.id == $id) | .rpm // empty' 2>/dev/null || true
}

t_eff="$(jfield "$status_json" '.thermal.t_eff_c // empty')"
live_rpm="$(jfield "$status_json" '.fan.rpm // empty')"
if [[ -z $t_eff ]] || ! printf '%s' "$t_eff" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
    refuse "the daemon did not report a usable t_eff_c (got [$t_eff])." \
        "Fix: run bin/omafan-ctl status --full --json"
fi
if [[ -z $live_rpm ]] || ! printf '%s' "$live_rpm" | grep -qE '^[0-9]+$'; then
    refuse "the daemon did not report a usable fan rpm (got [$live_rpm])." \
        "Fix: run bin/omafan-ctl status --full --json"
fi

# ------------------------------------------------------------------ hot policy
hot=0
if awk -v t="$t_eff" 'BEGIN { exit !(t >= 60) }'; then
    hot=1
fi

allowed=()
skipped=()
for id in off low med high full; do
    rpm="$(preset_rpm_of "$id")"
    if [[ -z $rpm ]]; then
        refuse "the ladder has no rpm for preset $id." "Fix: run bin/omafan-ctl presets --json"
    fi
    if [[ $hot -eq 0 || $rpm -ge $live_rpm ]]; then
        allowed+=("$id")
    else
        skipped+=("$id")
    fi
done
if [[ ${#allowed[@]} -eq 0 ]]; then
    refuse "no safe preset: every hold is below the live $live_rpm rpm at ${t_eff} °C." \
        "Fix: wait for the machine to cool, then retry"
fi

echo "hw-smoke: t_eff_c=$t_eff  live_rpm=$live_rpm"
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "hw-smoke: skipping ${skipped[*]} (below the live rpm; never reduce established airflow)"
fi
echo "hw-smoke: exercising ${allowed[*]}"

# --------------------------------------------------------------------- ladder
rows=()
for id in "${allowed[@]}"; do
    expected="$(preset_rpm_of "$id")"
    echo "-- $id: hold $expected rpm"
    apply_start="$(date +%s)"
    action_rc=0
    action_json="$("${ctl[@]}" preset "$id" --json 2>/dev/null)" || action_rc=$?
    if [[ $action_rc -ne 0 ]]; then
        echo "FAIL hw-smoke: preset $id refused (exit $action_rc):" >&2
        echo "              $(jfield "$action_json" '.message // empty')" >&2
        exit 1
    fi

    observed=""
    for _ in $(seq 1 20); do # 20 x 250 ms = 5 s
        doc="$(status_doc)"
        if [[ "$(jfield "$doc" '.hold.active // false')" == true \
            && "$(jfield "$doc" '.hold.rpm // empty')" == "$expected" ]]; then
            observed="$expected"
            break
        fi
        sleep 0.25
    done
    if [[ -z $observed ]]; then
        echo "FAIL hw-smoke: $id did not report hold.active with $expected rpm within 5 s" >&2
        exit 1
    fi
    rows+=("$id $expected $observed")

    if [[ $id == full ]]; then
        # full is the loudest preset, so cap the hold at 2 s and release at once.
        elapsed=$(( $(date +%s) - apply_start ))
        if [[ $elapsed -lt 2 ]]; then
            sleep $((2 - elapsed))
        fi
        break
    fi
done

# -------------------------------------------------------------------- release
echo "-- release: firmware auto"
if ! release_and_verify; then
    echo "FAIL hw-smoke: release did not reach mode=observe/manual=false within 10 s" >&2
    exit 1
fi

# The daemon's own document must agree with the CLI's translation.
raw_json="$(env AFANCTL_RUNTIME_DIR="$runtime_dir" \
    "$afanctl_bin" status --json 2>/dev/null || true)"
if ! printf '%s' "$raw_json" | jq -e \
    '.schema == "afanctl.status.v1" and .daemon.mode == "observe" and .fan.manual == false' \
    >/dev/null 2>&1; then
    echo "FAIL hw-smoke: afanctl status --json does not agree (want mode=observe, manual=false)" >&2
    printf '%s\n' "$raw_json" >&2
    exit 1
fi

echo
printf '%-8s %-12s %-12s %s\n' preset expected observed result
for row in "${rows[@]}"; do
    read -r id expected observed <<<"$row"
    printf '%-8s %-12s %-12s %s\n' "$id" "$expected rpm" "$observed rpm" verified
done
echo "final: mode=observe manual=false (omafan-ctl and afanctl agree)"

cleanup_done=1
exit 0
