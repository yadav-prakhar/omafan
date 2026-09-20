---
feature: in-panel-refresh
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-in-panel-refresh/PLAN.md
  - 2026-09-17-in-panel-refresh/LOG.md
---

# Summary — in-panel refresh control

## T5 in-panel refresh control (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `done/2026-09-17-t5-panel-refresh-control.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Ask: poll interval control settable from the panel UI.
Plan: [the plan](PLAN.md) · Evidence:
[the evidence](LOG.md) · Ruling: repo
`DEVIATIONS.md` R10.

## Completed

- Panel.qml: REFRESH row (Auto/Custom chips + ±1 s stepper in custom mode),
  writing `poll_mode`/`poll_seconds` via `omarchy bar set`; dedicated
  settingsProc + 20 s deadline + own error line; fan locks untouched.
- DESIGN.md §6.2 paragraph; DEVIATIONS.md R10 ruling (same changeset).
- tests/panel-refresh.test.sh (new, structural) as the gate's 8th suite.
- Mirrors: CONTRIBUTING.md count, README, docs/INSTALL/TROUBLESHOOTING/
  ARCHITECTURE, CHANGELOG.
- Gate: 8/8 suites PASS. Live: installed, panel opens, IPC `state` returns a
  live doc; the row's exact write path verified end-to-end and restored.

## Blocked / unverified

- Root `AGENTS.md` + `tests/AGENTS.md` suite-count mirrors (say 6/7, should
  say 8): agent-instruction files, edit approval timed out — pending a
  user-approved pass.
- The chip/stepper click behaviour itself is visual; the user confirms on
  screen (write path and guards are machine-verified).
