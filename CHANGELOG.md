# Changelog

All notable changes to omafan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-15

### Added

- Bar widget showing live CPU temperature, fan RPM, or both, tinted when a
  manual hold is active.
- Panel with six presets (Auto, Off, Low, Medium, High, Full) derived from the
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
