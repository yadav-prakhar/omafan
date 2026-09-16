# bin/

## OVERVIEW
bin/ is the sole afanctl interface: `omafan-ctl` (daemon verbs, JSON, writes via pkexec) and `omafan-keybindings` (Hyprland chord block manager).

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Reads: status/presets/doctor | `omafan-ctl` `run_status`/`run_doctor` | never pkexec; status still emits a doc when the daemon is down |
| Writes: preset/cycle/rpm/release | `omafan-ctl` | `write_prereqs` refuses degraded/stale/absent before any runner call |
| Undercooling guard | `omafan-ctl` `assert_undercooling` | hot (t_eff_c >= 80) + hold below current -> refuse; `--force` / `--force-undercooling` overrides |
| hw band + poll-interval cache | `omafan-ctl` `load_limits` | `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback `/tmp/omafan-<uid>/`), TTL 24 h |
| Chord block | `omafan-keybindings` | between `-- BEGIN omafan` / `-- END omafan` in `~/.config/hypr/bindings.lua`, `o.bind(chord, desc, cmd)` form |
| Conflict detection | `omafan-keybindings` `live_conflicts`/`lua_chord_conflicts` | live `hyprctl binds -j` (modmask 72) + Omarchy default Lua tree + user hypr dir |

## VERB TAXONOMY
- Reads: `status`, `presets`, `doctor`, `version`. Writes: `preset <id>`, `cycle`, `rpm <int>`, `release` (alias of `preset auto`).
- Preset ids (DESIGN.md frozen): `auto off low med high full`. CLI id for the floor hold is `off`; the UI label is `Floor (hardware floor)`. `off` never means stopped.
- afanctl side of a write is exactly `hold <rpm>` or `observe`.
- `rpm` takes an integer 0..100000; the band check against cached hw min/max runs before the runner.
- Globals parse in any position: `--afanctl`, `--runtime-dir`, `--config`, `--pkexec <path|none>`, `--json|--human` (json default), `--full`, `--notify|--no-notify`, `--dry-run`, `--force`, `--force-undercooling`.
- Env mirrors: `OMAFAN_AFANCTL`, `OMAFAN_RUNTIME_DIR`, `OMAFAN_PKEXEC`. Keybindings overrides: `OMAFAN_HYPR_CONFIG`, `OMAFAN_HYPRCTL`, `OMAFAN_STATE_DIR`, `OMAFAN_CTL`, `OMAFAN_DEFAULT_BINDINGS_DIR`.

## CONVENTIONS
- `set -euo pipefail`; no eval; every expansion quoted; scratch only via `tmpfile()`. Each scratch file is named for `$$` and reaped by `trap cleanup EXIT` from that name pattern — never from an array: `tmpfile()` is always called inside `$(...)`, so anything a subshell registers dies with it and the file leaks (see `tests/ctl.test.sh` "scratch reaping").
- Every external wait is bounded: runner 20 s, probes 3 s, notify-send 5 s. A runner timeout is reported as the auth refusal, never as success.
- `TIMEOUT_BIN` pins `/usr/bin/timeout` at startup: callers may clip PATH, and the hang guard must not be defeatable that way.
- All JSON is built by `jq -cn --arg/--argjson`, never printf-pasted; numeric compares (`is_undercooling_hot`) go through `jq -en` so jq does exact integer math.
- Daemon fields are extracted with `jq -c '.field // null'` and stay nullable; a missing reading is null, not 0.
- Privileged argv is exactly `[<runner>, <afanctl>, verb, args]`: no `env` wrapper, no extra flags. Custom `--runtime-dir`/`--config` on a write are refused at parse time (exit 2) because they cannot ride along past the argv pin.
- `usage()` in `omafan-keybindings` is self-printing (`sed -n '2,38p' "$0"` over the header comment); keep the header and the printed text in sync.
- The helper path is resolved at install time from `BASH_SOURCE` to an absolute path: Hyprland runs `bind ... exec` without the plugin on PATH.

## KEYBINDINGS BLOCK
- Eight chords `SUPER + ALT + {T,A,O,L,M,H,X,C}`. The panel toggle stays on `omarchy-shell` (on PATH); the seven fan chords call the resolved helper directly with `--notify`, so they survive a shell restart.
- The description strings are **mirrored and asserted verbatim**: this file, the `DESIGN.md` §7 table, `docs/KEYBINDINGS.md`, and the `print` assertion in `tests/keybindings.test.sh` must change together. The floor chord reads `omafan: fans floor` (id `off`); the older `… fans off (floor)` string is what broke the gate when only three of the four copies were updated.
- `install` writes or refreshes the block; refuses (exit 1) on any conflict, on an unusable helper (not executable, or path containing whitespace/quote/backslash), or when the compositor does not pick the block up after reload. First install keeps a timestamped backup under `~/.local/state/omafan-keybindings/`.
- `remove` cuts the block byte-identically and exits 0 when there is nothing to remove. `status` prints `installed|not-installed|conflict` plus per-chord verdicts. `print` touches nothing.
- Conflict sources, deduplicated: live binds with modmask 72 (own block excluded by its `omafan:` description prefix), the Omarchy default Lua tree, and the user's hypr config dir, with the managed block skipped. `code:<n>` chords conflict only when the keycode aliases one of our eight letters (`OMAFAN_KEYCODES`); Omarchy digits are code:10-19 and never collide.

## ANTI-PATTERNS
- NEVER let a read verb invoke the runner; pkexec appears on write paths only.
- NEVER insert anything between runner and afanctl (env wrapper, extra flag): afanctl's polkit rule matches argv exactly, and a mismatch falls back to a password prompt that hangs the panel.
- NEVER build JSON by string interpolation; hand-pasted fragments break the schema the panel parses.
- NEVER run an unbounded wait (pkexec, hyprctl, notify-send, afanctl probe); a hanging polkit prompt freezes the caller forever.
- NEVER coerce a missing rpm/temp to 0; jq null flows through to the envelope.
- NEVER bind a digit chord or a bare `omafan-ctl` in the block: digits are taken on Omarchy, and a bare name fails at key-press time.
- NEVER hand-edit inside the managed block; install overwrites it. Marker lines are exact matches, so the awk scan and the block surgery both depend on the literal `-- BEGIN omafan` / `-- END omafan` text.
- NEVER resolve the helper lazily at key press; resolve and validate once at install.
