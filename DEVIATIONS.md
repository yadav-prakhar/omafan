# DEVIATIONS.md — proposed changes to frozen contracts

Every entry: `D<n> — <item> — old → new — why — affected tickets — ruling`.

## Rulings made by the orchestrator (frozen items changed, tickets amended before dispatch)

- **R1 — preset model gained an undercooling guard.** `DESIGN.md §3` said presets
  are holds derived from the hardware band; live testing found the machine at
  97 °C with the firmware already at 4794 rpm, where `off`/`low`/`med` command
  *less* airflow. New: `DESIGN.md §5.1` (`isUndercoolingHot`,
  `undercoolingWarning`), exit code **8**, a second confirmation in the panel and
  `--force` on the CLI. Affected: T02b (new), T05, T09, T10.
- **R2 — runtime-directory plumbing.** afanctl has no `--runtime-dir` flag; it
  reads `AFANCTL_RUNTIME_DIR`. T04's card was amended before dispatch so no
  invented flag shipped.
- **R3 — the `qmllint` gate.** The plugin guide's `qmllint -I "$OMARCHY_PATH/shell"`
  cannot resolve `qs.Ui`/`qs.Commons` on this machine (no `qmltypes`; the import
  path needs a `qs/` directory) — verified against the shipped `omaplug` plugin.
  `tests/qml-lint.sh` (T01's file, already accepted) was rewritten by the
  orchestrator to build a shim import root, fail on syntax/unresolved-import/
  missing non-`qs.*` types, and report the `qs.*` member warnings instead of
  pretending they are clean. Affected: T01.
- **R4 — panel command plumbing.** `Panel.qml` resolves `bin/omafan-ctl` at
  runtime via `Qt.resolvedUrl` and honours `OMAFAN_AFANCTL`/`OMAFAN_RUNTIME_DIR`/
  `OMAFAN_PKEXEC`, and uses array-form `Process` commands only. Affected: T09.
- **R5 — `cycle` verb.** The frozen keybinding table and the panel's `c` key both
  need it and §4 did not define one; `DESIGN.md §4.5` now does. Affected: T04b,
  T05.
- **R6 — `status` exit-code split.** `status` renders a document even when the
  daemon is down and exits 5 in that case; consumers read `daemon.running` rather
  than treating a non-zero exit as a parse failure. Affected: T09, T05.
- **R7 — the privileged write path (three contract changes, all evidence-driven).**
  1. **Runner argv** is exactly `[<runner>, <afanctl>, <verb> (, <rpm>)]`.
     afanctl's polkit rule pins `program == /usr/bin/afanctl` and the exact argv,
     so the original `pkexec env AFANCTL_RUNTIME_DIR=… afanctl …` form made the
     rule NOT_HANDLED and pkexec fell back to a password prompt — **every real
     write hung** (verified: bare form 0.026 s, `env` form hangs). T04d.
     A custom `--runtime-dir` with a runner is now refused (exit 2). T04d.
  2. **Bounded runner calls**: a timeout is exit 3, never a hang; the panel kills a
     command at 20 s and banners instead of freezing. T04d, T09c.
  3. **Stale `state.json` refuses a write** with exit 5 (unless `--force`), because
     `state.json` is rewritten every poll and an old file means the daemon is not
     reporting; the command would sit latent in `cmd.json`. (REVIEW-R2 R2-3,
     fixed by the orchestrator after the review.) T04c lineage, orchestrator fix.
  Doctor check id list grew by `pkexec_write_path` (twelve ids). Affected: T04d,
  T05b, T09c.

## Fixes the orchestrator applied directly to worker-owned files

Recorded because the PLAN allows the orchestrator to fix after a re-dispatch, and
because these two files were owned by completed tickets:

- **`Panel.qml` — `release_after_minutes` was dead code (REVIEW-R2 R2-2,
  blocker).** The one-shot release timer was restarted on *every* successful poll
  while a hold was active, so an interval of ≥1 minute could never elapse: the
  only state the net exists to catch was the one it could not catch. Now armed on
  the hold's rising edge (`holdSeen`), restarted by genuine user action only, and
  the interval is clamped to ≥60 s. `DESIGN.md §8` wording updated to match
  (the old sentence literally prescribed the bug). Verified: `tests/qml-lint.sh`
  passes; the six-suite gate stays green.
- **`bin/omafan-ctl` — stale-state writes (REVIEW-R2 R2-3).** Added the staleness
  refusal described in R7.3, verified by transcript: a `state.json` touched two
  minutes ago refuses `preset med` with exit 5 and **no** write, `--force`
  overrides, and a fresh state writes normally. Not yet covered by a regression
  case in `tests/ctl.test.sh` (open item, listed in `docs/BUILD-LOG.md`).

- **R8 — two documentation corrections from REVIEW-R1.** (a) `DESIGN.md §7` claimed
  `tests/keybindings.test.sh` reproduces the free-chord analysis; it runs entirely
  against a stub `hyprctl` and a sandboxed Lua tree, so the sentence now attributes
  the analysis to orchestration-time evidence (PRD §2.7 + the live install record)
  and names the suite for what it is: a stub-based regression guard. (b)
  `DESIGN.md §6.2` described the preset chips as a "single horizontal row of 6";
  what shipped is a 2×3 grid that the keyboard cursor still treats as one row, so
  the wording was corrected to match the artifact (the grid is the better UI at
  this panel width). Affected: T12 (docs), T13.

## Rejected proposals

- Relaxing afanctl's polkit rule to accept an `env` wrapper, instead of fixing the
  argv: rejected — the rule is afanctl's audit surface, its exactness is the
  security property, and the sibling repo is already published.
