# PLAN.md — omafan build plan (phases, tickets, model assignment, runbook)

**Orchestrator:** Hermes Agent (`deepseek-v4.1-flash`, provider `opencode-go`).
**Workers:** OpenCode CLI one-shot sessions pinned per ticket
(`opencode run --model <model> --variant <v>`), provider `opencode-go`.
**Repo:** `/home/prakhar/Work/tries/2026-09-15-omafan` (git initialised; the
orchestrator alone commits).
**Frozen interfaces:** `DESIGN.md`. **Requirements:** `PRD.md`.
**Change channel:** `orchestration/QUESTIONS.md` (questions) and
`DEVIATIONS.md` (proposed contract changes: old → new → why → affected tickets).
A worker never edits another ticket's files and never edits `DESIGN.md`.

## Model routing (operator's rule)

| Tier | Model | `opencode run` invocation | Used for |
|---|---|---|---|
| trivial/mechanical | **MiMo V2.5** | `--model opencode-go/mimo-v2.5` | manifests, static overlays, changelog, lint harnesses |
| moderate | **deepseek v4.1 flash** | `--model opencode-go/deepseek-v4.1-flash` | fixtures, tests, docs, bar widget |
| complex/safety-critical | **glm 5.3 flash** | `--model opencode-go/glm-5.3-flash --variant high` | the privileged CLI, the keybinding installer, the panel state machine |
| review | **glm 5.3** | `--model opencode-go/glm-5.3 --variant high` | adversarial read-only review rounds |

## Phases, tickets, ownership

`—` = no other ticket may edit that file. **Dep** = must be merged before dispatch.

| Phase | Ticket | Model | Owns (exclusive) | Dep | Gate |
|---|---|---|---|---|---|
| P0 | recon + contracts (done) | orchestrator | `PRD.md`, `DESIGN.md`, `PLAN.md`, `.recon/` | — | contracts frozen |
| P1 | **T01** manifest + validate/lint harnesses | MiMo V2.5 | `manifest.json`, `tests/plugin-validate.sh`, `tests/qml-lint.sh` | — | `omarchy plugin validate .`, both harnesses exit 0 |
| P1 | **T02** `Model.js` + node unit tests | deepseek v4.1 flash | `Model.js`, `tests/model.test.mjs` | — | `node tests/model.test.mjs` all PASS |
| P2 | **T02b** `Model.js` undercooling-guard amendment | deepseek v4.1 flash | `Model.js`, `tests/model.test.mjs` (additive only) | T02 | new §5.1 functions table-tested; existing tests still PASS |
| P1 | **T03** test fixtures + harness lib | deepseek v4.1 flash | `tests/fixtures/**`, `tests/lib/harness.sh` | — | `tests/lib/harness.sh` self-test; fake afanctl emulates §4 of DESIGN.md |
| P2 | **T04** `bin/omafan-ctl` | glm 5.3 flash high | `bin/omafan-ctl` | T03 | `tests/ctl.test.sh` (T05) PASS + `--dry-run` argv proven |
| P2 | **T05** `tests/ctl.test.sh` | deepseek v4.1 flash | `tests/ctl.test.sh` | T03, T04 | runs green against T04; every exit code §4 exercised |
| P2 | **T06** `bin/omafan-keybindings` + `tests/keybindings.test.sh` | glm 5.3 flash high | `bin/omafan-keybindings`, `tests/keybindings.test.sh` | — | tempdir install/remove/conflict tests PASS; free-chord assertion reproduces PRD §2.7 |
| P2 | **T06b** keybindings fix round (helper path, guards, status) | glm 5.3 flash high | `bin/omafan-keybindings`, `tests/keybindings.test.sh` | T06 | defect list D1-D4 closed; suite ≥ 58 assertions green |
| P3 | **T07** `BarWidget.qml` | deepseek v4.1 flash | `BarWidget.qml` | T01, T02 | `tests/qml-lint.sh` clean; live load shows no `qs log` error |
| P3 | **T08** `KeyboardHelp.qml` | MiMo V2.5 | `KeyboardHelp.qml` | T01 | `tests/qml-lint.sh` clean |
| P3 | **T09** `Panel.qml` | glm 5.3 flash high | `Panel.qml` | T01, T02, T04 | `tests/qml-lint.sh` clean; live IPC round-trip G5 |
| P4 | **T10** `tests/integration-shell.sh` + `tests/hw-smoke.sh` | deepseek v4.1 flash | both files | T04, T09 | scripts `bash -n` clean; integration suite passes live; hw-smoke refuses without `OMAFAN_HW=1` |
| P4 | **T11** README + INSTALL + TROUBLESHOOTING | deepseek v4.1 flash | `README.md`, `docs/INSTALL.md`, `docs/TROUBLESHOOTING.md` | T04, T06, T09 | every command in the docs is one that exists (orchestrator re-runs them) |
| P4 | **T12** architecture/safety/keys/testing/prior-art docs | deepseek v4.1 flash | `docs/ARCHITECTURE.md`, `docs/SAFETY.md`, `docs/KEYBINDINGS.md`, `docs/TESTING.md`, `docs/PRIOR-ART.md` | T04, T06, T09 | mirrors DESIGN.md §5-§10 exactly; no invented flags |
| P4 | **T13** changelog + publishing inputs | MiMo V2.5 | `CHANGELOG.md`, `docs/PUBLISHING.md` | T01 | marketplace checklist complete; issue body ready |
| P4 | **T14** `tests/run-all.sh` + `docs/BUILD-LOG.md` | orchestrator | `tests/run-all.sh`, `docs/BUILD-LOG.md` | T01-T13 | full suite green |
| P5 | **T15** adversarial review — code vs contracts | glm 5.3 high | `orchestration/REVIEW-R1.md` | T01-T13 | every finding triaged in `orchestration/LEDGER.md` |
| P5 | **T16** adversarial review — safety/privilege/collision | glm 5.3 high | `orchestration/REVIEW-R2.md` | T01-T13 | ditto |
| P6 | live verification + ship | orchestrator | git history, `QUESTIONS.md`, `DEVIATIONS.md`, `orchestration/LEDGER.md`, `preview.png` | all | PRD §4 G1-G12 |

## Ticket cards

Each card below is also written verbatim to
`orchestration/tickets/<id>.md`; the orchestrator dispatches with:

```sh
cd /home/prakhar/Work/tries/2026-09-15-omafan
opencode run --model <model> [--variant high] \
  "Read orchestration/instructions/WORKER.md, DESIGN.md, PRD.md and \
   orchestration/tickets/<TICKET>.md. Implement exactly that ticket. \
   Do not run git. Do not touch files you do not own." 2>&1 | tee orchestration/logs/<TICKET>.log
```

### T01 — manifest + validate/lint harnesses
- **Goal:** the plugin's identity and two zero-dependency gates.
- **Files (own):** `manifest.json` (byte-exact from DESIGN.md §1),
  `tests/plugin-validate.sh`, `tests/qml-lint.sh`.
- **`tests/plugin-validate.sh`:** run `omarchy plugin validate "$repo_root"`,
  print its output, exit with its status; fail with a clear message if
  `omarchy` is absent; must not mutate anything.
- **`tests/qml-lint.sh`:** locate `qmllint` (`command -v qmllint`, else
  `/usr/lib/qt6/bin/qmllint`), resolve `OMARCHY_PATH` (`$OMARCHY_PATH` else
  `/usr/share/omarchy`), run it with `-I "$OMARCHY_PATH/shell"` over every
  `*.qml` in the repo root **that exists** (skip with a printed note when a QML
  file is not yet written — the harness must be usable from P1 onward), print
  findings and exit non-zero on any lint error (warnings are reported, not fatal).
- **Done:** `bash -n` clean; `omarchy plugin validate .` exits 0; both scripts
  print one final `PASS`/`FAIL` line.

### T02 — `Model.js` + `tests/model.test.mjs`
- **Goal:** all pure logic of DESIGN.md §5, fully table-tested.
- **Files (own):** `Model.js`, `tests/model.test.mjs`.
- **Spec:** implement exactly the 19 functions in DESIGN.md §5 with those
  signatures. ES5-safe: `var`/`function` only, no arrow functions, no template
  literals, no `Object.assign`, no imports, no I/O, no globals sniffing.
- **Tests:** `node tests/model.test.mjs`, no dependencies: read `Model.js` with
  `node:fs`, evaluate it in a `new Function(src + "; return {…}")()` sandbox, and
  assert tables for every function, including: the six-preset ladder for
  `(1200,7200)` → `1200/2700/4200/5700/7200`; `presetRpm("auto") === null`;
  clamping and snapping at both ends and for a step that does not divide the
  range; `cyclePreset` wrapping in both directions across all six ids;
  `modeTone` for each of the four tones; `degradedReason` naming the fix for
  `monitor_only`, `auto_restore_pending`, stale state, and a stopped daemon;
  `parseStatus` on valid JSON, on non-JSON, and on JSON with the wrong `schema`;
  `progressFraction` at min/undefined/max; `isStateStale(4)` false and
  `isStateStale(6)` true. Print `PASS n / FAIL m`, exit non-zero on any FAIL.
- **Done:** `node tests/model.test.mjs` exits 0, ≥ 40 assertions.

### T02b — `Model.js` undercooling-guard amendment (additive)
- **Goal:** add the two DESIGN.md §5.1 functions without touching the rest.
- **Files (own):** `Model.js`, `tests/model.test.mjs` (**additive only** — do not
  rewrite or delete existing functions or assertions).
- **Spec:** `isUndercoolingHot(status, targetRpm)` → true iff
  `status.thermal.t_eff_c >= 80` and `targetRpm != null` and
  `targetRpm < status.fan.rpm`; defensive when `status` is null/shapeless →
  `false`. `undercoolingWarning(status, targetRpm)` → `null` unless
  `isUndercoolingHot` is true, else a single sentence containing the temperature,
  the current rpm, the requested rpm, the word `below`, and a safe alternative
  (e.g. the nearest preset at or above the current rpm). ES5-safe, no imports,
  same file style.
- **Tests:** add a table in `tests/model.test.mjs`: cold machine → false; 80 °C
  exactly with a lower target → true; 79 °C → false; target equal to current rpm →
  false; target above current rpm → false; `targetRpm` null (auto) → false; null
  `status` → false; warning text contains all four facts and the safe
  alternative; warning is null when not undercooling.
- **Done:** `node tests/model.test.mjs` exits 0 with the previous assertions plus
  the new ones (report the new assertion count).

### T03 — fixtures + test harness lib
- **Goal:** a hardware-free stand-in for afanctl plus shared bash assertions.
- **Files (own):** `tests/fixtures/fake-afanctl`,
  `tests/fixtures/status-observe.json`, `tests/fixtures/status-hold.json`,
  `tests/fixtures/state-hold.json`, `tests/fixtures/state-monitor-only.json`,
  `tests/lib/harness.sh`.
- **`tests/fixtures/fake-afanctl`:** an executable bash script emulating the
  afanctl CLI surface omafan uses — `status [--json]` (prints a fixture, honours
  `--runtime-dir`/`AFANCTL_RUNTIME_DIR` and a `FAKE_AFANCTL_MODE` env var to
  select observe/hold/monitor-only/absent/error), `hold <rpm>` (validates the rpm
  against 1200..7200, exits 1 below min with afanctl's "below fan1_min" message
  shape, appends the argv to `$runtime_dir/argv.log`), `observe` (same logging),
  `--version` → `afanctl 0.1.0`, and an `AFANCTL_FAKE_FAIL=1` switch that makes
  every write exit 1 with a stderr message. It must never touch `/sys`, `/run/afanctl`
  or anything outside the caller-provided runtime dir, and must refuse to run
  unless a runtime dir is given.
- **`tests/lib/harness.sh`:** `assert_eq`, `assert_ne`, `assert_contains`,
  `assert_exit_code`, `assert_json_eq` (via `jq -e`), `new_tmpdir`, and a
  `summarize` that prints `PASS n / FAIL m` and returns non-zero on any FAIL.
  Safe under `set -euo pipefail`; no global state leaks between tests.
- **Done:** running the fixture by hand reproduces the DESIGN.md §4 JSON shapes
  (paste the output into your report); `bash -n` clean on both.

### T04 — `bin/omafan-ctl` (the only privileged path)
- **Goal:** implement DESIGN.md §4 exactly — verbs, globals, env, exit codes,
  JSON schemas, dry-run, notify, degraded/stale/absent handling.
- **Files (own):** `bin/omafan-ctl`.
- **Hard requirements:** `#!/usr/bin/env bash`; `set -euo pipefail`; argument
  parsing order-insensitive; **never** run `pkexec` for read verbs; all JSON
  emitted with `jq -n`/`jq -c` (never hand-built strings, never unescaped
  values); `--pkexec none` runs the afanctl binary directly (tests/dev);
  `--dry-run` prints `argv: <cmd>` and exits 0 without executing; `status` reads
  `state.json` first and only shells out to afanctl when limits are unknown or
  the cache is > 24 h old or `--full`; the hardware-limit cache lives in
  `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback `/tmp/omafan-$(id -u)/hw.json`) and
  an unwritable cache degrades with a `warnings` entry instead of failing; the
  freshness/`monitor_only` latch is surfaced, never hidden; every failure both
  prints a human fix line to stderr and (with `--json`) the error object to
  stdout; `--notify` uses `notify-send` only if present, with a failure that
  cannot change the exit code; no `eval`; no unquoted expansion; all temp files
  via `mktemp` with cleanup traps (`exec 3>file`-style clobbering is forbidden).
  **Implement DESIGN.md §5.1 (undercooling guard, exit 8) as well.**
- **Orchestrator ruling (R2, 2026-09-15):** `afanctl` has **no** `--runtime-dir`
  flag — it takes the directory from the environment. omafan-ctl therefore reads
  `<runtime-dir>/state.json` itself and exports
  `AFANCTL_RUNTIME_DIR=<runtime-dir>` for every afanctl invocation. `--config` is
  passed through as `--config <path>` only when the user supplied it (the afanctl
  global it documents); never invent flags afanctl does not have.
- **Done:** `bash -n` clean; a hand-run transcript of `status --json`,
  `presets --json`, `doctor --json`, `preset med --dry-run`,
  `rpm 99999 --json` (exit 7), `preset bogus` (exit 2) with
  `--afanctl tests/fixtures/fake-afanctl --pkexec none --runtime-dir <tmp>`
  attached to your report; `shellcheck` if available (not required).

### T05 — `tests/ctl.test.sh`
- **Goal:** every DESIGN.md §4 promise is machine-checked against the fixture.
- **Files (own):** `tests/ctl.test.sh`.
- **Must cover:** each verb's happy path; every documented exit code (0,1,2,3,4,
  5,6,7,8) with the exact situation that produces it, including exit 8 (a hold
  below the current rpm while `t_eff_c >= 80`) and that `--force` overrides 6, 7
  and 8; `--dry-run` prints the argv
  and writes nothing (fixture argv.log stays empty); `status --json` emits a
  document that `jq` validates field-by-field (schema ids, types, min/max,
  `hold.preset` derivation incl. `custom`); `presets --json` ladder values;
  `doctor --json` check id set + `ok` semantics; `--pkexec none` never invoking
  pkexec (assert with a `pkexec` stub earlier in PATH that exits 99); missing
  afanctl → exit 4; stale state → `state_stale: true`; unwritable cache dir →
  warning not failure; notify-send absent → exit code unchanged.
- **Done:** `bash -n` clean; suite green; ≥ 45 assertions.

### T06 — `bin/omafan-keybindings` + `tests/keybindings.test.sh`
- **Goal:** install/remove/status of DESIGN.md §7's block, safely.
- **Files (own):** `bin/omafan-keybindings`, `tests/keybindings.test.sh`.
- **Spec:** subcommands `install|remove|status|print`; target
  `${OMAFAN_HYPR_CONFIG:-$HOME/.config/hypr/bindings.lua}`; writes exactly one
  `-- BEGIN omafan` / `-- END omafan` block; **idempotent** (re-install leaves the
  file byte-identical when the block is already current); refuses (exit 1, writes
  nothing) if any of the eight chords is already bound elsewhere — the check reads
  `hyprctl binds -j` (`OMAFAN_HYPRCTL` override; a stub is used in tests) **and**
  greps the Lua sources under `$OMARCHY_PATH/default/hypr/bindings/` and the
  user's `~/.config/hypr/` for `code:`-style chords; backs up the original to
  `${OMAFAN_STATE_DIR:-$HOME/.local/state/omafan-keybindings}/bindings.lua.<stamp>`
  on first install; runs `hyprctl reload` (best-effort, never fatal) and re-reads
  `hyprctl binds -j` to confirm the new descriptions; `remove` restores the
  pre-install content when the rest of the file is unchanged and exits 0 when
  there is nothing to remove; sets the executable bit.
- **Tests (tempdir HOME + stub hyprctl + stub hypr config tree):** install adds
  exactly one block; install twice = byte-identical; conflicting chord ⇒ exit 1
  and file untouched; remove restores byte-identical content; remove with no
  block ⇒ exit 0; status reports installed/not-installed/conflict; `print` emits
  the block to stdout only; the eight chords in the emitted block equal the
  DESIGN.md §7 table.
- **Done:** `bash -n` clean; suite green; the free-chord analysis reproduces
  PRD §2.7 (paste the eight chords and the `hyprctl binds` evidence).

### T07 — `BarWidget.qml`
- **Goal:** the bar entry point per DESIGN.md §6.1.
- **Files (own):** `BarWidget.qml`.
- **Spec:** `BarWidget` root, `moduleName` = the plugin id, `panelItem` pattern
  with `Loader { active: true; visible: false }` loading `Panel.qml` and the
  `injectPanel()`/`onBarChanged`/`onSettingsChanged` wiring exactly as
  `omaplug`/`omarchy.monitor` do; `WidgetButton` text from `Model` per the `show`
  setting (`icon|temp|rpm|temp+rpm`); tint via `active`/`useActiveColor` while a
  hold is active; tooltip `"Fan <rpm> rpm · CPU <t> °C · <state>"`; left click
  toggles, right click releases to auto when a hold is active else opens the
  panel, wheel = ±100 rpm through the panel's command function (never direct);
  no IpcHandler here (the panel owns it); all user-visible strings sanitised with
  `Text.PlainText`; no writes of any kind from this file.
- **Done:** `bash -n`/qmllint clean (`tests/qml-lint.sh`); the file contains no
  `Process`/`pkexec`/`exec` call (verified by grep in your report).

### T08 — `KeyboardHelp.qml`
- **Goal:** the `?` key-map overlay (DESIGN.md §6.3 table), theme-aware.
- **Files (own):** `KeyboardHelp.qml`.
- **Spec:** a plain `Item` with `property bool open`, `property color foreground`,
  `property string fontFamily`, `signal closeRequested()`; renders the key map as
  a two-column `Column`/`Repeater` over an array built from a JS literal in the
  file; visible only when `open`; `Panel` handles `?`/`Esc` (this file must not
  steal keys); uses `Style.space`, `Style.font.*`, `Color.foreground`; text
  `Text.PlainText`; no timers, no I/O.
- **Done:** `tests/qml-lint.sh` clean; the rendered rows match DESIGN.md §6.3
  one-for-one (paste the key/action list from the file in your report).

### T09 — `Panel.qml`
- **Goal:** the control surface — state, polling, commands, banners, cursor model,
  IPC (DESIGN.md §6.2, §6.3).
- **Files (own):** `Panel.qml`.
- **Spec highlights:** `Panel` root with `ipcTarget: "omafan"`, `manageIpc: false`,
  one `IpcHandler` implementing the eight methods; a `Process` running
  `bin/omafan-ctl status --json` on a `poll_seconds` timer (started on load, not
  on open) with `--afanctl`/`--runtime-dir` overridable via `OMAFAN_` env for
  tests; every write goes through one `sendCommand(argv)` helper that (a)
  refuses while `busy` or while the daemon is degraded/offline, (b) debounces
  slider writes by 300 ms, (c) re-reads status on completion, (d) surfaces
  `lastError` with the fix; `status` drives hero (temp, rpm, mode), preset rows
  (rpm shown per preset), slider (from `presets`/`slider` min/max/step), a footer
  with uptime/polls/verified and `recent_errors`; banners for
  monitor_only / auto_restore_pending / daemon stopped / afanctl missing / stale
  state, each naming the fix command verbatim; `KeyboardPanel` + `PanelKeyCatcher`
  wired to the cursor model of DESIGN.md §6.3 (`focusSection`, `selectedIndex`,
  `cursorActive`, hover sets cursor, digits 1-6, `c`, `r`, `?`, `Esc` closes help
  first, `Tab` switches panels); `release_after_minutes` timer that returns to
  auto after N minutes without interaction and is restarted whenever a poll
  discovers an active hold; `KeyboardHelp` child toggled by `helpOpen`;
  **undercooling guard** (DESIGN.md §5.1): a preset whose rpm is below the current
  fan rpm while `t_eff_c >= 80` renders `undercoolingWarning(...)` and requires a
  second `Enter`/click within 10 s before it is sent.
- **Done:** `tests/qml-lint.sh` clean; live load with `OMAFAN_AFANCTL` pointed at
  the fixture shows the panel with no `qs log` errors; `omarchy-shell omafan state`
  returns the status JSON (orchestrator runs G5 and reports back).
- **Orchestrator ruling (R4, 2026-09-15) — how the panel finds the helper and how
  it is testable:** resolve the CLI from the plugin directory at runtime, never
  from a hardcoded absolute path:
  `readonly property string ctlPath: Qt.resolvedUrl("bin/omafan-ctl").toString().replace(/^file:\/\//, "")`.
  Pass the environment through so the same QML can be exercised against the
  fixture without touching the fan — read `Quickshell.env("OMAFAN_AFANCTL")`,
  `Quickshell.env("OMAFAN_RUNTIME_DIR")`, `Quickshell.env("OMAFAN_PKEXEC")` and
  add `--afanctl`/`--runtime-dir`/`--pkexec` arguments only when set. Use
  `Quickshell.Io` `Process` with the **array** `command:` form plus a
  `StdioCollector`; never build a shell string, never use `execDetached` for
  anything whose result the panel reads back.

### T10 — `tests/integration-shell.sh` + `tests/hw-smoke.sh`
- **Goal:** the two opt-in live suites, both safe by default.
- **Files (own):** both.
- **`integration-shell.sh`** (`OMAFAN_LIVE=1`, else exit 0 with a printed skip):
  assert the plugin directory is installed at the DESIGN.md §1 path or install it
  into a temp plugin dir; `omarchy-shell shell rescanPlugins`; assert
  `omarchy plugin list --json` lists the id with `enabled:true`; assert
  `omarchy-shell omafan state` returns a document with `schema == omafan.status.v1`;
  assert `omarchy-shell omafan preset bogus` returns an error string; assert
  `omarchy-shell omafan toggle` then `close` both return; dump the last
  `qs log -p "$OMARCHY_PATH/shell" --tail 200` and FAIL if it contains an error
  mentioning our id or file names.
- **`hw-smoke.sh`** (`OMAFAN_HW=1` plus an interactive confirmation, else exit 0
  with a skip): refuse unless `afanctl` is present and the daemon is running;
  **hot-machine policy — never reduce airflow that the firmware already
  established**: read `t_eff_c` and the live rpm first and (a) if `t_eff_c >= 75`
  only exercise holds at or **above** the current rpm (`high`, `full`) and skip
  `off`/`low`/`med` with a printed note, (b) if `t_eff_c < 60` exercise the full
  ladder. Then, in order: read state → apply each allowed preset → verify
  `hold.active` with the expected rpm within 5 s → for `full`, hold for at most
  2 s → **`release` immediately** → verify `mode=observe`, `manual=false` and that
  `afanctl status --json` agrees → print a final table. An `EXIT` trap must call
  `release` (and verify it) on any failure or interrupt. Nothing in the script may
  touch `/sys` directly.
- **Done:** `bash -n` clean on both; `integration-shell.sh` green live
  (orchestrator) and `hw-smoke.sh` refusing cleanly without `OMAFAN_HW=1`.

### T11 — README + INSTALL + TROUBLESHOOTING
- **Goal:** a stranger can install, use, and uninstall omafan; the marketplace
  blurb is accurate.
- **Files (own):** `README.md`, `docs/INSTALL.md`, `docs/TROUBLESHOOTING.md`.
- **Content:** the sibling-differentiation section (PRD §1.1, and the sibling
  list from PRD §2.6 with links), the afanctl dependency and how to install it
  (`packaging/` in the sibling repo), `omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable`,
  the widget click/right-click/wheel behaviour, the full keyboard map,
  `bin/omafan-keybindings install|remove|status`, the safety model in plain
  language (including "off is not off" and "presets are floors"), the exact
  uninstall sequence, a troubleshooting table with at least eight real failure
  modes each with the fix, licence, and the requirement that the plugin works
  with the *installed* afanctl version (no bundling).
- **Done:** every command quoted in the docs is verified to exist by the
  orchestrator; `grep -n "TODO"` empty.

### T12 — architecture/safety/keys/testing/prior-art docs
- **Goal:** the design and its reasons are retraceable by a stranger.
- **Files (own):** `docs/ARCHITECTURE.md`, `docs/SAFETY.md`,
  `docs/KEYBINDINGS.md`, `docs/TESTING.md`, `docs/PRIOR-ART.md`.
- **Content:** ARCHITECTURE = data flow (state.json → omafan-ctl → QML), file
  responsibilities, why the CLI is the only integration point, the polling/cache
  strategy, the failure surface; SAFETY = DESIGN.md §8 in operator language plus
  the afanctl guarantees it leans on (verified against the sibling README, cited);
  KEYBINDINGS = the in-panel map + the global chord table + provenance of the
  free-chord analysis + how to rebind; TESTING = every suite, what it proves,
  how to run the live and hardware suites safely; PRIOR-ART = the sibling survey
  with licences and the differentiation matrix.
- **Done:** no invented flags/commands (`grep` each quoted command against the
  repo/DESIGN.md in your report).

### T13 — changelog + publishing inputs
- **Goal:** release hygiene and the marketplace submission package.
- **Files (own):** `CHANGELOG.md`, `docs/PUBLISHING.md`.
- **Content:** Keep-a-Changelog `1.0.0` entry; PUBLISHING = the sibling repo's
  publish-guide requirements restated (public repo, root `manifest.json`, README,
  licence, safe install/removal, optional preview), the exact
  `gh repo create`/push commands the operator may re-run, the marketplace issue
  form fields (repository URL, category, tags, description), and a pre-submit
  checklist.
- **Done:** the issue body in PUBLISHING is copy-pasteable; no placeholder text
  such as `<...>` remains unresolved.

## Dispatch runbook (orchestrator)

1. **Before each wave:** confirm the previous wave's files exist and `tests/run-all.sh`
   sub-suites pass that can pass at that point; commit the wave
   (`git add -A && git commit -m "wave <n>: <tickets>"`).
2. **Dispatch:** one `opencode run` per ticket, `--variant high` for the glm
   tier, output tee'd to `orchestration/logs/<TICKET>.log`. At most **three**
   concurrent sessions; never two sessions on the same file.
3. **Verify (never trust the self-report):** read the produced file in full,
   re-run the ticket's gate command myself, and grep for the ticket's specific
   prohibitions (e.g. no `pkexec` in read paths, no `/sys` writes anywhere, no
   `git` invocations). Record the verdict in `orchestration/LEDGER.md` with the
   exact command and its output.
4. **Reject and re-dispatch** on: contract drift, a gate that fails, invented
   flags, unsafe shell (unquoted vars, `eval`, missing `set -euo pipefail`),
   hardware writes in a non-opt-in path, or a self-report that contradicts the
   code. Re-dispatch the same ticket with the defect list appended; at most two
   iterations per ticket, then the orchestrator fixes it and records the
   deviation.
5. **Never** let a worker run `git`, install packages, touch `/sys`, `/etc`,
   `/usr`, or another plugin's directory.
6. **Merges** are fast-forward only: workers never branch; the orchestrator
   commits each verified wave.
7. **Ledger discipline:** every dispatch, verification, rejection and ruling
   gets a line in `orchestration/LEDGER.md`; rulings that change behaviour are
   mirrored into `DESIGN.md` (frozen contracts) with a `DEVIATIONS.md` entry.

## Verification matrix (orchestrator-owned)

| After wave | Commands re-run by the orchestrator |
|---|---|
| P1 | `omarchy plugin validate .`; `bash -n tests/*.sh`; `node tests/model.test.mjs` |
| P2 | `bash tests/ctl.test.sh`; `bash tests/keybindings.test.sh`; manual dry-run argv inspection |
| P3 | `tests/qml-lint.sh`; live load + `qs log` scan; `omarchy-shell omafan state` |
| P4 | `tests/run-all.sh`; `bash -n` on every script; docs command audit |
| P5 | both review reports triaged; fixes re-gated |
| P6 | PRD §4 G1-G12 end-to-end, then push |

## Stop rules

- Any gate that cannot be made green after two re-dispatches → the orchestrator
  fixes it, records the deviation, and continues (the build never stalls).
- Any finding that would require touching system state outside PRD §3.3 S1 →
  stop, document in `QUESTIONS.md`, do not do it.
- Hardware writes are never performed by a worker; only the orchestrator, only
  through `tests/hw-smoke.sh` semantics, only with a verified return to `observe`.
