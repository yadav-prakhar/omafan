# omafan architecture

`omafan` is a keyboard-first Omarchy shell plugin (Quickshell / Omarchy
4.0.0.alpha) for the single fan of a pre-T2 Intel Mac (`applesmc`,
MacBookPro14,1 "A1708"). It renders live CPU temperature and fan rpm in the
bar and offers preset/slider control of the fan. It never touches `/sys`
itself: the installed `afanctl` daemon owns the fan, and omafan is a control
surface over that daemon's documented command channel.

This document describes the data flow, what each file is for, why the CLI is
the only integration point, how polling and caching work, and every way the
thing can fail.

## 1. Data flow

The arrows below are the only paths by which state or commands move. The
diagram is deliberately drawn daemon-first: the firmware curve is the default
owner, and every omafan layer sits *on top of* a daemon it cannot bypass.

```
  SMC firmware (applesmc)                 <- the fan's real owner
        ▲  writes fan1_manual / fan1_output (root only)
        │
  afanctl daemon  (systemd unit afanctl.service, root, mode=observe by default)
        │  every poll: read sensors, verify the fan, re-assert, then publish
        │
        ├── writes  /run/afanctl/state.json   (schema afanctl.state.v1, 0644)
        └── reads   /run/afanctl/cmd.json     (schema afanctl.cmd.v1)
                        ▲
                        │  write verbs
   read verbs           │
   (no root)            │
        │               │
  bin/omafan-ctl ───────┘
        │   - reads state.json directly for `status`
        │   - `pkexec afanctl hold <rpm>` / `pkexec afanctl observe` for writes,
        │     exactly the verbs afanctl's own polkit rule allows
        │
        │  emits: omafan.status.v1 / omafan.presets.v1 / omafan.doctor.v1 /
        │         omafan.action.v1 on stdout
        ▼
  Panel.qml  (Quickshell.Io Process, poll timer, single write gate)
        │  parses with Model.parseStatus()
        ├── renders hero, banners, presets, slider, footer
        ├── owns the one IpcHandler (target "omafan")
        └── exposes `status` to BarWidget.qml
                │
  BarWidget.qml ┘  renders the bar label and forwards gestures to the panel
                   (no Process, no pkexec, no I/O of its own)

  bin/omafan-keybindings  installs/removes the Hyprland chord block that
                          invokes `omafan-ctl` and `omarchy-shell omafan toggle`
```

Two consequences of this shape are worth stating plainly:

- **The fan command never originates in QML.** The panel and the bar widget
  only ever run `bin/omafan-ctl`; `omafan-ctl` is the only component that
  invokes `afanctl`, and only through `pkexec` for writes. A defect in the QML
  cannot reach the fan because the QML has no path to it.
- **The shell never parses afanctl.** QML reads the stable `omafan.status.v1`
  document, not `afanctl.state.v1` or `afanctl status --json`. Changes to
  afanctl's private shape are absorbed in one shell script, not across QML.

## 2. File responsibilities

| File | Owns | Never does |
|---|---|---|
| `manifest.json` | plugin identity, the `bar-widget` kind, the settings schema (`show`, `poll_mode`, `poll_seconds`, `release_after_minutes`) | describe behaviour that is not true |
| `BarWidget.qml` | the bar glyph/label, tooltip, left/right click and wheel gestures, hold tint | run a process, read a file, call `pkexec` (it forwards to `Panel.sendCommand`) |
| `Panel.qml` | all shell-side side effects: the polling `Process`, the write `Process`, the settings-write `Process` (`omarchy bar set` for the REFRESH row), the busy lock, the 300 ms slider debounce, the undercooling confirmation, banners, the cursor model, the single `IpcHandler`, the `release_after_minutes` timer | talk to afanctl or `/sys` directly |
| `Model.js` | pure logic: the preset ladder, clamping/snapping, cycle order, status parsing, format helpers, staleness, the undercooling guard | import QML, do I/O, hold state |
| `KeyboardHelp.qml` | the `?` key-map overlay: rows from a JS literal, `Text.PlainText` | steal keys (the panel owns `?` and `Esc`) |
| `bin/omafan-ctl` | the only afanctl integration: verbs, globals, exit codes, the four JSON schemas, the hardware-limit cache, the undercooling refusal | write `/sys`/`/etc`; run `pkexec` for read verbs |
| `bin/omafan-keybindings` | install/remove/status/print of the managed `bindings.lua` block; conflict detection; backups | touch any other part of `bindings.lua` |
| `tests/*` | hardware-free proof that the contracts hold | run against the live fan unless explicitly opted in |
| `docs/*` | the design and its reasons | — |

`Model.js` is shared deliberately: `Panel.qml` and `BarWidget.qml` import it
as `qs`-free JavaScript (`import "Model.js" as Model`), and
`tests/model.test.mjs` source-evaluates the same file inside a
`new Function(...)` sandbox. One definition of the preset ladder, one set of
formatters, no duplicated arithmetic between the CLI, the panel and the widget.

## 3. Why the CLI is the only integration point

There are four reasons, in order of importance.

1. **One privilege boundary.** Writes must go through `pkexec afanctl`. Putting
   `pkexec` in QML would spread a privileged call across a UI file, make it
   hard to audit, and put a shell command string next to user-controlled text.
   `omafan-ctl` keeps every privileged invocation in one bash file that uses the
   array form of `exec` and never `eval`.
2. **Testability without hardware.** Because the GUI speaks only to
   `omafan-ctl`, the whole plugin can be exercised against
   `tests/fixtures/fake-afanctl` with `--afanctl <fixture> --pkexec none
   --runtime-dir <tmp>`. No QML test harness, no fan, no root. `Panel.qml`
   passes `OMAFAN_AFANCTL`/`OMAFAN_RUNTIME_DIR`/`OMAFAN_PKEXEC` through as
   flags only when they are set (DESIGN.md §6.2, ruling R4).
3. **A stable contract for the UI.** afanctl's `status --json` is a large
   document whose fields (and degradation latches) are afanctl's business.
   `omafan-ctl status --json` publishes `omafan.status.v1`: only the fields the
   UI needs, in the shape `Model.js` parses. The UI is insulated from afanctl's
   schema evolution.
4. **One place for the failure model.** Exit codes 0–8, the human "problem +
   fix" line on stderr, the JSON error envelope on stdout, and the
   `status`-exits-5-with-a-document rule all live in `omafan-ctl`. The panel's
   job is to render them, not to re-derive them.

## 4. Polling and cache strategy

### 4.1 The panel poll

- The re-read cadence comes from the widget settings behind an Advanced
  toggle: `poll_mode` (`auto`|`custom`, default `auto`) selects the mode and
  `poll_seconds` (int, `1..10`, default `2`, whole seconds only) is the custom
  value. Mode `auto` means exactly 2 s regardless of any leftover
  `poll_seconds`; mode `custom` uses `poll_seconds` clamped into range.
  `poll_seconds` clamped into range.
  `Panel.qml` clamps a bad value into range. This governs how often omafan
  re-reads the daemon's status, never how often the daemon samples the SMC
  hardware (afanctl's own `[poll] interval_s`, 1 s, is out of scope).
  Both keys are also settable from the panel itself: the mouse-only REFRESH
 row (ruling R10) writes `poll_mode` / `poll_seconds` through
 `omarchy bar set`, and a settings-only write is patched into the running
 widgets in place — the cadence changes live, no reload.
- The poll `Timer` is started **on load, not on open**. The bar widget reads
  the panel's parsed status while the panel is invisible, so the bar is live
  without the panel ever having been opened.
- Each poll runs `bin/omafan-ctl status --json` through a `Quickshell.Io`
  `Process` with an array `command:` and a `StdioCollector` (`waitForEnd`).
  The stdout is parsed by `Model.parseStatus()`; a non-zero exit is **not** a
  parse failure — `status` still prints `omafan.status.v1` when the daemon is
  down and signals that with exit 5 and `daemon.running: false` (DESIGN.md
  §4.1, R6). The panel reads the document, not the exit code.
- The panel refreshes immediately after every write completes, so the UI
  renders what the daemon reports (`target_rpm`, `actual_rpm`, `verified`,
  `recent_errors`), never what it asked for (PRD F5).
- `r` (or a menu action) forces an immediate refresh.

### 4.2 The hardware-limit cache (inside `omafan-ctl`)

`status` and `presets` need `fan_min_rpm`/`fan_max_rpm` to compute the preset
ladder. Querying `afanctl status --json` on every poll would be wasteful, so:

- `state.json` is the primary source for the fast-changing fields (mode,
  temperature, fan rpm, hold, latches).
- `afanctl status --json` is executed only when the hardware limits are
  unknown, when the cached limits are older than 24 hours, or when `--full` is
  given.
- The cache lives at `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback
  `/tmp/omafan-<uid>/hw.json`) and holds
  `{"fan_min_rpm":…,"fan_max_rpm":…,"captured_at":…,"afanctl_version":…}`.
- An unwritable cache directory is **not** an error: the CLI degrades to
  querying afanctl each time and adds a `warnings[]` entry (DESIGN.md §4.1).
- A stale cache is kept as a fallback only when afanctl cannot be asked.

### 4.3 Staleness

`state_stale` is true when `state.json`'s mtime age exceeds
`max(5 s, 3 × poll interval)`. The CLI applies the documented 5 s floor
(`STALE_AFTER_S`); `Model.isStateStale` applies the same floor. A stale state
with no readable daemon becomes `running: false`. Writes refuse while the
daemon is degraded (exit 6) or unreadable (exit 5); refusing is the safe
direction (DESIGN.md §4.1, PRD F6).

## 5. The failure surface

Every failure has a machine signal (exit code for scripts, document field for
the UI), a human line naming the fix, and a rendered banner. The table is the
whole surface.

| Condition | CLI exit | Document / banner | Operator action |
|---|---|---|---|
| success | 0 | `ok: true`; normal render | — |
| runtime failure (afanctl nonzero, unparsable output, unknown hardware limits, failed write) | 1 | `action.v1`/`presets.v1` error naming the fix | read `status`; check `recent_errors` |
| usage error (bad verb/flag/preset, non-integer rpm) | 2 | error envelope, `error: "usage"` | `omafan-ctl --help` |
| `pkexec` absent | 3 | `action.v1` error, names polkit | install polkit / check the rule |
| authorisation denied or cancelled | 3 | `action.v1` error (`rc=126/127` or "Not authorized") | check `/usr/share/polkit-1/rules.d/` |
| afanctl missing/not executable | 4 (reads) | `afanctl.present: false`, warning | install afanctl, then `systemctl restart afanctl` |
| daemon down / runtime dir unreadable / no `state.json` | 5 | `daemon.running: false`, `state_stale: true` | `systemctl restart afanctl` |
| `monitor_only` latch | 6 | `daemon.monitor_only: true` | `systemctl restart afanctl` (freshness gate ignores a byte-identical re-issue) |
| `auto_restore_pending` | 6 | `daemon.auto_restore_pending: true` | wait, then `omafan-ctl status` |
| rpm outside `[fan_min_rpm, fan_max_rpm]` | 7 | `action.v1` error | pick an rpm in band (`--force` overrides) |
| undercooling risk (DESIGN.md §5.1) | 8 | `action.v1` error naming temp/rpm/alternatives | pick a higher preset, or confirm deliberately (`--force`, or a second `Enter` in the panel) |
| stale `state.json` | as above | `daemon.state_stale: true` | `systemctl restart afanctl` |
| unwritable hw-limit cache | 0 | `warnings[]` entry | none required |
| `notify-send` missing/failing | unchanged | — | none required (never changes the exit code) |

The panel does not wait for the CLI to report a degraded daemon: it refuses
writes locally with the same reason text (`Model.degradedReason`), so the
banner is truthful even before a round-trip. The CLI enforces the same rules,
so a script that bypasses the panel gets the identical refusal.

## 6. Boundaries and change channels

`DESIGN.md` is the frozen contract this architecture implements: §3 (preset
model), §4 (CLI), §5 (Model.js), §6 (QML), §7 (keybindings), §8 (safety),
§10 (tests). A change to any of those is proposed in `DEVIATIONS.md`, never
made silently. The requirements behind every decision are in `PRD.md`. The build
record that produced it (`PLAN.md`, `QUESTIONS.md`, `orchestration/`, whose
`BUILD-LOG.md` is the phase-by-phase audit trail) and the development record for
everything after it (`worknotes/`, one folder per piece of work) are kept on the
`dev` branch, together with the agent notes and the `orchestration/live-install.sh`
orchestrator tool — the default branch ships the plugin, its tests and this
documentation only (rulings R11, R12).
