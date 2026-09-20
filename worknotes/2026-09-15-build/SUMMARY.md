---
feature: build-2026-09-15
status: done
branch: dev
opened: 2026-09-15
updated: 2026-09-15
related:
  - PRD.md
  - DESIGN.md
  - orchestration/BUILD-LOG.md
  - orchestration/LEDGER.md
  - orchestration/tickets/
---

# The build (2026-09-15)

Narrative writeup of the one-night build: built, gate-tested and live-verified
against the reference A1708 on 2026-09-15. The machine record — ticket cards,
the flight recorder, the two adversarial reviews — is in `orchestration/`; the
phase-by-phase audit trail is [orchestration/BUILD-LOG.md](../../orchestration/BUILD-LOG.md).

| File | What it is |
|---|---|
| `SUMMARY.md` (this file) | the writeup: what shipped, what was verified, the two findings worth keeping |
| [orchestration/BUILD-LOG.md](../../orchestration/BUILD-LOG.md) | per-phase audit trail |
| [orchestration/LEDGER.md](../../orchestration/LEDGER.md) | flight recorder, one line per dispatch/verify/ruling |

## omafan — Omarchy fan-control plugin for the A1708 (build writeup)

*Migrated from the pre-`worknotes/` archive note `build-writeup.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

**Verdict:** built, gate-tested and live-verified in one night (2026‑09‑15).
`omafan` is an Omarchy Quattro shell plugin (bar widget + panel + CLI + global
chords) that drives the already-installed **afanctl** daemon; it installs **no**
new privilege surface and never writes `/sys`. Repo:
`https://github.com/yadav-prakhar/omafan`. Requirements: `PRD.md`, contracts:
`DESIGN.md`, tickets/routing: `PLAN.md`, flight recorder:
`orchestration/LEDGER.md`, narrative: `orchestration/BUILD-LOG.md`.

## What it is

| Piece                    | What it does                                                                                                                                                                                                                           |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BarWidget.qml`          | live CPU temperature in the bar (default `show=temp`), tinted while a hold is active; left click opens the panel, right click releases to firmware, wheel = ±100 rpm                                                                   |
| `Panel.qml`              | hero (temp · rpm · mode), six preset chips, RPM slider, banners for degraded/offline states, `?` key map, full keyboard cursor model                                                                                                   |
| `bin/omafan-ctl`         | the only thing that talks to afanctl: `status`, `presets`, `doctor`, `preset`, `cycle`, `rpm`, `release`; JSON documents `omafan.status.v1` / `omafan.presets.v1` / `omafan.action.v1` / `omafan.doctor.v1`; documented exit codes 0–8 |
| `bin/omafan-keybindings` | installs/removes one managed block in `~/.config/hypr/bindings.lua`, refuses on a conflict, restores byte-identically on removal, reports `stale-path`                                                                                 |
| `Model.js`               | pure logic (preset ladder, clamping, status parsing, undercooling guard) — 148 node assertions                                                                                                                                         |
| global chords            | `SUPER+ALT+T` panel · `A` auto · `O` off · `L` low · `M` medium · `H` high · `X` full · `C` cycle (all verified free against the 175 live binds, including `code:` chords)                                                             |

## Why it is not a duplicate of the existing Mac fan plugins

`io.github.moerdowo.fan` (Apple SMC), `benekuehn.macbook-fans` (T2),
`io.github.deadjoe.mbpfan`, `io.github.endijs.t2-fan-control` and
`nate.framework.fan-control` all ask the user to run a root installer that writes
`/etc/udev/rules.d`, `/etc/polkit-1/rules.d`, sudoers or a `/usr/local/libexec`
helper, then read/write `/sys` themselves. omafan reuses afanctl's existing,
auditable polkit rule, delegates every failure path to afanctl's
fail-toward-the-firmware model (per-poll verify/re-assert, async-signal-safe AUTO
restore, systemd watchdog, sensor-loss → AUTO) and is keyboard-first. Details and
licences: `docs/PRIOR-ART.md`.

## Verification actually performed

- `omarchy plugin validate .` → 0; `tests/run-all.sh` → **PASS 6 / FAIL 0**
  (plugin-validate, manifest, model 148 assertions, ctl, keybindings 71,
  qml-lint). `tests/qml-lint.sh` had to be rebuilt: the plugin guide's
  `qmllint -I $OMARCHY_PATH/shell` cannot resolve `qs.Ui`/`qs.Commons` on this box
  (no `qmltypes`, and the import path needs a `qs/` directory) — verified by
  running it against the shipped `omaplug` plugin, which shows the same failure.
- Live: plugin discovered → enabled → `omarchy-shell omafan state` returns a valid
  status document → `omarchy-shell omafan toggle` opens the panel → the rendered
  panel and the bar's `83 °C` readout were transcribed from real screenshots.
- Keybindings: all eight chords appear in `hyprctl binds -j` with their
  descriptions; `remove` restored `bindings.lua` byte-identically
  (md5 `3b5174804388…` before and after) and the binds disappeared.
- Hardware: `hold` through the real polkit path was exercised and the fan left in
  `observe`/`manual=false` (evidence in `orchestration/LEDGER.md`).

## Two findings worth keeping

1. **`pkexec env VAR=… program` defeats afanctl's polkit rule.** The rule pins
   `program == /usr/bin/afanctl` and the exact argv, so an `env` wrapper makes it
   NOT_HANDLED and pkexec silently falls back to a password prompt:
   `pkexec /usr/bin/afanctl status --json` answers in **0.026 s**, the `env` form
   hangs. Every write through the runner was therefore broken while the
   fixture-only tests stayed green — found by running the real path. Fixed in
   `bin/omafan-ctl` (bare argv, refuse a custom runtime dir with a runner, bound
   every runner call, new `pkexec_write_path` doctor check) and in the panel
   (a runner that never answers now kills itself and banners instead of freezing).
2. **afanctl's over-temperature escalation outranks a hold.** With `hold 7200`
   applied and held at 83 °C, the daemon later reported `target_rpm 6200` while
   still `mode=hold` at 94 °C — i.e. its `EscalateMax` path writes the config's
   `curve.max_rpm`. omafan renders the daemon's numbers, so the UI said 6,200 rpm;
   worth knowing before trusting a hold as an upper bound. This is afanctl
   behaviour, not omafan's, and is not a defect in either — but it is a surprise
   documented in `orchestration/BUILD-LOG.md`.
