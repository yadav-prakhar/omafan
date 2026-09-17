# Changelog

All notable changes to omafan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The RPM slider no longer keeps showing the last manual rpm after the fan is
  returned to firmware auto. `pendingRpm` is cleared only when a fresh daemon
  status confirms the hold is gone (never on a bare write exit), the slider
  falls back to its base/min rendering (`—` at the hardware floor), a queued
  slider debounce is cancelled on every release path so it cannot reapply a
  manual hold afterwards, and a stale hold document arriving after an Auto
  write can no longer repopulate the slider. A failed release keeps the
  truthful prior state. Guarded by `tests/panel-slider.test.sh` in the gate.
  Bug fix only — no contract change (ruling R9; `Model.js` signatures,
  presets, exit codes and the keyboard map are untouched).

- `omafan-ctl` no longer litters `TMPDIR`. Scratch files are reaped by a
  process-scoped name pattern instead of by an array: `tmpfile()` is always
  called as `x="$(tmpfile)"`, and a command substitution runs in a subshell, so
  the old `Tmpfiles+=(...)` registration happened in a copy that died with the
  subshell and the file was never removed. `status --full` (the bar and panel's
  live read) and `doctor` each left one 0-byte file per run — 1210 had piled up
  in `/tmp` on the reference machine, three a minute while the bar polled.
  `tests/ctl.test.sh` now asserts every verb leaves `TMPDIR` empty (RED against
  the old code, which left three files behind).
- The bar widget's hold tint follows the theme again — Omarchy's `bar.urgent` /
  `Color.urgent` "active" colour (red on the reference theme) instead of a
  hard-coded green `#5a995a`. The tint appears only while a hold is active.
- `tests/keybindings.test.sh` asserted the pre-rename floor chord description
  (`omafan: fans off (floor)`). It now matches the helper, `DESIGN.md` §7 and
  `docs/KEYBINDINGS.md` (`omafan: fans floor`), so the gate is green on a clean
  tree again.

### Added

+- In-panel refresh control: the panel's new REFRESH row (below the slider)
+  sets the Advanced polling control from the UI — Auto/Custom chips write
+  `poll_mode` and, in custom mode, a `−`/`+` stepper moves `poll_seconds` by
+  one whole second within 1–10 (clamped through `Model.effectivePollSeconds`).
+  Writes go through the shell's own `omarchy bar set` path (no new
+  privilege, no direct `shell.json` editing), take effect live without a
+  reload, are allowed while the daemon is degraded/offline, and never touch
+  the fan-write lock or the keyboard cursor model (ruling R10; guarded by
+  `tests/panel-refresh.test.sh`, the gate's 8th suite).
- Advanced polling control: a `poll_mode` setting (`auto`|`custom`, default
  `auto`) on top of the existing `poll_seconds` key (ruling R9, live-verified).
  `auto` re-reads the daemon every 2 s regardless of any leftover
  `poll_seconds` value; `custom` uses `poll_seconds` in whole seconds 1–10.
  The control governs how often omafan re-reads status, never how often the
  daemon samples the SMC.
- `CONTRIBUTING.md` — the gate, branch naming, commit conventions, the
  frozen-contract procedure and the code conventions per language.
- `SECURITY.md` — what security means for a fan controller (privilege boundary,
  `/sys`, refusal model, fan safety), how to report, supported versions.
- `skills/` — five task-shaped procedures for agents working in this repo:
  `run-the-gates`, `live-verify-in-the-shell`, `change-a-frozen-contract`,
  `capture-docs-screenshots`, `publish-a-release`.
- `.github/` — a PR template that mirrors the review checklist, and an issue
  template that asks for the hardware/version/`doctor` evidence.

### Changed

- `README.md` — refreshed hero and section screenshots taken from the current
  build (the previous hero showed the older `Off (floor)` label), a scannable
  feature table, and new Development and Contributing sections.
- `AGENTS.md` files revalidated against the tree: structure and mirror rules
  updated, the LEDGER line format corrected to em dashes, the test flag note
  corrected (`hw-smoke.sh` is `set -euo pipefail` too), and the
  chord-description mirror trap recorded in `bin/` and `tests/`.

## [1.0.0] - 2026-09-15

### Added

- Bar widget showing live CPU temperature, fan RPM, or both, tinted when a
  manual hold is active.
- Panel with six presets (Auto, Floor, Low, Medium, High, Full) derived from the
  live hardware fan range, plus an RPM slider.
- Keyboard-first cursor model inside the panel: j/k/h/l navigation, digits 1-6
  for direct presets, c to cycle, r to refresh, ? for a key-map overlay.
- Global keyboard shortcuts on chords verified free against the live compositor:
  SUPER+ALT+{T,A,O,L,M,H,X,C}.
- `bin/omafan-ctl` CLI exposing status, presets, doctor, preset, rpm, cycle,
  and release verbs with machine-readable JSON output.
- `bin/omafan-keybindings` installer/remover for the Hyprland keybinding block,
  with conflict detection and byte-identical restore.
- Safety features: undercooling guard (exit 8 / panel confirmation for presets
  below current RPM on hot machines), degraded/offline state banners with
  exact fix commands, debounced slider writes, optional release-after-minutes
  timer.
- Complete documentation set: README, ARCHITECTURE, SAFETY, KEYBINDINGS,
  INSTALL, TESTING, TROUBLESHOOTING, PUBLISHING, and PRIOR-ART.
- Automated test suites: manifest validation, Model.js unit tests (Node),
  CLI tests with fake afanctl, keybinding tests with stub hyprctl, QML lint,
  plugin validate, integration shell suite, and hardware smoke test.
- GPL-3.0-only licence.

[1.0.0]: https://github.com/yadav-prakhar/omafan/releases/tag/v1.0.0
[Unreleased]: https://github.com/yadav-prakhar/omafan/compare/v1.0.0...HEAD
