#!/usr/bin/env bash
# tests/ctl.test.sh - every promise of DESIGN.md section 4 is machine-checked
# against tests/fixtures/fake-afanctl. No hardware, no pkexec, no network: each
# case runs in its own tempdir and XDG_RUNTIME_DIR is redirected into it, so
# even the hardware-limit cache cannot reach the operator's real runtime dir.
#
# Covered here: each verb's happy path; exit codes 0-8 with the exact situation
# that produces them; the section 4.1-4.4 documents field by field; dry-run
# writing nothing; the section 5.1 undercooling guard (exit 8) and its --force
# override; the section 4.5 cycle verb; and the read/write privilege split.
#
# The fast path is held to section 4.1's values, not merely its types: with a
# seeded state.json that carries t_eff_c, the document must render that number
# (T04c D1) and uptime_s must equal polls x interval_s (T04c D2).
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$repo/tests/lib/harness.sh"

CTL="$repo/bin/omafan-ctl"
FAKE="$repo/tests/fixtures/fake-afanctl"
FIX="$repo/tests/fixtures"

CASE=""
RUN=""
XDG=""
farm=""

# ---------------------------------------------------------------------------
# Case plumbing
# ---------------------------------------------------------------------------

setup_case() {
    # setup_case [state-fixture] - a fresh runtime dir; the fixture becomes
    # state.json only when named, so "daemon absent" is just the no-arg form.
    local fixture="${1:-}"
    CASE="$(new_tmpdir)"
    RUN="$CASE/run"
    XDG="$CASE/xdg"
    mkdir -p "$RUN" "$XDG" "$CASE/bin"
    if [ -n "$fixture" ]; then
        cp -- "$fixture" "$RUN/state.json"
    fi
    export XDG_RUNTIME_DIR="$XDG"
}

# seed_state <jq-filter> - rewrite state.json from the hold fixture so a case
# states exactly the one daemon fact it exercises.
seed_state() {
    jq "$1" "$FIX/state-hold.json" > "$RUN/state.json"
}

# ctl <args...> - the canonical fixture invocation every case shares.
ctl() {
    "$CTL" "$@" --afanctl "$FAKE" --pkexec none --runtime-dir "$RUN"
}

# run_mode <mode> <args...> - ctl with the fixture's daemon mode selected.
run_mode() {
    local mode="$1"
    shift
    FAKE_AFANCTL_MODE="$mode" ctl "$@"
}

jget() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
argv_log() { cat -- "$RUN/argv.log" 2>/dev/null; }

# ---------------------------------------------------------------------------
# 0. syntax gate
# ---------------------------------------------------------------------------

assert_exit_code 0 bash -n "$CTL"

# ---------------------------------------------------------------------------
# 1. status --json: the section 4.1 document, field by field (hold state)
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode hold status --json 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "status exits 0 with a readable state"
assert_eq "omafan.status.v1" "$(jget "$out" '.schema')" "status.schema is the frozen id"
assert_eq "true" "$(jget "$out" '.ok')" "status.ok"
assert_eq "string" "$(jget "$out" '.generated_at | type')" "generated_at is a string"
assert_eq "true" "$(jget "$out" '.afanctl.present')" "afanctl.present is true"
assert_eq "0.1.0" "$(jget "$out" '.afanctl.version')" "afanctl.version is reported"
assert_eq "true" "$(jget "$out" '.daemon.running')" "daemon.running from state.json"
assert_eq "hold" "$(jget "$out" '.daemon.mode')" "daemon.mode is the applied mode"
assert_eq "false" "$(jget "$out" '.daemon.monitor_only')" "monitor_only is boolean"
assert_eq "false" "$(jget "$out" '.daemon.auto_restore_pending')" "auto_restore_pending is boolean"
assert_eq "2048" "$(jget "$out" '.daemon.polls')" "polls is carried through"
assert_eq "false" "$(jget "$out" '.daemon.state_stale')" "a fresh state is not stale"
assert_eq "1200" "$(jget "$out" '.hardware.fan_min_rpm')" "fan_min_rpm from afanctl"
assert_eq "7200" "$(jget "$out" '.hardware.fan_max_rpm')" "fan_max_rpm from afanctl"
assert_eq "true" "$(jget "$out" '.hardware.fan_min_rpm < .hardware.fan_max_rpm')" \
    "the hardware band is min < max"
assert_eq "4180" "$(jget "$out" '.fan.rpm')" "fan.rpm is numeric"
assert_eq "4200" "$(jget "$out" '.fan.target_rpm')" "fan.target_rpm is numeric"
assert_eq "true" "$(jget "$out" '.fan.manual')" "a hold reports manual:true"
assert_eq "true" "$(jget "$out" '.hold.active')" "hold.active true in hold mode"
assert_eq "med" "$(jget "$out" '.hold.preset')" "hold.preset derives from target_rpm"
assert_eq "4200" "$(jget "$out" '.hold.rpm')" "hold.rpm is the target"
assert_eq "6" "$(jget "$out" '.presets | length')" "the preset list carries all six"
assert_eq "array" "$(jget "$out" '.thermal.sensors | type')" "sensors is an array"
assert_eq "array" "$(jget "$out" '.recent_errors | type')" "recent_errors is an array"
assert_eq "array" "$(jget "$out" '.warnings | type')" "warnings is an array"
assert_eq "[]" "$(jget "$out" '.warnings')" "no warnings on the happy path"
assert_eq "number" "$(jget "$out" '.thermal.t_eff_c | type')" \
    "fast-path thermal.t_eff_c is numeric"
assert_eq "true" "$(jget "$out" '.thermal.t_eff_c == 65')" \
    "fast path renders state.json's t_eff_c"
assert_eq "number" "$(jget "$out" '.daemon.uptime_s | type')" \
    "fast-path daemon.uptime_s is numeric once interval_s is cached"
assert_eq "2048" "$(jget "$out" '.daemon.uptime_s')" \
    "uptime_s is polls x interval_s (2048 polls at 1 s)"

# ---------------------------------------------------------------------------
# 2. status --full: sensor list and afanctl's own effective temperature
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode observe status --json --full 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "status --full exits 0"
assert_eq "true" "$(jget "$out" '.thermal.t_eff_c == 64')" \
    "--full renders afanctl's effective temperature"
assert_eq "3" "$(jget "$out" '.thermal.sensors | length')" "--full carries the sensor list"
assert_eq "Package id 0" "$(jget "$out" '.thermal.sensors[0].label')" "sensor labels are strings"
assert_eq "number" "$(jget "$out" '.thermal.sensors[0].temp_c | type')" "sensor temps are numeric"
assert_eq "omafan.status.v1" "$(jget "$out" '.schema')" "--full keeps the status schema"

# ---------------------------------------------------------------------------
# 3. presets --json: the section 4.2 ladder values
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode observe presets --json 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "presets exits 0"
assert_eq "omafan.presets.v1" "$(jget "$out" '.schema')" "presets.schema is the frozen id"
assert_eq "1200" "$(jget "$out" '.fan_min_rpm')" "presets.fan_min_rpm"
assert_eq "7200" "$(jget "$out" '.fan_max_rpm')" "presets.fan_max_rpm"
assert_eq "1200" "$(jget "$out" '.slider.min_rpm')" "slider.min_rpm is fan_min_rpm"
assert_eq "7200" "$(jget "$out" '.slider.max_rpm')" "slider.max_rpm is fan_max_rpm"
assert_eq "100" "$(jget "$out" '.slider.step_rpm')" "slider.step_rpm is 100"
assert_eq "auto,off,low,med,high,full" "$(jget "$out" '[.presets[].id] | join(",")')" \
    "preset ids are the section 3 order"
ladder_rpms='[.presets[].rpm] | map(if . == null then "null" else tostring end) | join(",")'
assert_eq "null,1200,2700,4200,5700,7200" "$(jget "$out" "$ladder_rpms")" \
    "the ladder rpms are derived from the live band"
assert_eq "release,hold,hold,hold,hold,hold" "$(jget "$out" '[.presets[].kind] | join(",")')" \
    "auto releases, the rest hold"
assert_eq "Auto (firmware)" "$(jget "$out" '.presets[0].label')" "auto label"
assert_eq "Off (hardware floor)" "$(jget "$out" '.presets[1].label')" \
    "off names the hardware floor, never 'fan off'"
assert_eq "Medium" "$(jget "$out" '.presets[3].label')" "med label"

# ---------------------------------------------------------------------------
# 4. doctor --json: the section 4.4 check set and ok semantics
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode observe doctor --json 2>/dev/null)"; rc=$?
assert_eq "omafan.doctor.v1" "$(jget "$out" '.schema')" "doctor.schema is the frozen id"
assert_eq "11" "$(jget "$out" '.checks | length')" "doctor emits the eleven fixed checks"
expected_ids="afanctl_present,afanctl_version,applesmc,coretemp,daemon_running,"
expected_ids+="hw_limits,keybindings,pkexec_present,polkit_rule,shell_ipc,state_fresh"
assert_eq "$expected_ids" "$(jget "$out" '[.checks[].id] | sort | join(",")')" \
    "the check id set is exactly section 4.4"
bad_status='[.checks[] | select(.status != "PASS"'
bad_status+=' and .status != "WARN" and .status != "FAIL")] | length'
assert_eq "0" "$(jget "$out" "$bad_status")" "every check status is PASS, WARN or FAIL"
assert_eq "$(jget "$out" '.checks | length')" \
    "$(jget "$out" '.summary.pass + .summary.warn + .summary.fail')" \
    "summary counts every check exactly once"
assert_eq "true" "$(jget "$out" '.ok == (.summary.fail == 0)')" \
    "doctor.ok is true iff no check FAILed"
daemon_check='.checks[] | select(.id == "daemon_running") | .status == "PASS"'
assert_eq "true" "$(jget "$out" "$daemon_check")" "daemon_running PASSes with a seeded state"
expected_rc=0
[ "$(jget "$out" '.ok')" = "true" ] || expected_rc=1
assert_eq "$expected_rc" "$rc" "doctor exit is 0 iff ok"
assert_eq "string" "$(jget "$out" '.checks[0].detail | type')" "check details are human strings"

# ---------------------------------------------------------------------------
# 5. write verbs: happy paths, argv, cmd.json
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode hold preset med 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "preset med exits 0"
assert_eq "omafan.action.v1" "$(jget "$out" '.schema')" "write verbs emit the action schema"
assert_eq "true" "$(jget "$out" '.ok')" "action.ok"
assert_eq "preset" "$(jget "$out" '.action')" "action kind"
assert_eq "med" "$(jget "$out" '.preset')" "action.preset"
assert_eq "hold" "$(jget "$out" '.mode')" "a preset write is a hold"
assert_eq "4200" "$(jget "$out" '.rpm')" "action.rpm is the derived hold rpm"
assert_eq "hold" "$(jget "$out" '.argv[1]')" "action.argv names the hold verb"
assert_eq "4200" "$(jget "$out" '.argv[2]')" "action.argv names the held rpm"
assert_eq "hold 4200" "$(argv_log)" "the fixture saw exactly one write"
assert_eq "hold" "$(jq -r '.mode' "$RUN/cmd.json")" "cmd.json records the hold mode"
assert_eq "4200" "$(jq -r '.rpm' "$RUN/cmd.json")" "cmd.json records the held rpm"

setup_case "$FIX/state-hold.json"
out="$(run_mode hold release 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "release exits 0"
assert_eq "auto" "$(jget "$out" '.preset')" "release is preset auto"
assert_eq "observe" "$(jget "$out" '.mode')" "release writes observe"
assert_eq "null" "$(jget "$out" '.rpm')" "release has no rpm"
assert_eq "observe" "$(argv_log)" "release logs exactly observe"

setup_case "$FIX/state-hold.json"
out="$(run_mode hold rpm 3000 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "rpm 3000 exits 0"
assert_eq "rpm" "$(jget "$out" '.action')" "rpm action kind"
assert_eq "3000" "$(jget "$out" '.rpm')" "rpm action rpm"
assert_eq "hold 3000" "$(argv_log)" "rpm logs the exact hold"

# ---------------------------------------------------------------------------
# 6. version / --help
# ---------------------------------------------------------------------------

assert_eq "omafan-ctl 1.0.0" "$("$CTL" version 2>/dev/null)" "version prints the CLI version"
assert_exit_code 0 "$CTL" --version
help="$("$CTL" --help 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "--help exits 0"
assert_contains "$help" "cycle" "--help documents the cycle verb (R5)"
assert_contains "$help" "exits 5" "--help documents the status/write exit-5 split (R6)"
assert_contains "$help" "tests/dev only" "--help documents the tests-only pkexec escape"

# ---------------------------------------------------------------------------
# 7. --dry-run: prints the argv, executes nothing
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode hold preset med --dry-run 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "dry-run exits 0 without a daemon"
assert_eq "hold" "$(jget "$out" '.argv[1]')" "dry-run prints the verb it would run"
assert_eq "4200" "$(jget "$out" '.argv[2]')" "dry-run prints the rpm it would hold"
assert_eq "true" "$(jget "$out" '.ok')" "dry-run is a success document"
assert_eq "0" "$(test -e "$RUN/argv.log" && echo 1 || echo 0)" "dry-run writes no argv.log"
assert_eq "0" "$(test -e "$RUN/cmd.json" && echo 1 || echo 0)" "dry-run writes no cmd.json"
out="$(run_mode hold preset med --dry-run --human 2>/dev/null)"
assert_contains "$out" "argv:" "human dry-run prints the argv"

# ---------------------------------------------------------------------------
# 8. exit 2: usage errors never exit 0
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
assert_exit_code 2 ctl bogus
assert_exit_code 2 ctl preset bogus
assert_exit_code 2 ctl rpm abc
assert_exit_code 2 ctl status --nope
assert_exit_code 2 ctl rpm 100001
assert_exit_code 2 "$CTL"

# ---------------------------------------------------------------------------
# 9. exit 3: authorisation denied or cancelled
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
cat > "$CASE/bin/pkexec" <<'EOF'
#!/usr/bin/env bash
# A polkit dismissal: pkexec reports 126 and writes to stderr.
echo "Error executing command as another user: Request dismissed" >&2
exit 126
EOF
chmod +x "$CASE/bin/pkexec"
# Bypass ctl so its trailing `--pkexec none` cannot mask the stub; the stub's
# path is absolute on purpose, mirroring a real pkexec the operator installed.
run_denied() {
    FAKE_AFANCTL_MODE=hold "$CTL" "$@" --afanctl "$FAKE" \
        --pkexec "$CASE/bin/pkexec" --runtime-dir "$RUN"
}
assert_exit_code 3 run_denied preset med

cat > "$CASE/bin/pkexec" <<'EOF'
#!/usr/bin/env bash
echo "Not authorized" >&2
exit 1
EOF
chmod +x "$CASE/bin/pkexec"
assert_exit_code 3 run_denied preset med

# ---------------------------------------------------------------------------
# 10. exit 4: afanctl missing or not executable
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$("$CTL" status --json --afanctl /nonexistent/afanctl --pkexec none \
    --runtime-dir "$RUN" 2>/dev/null)"; rc=$?
assert_eq 4 "$rc" "status exits 4 when afanctl is missing"
assert_eq "omafan.status.v1" "$(jget "$out" '.schema')" "status still renders a document"
assert_eq "false" "$(jget "$out" '.afanctl.present')" "afanctl.present is false"
assert_eq "false" "$(jget "$out" '.daemon.running')" "no afanctl means no daemon"
warn_text="$(jget "$out" '.warnings | join(" ")')"
assert_contains "$warn_text" "missing" "the warning names the missing binary"
assert_exit_code 4 "$CTL" preset med --afanctl /nonexistent/afanctl --pkexec none \
    --runtime-dir "$RUN"

# ---------------------------------------------------------------------------
# 11. exit 5: daemon not running / state.json absent (the R6 read/write split)
# ---------------------------------------------------------------------------

setup_case ""
out="$(run_mode observe status --json 2>/dev/null)"; rc=$?
assert_eq 5 "$rc" "status exits 5 when state.json is absent"
assert_eq "omafan.status.v1" "$(jget "$out" '.schema')" "status still renders a document (R6)"
assert_eq "true" "$(jget "$out" '.ok')" "the offline document is still ok:true"
assert_eq "false" "$(jget "$out" '.daemon.running')" "daemon.running is false offline"
assert_eq "true" "$(jget "$out" '.daemon.state_stale')" "an absent state is stale"
assert_contains "$(jget "$out" '.warnings | join(" ")')" "state.json is absent" \
    "the warning names the absent state file"
assert_exit_code 5 run_mode observe preset med
assert_exit_code 5 run_mode observe release

# ---------------------------------------------------------------------------
# 12. exit 6: degraded daemon refuses writes; --force overrides
# ---------------------------------------------------------------------------

setup_case "$FIX/state-monitor-only.json"
out="$(run_mode monitor-only preset med --json 2>/dev/null)"; rc=$?
assert_eq 6 "$rc" "monitor-only refuses a write with 6"
assert_eq "false" "$(jget "$out" '.ok')" "the refusal is ok:false"
assert_eq "monitor_only" "$(jget "$out" '.error')" "the error envelope names monitor_only"
assert_eq "6" "$(jget "$out" '.exit_code')" "the envelope carries the exit code"
assert_contains "$(jget "$out" '.message')" "systemctl restart afanctl" \
    "the refusal names the fix command"
assert_eq "0" "$(test -e "$RUN/argv.log" && echo 1 || echo 0)" "a refused write writes nothing"
assert_exit_code 0 run_mode monitor-only preset med --force

setup_case "$FIX/state-hold.json"
seed_state '.auto_restore_pending = true'
assert_exit_code 6 run_mode hold preset med
assert_exit_code 0 run_mode hold preset med --force

# ---------------------------------------------------------------------------
# 13. exit 7: rpm outside the hardware band; --force overrides
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(run_mode hold rpm 99999 --json 2>/dev/null)"; rc=$?
assert_eq 7 "$rc" "rpm above fan_max is refused with 7"
assert_eq "rpm_out_of_band" "$(jget "$out" '.error')" "the error envelope names rpm_out_of_band"
assert_eq "7" "$(jget "$out" '.exit_code')" "the envelope carries 7"
assert_exit_code 7 run_mode hold rpm 100
assert_eq "0" "$(test -e "$RUN/argv.log" && echo 1 || echo 0)" "an out-of-band write writes nothing"
assert_exit_code 0 run_mode hold rpm 99999 --force
assert_eq "hold 7200" "$(argv_log)" "--force reaches the fixture, which clamps at fan_max"

# ---------------------------------------------------------------------------
# 14. exit 8: the undercooling guard; --force overrides
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
hot_hold='.t_eff_c = 90.0 | .actual_rpm = 4794 | .mode = "hold"'
hot_hold+=' | .target_rpm = 4794 | .last_written_rpm = 4794'
seed_state "$hot_hold"
out="$(run_mode hold preset low --json 2>/dev/null)"; rc=$?
assert_eq 8 "$rc" "a below-firmware preset on a hot machine is refused with 8"
assert_eq "false" "$(jget "$out" '.ok')" "the undercooling refusal is ok:false"
assert_eq "undercooling_risk" "$(jget "$out" '.error')" "the envelope names undercooling_risk"
assert_eq "8" "$(jget "$out" '.exit_code')" "the envelope carries 8"
msg="$(jget "$out" '.message')"
assert_contains "$msg" "90" "the warning names the temperature"
assert_contains "$msg" "4794" "the warning names the current rpm"
assert_contains "$msg" "2700" "the warning names the requested rpm"
assert_contains "$msg" "below" "the warning says the hold is below the curve"
assert_contains "$msg" "Safe alternative" "the warning offers a safe alternative"
assert_contains "$msg" "force" "the warning names the override"
assert_eq "0" "$(test -e "$RUN/argv.log" && echo 1 || echo 0)" \
    "an undercooling refusal writes nothing"
assert_exit_code 0 run_mode hold preset low --force
assert_eq "hold 2700" "$(argv_log)" "--force overrides the undercooling guard"

# 14b. cycle inherits the same guard (R5)
setup_case "$FIX/state-hold.json"
hot_floor='.t_eff_c = 90.0 | .actual_rpm = 4794 | .mode = "hold"'
hot_floor+=' | .target_rpm = 1200 | .last_written_rpm = 1200'
seed_state "$hot_floor"
assert_exit_code 8 run_mode hold cycle
assert_exit_code 0 run_mode hold cycle --force
assert_eq "hold 2700" "$(argv_log)" "cycle --force applies the next preset"

# ---------------------------------------------------------------------------
# 15. hold.preset derivation, including custom
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
seed_state '.target_rpm = 4321 | .last_written_rpm = 4321 | .actual_rpm = 4300'
out="$(run_mode hold status --json 2>/dev/null)"
assert_eq "true" "$(jget "$out" '.hold.active')" "a hold is active"
assert_eq "custom" "$(jget "$out" '.hold.preset')" "a non-preset rpm derives custom"
assert_eq "4321" "$(jget "$out" '.hold.rpm')" "custom still reports its rpm"

setup_case "$FIX/state-hold.json"
seed_state '.target_rpm = 7200 | .last_written_rpm = 7200'
out="$(run_mode hold status --json 2>/dev/null)"
assert_eq "full" "$(jget "$out" '.hold.preset')" "a hold at fan_max derives full"

setup_case "$FIX/state-hold.json"
seed_state '.mode = "observe" | .target_rpm = null | .last_written_rpm = null | .actual_rpm = 1787'
out="$(run_mode observe status --json 2>/dev/null)"
assert_eq "false" "$(jget "$out" '.hold.active')" "observe mode has no active hold"
assert_eq "null" "$(jget "$out" '.hold.preset')" "observe mode has no preset"
assert_eq "null" "$(jget "$out" '.hold.rpm')" "observe mode has no hold rpm"
assert_eq "false" "$(jget "$out" '.fan.manual')" "observe mode is not manual"

# ---------------------------------------------------------------------------
# 16. stale state
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
touch -d '2 minutes ago' "$RUN/state.json"
out="$(run_mode hold status --json 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "a stale state is still rendered, not treated as offline"
assert_eq "true" "$(jget "$out" '.daemon.state_stale')" "state_stale is true past the 5 s floor"
assert_eq "true" "$(jget "$out" '.daemon.state_age_s > 5')" "state_age_s exceeds the stale floor"
assert_eq "true" "$(jget "$out" '.daemon.running')" "a stale state with a daemon still runs"

# ---------------------------------------------------------------------------
# 17. unwritable hardware-limit cache: a warning, never a failure
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
touch "$CASE/xdg-file" # a regular file cannot host the cache directory
XDG_RUNTIME_DIR="$CASE/xdg-file"
out="$(run_mode hold status --json 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "an unwritable cache dir does not fail the read"
assert_eq "true" "$(jget "$out" '.ok')" "the document is still ok"
assert_eq "true" "$(jget "$out" '([.warnings[] | select(test("cache"))] | length) > 0')" \
    "a cache warning is present"
assert_eq "true" "$(jget "$out" '.hardware.fan_min_rpm == 1200')" \
    "limits are still resolved despite the bad cache dir"

# ---------------------------------------------------------------------------
# 18. --pkexec none never invokes pkexec; reads never invoke it either
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
cat > "$CASE/bin/pkexec" <<'EOF'
#!/usr/bin/env bash
# Any invocation of this stub proves a privileged call happened; 99 is loud.
exit 99
EOF
chmod +x "$CASE/bin/pkexec"
with_stub() { PATH="$CASE/bin:$PATH" "$@"; }
assert_exit_code 0 with_stub run_mode hold status --json
assert_exit_code 0 with_stub run_mode hold presets --json
assert_exit_code 0 with_stub run_mode hold doctor --json
assert_exit_code 0 with_stub run_mode hold preset med --pkexec none
assert_eq "hold 4200" "$(argv_log)" "the write ran through afanctl, not pkexec"

# ---------------------------------------------------------------------------
# 19. notify-send absent: the exit code is unchanged
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
farm="$CASE/farm"
mkdir -p "$farm"
# A minimal PATH with no notify-send: every tool the CLI and fixture need.
for c in jq mktemp date stat id head tr cat grep env rm mkdir mv sed dirname \
    pwd bash sh true false find wc cut sort; do
    p="$(command -v "$c" 2>/dev/null || true)"
    case "$p" in
        /*) ln -sf -- "$p" "$farm/$c" ;;
    esac
done
assert_eq "0" "$(test -e "$farm/notify-send" && echo 1 || echo 0)" \
    "the reduced PATH deliberately omits notify-send"
with_farm() { PATH="$farm" "$@"; }
with_farm_fail() { PATH="$farm" AFANCTL_FAKE_FAIL=1 "$@"; }
assert_exit_code 0 with_farm run_mode hold preset med --notify
assert_exit_code 1 with_farm_fail run_mode hold preset med --notify

# ---------------------------------------------------------------------------
# 20. exit 1: runtime failures (afanctl write failed; unparsable state)
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
out="$(AFANCTL_FAKE_FAIL=1 run_mode hold preset med --json 2>/dev/null)"; rc=$?
assert_eq 1 "$rc" "a failing afanctl write exits 1"
assert_eq "false" "$(jget "$out" '.ok')" "the failure is ok:false"
assert_eq "write_failed" "$(jget "$out" '.error')" "the envelope names write_failed"

setup_case "$FIX/state-hold.json"
printf '{"schema":"bogus"}' > "$RUN/state.json"
assert_exit_code 1 run_mode hold status --json
assert_exit_code 1 run_mode hold preset med

# ---------------------------------------------------------------------------
# 21. cycle walks the section 3 ladder with wraparound (R5)
# ---------------------------------------------------------------------------

setup_case "$FIX/state-hold.json"
seed_state '.mode = "observe" | .target_rpm = null | .last_written_rpm = null'
out="$(run_mode observe cycle 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "cycle from auto exits 0"
assert_eq "cycle" "$(jget "$out" '.action')" "cycle reports its action kind"
assert_eq "off" "$(jget "$out" '.preset')" "auto cycles to off"
assert_eq "1200" "$(jget "$out" '.rpm')" "off holds the hardware floor"
assert_eq "hold 1200" "$(argv_log)" "cycle applies off through hold"

setup_case "$FIX/state-hold.json"
seed_state '.mode = "hold" | .target_rpm = 1200 | .last_written_rpm = 1200'
assert_exit_code 0 run_mode hold cycle
assert_eq "hold 2700" "$(argv_log)" "off cycles to low"

setup_case "$FIX/state-hold.json"
seed_state '.mode = "hold" | .target_rpm = 4321 | .last_written_rpm = 4321'
assert_exit_code 0 run_mode hold cycle
assert_eq "hold 1200" "$(argv_log)" "a custom hold cycles to off (section 4.5)"

setup_case "$FIX/state-hold.json"
seed_state '.mode = "hold" | .target_rpm = 7200 | .last_written_rpm = 7200'
out="$(run_mode hold cycle 2>/dev/null)"
assert_eq "auto" "$(jget "$out" '.preset')" "full cycles to auto"
assert_eq "observe" "$(jget "$out" '.mode')" "the wrap to auto is an observe write"
assert_eq "observe" "$(argv_log)" "cycle to auto logs observe"

setup_case "$FIX/state-hold.json"
seed_state '.mode = "observe" | .target_rpm = null | .last_written_rpm = null'
out="$(run_mode observe cycle --dry-run 2>/dev/null)"
assert_eq "off" "$(jget "$out" '.preset')" "cycle --dry-run names the next preset"
assert_eq "0" "$(test -e "$RUN/argv.log" && echo 1 || echo 0)" "cycle --dry-run writes nothing"

setup_case "$FIX/state-monitor-only.json"
assert_exit_code 6 run_mode monitor-only cycle

summarize
