# DESIGN.md — omafan frozen contracts

**Status: FROZEN.** Every subagent builds against this document. Do not change a
public item in this file without a `DEVIATIONS.md` entry (propose old → new →
why → affected tickets). Written by the orchestrator after first-hand recon on
2026-09-15 (see `PRD.md` §2 for the verified environment facts).

`omafan` is an Omarchy *shell plugin* (Quickshell / Omarchy 4.0.0.alpha
"Quattro") that gives a pre-T2 Intel Mac (`applesmc`, single fan) **preset and
slider control of the fan** plus a live readout — by driving the already-installed
`afanctl` daemon. The plugin never touches `/sys` itself. `afanctl` owns the fan;
`omafan` is a control surface over its documented command channel.

---

## 1. Identity

| Item | Value |
|---|---|
| Repository | `https://github.com/yadav-prakhar/omafan` (public, GPL-3.0-only) |
| Plugin id | `io.github.yadav-prakhar.omafan` |
| Installed path | `~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/` |
| Kinds | `["bar-widget"]` (the panel is a nested `Panel.qml`, not a second kind) |
| IPC target | `omafan` (exactly one `IpcHandler` in the plugin, in `Panel.qml`) |
| Version | `1.0.0` |
| License | `GPL-3.0-only` (repo `LICENSE` = GPL-3.0 full text) |
| Bar section | `barWidget.defaultSection = "right"` |
| Dependency | `afanctl` ≥ 0.1.0 installed and its daemon running (`/usr/bin/afanctl`) |

`manifest.json` (exact):

```json
{
  "schemaVersion": 1,
  "id": "io.github.yadav-prakhar.omafan",
  "name": "omafan",
  "version": "1.0.0",
  "author": "Prakhar Yadav",
  "license": "GPL-3.0-only",
  "description": "Fan control for pre-T2 Intel Macs: firmware auto, five presets and an RPM slider on top of afanctl, with live temperature and RPM in the bar.",
  "homepage": "https://github.com/yadav-prakhar/omafan",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Fan Control",
    "description": "Fan presets, slider and live thermals for Apple SMC Macs (via afanctl)",
    "category": "Hardware",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "show": "temp", "poll_seconds": 2, "release_after_minutes": 0 },
    "schema": [
      { "key": "show", "type": "enum", "label": "Bar shows", "options": ["icon", "temp", "rpm", "temp+rpm"], "default": "temp" },
      { "key": "poll_seconds", "type": "int", "label": "Refresh interval (s)", "min": 1, "max": 10, "default": 2 },
      { "key": "release_after_minutes", "type": "int", "label": "Return to firmware auto after (min, 0 = never)", "min": 0, "max": 240, "default": 0 }
    ]
  }
}
```

> If the shell rejects an unknown manifest key it is ignored, never fatal; the
> `validate` gate (`omarchy plugin validate`) must still exit 0.

## 2. File map (fixed — file ownership in `PLAN.md`)

```
manifest.json          plugin manifest (§1)
BarWidget.qml          bar entry point: glyph/label, click, wheel, IpcHandler is NOT here
Panel.qml              the panel: state, polling, commands, keyboard model, IpcHandler
Model.js               pure logic (no QtQuick import, no QML types)
KeyboardHelp.qml       the "?" key-map overlay (a child item of Panel.qml)
bin/omafan-ctl         the ONLY thing that talks to afanctl (POSIX sh)
bin/omafan-keybindings install/remove/status of the Hyprland keybinding block
docs/*.md              architecture, keybindings, safety, install, troubleshooting, testing, publishing, prior-art
tests/*                every automated test (no hardware writes)
LICENSE  README.md  CHANGELOG.md  PREVIEW (preview.png, optional)
```

## 3. Preset model (frozen)

Presets are **holds** (`afanctl hold <rpm>`) except `auto`, which **releases** the
fan to the SMC firmware (`afanctl observe`). RPMs are derived from the live
hardware range `[fan_min_rpm, fan_max_rpm]` read from `afanctl status --json`.

| id | label | kind | rpm |
|---|---|---|---|
| `auto` | Auto (firmware) | release | `null` → `afanctl observe` |
| `off` | Off (hardware floor) | hold | `fan_min_rpm` |
| `low` | Low | hold | `round(min + 0.25 × (max − min))` |
| `med` | Medium | hold | `round(min + 0.50 × (max − min))` |
| `high` | High | hold | `round(min + 0.75 × (max − min))` |
| `full` | Full | hold | `fan_max_rpm` |

On the reference machine (`MacBookPro14,1`, `fan1_min=1200`, `fan1_max=7200`)
that is `off 1200 · low 2700 · med 4200 · high 5700 · full 7200`.

Rules:
- **`off` is not "fan off".** The SMC floor is `fan1_min` (1200 rpm); sysfs cannot
  stop the fan. Every surface that renders `off` must say so (`Off (hardware
  floor)` / a footnote) — never claim the fan is stopped.
- **Presets are floors, not quieter-than-firmware modes.** The firmware idles
  near 1787 rpm on the reference machine, so `low` (2700) is *louder* than
  firmware auto. `auto` is the only quiet option. Say this in the UI legend.
- Slider range is `[fan_min_rpm, fan_max_rpm]`, `step_rpm = 100`, default 1 step
  per key press, 5 steps with `Shift`.
- A hold at an rpm that matches no preset renders as `custom`.

## 4. `bin/omafan-ctl` — CLI contract (frozen)

```
omafan-ctl status   [--json|--human] [--full] [--afanctl P] [--runtime-dir D] [--config C] [--pkexec P]
omafan-ctl presets  [--json|--human]  ...same globals
omafan-ctl doctor   [--json|--human]  ...same globals
omafan-ctl preset <auto|off|low|med|high|full> [--notify] [--dry-run] ...
omafan-ctl rpm <integer 0..100000>   [--notify] [--dry-run] [--force] ...
omafan-ctl release  [--notify] [--dry-run] ...          # alias of `preset auto`
omafan-ctl version | --version | -h | --help
```

Globals / env:

| Flag | Env | Default |
|---|---|---|
| `--afanctl <path>` | `OMAFAN_AFANCTL` | `afanctl` (PATH lookup) |
| `--runtime-dir <dir>` | `OMAFAN_RUNTIME_DIR` | `/run/afanctl` |
| `--config <path>` | — | `/etc/afanctl/afanctl.toml` (passed through when used) |
| `--pkexec <path|none>` | `OMAFAN_PKEXEC` | `pkexec`; **`none` = run the afanctl binary directly (tests/dev only)** |
| `--notify` / `--no-notify` | — | no notification |

Exit codes (frozen; a bad flag never exits 0):

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | runtime failure (afanctl nonzero exit, unparsable output, write failed) |
| 2 | usage error (unknown verb/flag/preset, non-integer rpm) |
| 3 | authorization denied or cancelled (pkexec 126/127, "Not authorized") |
| 4 | afanctl missing or not executable |
| 5 | afanctl daemon not running / runtime dir unreadable / `state.json` absent |
| 6 | daemon degraded (`monitor_only` or `auto_restore_pending`) — writes refused; `--force` overrides |
| 7 | rpm outside `[fan_min_rpm, fan_max_rpm]` — writes refused |

Write path: `pkexec <afanctl> hold <rpm>` / `pkexec <afanctl> observe`.
`--dry-run` prints the argv it *would* run and exits 0 without executing.
`status`/`presets`/`doctor` never write, never call pkexec, and never require root.
Notifications use `notify-send` when available; a missing/failing `notify-send`
never changes the exit code.

### 4.1 JSON: `omafan.status.v1` (`status --json`)

```json
{
  "schema": "omafan.status.v1",
  "ok": true,
  "generated_at": "2026-09-15T03:30:00Z",
  "afanctl": { "path": "/usr/bin/afanctl", "present": true, "version": "0.1.0" },
  "daemon": { "running": true, "mode": "observe", "monitor_only": false,
              "auto_restore_pending": false, "uptime_s": 1278, "polls": 1278,
              "state_age_s": 1, "state_stale": false },
  "hardware": { "fan_min_rpm": 1200, "fan_max_rpm": 7200 },
  "fan": { "rpm": 1787, "target_rpm": null, "manual": false },
  "thermal": { "t_eff_c": 64.0, "sensors": [ { "label": "Package id 0", "temp_c": 64.0 } ] },
  "hold": { "active": false, "preset": null, "rpm": null },
  "presets": [ { "id": "auto", "label": "Auto (firmware)", "rpm": null, "kind": "release" } ],
  "recent_errors": [],
  "warnings": []
}
```

- Fast path: `state.json` in the runtime dir is the primary source (mode,
  `t_eff_c`, `target_rpm`, `last_written_rpm`, `actual_rpm`, `verified`,
  `monitor_only`, `auto_restore_pending`, `polls`, `recent_errors`, `ts`).
- `afanctl status --json` is executed only when the hardware limits are unknown
  or the cached limits (see below) are older than 24 h, or with `--full`.
- Hardware-limit cache: `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback
  `/tmp/omafan-<uid>/hw.json`), containing `{"fan_min_rpm":…,"fan_max_rpm":…,
  "captured_at":…,"afanctl_version":…}`. Unwritable cache is **not** an error —
  degrade to querying afanctl each time and add a `warnings` entry.
- `state_stale` is true when `state.json`'s mtime age exceeds
  `max(5 s, 3 × poll interval)`; a stale state with no daemon ⇒ `running:false`.
- `hold.active` = daemon `mode == "hold"`; `hold.rpm` =
  `target_rpm ?? last_written_rpm`; `hold.preset` = the preset id whose rpm equals
  `hold.rpm`, else `"custom"`.
- `warnings[]` are non-fatal human strings (`"hardware limits cache not writable"`).

### 4.2 JSON: `omafan.presets.v1`

```json
{ "schema": "omafan.presets.v1", "fan_min_rpm": 1200, "fan_max_rpm": 7200,
  "presets": [ { "id": "med", "label": "Medium", "rpm": 4200, "kind": "hold" } ],
  "slider": { "min_rpm": 1200, "max_rpm": 7200, "step_rpm": 100 } }
```

### 4.3 JSON: `omafan.action.v1` (write verbs, stdout)

```json
{ "schema": "omafan.action.v1", "ok": true, "action": "preset", "preset": "med",
  "mode": "hold", "rpm": 4200, "argv": ["/usr/bin/afanctl", "hold", "4200"],
  "exit_code": 0, "message": "Holding 4200 rpm" }
```

On failure: `"ok": false`, `"error": "<short_code>"`, `"message": "<human, names
the fix>"` and the exit code from §4. Errors print the JSON to stdout and a
human line to stderr — never the reverse.

### 4.4 JSON: `omafan.doctor.v1`

```json
{ "schema": "omafan.doctor.v1", "ok": true,
  "checks": [ { "id": "afanctl_present", "status": "PASS", "detail": "/usr/bin/afanctl 0.1.0" } ],
  "summary": { "pass": 8, "warn": 1, "fail": 0 } }
```

Check ids (fixed): `afanctl_present`, `afanctl_version`, `daemon_running`,
`state_fresh`, `pkexec_present`, `polkit_rule`, `applesmc`, `coretemp`,
`hw_limits`, `shell_ipc`, `keybindings`. Any `FAIL` ⇒ exit 1. `WARN` never
fails the exit code. `status` ∈ `PASS|WARN|FAIL`.

## 5. `Model.js` — pure function contract (frozen)

No `import` of QtQuick/Quickshell, no QML types, no side effects, no I/O. Used
by QML as `import "Model.js" as Model` **and** source-evaluated by the Node test
harness (so: plain `function` declarations, only ES5-safe syntax).

```
presetsFor(minRpm, maxRpm)                  -> [{id,label,rpm,kind}]   // §3 order
presetById(list, id)                        -> {id,label,rpm,kind} | null
presetRpm(id, minRpm, maxRpm)               -> int | null              // null for auto
clampRpm(rpm, minRpm, maxRpm)               -> int
snapRpm(rpm, minRpm, maxRpm, stepRpm)       -> int                     // clamp + snap to step grid
sliderPosFromRpm(rpm, minRpm, maxRpm)       -> real 0..1
rpmFromSliderPos(pos, minRpm, maxRpm, step) -> int
cyclePreset(currentId, dir)                 -> string                  // dir ±1, wraps, all six ids
statusLabel(status)                         -> string
modeTone(status)                            -> "auto"|"hold"|"degraded"|"offline"
degradedReason(status)                      -> string | null           // human, names the fix
parseStatus(text)                           -> {ok:true,status} | {ok:false,error}
progressFraction(status)                    -> real 0..1               // fan rpm inside [min,max]
formatRpm(n)                                -> string                  // "4,200 rpm"
formatTemp(c)                               -> string                  // "64 °C"
formatUptime(seconds)                       -> string                  // "1 h 22 m" / "45 s"
isStateStale(ageSeconds)                    -> bool
```

`label`s are English; `formatRpm` uses a plain `,` thousands separator (no locale).

## 6. QML contract

### 6.1 `BarWidget.qml`

```
BarWidget { id: root; moduleName: "io.github.yadav-prakhar.omafan" }
  readonly property bool opened            // panelItem.opened
  readonly property bool popoutSwitchClosing
  property var panelItem: null
  function open(); function close(); function togglePanel()
  function closeForPopoutSwitch(); function injectPanel()
  Loader { id: panelLoader; active: true; visible: false; source: Qt.resolvedUrl("Panel.qml") }
  WidgetButton { id: button ... }          // text = glyph/label per `show` setting
```

- Left click: `togglePanel()`. Right click: if a hold is active, release to
  `auto`; else open the panel. Wheel up/down: hold ±100 rpm (from the current
  target, or from `med` when nothing is held) — a wheel action *is* a write and
  must go through the panel's command function so its banners/debounce apply.
- Tooltip: `"Fan 4200 rpm · CPU 64 °C · hold"` (state-appropriate).
- The bar text is tinted (`WidgetButton.active`/`useActiveColor`) whenever a
  hold is active, so a forgotten manual setting is visible at a glance.

### 6.2 `Panel.qml`

```
Panel { id: root; moduleName: "io.github.yadav-prakhar.omafan"; ipcTarget: "omafan"; manageIpc: false }
  function open(); function close(); function toggle(); function closeForPopoutSwitch()
  KeyboardPanel { anchorItem: root.anchorItem; owner: root.hostWidget || root; bar: root.bar
                  open: root.opened; focusTarget: keyCatcher
                  PanelKeyCatcher { id: keyCatcher; onMoveRequested; onActivateRequested;
                                    onReturnRequested; onCloseRequested; onTabRequested; onTextKey }
                    Column { /* hero, banners, presets, slider, footer */ } }
  IpcHandler { target: "omafan"
    function toggle(): void
    function open(): void
    function close(): void
    function preset(name: string): string   // "ok: med 4200 rpm" | "error: <message>"
    function rpm(value: string): string
    function release(): string
    function refresh(): void
    function state(): string                // the last `omafan.status.v1` JSON, verbatim
  }
```

State: `status` (parsed), `lastError`, `busy`, `pendingRpm`, `focusSection`
(`presets|slider`), `selectedIndex`, `cursorActive`, `helpOpen`, `pollSeconds`.

Sections cursor model (same shape as `omarchy.monitor`'s panel):
`visibleSections` = `["presets","slider"]`; `presets` is a single horizontal row
of 6 (`h`/`l` moves between presets, `k`/`j` moves to/from `slider`); `slider` is
a lone row with `selectedIndex = -1`. Mouse hover sets the same cursor state so
keyboard and pointer share one highlight.

### 6.3 Keyboard map (frozen; §7 of `docs/KEYBINDINGS.md` mirrors this)

| Key | Action |
|---|---|
| `j` / `↓` | cursor down (section) |
| `k` / `↑` | cursor up (section) |
| `h` / `←` | presets: previous preset · slider: −1 step (100 rpm) |
| `l` / `→` | presets: next preset · slider: +1 step |
| `Shift` + `h`/`l` | slider: ±500 rpm |
| `Enter` / `Space` | presets: apply focused preset · slider: apply current value now |
| `1`…`6` | apply `auto, off, low, med, high, full` directly |
| `c` | cycle presets forward (`auto → off → low → med → high → full → auto`) |
| `r` | refresh status now |
| `?` | toggle the key-map overlay (`KeyboardHelp.qml`) |
| `Esc` | close the help overlay if open, else close the panel |
| `Tab` / `Shift+Tab` | switch to the next/previous bar panel (shell popout switch) |
| mouse | hover = cursor, click = apply, wheel on the slider = ±1 step |

`PanelKeyCatcher` already consumes `h/j/k/l`, arrows, `Enter`, `Space`, `Esc`,
`Tab` and forwards other printable keys as `onTextKey` — digits, `c`, `r`, `?`
arrive there. `?` must not be swallowed before `KeyboardHelp` opens; `Esc` must
close help first (`helpOpen` handler runs before `root.close()`).

## 7. Global keybindings (frozen; installed by `bin/omafan-keybindings`)

**Verified free on this machine** against the live compositor (`hyprctl binds -j`,
175 bound chords) *and* against the Omarchy default + user Lua sources (including
`code:` chords). Free-chord analysis is reproduced by `tests/keybindings.test.sh`.

| Chord | Description | Command |
|---|---|---|
| `SUPER + ALT + T` | omafan: toggle fan panel | `omarchy-shell omafan toggle` |
| `SUPER + ALT + A` | omafan: fans auto (firmware) | `omafan-ctl preset auto --notify` |
| `SUPER + ALT + O` | omafan: fans off (floor) | `omafan-ctl preset off --notify` |
| `SUPER + ALT + L` | omafan: fans low | `omafan-ctl preset low --notify` |
| `SUPER + ALT + M` | omafan: fans medium | `omafan-ctl preset med --notify` |
| `SUPER + ALT + H` | omafan: fans high | `omafan-ctl preset high --notify` |
| `SUPER + ALT + X` | omafan: fans full | `omafan-ctl preset full --notify` |
| `SUPER + ALT + C` | omafan: cycle fan presets | `omafan-ctl cycle --notify` |

Rules:
- Preset/cycle chords call **`omafan-ctl` directly** (works even while
  `omarchy-shell` restarts); only the panel toggle goes through shell IPC.
- `bin/omafan-keybindings install` writes exactly one managed block into
  `~/.config/hypr/bindings.lua`:
  `-- BEGIN omafan` … `-- END omafan`, idempotent (re-install replaces the
  block, byte-identical file when unchanged), then `hyprctl reload` and a
  re-read of `hyprctl binds -j` to confirm every chord carries its omafan
  description. If **any** chord is already bound to something else, install
  refuses (exit 1), writes nothing, and names the conflicting chord + description.
- `remove` deletes the block (byte-identical restoration of the original file
  when nothing else changed), `reload`s, and confirms the chords are gone.
- `status` prints `installed|not-installed|conflict` plus the per-chord verdict.
- The block is commented with the plugin path and an uninstall hint, and uses the
  Omarchy `o.bind("<CHORD>", "<description>", "<shell command>")` helper form.
- Never touch anything else in `bindings.lua`; never rewrite the file's
  newline style; keep a timestamped backup in
  `~/.local/state/omafan-keybindings/` on the first install.

## 8. Safety model (plugin side)

`omafan` adds no privileged surface of its own:

- It **only** calls `afanctl` (`status`, `hold`, `observe`) through `pkexec`.
  The privilege boundary is afanctl's own auditable polkit rule
  (`/usr/share/polkit-1/rules.d/49-afanctl.rules`), which grants only
  `status [--json]`, `observe`, `curve` and `hold <u32>` to `wheel` users in a
  local active session.
- It never writes `/sys`, never edits `/etc`, never installs a unit, never asks
  for a root-owned helper, and never runs anything from the plugin directory as
  root.
- Every write is followed by a status re-read; the UI renders what the daemon
  reports (`monitor_only`, `auto_restore_pending`, `verified`, `recent_errors`),
  not what it asked for.
- Degraded (`monitor_only`) or pending-auto-restore states **disable** writes and
  show the cause plus the fix command; `--force` exists on the CLI only.
- If the daemon is missing/stopped/stale, the panel shows an offline banner with
  the exact `systemctl` command and keeps read-only behaviour.
- `release_after_minutes` (plugin setting, default `0` = never) returns the fan
  to firmware auto after N minutes of no interaction — an optional safety net
  for a forgotten hold. Its timer restarts when a status poll discovers an active
  hold and the setting is non-zero.
- Uninstall is `omarchy plugin remove io.github.yadav-prakhar.omafan`; the only
  things omafan ever writes outside its own directory are `~/.config/omarchy/shell.json`
  (by `omarchy plugin enable`, the shell's own doing) and the managed
  `bindings.lua` block (removable with `bin/omafan-keybindings remove`).

## 9. Conventions block (paste verbatim into every subagent instruction)

```
CONVENTIONS (omafan, frozen)
- Repo: /home/prakhar/Work/tries/2026-09-15-omafan. Do NOT run git commands; the
  orchestrator commits. Do not create or edit files you do not own (see your ticket).
- Read DESIGN.md before writing code; it is frozen. If you believe it is wrong,
  stop and write your objection into orchestration/QUESTIONS.md — never silently
  deviate.
- Language: shell is POSIX-ish bash (#!/usr/bin/env bash, set -euo pipefail is
  allowed; quote everything; no bash-isms that break on dash are needed since we
  require bash). QML targets Quickshell/Omarchy 4.0.0.alpha: import QtQuick,
  Quickshell, Quickshell.Io, qs.Ui, qs.Commons only. JS in Model.js is ES5-safe,
  no imports, no I/O, no side effects.
- Dependencies: none beyond what is present on the machine — bash, coreutils,
  jq, awk, sed, grep, find, procps, pkexec, notify-send, node (tests only),
  /usr/lib/qt6/bin/qmllint. No new packages, no network at runtime, no curl.
- Error model: every failure prints (a) a human line naming the problem AND the
  fix, (b) for --json verbs, the JSON error object of DESIGN.md §4.3. Never exit 0
  on a failure. Never swallow stderr from afanctl.
- Never write to real /sys, /etc, /usr or /run in code paths exercised by tests;
  tests use fixtures (tests/fixtures/fake-afanctl, --afanctl/--runtime-dir).
- Comments explain WHY (safety decisions especially), not what. British-neutral
  English. No emoji. No TODO left in shipped files.
- Gates you must run and paste the output of: bash -n <each shell file>;
  node tests/model.test.mjs (if Model.js is yours); tests/qml-lint.sh (if QML is
  yours); omarchy plugin validate . ; tests/run-all.sh once it exists.
- Style: 2-space indent in QML/JS, 4 in shell; max ~100 columns; no trailing
  whitespace; files end with a newline.
```

## 10. Test contract

`tests/run-all.sh` runs, in order, every test that must pass without hardware:
`manifest.test.sh`, `model.test.mjs` (node), `ctl.test.sh` (fake-afanctl),
`keybindings.test.sh` (tempdir HOME + stub hyprctl), `qml-lint.sh`
(`/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell"`), and `plugin-validate.sh`
(`omarchy plugin validate .`). Exit non-zero on the first failure, print a final
`PASS n / FAIL m` line. `tests/integration-shell.sh` and `tests/hw-smoke.sh` are
**opt-in** (`OMAFAN_LIVE=1`, `OMAFAN_HW=1`) and never run inside `run-all.sh`.
