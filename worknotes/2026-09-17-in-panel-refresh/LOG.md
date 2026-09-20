---
feature: in-panel-refresh
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-in-panel-refresh/PLAN.md
  - 2026-09-17-in-panel-refresh/SUMMARY.md
---

# Log — in-panel refresh control

## T5 in-panel refresh control: implementation + evidence (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t5-panel-refresh-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Plan: [the plan](PLAN.md). Ruling: DEVIATIONS R10
(same repo changeset). Prior art: [T3 polling evidence](../2026-09-17-advanced-polling/LOG.md) (§1b
proved `omarchy bar set` writes and the string/integer typing nuance).

## 1. Shell-source reads that fixed the design

- `/usr/share/omarchy/shell/services/PluginRegistry.qml:342` `setBarWidget`
  mutates the layout entry via `shellConfigMutator`, bumps `registryRevision`,
  calls `pluginsChanged()`. Persisted to shell.json by the mutator.
- `/usr/share/omarchy/shell/plugins/bar/Bar.qml` `applyBarConfig`:
  `BarModel.inlineSettingsDelta` detects a settings-only change and
  `applySettingsDelta` assigns the new entry object straight onto
  `item.settings` of every matching module slot — no widget rebuild.
- `/usr/share/omarchy/shell/Ui/BarWidget.qml:41` `setting()` reads
  `settings[name]`; omafan's `BarWidget.onSettingsChanged: injectPanel()`
  re-injects into Panel. Conclusion: a panel-side `omarchy bar set` write
  updates `pollMode`/`pollSeconds` bindings live.

## 2. Implementation notes

- `setPollMode(mode)`: skip if unchanged (`next === root.pollMode`), else
  `["omarchy","bar","set",moduleName,"poll_mode",next]`.
- `stepPollSeconds(delta)`: `Model.effectivePollSeconds("custom",
  pollSeconds + delta)` clamps to whole seconds 1–10; skip at boundaries;
  integer write carries `--json` (T3 §1c typing nuance).
- `settingsProc` collects stderr; on exit != 0 the first stderr line lands in
  `settingsError` (rendered in the refresh row), never in `lastError` (fan
  banner). Exit 0 clears `settingsError`.
- `settingsDeadline` (20 s) kills a hung write, releases `settingsBusy`,
  names the symptom. `settingsBusy` deliberately independent of `busy`.
- `RefreshChip` component: plain Rectangle + MouseArea (NOT CursorSurface)
  because the row is outside the keyboard cursor model by design.

## 3. Gate evidence (repo /home/prakhar/Work/tries/2026-09-15-omafan)

```
$ bash tests/panel-refresh.test.sh        -> PASS 24 / FAIL 0
$ bash tests/qml-lint.sh                  -> PASS qml-lint: 3 file(s) clean; 143 expected non-fatal warning(s)
$ bash tests/run-all.sh
RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS
RUN   panel-refresh          PASS
PASS suites 8 / FAIL suites 0 / SKIP 0
```

No fan writes; no hw-smoke (per standing rule — the user runs those).

## 4. Live evidence (post-install, 2026-09-17) — committed

Committed as `fd62b55` and pushed to origin/master (18 files, gate evidence
in the commit body).

```
$ orchestration/live-install.sh install
backed up shell.json -> orchestration/backups
copied working tree -> ~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
Enabled and moved io.github.yadav-prakhar.omafan

$ omarchy-shell shell rescanPlugins; omarchy-shell omafan toggle; omarchy-shell omafan state
→ omafan.status.v1 document returned (ok:true, daemon running) — the panel
  with the REFRESH row loaded without a QML error (a broken Panel.qml would
  have killed the IpcHandler too).

$ omarchy bar set … poll_mode custom; omarchy bar set … poll_seconds 4 --json
→ shell.json entry: poll_mode "custom", poll_seconds 4 (integer) — the exact
  writes the Custom chip and + stepper issue. Restored to auto / 5 afterwards.
```

The chips/stepper themselves are mouse-only and cannot be clicked from a
terminal; the structural suite pins their wiring (`tests/panel-refresh.test.sh`
PASS 24 / FAIL 0) and the row's write path is proven live above. The user
confirms the click behaviour visually.

Open item: root `AGENTS.md` / `tests/AGENTS.md` suite-count mirrors blocked
on a user-approved edit (agent-instruction files; approval timed out).
