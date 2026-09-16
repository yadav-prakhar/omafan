#!/usr/bin/env bash
# tests/keybindings.test.sh - bin/omafan-keybindings against a sandboxed HOME,
# a stub hyprctl and a stub Hypr config tree. No real compositor, no real
# ~/.config/hypr, no hardware: everything lives under per-case tempdirs.
#
# The stub compositor derives its live bind list from the target
# bindings.lua (as a real compositor does after `hyprctl reload`); a test
# may additionally seed a live-bindings JSON via OMAFAN_STUB_BINDS to stand
# in for bindings that exist only in the compositor's memory.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$repo/tests/lib/harness.sh"

KB="$repo/bin/omafan-keybindings"

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

stub_hyprctl() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    binds)
        # Live entries: seeded bindings (compositor memory)...
        derived="$(
            {
                if [ -s "$OMAFAN_STUB_MEM" ]; then jq -c '.[]' "$OMAFAN_STUB_MEM"; fi
                # ...plus derived entries: every o.bind on disk, as a
                # compositor that just re-read its config would report.
                grep '^o\.bind(' "$OMAFAN_HYPR_CONFIG" 2>/dev/null |
                    sed -n 's|^o\.bind("SUPER + ALT + \([^"]*\)", "\([^"]*\)".*|\1\t\2|p' |
                    jq -R -c 'split("\t") as $p |
                              { modmask: 72, key: $p[0], description: $p[1] }'
            } | paste -sd, -
        )"
        printf '[%s]\n' "$derived"
        ;;
    reload) printf 'reloaded\n' ;;
    *) exit 1 ;;
esac
STUB
    chmod +x "$dir/hyprctl"
}

# sandbox <seeded-live-binds-json> - a fresh case dir: sandboxed HOME, stub
# Hypr tree, stub hyprctl. Exports the OMAFAN_* overrides, prints the dir.
sandbox() {
    local dir
    dir="$(new_tmpdir)"
    mkdir -p "$dir/home/.config/hypr" "$dir/bin" "$dir/defaults" "$dir/state"
    stub_hyprctl "$dir/bin"
    printf '%s' "$1" > "$dir/mem.json"
    HOME="$dir/home"
    OMAFAN_HYPR_CONFIG="$dir/home/.config/hypr/bindings.lua"
    OMAFAN_HYPRCTL="$dir/bin/hyprctl"
    OMAFAN_STATE_DIR="$dir/state"
    OMAFAN_DEFAULT_BINDINGS_DIR="$dir/defaults"
    OMAFAN_STUB_MEM="$dir/mem.json"
    # T06b: the helper override defaults to unset, so the plugin's own
    # bin/omafan-ctl resolves; cases that exercise the guard export their own.
    unset OMAFAN_CTL
    SANDBOXDIR="$dir"
    HOMEDIR="$dir/home"
    HKDIR="$HOMEDIR/.config/hypr"
    STATEDIR="$dir/state"
    DEFAULTS="$dir/defaults"
    export HOME OMAFAN_HYPR_CONFIG OMAFAN_HYPRCTL OMAFAN_STATE_DIR \
        OMAFAN_DEFAULT_BINDINGS_DIR OMAFAN_STUB_MEM
    # (callers read the overrides, not the printed path; nothing is emitted)
    true
}

unsandbox() {
    unset HOME OMAFAN_HYPR_CONFIG OMAFAN_HYPRCTL OMAFAN_STATE_DIR \
        OMAFAN_DEFAULT_BINDINGS_DIR OMAFAN_STUB_MEM OMAFAN_CTL \
        SANDBOXDIR HOMEDIR HKDIR STATEDIR DEFAULTS || true
}

# the eight chords in DESIGN.md section 7 order (pipe-joined)
CHORDS_EXPECTED="SUPER + ALT + T|SUPER + ALT + A|SUPER + ALT + O|SUPER + ALT + L|SUPER + ALT + M|SUPER + ALT + H|SUPER + ALT + X|SUPER + ALT + C|"

block_chords() {
    grep '^o\.bind(' "$1" | sed 's/o\.bind("\([^"]*\)".*/\1/' | tr '\n' '|'
}

block_descs() {
    grep '^o\.bind(' "$1" | sed 's/o\.bind("[^"]*", "\([^"]*\)".*/\1/' | tr '\n' '|'
}

# ---------------------------------------------------------------------------
# 0. syntax gate
# ---------------------------------------------------------------------------

assert_exit_code 0 bash -n "$KB"

# ---------------------------------------------------------------------------
# 1. install on a fresh HOME (no bindings.lua yet)
# ---------------------------------------------------------------------------

sandbox '[]'
assert_exit_code 0 "$KB" install
assert_eq "1" "$(grep -cFx -e '-- BEGIN omafan' "$OMAFAN_HYPR_CONFIG")" \
    "install writes exactly one block (fresh HOME)"
assert_eq "$CHORDS_EXPECTED" "$(block_chords "$OMAFAN_HYPR_CONFIG")" \
    "fresh install carries all eight section 7 chords in table order"
assert_eq "0" "$(ls -1A "$STATEDIR" | wc -l)" \
    "no backup taken when no pre-install file existed"
unsandbox

# ---------------------------------------------------------------------------
# 2. install into an existing bindings.lua: original content kept, backup made
# ---------------------------------------------------------------------------

sandbox '[]'
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
-- mine
o.bind("SUPER + Q", "my own", "true")
EOF
assert_exit_code 0 "$KB" install
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" '-- mine' \
    "existing user content survives the install"
assert_eq "1" "$(grep -cFx -e '-- BEGIN omafan' "$OMAFAN_HYPR_CONFIG")" \
    "install writes exactly one block (existing file)"
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" \
    'o.bind("SUPER + ALT + T", "omafan: toggle fan panel", "omarchy-shell omafan toggle")' \
    "the toggle chord is in the block"
assert_eq "1" "$(ls -1 "$STATEDIR" | wc -l)" \
    "first install takes exactly one backup"
assert_eq "-- mine" "$(head -n 1 "$(ls -1d "$STATEDIR"/*)")" \
    "backup holds the pre-install content"
unsandbox

# ---------------------------------------------------------------------------
# 3. idempotence: install twice leaves the file byte-identical
# ---------------------------------------------------------------------------

sandbox '[]'
printf 'extra = "content"\n' > "$OMAFAN_HYPR_CONFIG"
assert_exit_code 0 "$KB" install
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/after1"
assert_exit_code 0 "$KB" install
assert_eq "0" "$?" "second install exits 0"
cmp -s "$HOMEDIR/after1" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "install twice is byte-identical"
assert_eq "1" "$(grep -cFx -e '-- BEGIN omafan' "$OMAFAN_HYPR_CONFIG")" \
    "re-install does not add a second block"
unsandbox

# ---------------------------------------------------------------------------
# 4. conflict via the live compositor: refuse, write nothing
# ---------------------------------------------------------------------------

sandbox '[
  {"modmask":72,"key":"T","description":"Some other tool"}
]'
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
untouched = true
EOF
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/expected"
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "conflicting live chord makes install fail"
cmp -s "$HOMEDIR/expected" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "refused install leaves the file untouched"
assert_contains "$out" 'SUPER + ALT + T is already live-bound to "Some other tool"' \
    "conflict output names the chord and its rival description"
unsandbox

# ---------------------------------------------------------------------------
# 5. conflict in the Omarchy default Lua tree: refuse, write nothing
# ---------------------------------------------------------------------------

sandbox '[]'
printf 'o.bind("SUPER + ALT + M", "od", "true")\n' > "$DEFAULTS/others.lua"
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
untouched = true
EOF
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/expected"
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "default-tree conflict makes install fail"
cmp -s "$HOMEDIR/expected" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "refused install (defaults) leaves the file untouched"
assert_contains "$out" 'SUPER + ALT + M is bound in the Omarchy defaults' \
    "conflict output names the default-tree chord"
assert_eq "0" "$(grep -c omafan "$OMAFAN_HYPR_CONFIG")" \
    "no omafan trace in the refused file"
unsandbox

# ---------------------------------------------------------------------------
# 6. conflict via a code: chord in the user tree; digit code: chords do not block
# ---------------------------------------------------------------------------

sandbox '[]'
printf 'o.bind("SUPER + ALT + code:28", "alias T", "true")\n' > "$HKDIR/others.lua"
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
untouched = true
EOF
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/expected"
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "code:28 (= T) conflict makes install fail"
cmp -s "$HOMEDIR/expected" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "refused install (code chord) leaves the file untouched"
assert_contains "$out" 'SUPER + ALT + code:28 is bound in' \
    "conflict output names the code: chord"
unsandbox

# 6b: a code: chord on a digit key must not block the install (checked inside)
sandbox '[]'
printf 'o.bind("SUPER + ALT + code:20", "digit one", "true")\n' > "$HKDIR/digits.lua"
"$KB" install >/dev/null 2>&1
assert_eq "0" "$?" "a code: chord on a digit key must not block the install"
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" '-- BEGIN omafan' \
    "digit code: chord case still installs the block"
unsandbox

# ---------------------------------------------------------------------------
# 7. remove restores byte-identical content; nothing to remove exits 0
# ---------------------------------------------------------------------------

sandbox '[]'
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
-- my stuff
o.bind("SUPER + Z", "zed", "true")
EOF
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/original"
assert_exit_code 0 "$KB" install
assert_exit_code 0 "$KB" remove
cmp -s "$HOMEDIR/original" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "remove restores the pre-install file byte-identically"
assert_exit_code 0 "$KB" remove
unsandbox

# remove without any backup (a pre-existing block someone else wrote)
sandbox '[]'
cat > "$OMAFAN_HYPR_CONFIG" <<'EOF'
pre = 1

-- BEGIN omafan
-- forged content
-- END omafan
EOF
assert_exit_code 0 "$KB" remove
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" 'pre = 1' \
    "backupless remove keeps the surrounding content"
assert_eq "0" "$(grep -c omafan "$OMAFAN_HYPR_CONFIG")" \
    "backupless remove cuts the block"
unsandbox

# ---------------------------------------------------------------------------
# 8. status: installed / not-installed / conflict
# ---------------------------------------------------------------------------

sandbox '[]'
out="$("$KB" status)"
assert_exit_code 0 "$KB" status
assert_contains "$out" 'block: not-installed' \
    "status reports not-installed with no block present"
assert_exit_code 0 "$KB" install
out="$("$KB" status)"
assert_exit_code 0 "$KB" status
assert_contains "$out" 'block: installed' \
    "status reports installed once the block is on disk"
assert_contains "$out" 'SUPER + ALT + T' \
    "status lists per-chord verdicts"
unsandbox

sandbox '[
  {"modmask":72,"key":"X","description":"Rival"}
]'
out="$("$KB" status 2>&1)"
assert_ne "0" "$?" "status exits 1 on conflict"
assert_contains "$out" 'conflict' "status states the conflict word"
assert_contains "$out" 'SUPER + ALT + X is already live-bound to "Rival"' \
    "status names the conflicting chord"
unsandbox

# ---------------------------------------------------------------------------
# 9. print: block on stdout only, exactly the section 7 table, nothing written
# ---------------------------------------------------------------------------

sandbox '[]'
out="$("$KB" print)"
assert_eq "$CHORDS_EXPECTED" "$(printf '%s\n' "$out" | grep '^o\.bind(' | sed 's/o\.bind("\([^"]*\)".*/\1/' | tr '\n' '|')" \
    "print emits the section 7 chord table (chords)"
assert_eq "omafan: toggle fan panel|omafan: fans auto (firmware)|omafan: fans floor|omafan: fans low|omafan: fans medium|omafan: fans high|omafan: fans full|omafan: cycle fan presets|" \
    "$(printf '%s\n' "$out" | grep '^o\.bind(' | sed 's/o\.bind("[^"]*", "\([^"]*\)".*/\1/' | tr '\n' '|')" \
    "print emits the section 7 chord table (descriptions)"
assert_exit_code 0 test ! -f "$OMAFAN_HYPR_CONFIG"
unsandbox

# ---------------------------------------------------------------------------
# 10. usage errors never exit 0
# ---------------------------------------------------------------------------

sandbox '[]'
assert_exit_code 2 "$KB" bogus
assert_exit_code 2 "$KB"
assert_exit_code 2 "$KB" --help
unsandbox

# ---------------------------------------------------------------------------
# 11. helper-path defects (T06b D1-D4)
# ---------------------------------------------------------------------------

# helper_emit() -> the command field of every o.bind line in <file>
block_cmds() {
    grep '^o\.bind(' "$1" | sed -n 's/^o\.bind("[^"]*", "[^"]*", "\(.*\)")$/\1/p'
}

# 11a (D1): the block carries an absolute helper path that exists as an
# executable inside the tempdir; no bare `omafan-ctl` token remains.
sandbox '[]'
SBOX="$SANDBOXDIR"
mkdir -p "$SBOX/ctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SBOX/ctl/omafan-ctl"
chmod +x "$SBOX/ctl/omafan-ctl"
OMAFAN_CTL="$SBOX/ctl/omafan-ctl"
export OMAFAN_CTL

assert_exit_code 0 "$KB" install
assert_eq "0" "$(grep -cE '^o\.bind\("[^"]*", "[^"]*", "omafan-ctl ' "$OMAFAN_HYPR_CONFIG")" \
    "no bare omafan-ctl token remains in the block"
assert_eq "0" "$(grep -cE ' o\.bind\([^"]*, "[^"]*", "omafan-ctl' "$OMAFAN_HYPR_CONFIG")" \
    "every helper call is an absolute path, not a PATH lookup"
block_cmds "$OMAFAN_HYPR_CONFIG" | grep -E ' (preset|cycle) ' |
while IFS= read -r cmd; do
    assert_eq "0" "$(test -x "${cmd%% *}"; printf %s $?)" \
        "helper path in the block is an executable: ${cmd%% *}"
done
unset OMAFAN_CTL
unsandbox

# 11b (D2): install refuses when OMAFAN_CTL points at a missing file;
# target file untouched.
sandbox '[]'
printf 'untouched = true\n' > "$OMAFAN_HYPR_CONFIG"
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/expected"
OMAFAN_CTL="$SANDBOXDIR/ctl/missing-omafan-ctl"
export OMAFAN_CTL
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "missing OMAFAN_CTL helper makes install fail"
cmp -s "$HOMEDIR/expected" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "refused install (missing helper) leaves the file untouched"
assert_contains "$out" 'not an executable file' \
    "refusal names the helper problem and the fix"
unsandbox

# 11c (D2): install refuses when OMAFAN_CTL contains a space.
sandbox '[]'
mkdir -p "$SANDBOXDIR/ctlspace dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOXDIR/ctlspace dir/omafan-ctl"
chmod +x "$SANDBOXDIR/ctlspace dir/omafan-ctl"
printf 'untouched = true\n' > "$OMAFAN_HYPR_CONFIG"
cp "$OMAFAN_HYPR_CONFIG" "$HOMEDIR/expected"
OMAFAN_CTL="$SANDBOXDIR/ctlspace dir/omafan-ctl"
export OMAFAN_CTL
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "helper path with a space makes install fail"
cmp -s "$HOMEDIR/expected" "$OMAFAN_HYPR_CONFIG"
assert_eq "0" "$?" "refused install (space in path) leaves the file untouched"
assert_contains "$out" 'whitespace' \
    "refusal names the unsafe whitespace in the helper path"
unset OMAFAN_CTL
unsandbox

# 11d (D2): install refuses on a quote character too (defence in depth).
sandbox '[]'
mkdir -p "$SANDBOXDIR/ctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOXDIR/ctl/omafan'quote"
chmod +x "$SANDBOXDIR/ctl/omafan'quote"
printf '' > "$OMAFAN_HYPR_CONFIG"
OMAFAN_CTL="$SANDBOXDIR/ctl/omafan'quote"
export OMAFAN_CTL
out="$("$KB" install 2>&1)"
assert_ne "0" "$?" "helper path with a quote makes install fail"
assert_contains "$out" 'whitespace, a quote or a backslash' \
    "refusal names the unquotable character"
unset OMAFAN_CTL
unsandbox

# 11e (D3): status reports stale-path when the block on disk calls a helper
# path different from the one that resolves now; re-install refreshes it.
sandbox '[]'
SBOX="$SANDBOXDIR"
mkdir -p "$SBOX/ctla" "$SBOX/ctlb"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SBOX/ctla/omafan-ctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SBOX/ctlb/omafan-ctl"
chmod +x "$SBOX/ctla/omafan-ctl" "$SBOX/ctlb/omafan-ctl"

OMAFAN_CTL="$SBOX/ctla/omafan-ctl"
export OMAFAN_CTL
assert_exit_code 0 "$KB" install
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" "$SBOX/ctla/omafan-ctl" \
    "the block names helper ctla as installed"

OMAFAN_CTL="$SBOX/ctlb/omafan-ctl"
out="$("$KB" status)"
assert_exit_code 0 "$KB" status
assert_contains "$out" 'stale-path' "status reports stale-path after the ctl path moved"
assert_contains "$out" 're-run install' "the stale-path line names the fix"
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" "$SBOX/ctla/omafan-ctl" \
    "status wrote nothing; the block still calls the old helper"

assert_exit_code 0 "$KB" install
assert_contains "$(cat "$OMAFAN_HYPR_CONFIG")" "$SBOX/ctlb/omafan-ctl" \
    "re-running install refreshes the block to the current helper"
first_helper="$(block_cmds "$OMAFAN_HYPR_CONFIG" |
    grep -E ' (preset|cycle) ' | grep -o '^[^ ]*' | head -n 1)"
assert_eq "$SBOX/ctlb/omafan-ctl" "$first_helper" \
    "the refreshed block calls the new helper as its first token"
if grep -q 'ctla/omafan-ctl' "$OMAFAN_HYPR_CONFIG" 2>/dev/null; then
    assert_eq "0" "1" "old helper ctla must be gone after the refresh"
else
    assert_eq "0" "0" "old helper ctla is gone after the refresh"
fi
unset OMAFAN_CTL
unsandbox

summarize
