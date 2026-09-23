# omafan testing

omafan ships two classes of tests: a **hardware-free gate** that must pass on
any machine, and two **opt-in live suites** for the machine that actually has a
fan. Nothing in the default gate writes to `/sys`, calls `pkexec`, or needs
root, and no test ever touches `/run/afanctl`.

## 1. The hardware-free gate

```sh
tests/run-all.sh
```

This runs the suites below in order, prints a final
`PASS suites n / FAIL suites m / SKIP k` line, and exits non-zero on the first
failure. A suite whose file has not been written yet is reported as `SKIP`
with a `missing:` note, so the harness is usable while the build is in
progress. Each suite can also be run alone.

| # | Suite | Run alone | What it proves |
|---|---|---|---|
| 1 | plugin validator | `tests/plugin-validate.sh` | `omarchy plugin validate .` exits 0: `schemaVersion == 1`, required fields, non-reserved id, one entry point, entry points safe and existing, no symlinks in the plugin tree (PRD §2.10, G1) |
| 2 | manifest | `tests/manifest.test.sh` | the marketplace-facing fields match DESIGN.md §1 (id, version, author, licence, homepage), the `bar-widget` kind and `entryPoints.barWidget` are correct, the settings schema keys/bounds/defaults are the ones the panel reads, and repo hygiene holds (no symlinks, GPL-3.0 `LICENSE`, `README.md` present, no secret patterns committed) |
| 3 | model | `node tests/model.test.mjs` | every pure function of DESIGN.md §5: the six-preset ladder for `(1200,7200)` → `1200/2700/4200/5700/7200`, `presetRpm("auto") === null`, clamping and snapping at both ends and for a step that does not divide the range, `cyclePreset` wrapping in both directions, `modeTone` for all four tones, `degradedReason` naming the fix for each degraded state, `parseStatus` on valid/invalid/wrong-schema input, `progressFraction`, `isStateStale(4)` false / `isStateStale(6)` true, the DESIGN.md §5.1 undercooling guard (cold, exactly 80 °C, 79 °C, equal target, higher target, null target, null status, warning text and its safe alternative), and the omafan#4 schema helpers `parseSchemaId`/`selectSchema` (exact, older-but-supported, newer-unknown, far-older, missing, malformed) with `parseStatus` tolerance of a newer `omafan.status.v*`. Prints `PASS n / FAIL m`. |
| 4 | ctl | `tests/ctl.test.sh` | every DESIGN.md §4 promise against the fake afanctl: each verb's happy path; exit codes 0,1,2,3,4,5,6,7,8 with the exact situation that produces each; `--force` overriding 6, 7 and 8; `--dry-run` printing the argv without writing; the `status --json`/`presets --json`/`doctor --json` documents field-by-field; the `hold.preset` derivation including `custom`; `--pkexec none` never invoking pkexec (asserted with a pkexec stub that exits 99 on PATH); missing afanctl → 4; stale state → `state_stale: true`; unwritable cache → warning not failure; absent notify-send → exit code unchanged; and (section 22) omafan#4 schema negotiation across the `FAKE_AFANCTL_SCHEMA` matrix, including the negotiated `status --schema` re-request and the newer `afanctl.state.v*` tolerance |
| 5 | keybindings | `tests/keybindings.test.sh` | install/remove/status/print against a sandboxed `HOME` and a stub `hyprctl`: exactly one managed block; install twice byte-identical; a conflicting chord refuses and writes nothing; remove restores byte-identically and exits 0 when there is nothing to remove; status reports installed/not-installed/conflict and `stale-path`; the emitted block equals the DESIGN.md §7 table for all eight chords; helper-path guards (missing, whitespace, quote) refuse safely |
| 6 | qml-lint | `tests/qml-lint.sh` | every shipped `*.qml` parses and its imports resolve, using `/usr/lib/qt6/bin/qmllint` against the installed shell. Because the shell's `qs.*` modules ship no `qmltypes`, the harness builds a shim import root and classifies diagnostics: syntax errors, unresolved imports and missing non-`qs.*` types are fatal; expected `qs.*` member warnings are reported, not fatal (ruling R3) |
| 7 | panel-slider | `tests/panel-slider.test.sh` | the T2 slider Auto-reset guards, asserted structurally against `Panel.qml` because the gate has no QML runtime: a confirmed Auto clears `pendingRpm` and a late status document never repopulates it (ruling R9) |
| 8 | panel-refresh | `tests/panel-refresh.test.sh` | the T5 in-panel REFRESH row, likewise structural: its own `Process` with its own deadline, no `pkexec`, no fan-write lock, the clamp through `Model.effectivePollSeconds`, and the row staying outside the keyboard cursor's two frozen sections (ruling R10) |
| 9 | branch-model | `tests/branch-model.test.sh` | the shipped branch carries no development material: it reads the tree of `master` (or `origin/master`) and fails naming every denylisted path it finds — `AGENTS.md` at any depth, `worknotes/`, `orchestration/`, `skills/`, `.githooks/`, `docs/agents/`, `PLAN.md`, `QUESTIONS.md`, `.recon/`, `.omc/`. Users clone the whole repository into `~/.config/omarchy/plugins/<id>`, so this is a plugin defect, not untidiness (rulings R11, R13). With no such ref in the clone it prints a visible `SKIPPED` line instead of passing quietly; `.github/workflows/ci.yml` fetches the ref and rejects that skip |

Related one-liners used while iterating:

```sh
bash -n bin/omafan-ctl bin/omafan-keybindings   # shell syntax
omarchy plugin validate .                       # the shell's own gate
```

### How the gate stays hardware-free

- `tests/fixtures/fake-afanctl` emulates the afanctl surface omafan uses
  (`status [--json]`, `hold <rpm>`, `observe`, `--version`). It validates an
  rpm against `1200..7200`, logs every write argv to
  `$runtime_dir/argv.log`, refuses to run without an explicit runtime dir, and
  refuses to run against the live `/run/afanctl` at all.
- Fixtures `status-observe.json`, `status-hold.json`, `state-hold.json` and
  `state-monitor-only.json` provide the daemon documents.
- Every CLI test passes `--afanctl <fixture> --pkexec none --runtime-dir <tmp>`:
  `--pkexec none` means the afanctl binary is executed directly, so no
  privilege runner is involved and no `/sys` write is possible from the
  fixture.
- Every keybinding test runs with a sandboxed `HOME`, a stub `hyprctl`, and a
  stub Hypr config tree; the real `~/.config/hypr/` is never touched.
- `tests/lib/harness.sh` provides `assert_eq`, `assert_ne`, `assert_contains`,
  `assert_exit_code`, `assert_json_eq` (via `jq -e`), `new_tmpdir` and
  `summarize`; it leaks no state between tests and is safe under
  `set -euo pipefail`.

## 2. Opt-in live suites

Both live suites are excluded from `tests/run-all.sh` and exit 0 with a printed
skip unless their switch is set. They are the only scripts allowed near real
hardware.

### 2.1 `tests/integration-shell.sh` — the shell, live

```sh
OMAFAN_LIVE=1 tests/integration-shell.sh
```

Proves the plugin loads and its IPC works end to end: the plugin is installed
at the DESIGN.md §1 path (or a temp plugin dir); `omarchy-shell shell
rescanPlugins`; `omarchy plugin list --json` lists the id with `enabled: true`;
`omarchy-shell omafan state` returns a document with
`schema == "omafan.status.v1"`; `omarchy-shell omafan preset bogus` returns an
error string; `omarchy-shell omafan toggle` and `close` both return; and the
last `qs log` lines contain no error mentioning the plugin id or its file
names.

It does not write to the fan. Running it against a live shell does not change
the fan mode; `preset bogus` is an intentional error path.

### 2.2 `tests/hw-smoke.sh` — the fan, live (supervised)

```sh
OMAFAN_HW=1 tests/hw-smoke.sh
```

This is the only script that commands real hardware. It refuses unless
`afanctl` is present and the daemon is running, and it requires an interactive
confirmation. Its policy is **never reduce airflow the firmware already
established**:

- It reads `t_eff_c` and the live rpm first.
- If `t_eff_c >= 75`, it exercises only holds at or **above** the current rpm
  (`high`, `full`) and skips `off`/`low`/`med` with a printed note.
- If `t_eff_c < 60`, it exercises the full ladder.
- Then, in order: read state → apply each allowed preset → verify `hold.active`
  with the expected rpm within 5 s → hold `full` for at most 2 s → **`release`
  immediately** → verify `mode: observe`, `manual: false`, and that
  `afanctl status --json` agrees → print a final table.
- An `EXIT` trap calls `release` (and verifies it) on any failure or
  interrupt, so the machine is left in `observe`.

Nothing in the script touches `/sys` directly; all writes go through
`omafan-ctl`. Do not run it unattended, and do not run it late at night on a
hot machine.

## 3. Which gate applies to which file

| Change | Run |
|---|---|
| `Model.js` | `node tests/model.test.mjs` |
| `bin/omafan-ctl` | `bash -n`, `tests/ctl.test.sh`, `tests/run-all.sh` |
| `bin/omafan-keybindings` | `bash -n`, `tests/keybindings.test.sh` |
| any `*.qml` | `tests/qml-lint.sh`, then a live load (integration suite) |
| `manifest.json` | `omarchy plugin validate .`, `tests/manifest.test.sh` |
| `docs/*`, `README.md` | the command audit: every quoted command exists (grep against the repo/DESIGN.md) |
| anything before a release | `tests/run-all.sh` |

The full acceptance gate for a release is PRD §4 (G1–G12); the tests above
provide G1–G3 and feed G4–G8.
