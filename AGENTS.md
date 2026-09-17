# PROJECT KNOWLEDGE BASE

**Generated:** 2026-09-16
**Revalidated:** 2026-09-16 against the tree at commit `31f977a`
**Commit:** 31f977a
**Branch:** master

## OVERVIEW
omafan: Omarchy shell plugin (Quickshell, Omarchy 4.0.0.alpha) — fan control
for pre-T2 Intel Macs (`applesmc`). Control surface over the installed afanctl
daemon; never touches `/sys` itself.

## STRUCTURE
```
./
├── BarWidget.qml      # bar entry (thin; no I/O)
├── Panel.qml          # panel UI; owns ALL QML side effects
├── Model.js           # pure logic (shared QML + tests)
├── KeyboardHelp.qml   # passive keymap overlay
├── manifest.json      # plugin manifest (entry + settings schema)
├── bin/               # omafan-ctl (sole afanctl interface) + keybindings installer
├── tests/             # hardware-free gate (bash harness + fixtures)
├── docs/              # operator docs (ARCHITECTURE, SAFETY, TESTING, ...) + docs/images/
├── skills/            # task-shaped procedures for agents (run-the-gates, live-verify-*)
├── .github/           # PR template + issue templates (no CI workflows)
├── orchestration/     # build tickets/logs (history, not runtime)
├── DESIGN.md          # FROZEN contract; changes need DEVIATIONS.md ruling
├── CONTRIBUTING.md    # branch naming, commit conventions, gates, PR flow
├── SECURITY.md        # threat surface, reporting, supported versions
├── CHANGELOG.md       # Keep a Changelog; Unreleased section while working
└── .recon/            # gitignored recon evidence (ignore)
```

Generated artifacts worth knowing: `preview.png` (README hero, real capture of
the current build) and `docs/images/*` (bar widget, `?` overlay).

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Bar/panel UI | `BarWidget.qml`, `Panel.qml` | Panel polls via `omafan-ctl status --json`, re-reads after every write |
| Pure logic | `Model.js` | preset ladder, `parseStatus`, undercooling guard |
| CLI verbs/exit codes | `bin/omafan-ctl` | reads never pkexec; writes via `pkexec afanctl hold\|observe` |
| Global chords | `bin/omafan-keybindings` | managed block in `~/.config/hypr/bindings.lua` |
| Test gate | `tests/run-all.sh` | 6 suites; all hardware-free |
| Data flow/failure modes | `docs/ARCHITECTURE.md` | daemon-first diagram |
| Contract | `DESIGN.md` + `DEVIATIONS.md` | 8 deviation rulings (R1–R8) |
| How to contribute | `CONTRIBUTING.md` | branches `<type>/<slug>`, Conventional Commits with a scope |
| Task procedures for agents | `skills/<name>/SKILL.md` | gates, live verify, frozen-contract change, screenshots, release |

## CODE MAP
No LSP/codegraph coverage for QML+bash (centrality unmeasured; from reads).

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `BarWidget` | QML entry | `BarWidget.qml` | label + gestures; reads `panelItem.status`, zero I/O |
| `Panel` | QML surface | `Panel.qml` | Timer poll, 2 Process gates, IPC target `omafan` |
| `presetRpm/presetsFor` | JS pure | `Model.js` | ladder from live `(minRpm,maxRpm)` band |
| `parseStatus` | JS pure | `Model.js` | `omafan.status.v1` → `{ok,status}` wrapper |
| `isUndercoolingHot` | JS pure | `Model.js` | `t≥80°C` + lower hold → refuse (exit 8) |
| `run_status/run_doctor` | bash verb | `bin/omafan-ctl` | status doc always emitted, even daemon-down |
| `write_prereqs` | bash gate | `bin/omafan-ctl` | degraded/stale/absent refusals before any write |
| `install/remove/status` | bash verb | `bin/omafan-keybindings` | 8 chords `SUPER+ALT+{T,A,O,L,M,H,X,C}` |
| `fake-afanctl` | fixture | `tests/fixtures/` | hardware-free daemon stand-in |

## WORK RECORDS (MANDATORY)
- Record all work for this repository in the Obsidian folder
  `/home/prakhar/Documents/Default/Workspace/omarchy plugin development/omafan`.
- Organize notes by purpose: `plans/` for phased plans and tickets, `logs/` for
  implementation decisions and command evidence, `reviews/` for findings and
  verification, and `done/` for completion summaries linked to the related notes.
- Use dated, descriptive filenames and relative links between related notes.
  Keep records current as work progresses; distinguish planned, completed,
  blocked, and unverified work. Never claim a check passed without evidence.
- Add other subfolders only when useful and explain their purpose in the notes.
  Preserve existing notes; do not reorganize or overwrite unrelated material.
- Obsidian records supplement, not replace, repository documentation, tests,
  CHANGELOG.md, and required DEVIATIONS.md rulings.
- The Advanced polling control work is scoped to omafan status refresh only.
  afanctl hardware polling control is future work; do not conflate the two.
  If future work changes afanctl, also document it in its Obsidian project folder.

## CONVENTIONS
- Fan command never originates in QML: QML → `omafan-ctl` → `pkexec afanctl`.
  Panel renders what daemon reports, never what was asked.
- `Model.js` ES5-only (`var`/function); no imports, no I/O, no side effects —
  QML imports it AND `tests/model.test.mjs` evals it via `new Function`.
- CLI JSON envelope: `{schema, ok, ...}`; errors `{schema, ok:false, error, message, exit_code}`.
  Default output JSON; `--human` for lines. `--dry-run` writes nothing.
- Exit codes: 0 ok · 1 runtime · 2 usage · 3 auth · 4 afanctl missing ·
  5 daemon down · 6 degraded · 7 out-of-band · 8 undercooling.
- Privileged argv exactly `[<runner>, <afanctl>, verb, args]` — no `env` wrapper
  (polkit pins argv). Custom `--runtime-dir`/`--config` refused on writes (exit 2).
- Keybindings: refuse-on-conflict, byte-identical install/remove, timestamped
  backup under `~/.local/state/omafan-keybindings/`.
- Tests isolate per-case: fresh tempdir, `XDG_RUNTIME_DIR` redirected, sandboxed
  `HOME`, stub `hyprctl`; never touch `/run/afanctl`, real HOME, or `/sys`.
- Branch/commit conventions live in `CONTRIBUTING.md`; scopes follow file
  ownership (`panel bar model ctl keybindings manifest docs tests design
  release repo`).
- Facts with mirrors must move together: chord descriptions live in
  `bin/omafan-keybindings` + DESIGN §7 + `docs/KEYBINDINGS.md` +
  `tests/keybindings.test.sh`; the version lives in `manifest.json` +
  `bin/omafan-ctl` (variable and usage header) + `CHANGELOG.md` +
  two test assertions.

## ANTI-PATTERNS (THIS PROJECT)
- NEVER write `/sys`, `/etc`, `/usr`, `/run/afanctl` from omafan code.
- Reads NEVER pkexec; only write verbs use the runner.
- NEVER claim "Floor" stops the fan — label is `Floor (hardware floor)`.
- NEVER hardcode RPMs in UI/logic — derive from `[fan_min_rpm, fan_max_rpm]`.
- NEVER `as any`-style coercion of missing readings: null rpm/temp is not 0.
- NEVER import Qt/Quickshell in `Model.js` (breaks the Node harness silently).
- NEVER add symlinks to plugin tree (`omarchy plugin validate` fails).
- Contract changes without a `DEVIATIONS.md` ruling entry.
- NEVER edit a mirrored constant in one place only — the gate asserts chord
  descriptions and the version verbatim, so a half-updated rename turns the
  suite red on a clean tree (already happened once with the floor chord).

## UNIQUE STYLES
- `DESIGN.md` frozen; `DEVIATIONS.md` records old→new→why→tickets→ruling.
- QML key handling via `PanelKeyCatcher` signals (`onMoveRequested`,
  `onTextKey`, …), not raw key events; `KeyboardHelp.qml` is passive.
- Staleness = `max(5s, 3×poll interval)`; interval cached in hw.json.
- Polling: fast path every `poll_seconds` (default 2s), every 10th `--full`;
  post-write `Qt.callLater(refresh)`; 20s process deadlines.
- Undercooling guard: hot (`t_eff_c≥80`) + below-current hold needs `--force`
  (CLI) or second `Enter` within 10s (panel).

## COMMANDS
```bash
tests/run-all.sh                          # full hardware-free gate (8 suites)
bash tests/qml-lint.sh                    # QML lint (qmllint + qs.* shim)
bash -n bin/omafan-ctl bin/omafan-keybindings  # shell syntax
omarchy plugin validate .                 # shell's structural gate
bin/omafan-ctl doctor                     # first response to any failure
OMAFAN_LIVE=1 tests/integration-shell.sh  # opt-in live (excluded from gate)
OMAFAN_HW=1 tests/hw-smoke.sh             # opt-in hardware (interactive yes)
```

## NOTES
- Deps (not bundled): afanctl ≥0.1.0 running, `omarchy-shell`, `pkexec`,
  `jq`; Node only for tests. No build step — `omarchy plugin add <git-url>`.
- `status` exits 5 with `daemon.running:false` when down — read the doc, not
  just the code. `doctor` names the fix per FAIL line.
- `orchestration/logs|backups`, `.recon/`, `.omo/` gitignored — ignore them.
- No CI workflows, Makefile, or package.json exist in this repo. `.github/`
  holds only the PR template and the issue templates.

