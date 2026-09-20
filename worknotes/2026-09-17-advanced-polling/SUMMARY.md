---
feature: advanced-polling
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-advanced-polling/PLAN.md
  - 2026-09-17-advanced-polling/LOG.md
---

# Summary — advanced polling control + slider Auto-reset

## planning session (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `done/2026-09-17-planning-session-summary.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

**Status: completed.** This session planned, gathered evidence, and wrote
notes. It did **not** implement anything.

## What was done

- Inspected the omafan repo contracts: `DESIGN.md` (frozen, §1 manifest block,
  §3 preset model, §5.1 undercooling guard), `DEVIATIONS.md` (rulings R1–R8),
  `manifest.json`, `Panel.qml` slider/pending plumbing, `Model.js` slider math,
  and the test assertions that pin `poll_seconds` (keys list, defaults, 1–10
  bounds in `tests/manifest.test.sh`).
- Created the notes subfolders `plans/`, `logs/`, `reviews/`, `done/` and an
  [worknotes index](../INDEX.md) under the Obsidian folder, preserving all four pre-existing
  loose notes untouched.
- Gathered read-only polling evidence (configured/default/observed) —
  [afanctl polling evidence](LOG.md).
- Wrote the phased plan + tickets —
  [the plan](PLAN.md) — and the settings API
  review — [the review](REVIEW.md).

## Key conclusions

- afanctl polls at **1 s** (configured = default = observed), proven by the
  daemon's own `config.interval_s` + `source` fields and `polls == uptime_s`.
- **No afanctl change is needed** for the Advanced polling control: it governs
  omafan's own refresh (`poll_seconds`, already a persisted shell setting).
- The shell's settings schema supports `boolean`/`enum`/`integer` — proven
  from installed built-in widget manifests — so the Advanced toggle persists
  through the supported shell settings mechanism.
- Scope ruling recorded: omafan status refresh only; afanctl hardware polling
  is future work.

## What was not done (deliberately)

- No product-code edits, no fan writes, no commits, no system-config changes.
- No checks were claimed as run (the gate, qml-lint, live verification belong
  to the implementation tickets T1–T5 and will be evidenced in `logs/` when
  run).
- No `.omo` plan file — the operator asked for Obsidian notes.

## Next actions

Dispatch T1 → T5 from
[the plan](PLAN.md) in dependency order;
start with T2 (slider fix) after T1's policy verification.

## Agent identity note

This session's operator requested "Union Alpha Free" subagents. The task API
cannot select a model; the harness reports this session as model
`deepseek-v4-pro` (id `opencode-go/deepseek-v4-pro`). Recorded rather than
guessed.

## Advanced polling + slider Auto-reset implementation (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `done/2026-09-17-implementation-summary.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

**Status: implemented in the working tree, hardware-free gate green 7/7, live
verify partial (read-only).** No commits made (orchestrator owns commits);
tree state reported below. `tests/hw-smoke.sh` never run (hot machine, no
operator request).

## Ticket map (all links relative to the Obsidian omafan folder)

| Ticket | Plan / notes | What landed (worktree, uncommitted) | Gate / evidence |
|---|---|---|---|
| T1 notes policy | [the plan](PLAN.md) §T1 | `AGENTS.md` work-records + scope lines (verified present) | policy text check, no code |
| T2 slider Auto-reset + race regression | plan §T2 | `Panel.qml`: `expectingAuto`/`lastWriteWasRelease`, debounce cancel on release, confirm-on-fresh-auto-status only, failure voids expectation; `CHANGELOG.md` Fixed entry | new `tests/panel-slider.test.sh`: **PASS 26 / FAIL 0**; `qml-lint` clean |
| T3 polling mode (Auto=2s / custom 1–10) | plan §T3; [the review](REVIEW.md) | `manifest.json` + `DESIGN.md §1`: `poll_mode` enum `auto\|custom` default `auto`; `Model.js`: pure ES5 `effectivePollSeconds(mode, pollSeconds)`; `Panel.qml`: `pollMode` + `pollSeconds` via that function; `poll_seconds` kept as the custom value | `tests/model.test.mjs`: **PASS 167 / FAIL 0** (18 new mode-math assertions); `tests/manifest.test.sh`: **PASS 26 / FAIL 0** |
| T4 docs/contract/changelog | plan §T4 | `DEVIATIONS.md` provisional ruling R9; mirrors moved together: `README.md`, `docs/INSTALL.md`, `docs/TROUBLESHOOTING.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md` Unreleased | DESIGN §1 block == `manifest.json` (parsed-JSON equality verified) |
| T5 tests + QA | plan §T5 | test-only additions (by concurrent workers, verified by T5); T5 proper: verification, hermeticity audit, evidence log | [T5 gate evidence](LOG.md) — full outputs pasted |

Prior evidence this phase builds on: [afanctl polling evidence](LOG.md)
(afanctl `interval_s` = 1 s configured/default/observed → out of scope, no
afanctl change), [the planning summary](SUMMARY.md) (Phase 0).

## Files changed (worktree vs `origin/master`, uncommitted)

`AGENTS.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (6→7 suites), `DESIGN.md` (§1),
`DEVIATIONS.md` (R9 provisional), `Model.js` (+`effectivePollSeconds`),
`Panel.qml` (T2 guards + `pollMode`/`pollSeconds`), `README.md`,
`docs/ARCHITECTURE.md`, `docs/INSTALL.md`, `docs/TROUBLESHOOTING.md`,
`manifest.json` (+`poll_mode`), `tests/AGENTS.md`, `tests/manifest.test.sh`,
`tests/model.test.mjs`, `tests/run-all.sh` (7th suite); new
`tests/panel-slider.test.sh`. Unrelated untracked: `linkedin_post.md`,
`x_post.md`, `x_threads.md`.

## Gate results (pinned to the 02:39 IST run — re-run before shipping)

`bash tests/run-all.sh` → **PASS suites 7 / FAIL 0 / SKIP 0** (EXIT 0).
Per-suite: plugin-validate OK · manifest 26/0 · model 167/0 · ctl 239/0 ·
keybindings 71/0 · qml-lint 3 files clean (114 expected non-fatal `qs.*`
warnings) · panel-slider 26/0. `bash -n` clean on both bins + new suite.
`omarchy plugin validate .` exit 0. Full pasted outputs:
[T5 gate evidence](LOG.md).

## Live verify — verified vs unverified

- Verified read-only: plugin `enabled:true`; `omafan state` IPC returns
  `omafan.status.v1` healthy (`observe`, `state_stale:false`); `status --human`
  reads mode/rpm/t_eff/band; shell ping `ok`; no omafan lines in the last 300
  shell-log lines; user `shell.json` has no poll overrides.
- Unverified: `bar set poll_mode` persistence + restart survival + Auto=2s /
  custom cadence behaviour (installed plugin copy is still the OLD 3-key
  build; live-install deferred — unsafe while workers edit, on a hot
  machine); slider Auto-reset visual + settings-UI screenshots (need
  live-install; fan writes refused on a 78–90 °C machine).

## Residual risks

1. Re-run the gate before the ship commit — the tree moved three times during
   T5 verification.
2. R9 provisional: the `poll_custom` boolean fallback is decided only by the
   pending live settings-UI check.
3. `panel-slider.test.sh` is structural by necessity (no QML runtime in-gate);
   its assertions must move with any panel refactor.
4. `effectivePollSeconds` ignores (→2 s) rather than rounds fractional input;
   `docs/ARCHITECTURE.md` §4.1 says "clamped" — one clarifying sentence if
   docs are reopened.
5. Ship step still needs: live-install → `bar set poll_mode custom` →
   restart → persistence + cadence check → restore defaults → screenshots.
