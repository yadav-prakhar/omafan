---
feature: advanced-polling
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - DESIGN.md
  - DEVIATIONS.md (R9, R10)
  - Panel.qml
  - Model.js
  - tests/panel-slider.test.sh
  - tests/panel-refresh.test.sh
---

# Advanced polling control + slider Auto-reset

The post-build feature stream (three asks: reset the rpm slider when a preset
returns to auto; add an Advanced polling toggle, auto = 2 s default / custom
1–10 s; and keep the work records) — files, tickets, evidence, and what landed.
Shipped in `fd62b55` (`feat(panel): advanced polling control and in-panel refresh row`).

**Scope ruling (binding for every ticket in this folder):** the Advanced
control governs how often **omafan re-reads the daemon's status**
(`poll_seconds` → `Panel.qml` timer). afanctl's own hardware poll interval
(`[poll] interval_s` in `/etc/afanctl/afanctl.toml`) is **out of scope, future
work** — the two must never be conflated. Evidence that the daemon's interval is
1 s and needs no change: [LOG.md](LOG.md).

| File | What it is |
|---|---|
| `ASK.md` | the operator's verbatim ask that opened this work |
| `PLAN.md` | the phased plan and its tickets (T1–T5) |
| `LOG.md` | chronological evidence: the afanctl read-only poll survey, then T1–T5 |
| `REVIEW.md` | findings + settings-schema recommendations that shaped the design |
| `SUMMARY.md` | the planning session and the implementation summary |

## slider Auto-reset + Advanced polling control (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `plans/2026-09-17-advanced-polling-slider-plan.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Source asks: [the ask](ASK.md) ("reset slider on auto", "advanced polling toggle"),
[BACKLOG.md](../BACKLOG.md) ("Big work" section). Evidence:
[afanctl polling evidence](LOG.md),
[the review](REVIEW.md).

## Scope ruling (fixed before any ticket dispatches)

- In scope: **omafan's status refresh interval** (`poll_seconds` widget setting,
  the `Panel.qml` timer at `interval: root.pollSeconds * 1000`).
- Out of scope (future work, do not conflate): afanctl's own hardware poll
  interval (`[poll] interval_s`, today **1 s** configured = default = observed).
  No afanctl change is needed for anything in this plan — evidence in the log
  note. If a future change touches afanctl, document it in the afanctl Obsidian
  folder per the standing instruction.
- User-facing wording: the Advanced control governs *how often omafan re-reads
  the daemon's status*, never how often the daemon samples the SMC.

## Execution status and constraints

- Planning notes saved; root `AGENTS.md` policy edit independently verified.
- T2–T5 implementation has **not started**. No slider or polling UI changes and no test runs are claimed.
- Model routing blocker: the planning task actually ran `opencode-go/deepseek-v4-pro`, not the requested `opencode-go/union-alpha`. The task API exposes no model selector. Do not launch further workers without resolving this constraint with the user.
- T2 clarification: a successful write exit alone is NOT confirmation of Auto. Only a fresh daemon status reporting firmware Auto may clear the displayed manual target. Cancel queued slider debounce when accepting Auto/release so it cannot immediately reapply a manual hold; retain truthful state when release fails. Test this explicitly.
- T3 needs the actual supported QML settings-write API verified before execution; schema type support alone does not establish persistence. Preserve or explicitly address existing users' nondefault `poll_seconds` settings.
- T4's deviation ruling must precede T3 implementation, despite the shorthand dependency diagram below. Shared `Panel.qml` edits need one owner.

## Phases

- **Phase 0 (done 2026-09-17):** notes scaffolding + read-only evidence
  gathering. Nothing in the repo changed. See
  [the planning summary](SUMMARY.md).
- **Phase 1:** tickets T1–T5 below, in dependency order. Each ticket: implement,
  run its gates, record evidence in `logs/`.
- **Phase 2:** full gate + live verify + QA, then completion summary in
  `done/` linking every ticket.

## Tickets

### T1 — notes policy (verification-only, no code)

Root `AGENTS.md` already carries the work-records policy (Obsidian folder,
plans/logs/reviews/done organization, dated filenames, relative links,
"never claim a check passed without evidence") and the scope line "The Advanced
polling control work is scoped to omafan status refresh only." **Root policy
already edited — this ticket verifies it, records it, and moves on.**

- Verify the exact policy text in the repo `AGENTS.md` matches the mandated
  wording; paste it into `logs/`.
- Outcome: one log entry. No commits.

### T2 — slider: confirmed Auto clears pending and shows min/inactive, with debounce-race regression

User bug: *"when preset is set to auto, the rpm slider continues to show the
rpm that was last set manually. need to reset it to base value to indicate the
custom value is not in effect."*

Known surface (repo `Panel.qml`, current):
- `root.pendingRpm` drives the slider label (`sliderValue.text`,
  `pendingRpm ?? "—"`) and position (`pendingRpm ?? fanMinRpm`).
- A stale status re-read after the Auto write can repopulate `pendingRpm` from
  the old hold doc (the `holdDoc.rpm` path) — the debounce/race risk this
  ticket must kill.

Required behaviour:
1. When `applyPreset("auto")` is **confirmed** (write accepted), set
   `pendingRpm = null` and render the slider at its base/min value with an
   inactive visual — the panel must *not* keep showing the last manual rpm.
2. Guard the race: a status document for a *previous* hold arriving after the
   Auto write (or any stale response) must not repopulate the slider; pending
   state is only set from the freshest accepted write, and post-write refresh
   (`Qt.callLater(refresh)`) never resurrects it.
3. "Base value" = `fan_min_rpm` (hardware floor) per DESIGN §3; never claim
   the fan is stopped — label stays `Floor (hardware floor)` for the `floor`
   preset and the slider just shows the band minimum when nothing custom is
   held.
4. Regression test: extend `tests/model.test.mjs` where pure (`sliderPosFromRpm`
   etc. stay frozen) and add a QML-lint / behavioural coverage for the race
   (stale-doc-after-auto must keep the slider reset). No new pure-Model
   contracts without a DESIGN amendment.

Do not: change `Model.js` signatures, presets, exit codes, or the frozen
keyboard map.

### T3 — Advanced polling control: Auto=2 s / custom whole seconds 1–10, persisted via supported shell settings

User spec: *"add polling interval control in an advanced toggle: auto: current
default, custom: takes input from user, unit is in seconds."* Ticket contract
agreed here: **Auto = 2 s** (today's default), **Custom = whole seconds 1–10**.

Recommended schema (evidence:
[the review](REVIEW.md)):

- Reuse the existing `poll_seconds` int key (1–10, default 2) as the custom
  value — it is already persisted by the shell and already consumed with a
  1–10 clamp (`Panel.qml` line 91).
- Add one schema key for the toggle. The shell's own built-in widgets prove
  `boolean` and `enum` schema types work (Indicators `alwaysShow`,
  agents `syncMode`). Prefer an `enum` (`auto|custom`, default `auto`) or a
  `boolean` (`poll_custom`) — pick in implementation, but the choice must be
  verified live with `omarchy bar set ... <key> <value>` against the running
  shell before the ticket closes.
- Persistence must go through the supported shell settings mechanism only
  (manifest schema + `shell.json`), never a side file. `--config`-style
  plumbing is for the CLI, not the panel.
- When mode is `auto`, `pollSeconds` is exactly 2 regardless of any leftover
  `poll_seconds` value; when `custom`, use the int value, clamped 1–10,
  whole seconds only (reject/ignore fractional and out-of-band values).

No afanctl change is needed for this ticket (see scope ruling).

### T4 — docs / contract / changelog (moves with T3, never alone)

The manifest schema block is frozen in `DESIGN.md §1` and mirrored in
`manifest.json`, `README.md` (Settings table), `docs/INSTALL.md`,
`docs/TROUBLESHOOTING.md`, `docs/ARCHITECTURE.md` (polling section), and
asserted verbatim in `tests/manifest.test.sh` (keys list, defaults, bounds).
**A schema change needs a `DEVIATIONS.md` ruling entry first** (old → new →
why → affected tickets), per the repo contract rule.

- Write the ruling for T3's new key (and any `poll_seconds` semantic change),
  then update every mirror in the same commit set — a half-updated rename
  turns the gate red (this already happened once with the floor chord).
- Update `CHANGELOG.md` Unreleased section.
- T2's slider behaviour is a bug fix, not a contract change; describe it in
  the changelog and, if DESIGN §6 wording contradicts the fix, propose the
  wording amendment in the same ruling.

### T5 — tests + QA (closes the phase)

- Extend `tests/manifest.test.sh` for the new schema key (type, default,
  bounds) — keep it in sync with the DESIGN manifest block.
- Regression for T2's race (see T2) and T3's mode math (auto ⇒ 2 s; custom ⇒
  clamp 1–10) where pure logic lives in `Model.js`.
- Gate: `bash tests/run-all.sh`, `bash tests/qml-lint.sh`,
  `bash -n bin/omafan-ctl bin/omafan-keybindings`, `omarchy plugin validate .`
  — paste outputs into `logs/`.
- Live verify with the `skills/live-verify-*` procedure (and screenshots via
  the screenshots skill if the shell's settings UI renders the new controls).
- Do not run `tests/hw-smoke.sh` (writes the fan) unless the operator asks;
  this work needs no fan writes.

## Dependency order

```
T1 (verify policy, no blockers)
 └─ T2 (slider fix + race regression)
     └─ T3 (Advanced toggle, schema)
         └─ T4 (DEVIATIONS ruling + docs + changelog, same changeset as T3)
             └─ T5 (tests + gate + live QA)
```

## Exit criteria

- Slider resets to min/inactive on a confirmed Auto, survives the stale-doc
  race, with a regression test in the gate.
- Advanced control persists via shell settings; Auto=2 s, custom 1–10 whole
  seconds; works after a shell restart.
- All mirrored facts moved together; gate green; evidence pasted in `logs/`;
  completion summary in `done/`.
