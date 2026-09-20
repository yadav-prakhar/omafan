---
feature: in-panel-refresh
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - Panel.qml
  - DESIGN.md §6.2
  - DEVIATIONS.md (R10)
  - tests/panel-refresh.test.sh
---

# In-panel refresh control

Ask: make the poll interval settable from the panel UI, not only through the
shell's settings keys. Shipped as the mouse-only REFRESH row (Auto/Custom chips
plus a ±1 s stepper) writing `poll_mode`/`poll_seconds` through `omarchy bar set`;
ruled in `DEVIATIONS.md` **R10**; guarded by `tests/panel-refresh.test.sh`, the
gate's eighth suite. Landed in `fd62b55`.

| File | What it is |
|---|---|
| `PLAN.md` | approach, source-verified before coding |
| `LOG.md` | the shell-source reads that fixed the design, plus the evidence |
| `SUMMARY.md` | what was completed |

## T5 in-panel refresh control (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `plans/2026-09-17-t5-panel-refresh-control.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Ask: "i want the poll interval control in a way that it can be set from panel
in the ui." The T3 Advanced polling control (`poll_mode`/`poll_seconds`, R9)
was settings-key-only; this ticket gives it a surface inside the panel.

## Approach (source-verified before coding)

- Write path: `omarchy bar set <id> <key> <value> [--json]` — the shell's own
  settings IPC (`PluginRegistry.setBarWidget` → `shellConfigMutator`).
- Reactivity: `Bar.applySettingsDelta` patches a settings-only write into the
  running widgets in place (no reload); `BarWidget.onSettingsChanged` →
  `injectPanel()` re-injects settings, so `pollSeconds` re-evaluates live.
- UI: mouse-only REFRESH row below the slider — Auto/Custom chips + (custom
  mode only) a −/+ stepper, ±1 s, clamped via `Model.effectivePollSeconds`.
- Scope guards (ruling R10): no pkexec, no fan-write lock (`busy` untouched),
  own Process + 20 s deadline + own `settingsError` line (survives the next
  good poll clearing `lastError`), works while daemon degraded/offline,
  keyboard cursor model (`visibleSections = ["presets","slider"]`) unchanged,
  no new IPC methods, no manifest change (keys exist from R9).

## Changeset

`Panel.qml` (state, setPollMode/stepPollSeconds, settingsProc,
settingsDeadline, REFRESH row, RefreshChip component) · `DESIGN.md` §6.2 ·
`DEVIATIONS.md` R10 · `tests/panel-refresh.test.sh` (new structural suite) ·
`tests/run-all.sh` (8th suite) · `CONTRIBUTING.md` count · `README.md` ·
`docs/INSTALL.md` §6 · `docs/TROUBLESHOOTING.md` §4 · `docs/ARCHITECTURE.md`
§2 + §4.1 · `CHANGELOG.md`.

## Status

Implemented; gate green (see [the evidence](LOG.md)).

Open: root `AGENTS.md` + `tests/AGENTS.md` suite-count mirrors (6/7 → 8) are
agent-instruction files and the edit approval timed out — needs a user-approved
pass.
