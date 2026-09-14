#!/usr/bin/env bash
# tests/lib/harness.sh - shared assertion helpers for omafan's test suites.
#
# Source it (do not execute it) from a test script:
#     source "$(dirname "$0")/lib/harness.sh"
#     assert_eq 1 1 "one is one"
#     summarize
#
# A failed assertion records a failure and returns 0, so a suite never aborts
# mid-run under `set -e` and `summarize` can report every failure. `summarize`
# prints `PASS n / FAIL m`, removes the harness temp root, and returns non-zero
# when anything failed. Run this file directly to self-test the helpers.

# Shared counters. Prefixed so they cannot collide with a suite's own variables.
_HARNESS_PASS=0
_HARNESS_FAIL=0

# All case temp dirs live under one root created at source time. `new_tmpdir`
# is normally used in a command substitution (a subshell), so a root assigned
# lazily inside it would not survive in the caller; creating it here keeps the
# accounting in the parent shell. `harness_cleanup` removes the whole tree, so
# no temp state leaks between suites.
if [ -z "${_HARNESS_TMPROOT:-}" ]; then
    _HARNESS_TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/omafan-test.XXXXXX")"
fi

_harness_pass() { _HARNESS_PASS=$((_HARNESS_PASS + 1)); }

_harness_fail() {
    _HARNESS_FAIL=$((_HARNESS_FAIL + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

# assert_eq <expected> <actual> [message]
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    if [ "$expected" = "$actual" ]; then
        _harness_pass
    else
        _harness_fail "$msg: expected [$expected], got [$actual]"
    fi
}

# assert_ne <unexpected> <actual> [message]
assert_ne() {
    local unexpected="$1" actual="$2" msg="${3:-assert_ne}"
    if [ "$unexpected" != "$actual" ]; then
        _harness_pass
    else
        _harness_fail "$msg: did not expect [$unexpected]"
    fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    case "$haystack" in
        *"$needle"*)
            _harness_pass ;;
        *)
            _harness_fail "$msg: [$haystack] does not contain [$needle]" ;;
    esac
}

# assert_exit_code <expected-code> <command> [args...]
# Runs the command, swallows its output, and compares its exit code.
assert_exit_code() {
    local expected="$1"
    shift
    local rc=0
    # The `|| rc=$?` form keeps the call safe under `set -e`.
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq "$expected" ]; then
        _harness_pass
    else
        _harness_fail "assert_exit_code: [$*] exited $rc, expected $expected"
    fi
}

# assert_json_eq <expected-json> <actual-json> [message]
# Compares two JSON values semantically (key order and whitespace do not
# matter). Not-valid JSON on either side counts as a failure.
assert_json_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_json_eq}"
    if jq -e -n --argjson expected "$expected" --argjson actual "$actual" \
        '$expected == $actual' >/dev/null 2>&1; then
        _harness_pass
    else
        _harness_fail "$msg: JSON mismatch (expected=$expected actual=$actual)"
    fi
}

# new_tmpdir -> prints a fresh empty temp dir under the harness root.
new_tmpdir() {
    mktemp -d "$_HARNESS_TMPROOT/case.XXXXXX"
}

# Remove the harness temp root. `summarize` calls this; a suite may also call it
# from its own `trap ... EXIT` handler when it needs output kept on failure.
harness_cleanup() {
    if [ -n "${_HARNESS_TMPROOT:-}" ] && [ -d "$_HARNESS_TMPROOT" ]; then
        rm -rf -- "$_HARNESS_TMPROOT"
    fi
    _HARNESS_TMPROOT=""
}

# reset_counts - clear the counters (used by the self-test probes).
reset_counts() {
    _HARNESS_PASS=0
    _HARNESS_FAIL=0
}

# summarize -> prints `PASS n / FAIL m`, cleans up, non-zero if any failure.
summarize() {
    printf 'PASS %d / FAIL %d\n' "$_HARNESS_PASS" "$_HARNESS_FAIL"
    local failed="$_HARNESS_FAIL"
    harness_cleanup
    [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Self-test: run this file directly (`bash tests/lib/harness.sh`) to prove the
# helpers count and clean correctly. Sourced use never reaches this block.
# ---------------------------------------------------------------------------

_selftest_assert_eq_pass() { reset_counts; assert_eq 1 1; [ "$_HARNESS_PASS" -eq 1 ] && [ "$_HARNESS_FAIL" -eq 0 ]; }
_selftest_assert_eq_fail() { reset_counts; assert_eq 1 2; [ "$_HARNESS_FAIL" -eq 1 ] && [ "$_HARNESS_PASS" -eq 0 ]; }
_selftest_assert_ne_pass() { reset_counts; assert_ne 1 2; [ "$_HARNESS_PASS" -eq 1 ] && [ "$_HARNESS_FAIL" -eq 0 ]; }
_selftest_assert_ne_fail() { reset_counts; assert_ne 1 1; [ "$_HARNESS_FAIL" -eq 1 ]; }
_selftest_assert_contains_pass() { reset_counts; assert_contains "hello world" "lo wo"; [ "$_HARNESS_PASS" -eq 1 ]; }
_selftest_assert_contains_fail() { reset_counts; assert_contains "hello" "xyz"; [ "$_HARNESS_FAIL" -eq 1 ]; }
_selftest_assert_exit_code_pass() { reset_counts; assert_exit_code 0 true; [ "$_HARNESS_PASS" -eq 1 ]; }
_selftest_assert_exit_code_fail() { reset_counts; assert_exit_code 0 false; [ "$_HARNESS_FAIL" -eq 1 ]; }
_selftest_assert_json_eq_pass() { reset_counts; assert_json_eq '{"a":1,"b":[2,3]}' '{"b":[2,3],"a":1}'; [ "$_HARNESS_PASS" -eq 1 ]; }
_selftest_assert_json_eq_fail() { reset_counts; assert_json_eq '{"a":1}' '{"a":2}'; [ "$_HARNESS_FAIL" -eq 1 ]; }
_selftest_assert_json_eq_invalid() { reset_counts; assert_json_eq 'not-json' '{}'; [ "$_HARNESS_FAIL" -eq 1 ]; }

_selftest_new_tmpdir() {
    local d
    d="$(new_tmpdir)"
    [ -d "$d" ] || return 1
    case "$d" in
        "$_HARNESS_TMPROOT"/*)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

_harness_selftest() {
    local total=0 fail=0 probe err
    for probe in \
        _selftest_assert_eq_pass \
        _selftest_assert_eq_fail \
        _selftest_assert_ne_pass \
        _selftest_assert_ne_fail \
        _selftest_assert_contains_pass \
        _selftest_assert_contains_fail \
        _selftest_assert_exit_code_pass \
        _selftest_assert_exit_code_fail \
        _selftest_assert_json_eq_pass \
        _selftest_assert_json_eq_fail \
        _selftest_assert_json_eq_invalid \
        _selftest_new_tmpdir; do
        total=$((total + 1))
        # Each probe runs in a subshell so the shared counters stay pristine.
        # Probes that deliberately fail still return 0; their expected-failure
        # noise is captured and dropped, and only a real probe failure prints.
        if ! err="$("$probe" 2>&1)"; then
            fail=$((fail + 1))
            printf 'FAIL: harness self-test: %s\n%s\n' "$probe" "$err" >&2
        fi
    done
    printf 'PASS %d / FAIL %d\n' "$((total - fail))" "$fail"
    harness_cleanup
    [ "$fail" -eq 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    _harness_selftest
fi
