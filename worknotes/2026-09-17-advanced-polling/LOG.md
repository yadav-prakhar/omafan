---
feature: advanced-polling
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-advanced-polling/PLAN.md
  - 2026-09-17-advanced-polling/REVIEW.md
  - 2026-09-17-advanced-polling/SUMMARY.md
---

# Log — advanced polling control + slider Auto-reset

Chronological, oldest first.

Contents:
- afanctl polling interval evidence (read-only, 2026-09-17)
- T1 — work-records policy verification (2026-09-17)
- T2 slider Auto-reset + debounce-race fix (2026-09-17)
- T3 Advanced polling control: implementation + live evidence (2026-09-17)
- T4 docs/contract/changelog evidence (2026-09-17)
- T5 tests + QA gate evidence (2026-09-17)

## afanctl polling interval evidence (read-only, 2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-afanctl-polling-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

All commands below are **read-only** (no `hold`/`observe`, no pkexec, no
`/sys` writes). Goal: determine the afanctl polling interval, distinguishing
**configured / default / observed**, before planning the Advanced polling
control (scoped to omafan's own refresh; afanctl polling = future work).

## Installed package

```
pacman -Q afanctl → afanctl 0.1.0-1
file /usr/bin/afanctl → ELF 64-bit pie, x86-64, stripped, 1,039,216 bytes
```

## Configured interval (the file the daemon actually reads)

`/etc/afanctl/afanctl.toml` — present, root-owned, contains:

```toml
[thresholds]
high = 66   # ramp starts here; low is derived: high - 3
max  = 86   # full speed from here; guard: max <= 95

[curve]
min_rpm = 1200
max_rpm = 6200

[poll]
interval_s = 1        # >= 1
```

Header comment states: exactly five keys are honoured; unknown keys are warned
and ignored; a *missing* file falls back to built-in defaults; the daemon
refuses to start on an invalid or incomplete file.

## Default interval (shipped)

`/usr/share/afanctl/afanctl.toml.default` — byte-for-byte the same content as
the installed `/etc/afanctl/afanctl.toml`, i.e. **`interval_s = 1`**. The
built-in fallback (file missing) is documented to equal the default file, so
the built-in default is also 1 s.

## Observed interval (daemon-reported)

`afanctl status --json` (read verb, no pkexec) — the daemon reports its own
config provenance:

```json
"config": { "high_c": 66, "interval_s": 1, "max_c": 86,
            "max_rpm": 6200, "min_rpm": 1200,
            "source": "/etc/afanctl/afanctl.toml" }
```

Cross-check against the daemon's counters in `/run/afanctl/state.json`
(`afanctl.state.v1`):

```
polls        = 4989
uptime_s     = 4989   (via afanctl status --json: daemon.uptime_s = 4989)
watchdog_pings = 9977
```

`polls == uptime_s` to the second ⇒ the supervisor loop iterates **once per
second** while running. `state.json` mtime age was **1 s** at capture time
(the file is rewritten every poll). Both observations match `interval_s = 1`.

## Service unit

`/usr/lib/systemd/system/afanctl.service`: `ExecStart=/usr/bin/afanctl daemon
--mode observe`, `WatchdogSec=15`, `Restart=always`, `RuntimeDirectory=afanctl`
(hence `/run/afanctl`), `ProtectSystem=strict` with only the applesmc sysfs
path writable. No `interval` override on the command line — the unit passes no
`--config`, so the daemon reads the default `/etc/afanctl/afanctl.toml`.

## Binary-level confirmation

`strings /usr/bin/afanctl` shows the config surface:
- keys `thresholds.high`, `thresholds.max`, `curve.min_rpm`, `curve.max_rpm`,
  `poll.interval_s`, `interval_s`
- validation message `set \`interval_s\` to 1 or more seconds`
- global flag `--config <path> config TOML (default /etc/afanctl/afanctl.toml)`
- `config_source` reported in output; `AFANCTL_RUNTIME_DIR` honoured.

## Verdict

| Kind | Value | Evidence |
|---|---|---|
| configured | **1 s** | `/etc/afanctl/afanctl.toml` `[poll] interval_s = 1`; daemon reports `source` = that file |
| default | **1 s** | `/usr/share/afanctl/afanctl.toml.default` identical; missing-file fallback documented as built-in defaults |
| observed | **~1 s** | `polls == uptime_s` (4989/4989), `state.json` age 1 s at capture |

No afanctl change is required for the Advanced polling work: that work changes
how often *omafan* re-reads status, and afanctl's `status --json` already
exposes `config.interval_s` + `config.source` read-only, should the panel ever
want to display the daemon's own interval (future work).

Related: [the review](REVIEW.md),
[the plan](PLAN.md).

## T1 — work-records policy verification (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t1-policy-verification.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Ticket: [the plan](PLAN.md) T1 section
(verification-only, no code). Scope ruling per plan: omafan status refresh
in scope; afanctl hardware polling is future work, do not conflate.

## Source read

- Repo file: `AGENTS.md` in `/home/prakhar/Work/tries/2026-09-15-omafan`
  (branch `master`), `## WORK RECORDS (MANDATORY)` section, lines 65–80.
- Plan: [the plan](PLAN.md) T1 section
  (lines ~41–51).

## Exact policy text pasted (AGENTS.md lines 65–80, worktree as read)

```
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
```

## Verdict per checklist line

| # | Required string | Verdict | Evidence |
|---|---|---|---|
| 1 | Obsidian folder path `/home/prakhar/Documents/Default/Workspace/omarchy plugin development/omafan` | PASS | AGENTS.md lines 66–67, verbatim |
| 2 | `plans/`/`logs/`/`reviews/`/`done/` organization with purposes | PASS | Lines 68–70 list all four with roles (plans = phased plans and tickets; logs = implementation decisions and command evidence; reviews = findings and verification; done = completion summaries) |
| 3 | Dated filenames + relative links | PASS | Line 71: "Use dated, descriptive filenames and relative links between related notes." |
| 4 | "Never claim a check passed without evidence" | PASS | Line 73, verbatim (capital N: "Never claim a check passed without evidence.") |
| 5 | Scope line "Advanced polling control work is scoped to omafan status refresh only" | PASS | Line 78: "The Advanced polling control work is scoped to omafan status refresh only." (ticket quote is an exact substring; leading "The" present in file, matching the plan's quote) |
| 6 | afanctl future-work line | PASS | Line 79: "afanctl hardware polling control is future work; do not conflate the two." plus line 80: "If future work changes afanctl, also document it in its Obsidian project folder." |
| 7 | Match vs plan T1 section | PASS | Plan T1 (lines 41–51) accurately describes the policy: Obsidian folder, plans/logs/reviews/done, dated filenames, relative links, "never claim…" line, and the scope line. No mismatch found. |

Overall: **PASS** — all checklist items present in the worktree `AGENTS.md`.

## Worktree state note (evidence, not a T1 change)

- `git status --porcelain` at verification time showed `M AGENTS.md` plus
  untracked `linkedin_post.md`, `x_post.md`, `x_threads.md`.
- `git diff --stat` showed `AGENTS.md | 17 +++++++++++++++++`
  (1 file changed, 17 insertions); the diff is exactly the added
  `## WORK RECORDS (MANDATORY)` block quoted above.
- That edit pre-dates this T1 run (consistent with the plan's "Root policy
  already edited — this ticket verifies it"); HEAD does not contain the
  section, the worktree does. Verification was performed against the
  worktree file as the ticket instructs.

## Explicit no-change statement

**This T1 run changed no repo files, made no commits, ran no fan writes,
ran no tests, and did not run hw-smoke.** Read-only repo operations were
`read` of `AGENTS.md` and read-only `git status` / `git diff` for evidence.
The only file written was this log note itself, in the Obsidian `logs/`
folder (outside the repo), as the ticket requires.

## T2 slider Auto-reset + debounce-race fix (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t2-slider-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Plan: [T2](PLAN.md).
Ticket: implement, gate, evidence here. Phase 2 (T5) closes the phase.

## Decision summary

- **Guard mechanism: explicit `expectingAuto` flag, not a generation counter.**
  The plan allows either ("e.g."). Only one status request is ever in flight
  (`refresh()` refuses while `statusProc.running`), so responses cannot
  reorder — a boolean expectation armed at release-send and cleared only by a
  fresh auto status fully covers the stale-doc window with less surface than a
  counter. If a future change pipelines status requests, revisit to a
  generation.
- **All release paths funnel through `sendCommand`** — `applyPreset("auto")`,
  IPC `release()`, `releaseTimer` firing, `cycle()` landing on auto, and the
  bar right-click release all call it (verified: `BarWidget.applyToPanel` only
  forwards argv). So the funnel owns arming (`expectingAuto = true`),
  the debounce cancel (`sliderSend.stop()`), and recording the write kind
  (`lastWriteWasRelease`). No change was needed in `applyPreset` itself.
- **Confirmation is status-only.** `onExited` success clears nothing — an exit
  code is not a daemon state. A newer manual write supersedes the expectation
  (`expectingAuto = false` on non-release sends, placed after the
  busy/degraded/`cmdProc.running` refusals so a refused write never mutates
  it). A failed release voids the expectation but keeps the truthful prior
  `pendingRpm`; a killed (deadline) release voids it too, so the next fresh
  hold status resyncs.
- **Inactive visual = the existing null rendering.** `pendingRpm = null`
  already renders label `—` at `fanMinRpm` (Panel.qml slider bindings,
  unchanged). No new visual state was added; dimming the slider whenever null
  would also dim the normal firmware-auto look, which nobody reported broken.
- **No `Model.js` change.** Signatures stay frozen per the ticket; therefore no
  `tests/model.test.mjs` change (it still passes 167/167 untouched).
  Regression coverage is the new structural suite below — documented
  limitation: the gate has no QML runtime (`qml-lint.sh` only lints), so the
  guards are pinned by asserting the exact QML structure. If the panel logic
  is refactored, the suite fails loudly rather than silently passing.
- **DESIGN §6 check for T4:** no contradiction found — §6.2 lists
  `pendingRpm` state but never specifies post-Auto slider content, and §3
  already defines base = `fan_min_rpm` with the Floor wording. Treated as bug
  fix; no ruling proposed beyond the note below.

## Behaviour before / after

| Scenario | Before | After |
|---|---|---|
| Auto confirmed by fresh status (hold inactive) | slider kept last manual rpm | `pendingRpm = null`, debounce cancelled, knob at floor, label `—` |
| Stale hold doc lands after Auto write, before confirm | repopulated `pendingRpm` from `holdDoc.rpm` | blocked by `!expectingAuto` gate; old value lingers only until the confirming status, never resurrected after |
| Queued slider debounce fires after release sent | `["rpm", stale]` reapplied a manual hold post-release | `sliderSend.stop()` at release-send and at confirmation |
| Release write fails (nonzero exit) | (unchanged) error banner | expectation voided, prior `pendingRpm` retained, post-write refresh kept |
| Release write killed at 20 s deadline | `pendingRpm = null`, expectation left armed | same nulling (kept consistent) + expectation voided so a live hold resyncs |
| Manual write while Auto pending | — | supersedes: expectation cleared, normal hold tracking resumes |

## Files changed (uncommitted working tree; no commit made)

- `Panel.qml` — state props lines 36–46 (`expectingAuto`, `lastWriteWasRelease`);
  `sendCommand` lines 292–305 (release detect, debounce cancel, arm/supersede);
  `applyStatus` lines 393–412 (confirm-on-fresh-auto, gated hold sync);
  `cmdProc onExited` lines 533–544 (void-on-failed-release, never clear);
  `commandDeadline onTriggered` lines 555–565 (void-on-kill, nulling kept).
- `tests/panel-slider.test.sh` (new) — 26 structural assertions, harness-style.
- `tests/run-all.sh` — 7th suite wired + `--list` updated.
- `tests/AGENTS.md`, `CONTRIBUTING.md` — 6→7 suite mirrors moved together.
- `CHANGELOG.md` — Unreleased bug-fix entry.
- Untouched as required: `Model.js` signatures, presets, exit codes, keyboard
  map, `pollSeconds` logic (the `pollMode`/`effectivePollSeconds` lines in the
  dirty tree are pre-existing T3 work, not mine — my hunks do not overlap them).

## Gate outputs (2026-09-17, hardware-free, this tree)

`bash tests/run-all.sh` → exit 0:

```text
omafan test suite — 2026-09-17T02:37:21+05:30
repo: /home/prakhar/Work/tries/2026-09-15-omafan

RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS

PASS suites 7 / FAIL suites 0 / SKIP 0
```

`bash tests/qml-lint.sh` → exit 0:

```text
PASS qml-lint: 3 file(s) clean; 114 expected non-fatal warning(s) about qs.* members
```

Spot checks: `bash tests/panel-slider.test.sh` → `PASS 26 / FAIL 0`;
`node tests/model.test.mjs` → `PASS 167 / FAIL 0` (untouched);
`bash -n bin/omafan-ctl bin/omafan-keybindings` → OK.

## Constraint compliance

- No writes to `/sys /etc /usr /run/afanctl`; `tests/hw-smoke.sh` not run;
  tests isolated per repo convention.
- No commit: CONTRIBUTING branch convention (`fix/<slug>`) requires a branch
  and the tree already holds other owners' uncommitted work (T3 `pollMode`
  lines, etc.) — left everything uncommitted in the working tree.

## Note for T4 owner (coordination, not a ruling)

- CHANGELOG wording above is mine; adjust freely when you land the T3/T4
  entries — no DEVIATIONS overlap claimed (T2 is a bug fix).
- Open question: adding a 7th suite to `tests/run-all.sh` touches the suite
  list DESIGN §10 describes. I treated it as additive gate plumbing needing no
  ruling (no contract semantics changed), but confirm when you write the T3
  ruling — happy to move the suite registration under your entry if you rule
  otherwise.

## T3 Advanced polling control: implementation + live evidence (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t3-polling-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Plan: [the plan](PLAN.md) (ticket T3).
Review: [the review](REVIEW.md).
Prior read-only evidence: [afanctl polling evidence](LOG.md).
Scope: omafan's OWN status refresh only (`poll_seconds` → `Panel.qml` pollTimer).
afanctl hardware poll (`[poll] interval_s = 1 s`) is future work — untouched.

## Status: implemented, gate green. Ruling dependency noted below.

## 1. Live settings-API verification (done FIRST, before coding)

Backup: `~/.config/omarchy/shell.json` copied to `/tmp/opencode/shell.json.bak-t3`
before any write; restored afterwards and diffed clean (see §5).

### 1a. Built-in manifests prove the schema types (read-only)

- `boolean`: `/usr/share/omarchy/shell/plugins/bar/widgets/Indicators.manifest.json`
  `{"key":"alwaysShow","type":"boolean","label":"Always Show","defaultValue":false}`,
  consumed in `Indicators.qml:17` as `setting("alwaysShow", false) === true`.
- `integer` + min/max/step: `/usr/share/omarchy/shell/plugins/agents/manifest.json`
  `{"key":"refreshIntervalSec","type":"integer","min":30,"max":3600,"step":30,"defaultValue":900}`,
  consumed in `agents/Main.qml:117` as
  `Math.max(30, Number(setting("refreshIntervalSec", 900)))` — the same
  `setting(key, fallback)` pattern omafan uses.
- `enum`: agents manifest
  `{"key":"syncMode","type":"enum","options":["Off","On"],"defaultValue":"Off"}`,
  consumed in `agents/Main.qml:285` via `setting("syncMode", …)`.
- omafan's own spelling (`type: "int"` + `default`) passes
  `omarchy plugin validate` and works live (proven §1b) — the shell accepts
  both spellings. New key follows omafan's own `show`-enum convention
  (`type: "enum"` + `default`), NOT mixed with the built-ins' `defaultValue`
  spelling, so the manifest stays internally consistent. Standardising
  `int`→`integer` / `default`→`defaultValue` is left to T4 as a deliberate
  decision (it would touch all four schema entries + the DESIGN §1 block).

### 1b. `omarchy bar set` write path (live, against the running shell)

Mechanism (source-read, `/usr/bin/omarchy-bar` `cmd_set`): values are stored
as **strings** unless `--json` is given (`jq --arg` vs `--argjson`), then
written via `omarchy-shell shell setBarWidget` into the `shell.json` layout
entry. No client-side schema validation — persistence is schema-agnostic;
the manifest schema drives the settings UI + defaults.

Live transcript (backup taken first, restored after):

```
$ omarchy bar set io.github.yadav-prakhar.omafan poll_seconds 3 --json
Set poll_seconds on io.github.yadav-prakhar.omafan      (rc=0)
→ shell.json entry: {"id": "…omafan", "show": "temp", "poll_seconds": 3}   (integer)

$ omarchy bar set io.github.yadav-prakhar.omafan poll_mode custom
Set poll_mode on io.github.yadav-prakhar.omafan         (rc=0)
→ shell.json entry: {…, "poll_seconds": 3, "poll_mode": "custom"}          (string)
```

Note: `poll_mode` persisted even though it was NOT yet in the manifest —
write path needs no schema entry. Restore verified by
`diff /tmp/opencode/shell.json.bak-t3 ~/.config/omarchy/shell.json` → clean,
entry back to `{"id": "…omafan", "show": "temp"}`.

### 1c. Typing nuance for T4's docs mirror

Without `--json`, integer settings store as strings (`"5"`). `Panel.qml`
reads via `Number(...)` / `Model.finite`, so both work at runtime — but
`docs/INSTALL.md` (T4-staged) shows `omarchy bar set … poll_seconds 5`
without `--json`. Recommend T4 add `--json` to integer examples so
`shell.json` keeps clean types.

## 2. Chosen schema (enum — live evidence above, no fallback needed)

```json
{ "key": "poll_mode", "type": "enum", "label": "Refresh mode",
  "options": ["auto", "custom"], "default": "auto" }
```

- `poll_seconds` reused unchanged as the custom value (int 1–10, default 2).
- `defaults` gains `"poll_mode": "auto"`.
- `poll_seconds` label becomes `"Custom refresh interval (s)"` (was
  `"Refresh interval (s)"`) — pre-staged in the working tree with T4's
  mirrors; semantics of the key itself are unchanged.
- `omarchy plugin validate .` → rc=0 with the new schema (enum accepted).

The boolean fallback (`poll_custom`) was NOT needed: enum is proven in a
shipped manifest (agents `syncMode`) AND proven writable live (§1b).

## 3. Files changed by T3 (this ticket)

- `Model.js` — added `AUTO_POLL_SECONDS`/`MIN_POLL_SECONDS`/`MAX_POLL_SECONDS`
  + `effectivePollSeconds(mode, pollSeconds)` (ES5-safe: var/function only,
  reuses `finite()`, no imports/IO). Placed after `isStateStale`.
- `Panel.qml` — pollSeconds derivation only (old line 91/101, new lines
  ~96–101): added `pollMode` property
  (`String(root.setting("poll_mode", "auto"))`) and
  `pollSeconds: Model.effectivePollSeconds(root.pollMode,
  root.setting("poll_seconds", 2))`. pendingRpm/slider race paths (T2's)
  untouched.
- `tests/model.test.mjs` — additive `POLL_NAMES` export (same pattern as
  T02b's `GUARD_NAMES`; frozen lists/assertions undisturbed) + 18
  `effectivePollSeconds` cases.

Pre-existing in the working tree (NOT T3 — T4/T2 staged, uncommitted, T3
verified against them): `manifest.json` poll_mode entry, `DEVIATIONS.md`
R9 provisional ruling, `DESIGN.md` §1 block, `README.md` Settings table +
panel paragraph, `docs/INSTALL.md` §6, `docs/TROUBLESHOOTING.md` (§2 row +
§4 note), `docs/ARCHITECTURE.md` (§2 row + §4.1), `tests/manifest.test.sh`
(keys/defaults/poll_mode assertions), `CHANGELOG.md` Unreleased entries,
`Panel.qml` T2 slider-reset paths, `AGENTS.md` work-records policy.

## 4. Mode-math semantics (as implemented + tested)

- Mode anything-but-`"custom"` (`auto`, missing, null, unknown, wrong case)
  → exactly **2**, regardless of leftover `poll_seconds`. Existing
  `shell.json` files with nondefault `poll_seconds` keep today's behaviour
  with zero user action (default mode is `auto`).
- Mode `custom`:
  - whole seconds 1–10 → as-is (numeric strings coerce, so
    `bar set` without `--json` keeps working);
  - whole seconds <1 / >10 → clamped to 1 / 10 (never fatal; a huge value
    must not make the panel look dead);
  - fractional (`2.5`), non-numeric (`"abc"`, `""`, null, undefined) →
    ignored → **2**.
- Behaviour delta vs old derivation: fractional values used to round
  (`Math.round`); now ignored → 2. Unreachable via the schema UI (int type),
  only via hand-edited `shell.json`. `poll_seconds: 0` used to yield 2
  (falsy-`||`); now yields 1 under custom (honest clamp), 2 under auto.
- Wording: user-facing = "how often omafan re-reads daemon status".

Interpretation flag for T4: the ticket says "clamped 1–10 … (reject/ignore
fractional & out-of-band)". "Clamped" is vacuous unless it applies to
out-of-band numbers, so integers clamp while fractional/non-numeric ignore.
R9's draft says "(fractional and out-of-band values clamped, never fatal)" —
if T4 wants fractional to round-then-clamp instead, say so when formalising;
the tests pin the reject reading until then.

## 5. Gate outputs (2026-09-17, repo `/home/prakhar/Work/tries/2026-09-15-omafan`)

```
$ node tests/model.test.mjs
PASS 167 / FAIL 0
$ bash tests/manifest.test.sh
manifest: PASS 26 / FAIL 0
$ node --check Model.js → Model.js syntax OK
$ omarchy plugin validate . → rc=0 (silent)
$ bash tests/qml-lint.sh
PASS qml-lint: 3 file(s) clean; 114 expected non-fatal warning(s) about qs.* members (rc=0)
$ bash tests/run-all.sh
RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS
PASS suites 7 / FAIL suites 0 / SKIP 0
```

No fan writes, no hw-smoke (per ticket). T2's `panel-slider` suite still
passes — T3 did not disturb the pendingRpm paths.

## 6. Ruling proposal for T4 (DEVIATIONS entry — old → new → why)

- **Old:** schema keys `show` / `poll_seconds` (int 1–10 dflt 2, the only
  refresh knob) / `release_after_minutes`; `Panel.qml` consumed
  `poll_seconds` directly with round+clamp; `DESIGN.md` §5 had no polling
  function; `DESIGN.md` §1 manifest block had three keys.
- **New:** `poll_seconds` kept as the *custom* value (int 1–10 dflt 2, whole
  seconds only; label "Custom refresh interval (s)") + ONE toggle key
  `poll_mode` enum `auto|custom` dflt `auto`; `Panel.qml` derives
  `pollSeconds` via `Model.effectivePollSeconds(mode, pollSeconds)` with the
  §4 semantics; `DESIGN.md` §5 gains
  `effectivePollSeconds(mode, pollSeconds) -> int`; §1 block gains the
  `poll_mode` entry + `defaults` entry.
- **Why:** user ask (advanced toggle, auto = current default, custom = user
  seconds) + scope ruling (omafan re-read cadence only; afanctl 1 s interval
  out of scope, evidence [afanctl polling evidence](LOG.md)) + live
  proof enum persists via supported shell settings (§1b) with zero new
  plumbing. Backward compat: default `auto` = today's 2 s for everyone.
- **Ruling dependency (explicit):** the `manifest.json` change is staged
  provisional — R9 already marks it provisional pending this ticket's live
  verification, now delivered (§1b). T4 formalises R9 (final) and owns the
  docs mirrors; T3's code+tests are implemented against the provisional
  schema. Do not split the changeset (floor-chord precedent).
- **Mirrors:** `manifest.json` ✓ staged · `DESIGN.md` §1 ✓ staged ·
  `README.md` Settings table + panel paragraph ✓ staged ·
  `docs/INSTALL.md` §6 ✓ staged (needs the `--json` fix from §1c) ·
  `docs/TROUBLESHOOTING.md` ✓ staged · `docs/ARCHITECTURE.md` polling §4.1
  + §2 row ✓ staged · `tests/manifest.test.sh` ✓ staged+passing ·
  `CHANGELOG.md` Unreleased ✓ staged · `DEVIATIONS.md` R9 provisional →
  T4 to finalise.

## T4 docs/contract/changelog evidence (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t4-docs-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Ticket: T4 (plan: [the plan](PLAN.md)).
Moves with T3, never alone. **Ruling (DEVIATIONS.md R9) was written BEFORE any
mirror edit** — ruling precedes implementation per the contract rule.

## Ruling

`DEVIATIONS.md` **R9 — Advanced polling mode key (PROVISIONAL pending T3's
live verification) + T2 slider-reset clarification.** Full text lives in the
repo; the shape:

- Old schema: `show` (enum, `temp`), `poll_seconds` (int 1–10, default 2, the
  only refresh knob), `release_after_minutes` (int 0–240, default 0).
- New schema: `poll_seconds` kept as the *custom* value + one toggle key.
  Primary: `poll_mode` enum `auto|custom`, default `auto` (recommended).
  Fallback: `poll_custom` boolean, default false, if live verification
  rejects the enum. Auto ⇒ exactly 2 s; custom ⇒ `poll_seconds` clamped
  1–10 whole seconds.
- Why: user ask (advanced toggle auto=current default/custom=user seconds) +
  scope ruling (omafan re-read cadence only, afanctl `[poll] interval_s = 1 s`
  untouched — evidence [afanctl polling evidence](LOG.md)).
- Affected: T3, T4, T5. Provisional because **T3 had not finished at ruling
  time** (no `poll_mode`/`poll_custom` key anywhere in the tree), so T4 wrote
  the `poll_mode` variant into `manifest.json`; T3 must verify live via
  `omarchy bar set` and may swap the spelling (mirrors move again together).
- T2 slider part: **bug fix, not a contract change.** No `DESIGN.md §6`
  sentence prescribes the old behaviour (§6.2 lists `pendingRpm` without reset
  semantics; repopulation lives only in `Panel.qml applyStatus` lines 366–368).
  Proposed additive §6.2 wording recorded in R9 for T2's changeset (NOT applied
  by T4).

Variant evidence: [the review](REVIEW.md).

## Mirrors updated (same changeset)

| File | Lines | Change |
|---|---|---|
| `DEVIATIONS.md` | R9 block (~+53) | ruling entry, next number R9, D-format |
| `manifest.json` | 18, 21–22 | + `poll_mode` default/schema; `poll_seconds` label → "Custom refresh interval (s)" |
| `DESIGN.md` §1 | 50, 53–54 | manifest block byte-matches `manifest.json` |
| `tests/manifest.test.sh` | 64–67 | keys `show,poll_mode,poll_seconds,release_after_minutes`; defaults; new `poll_mode` enum:options:default assertion; `poll_seconds` bounds unchanged |
| `README.md` | 120–124, 153–164 | panel paragraph + Settings table (4 keys, auto=2s/custom note, SMC-scope sentence) |
| `docs/INSTALL.md` | 170–188 | §6 settings: `poll_mode custom` example, 4-key table, SMC-scope sentence |
| `docs/TROUBLESHOOTING.md` | 46, 113–119 | §2 frozen-bar row + §4 note rewritten to `poll_mode`/`poll_seconds`, SMC-scope sentence |
| `docs/ARCHITECTURE.md` | 69, 114–121 | §2 responsibility row key list + §4.1 auto/custom semantics, SMC-scope sentence |
| `CHANGELOG.md` | Unreleased Fixed/Added | T2 slider-reset fix line + T3 `poll_mode` feature line (marked provisional) |

Mirror-agreement check: `grep poll_mode|poll_custom` over the repo — all hits
agree (enum `auto|custom` default `auto`; `poll_seconds` 1–10 default 2,
custom-only). No stale "poll_seconds is the only knob" language left in live
docs (remaining hits are the historical DEVIATIONS wording and the new
custom-only table cells). `Panel.qml` intentionally untouched.

## Gates (this changeset)

```
bash tests/manifest.test.sh
manifest: PASS 26 / FAIL 0

omarchy plugin validate .
exit=0   (silent success)

bash tests/run-all.sh  (full gate)
RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
PASS suites 6 / FAIL suites 0 / SKIP 0
```

## Coordination notes (T2/T3 owners)

- T4 did NOT edit `Panel.qml` (no poll/slider logic) — T2 owns the slider
  reset + race guard (`pendingRpm`, `applyStatus`), T3 owns the `pollSeconds`
  mode math + live `omarchy bar set` verification.
- Known interim state: the manifest advertises `poll_mode` before the panel
  consumes it (`Panel.qml:91` still reads `poll_seconds` only). This is
  expected — T3 + T4 land together; do not "fix" one side alone.
- **Observed during T4's session: T2 owner is concurrently editing `Panel.qml`**
  (`expectingAuto` / `lastWriteWasRelease` — release-expectation + stale-doc
  guard in `sendCommand`/`applyStatus`/write-failure path). T4 made zero edits
  to `Panel.qml`; files are disjoint, no merge action needed from T4's side.
- If T3's live check rejects the enum spelling, T3 swaps to `poll_custom`
  boolean and T4's mirrors (table above) move again in that same changeset.
- Pre-existing worktree modification to root `AGENTS.md` was left untouched
  (not T4's file). No branches/commit by T4 (orchestrator commits).

## Safety

No fan writes, no hw-smoke, no live IPC. Only docs/manifest/tests/changelog
touched. `git status` shows only the nine files above (plus the pre-existing
`AGENTS.md` modification and untracked marketing drafts).

## T5 tests + QA gate evidence (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-t5-gate-evidence.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Plan: [the plan](PLAN.md) (T5 closes the phase).
Depends on T2 (slider race) + T3 (polling mode) + T4 (docs). Scope ruling (omafan
refresh only, afanctl `interval_s` out of scope): [afanctl polling evidence](LOG.md),
settings recommendations: [the review](REVIEW.md).

## T2/T3/T4 completion status at T5 time

T5 started against a clean pre-T2 tree (manifest still 3 keys, `Panel.qml`
without the Auto guard), ran the 6-suite baseline green, and then observed
concurrent workers landing T2/T3/T4 in the working tree while verification was
in progress. Final tree state (uncommitted, `git status` at evidence time):

```
 M AGENTS.md, CHANGELOG.md, CONTRIBUTING.md, DESIGN.md, DEVIATIONS.md,
 M Model.js, Panel.qml, README.md, docs/ARCHITECTURE.md, docs/INSTALL.md,
 M docs/TROUBLESHOOTING.md, manifest.json, tests/AGENTS.md,
 M tests/manifest.test.sh, tests/model.test.mjs, tests/run-all.sh
?? tests/panel-slider.test.sh (+ linkedin_post/x_post/x_threads, unrelated)
```

What each ticket delivered (verified by reading the diffs, not by self-report):

- **T2 (slider Auto-reset):** `Panel.qml` gained `expectingAuto` /
  `lastWriteWasRelease`; `sendCommand` arms the Auto expectation on
  `release` / `preset auto` and cancels the 300 ms debounce; `applyStatus`
  clears `pendingRpm` only on a fresh status with `hold.active == false`;
  `onExited` / `commandDeadline` void the expectation on failure. No
  `Model.js` signature changes. Bug fix, not a contract change (ruling R9).
- **T3 (Advanced polling):** `manifest.json` + `DESIGN.md §1` gained
  `poll_mode` (`enum auto|custom`, default `auto`); `poll_seconds` kept as the
  custom value (relabeled "Custom refresh interval (s)"). `Model.js` gained the
  pure ES5 function `effectivePollSeconds(mode, pollSeconds)` (+
  `AUTO_POLL_SECONDS`/`MIN_POLL_SECONDS`/`MAX_POLL_SECONDS`); `Panel.qml`
  consumes it (`pollMode` from `setting("poll_mode","auto")`). Auto ⇒ exactly
  2 s regardless of leftover `poll_seconds`; custom ⇒ whole seconds 1–10
  (fractional/non-numeric ignored → 2; out-of-band clamped, never fatal).
- **T4 (docs/contract/changelog):** provisional ruling R9 in `DEVIATIONS.md`
  (uncommitted); `DESIGN.md §1` block == `manifest.json` byte-for-byte in
  parsed JSON (verified below); mirrors moved together (`README.md` Settings
  table + panel paragraph, `docs/INSTALL.md` §6, `docs/TROUBLESHOOTING.md`,
  `docs/ARCHITECTURE.md` §2/§4.1, `CHANGELOG.md` Unreleased with both the
  slider fix and the polling addition).
- **T5-owned test work landed by concurrent workers and verified here:**
  `tests/manifest.test.sh` asserts the 4-key schema + `poll_mode`
  `enum:auto+custom:auto`; `tests/model.test.mjs` gained 18
  `effectivePollSeconds` assertions (+1 export check); new 7th gate suite
  `tests/panel-slider.test.sh` (26 structural assertions pinning the T2
  guards); `tests/run-all.sh --list` + `CONTRIBUTING.md` + `tests/AGENTS.md`
  updated 6 → 7 suites. T5's own contribution this session: tree verification,
  the full gate + per-suite evidence below, hermeticity audit, DESIGN-sync
  check, read-only live verify, and the `done/` summary. No product-code edits
  by T5; no commits (orchestrator owns commits).

DESIGN-sync check (parsed-JSON equality, run in tree):

```
DESIGN-block == manifest.json: True
schema keys: ['show', 'poll_mode', 'poll_seconds', 'release_after_minutes']
defaults: {'show': 'temp', 'poll_mode': 'auto', 'poll_seconds': 2, 'release_after_minutes': 0}
```

## Mandatory gate — FULL outputs (2026-09-17, IST)

`bash tests/run-all.sh` (EXIT:0):

```
omafan test suite — 2026-09-17T02:39:22+05:30
repo: /home/prakhar/Work/tries/2026-09-15-omafan

RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS

PASS suites 7 / FAIL suites 0 / SKIP 0
```

Per-suite counts (each run individually, all EXIT:0):

```
plugin-validate : --- omarchy plugin validate /home/prakhar/Work/tries/2026-09-15-omafan ---
                  --- plugin-validate: OK ---
                  PASS plugin-validate
manifest        : manifest: PASS 26 / FAIL 0            (was 25 pre-phase)
model           : PASS 167 / FAIL 0                     (was 148 pre-phase; +18 mode-math eq, +1 export check)
ctl             : PASS 239 / FAIL 0                     (unchanged)
keybindings     : PASS 71 / FAIL 0                      (unchanged)
qml-lint        : PASS qml-lint: 3 file(s) clean; 114 expected non-fatal warning(s) about qs.* members
panel-slider    : PASS 26 / FAIL 0                      (new T2 regression suite)
```

`bash tests/qml-lint.sh` (EXIT:0):

```
PASS qml-lint: 3 file(s) clean; 114 expected non-fatal warning(s) about qs.* members
```

`bash -n bin/omafan-ctl bin/omafan-keybindings` → silent, EXIT:0.
`bash -n tests/panel-slider.test.sh` → OK.
`omarchy plugin validate .` → silent, EXIT:0.

`tests/hw-smoke.sh` was NOT run (writes the fan; machine was hot at 78–90 °C
during this session — see live-verify below). No operator request for it.

## Hermeticity audit (T5 constraint)

- `tests/panel-slider.test.sh` reads only `Panel.qml` + `Model.js` via grep/awk;
  no `HOME`, `/run`, `/sys`, `/etc`, network, `pkexec`, `afanctl`, or `hyprctl`
  references (the single grep hit for `/usr` is the `#!/usr/bin/env bash`
  shebang). `bash -n` clean; ends via harness `summarize`.
- `Model.js` addition is ES5-only (`var`/`function`, `Math.floor`); the model's
  own purity suite (no `=>`, no backticks, no `Object.assign`, no
  `require`/`import`, no Qt sniffing, trailing newline) passes as part of the
  167 assertions.
- Per-case isolation unchanged: ctl/keybindings suites still use fresh tempdir,
  redirected `XDG_RUNTIME_DIR`, sandboxed `HOME`, stub `hyprctl`.

## Live verify (skills/live-verify-in-the-shell) — read-only subset

Machine state during verify: **hot** — `bin/omafan-ctl status --human` read
`t_eff 90.0 °C, fan 5574 rpm`; `omarchy-shell omafan state` read daemon
`observe`, `t_eff_c 78.0`, `fan.rpm 5629`, `hold.active false`. No fan writes
were performed (no `preset`/`rpm`/`release`/`cycle` calls, no hw-smoke).

VERIFIED (read-only, with output):

- `omarchy plugin list --json` lists `io.github.yadav-prakhar.omafan` with
  `enabled:true`.
- `omarchy-shell omafan state` returns `schema omafan.status.v1`, `ok:true`,
  `daemon.running:true`, `state_stale:false` (full document captured at
  verify time; `presets` ladder 1200/2700/4200/5700/7200 over band 1200..7200).
- `bin/omafan-ctl status --human` reads daemon mode/rpm/t_eff/band without pkexec.
- `omarchy-shell shell ping` → `ok`.
- `qs log -p /usr/share/omarchy/shell --tail 300 | grep -iE omafan` → no lines
  (no omafan errors in the recent shell log).
- `omarchy bar set` usage exists (`omarchy bar set <id> <key> <value>`); user
  `shell.json` carries **no** `poll_seconds`/`poll_mode` overrides (defaults apply).

NOT VERIFIED (explicitly unverified, with reason):

- `bar set poll_mode ...` persistence + shell-restart survival + Auto=2s /
  custom 1–10 behaviour: the **installed** plugin copy at
  `~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/` still carries
  the OLD 3-key manifest (no `poll_mode`), so a live-settings check now would
  exercise the old build, not this tree. Live-installing the worktree
  (`orchestration/live-install.sh install` + rescan/restart) while concurrent
  workers are still editing it, on a hot machine, was judged unsafe — left for
  the orchestrator as the ship-step, with the exact commands in the plan's exit
  criteria. The hermetic half of this (shell accepts the schema shape) is
  covered by `plugin-validate` + `manifest.test.sh`.
- Slider Auto-reset visual + settings-UI screenshots (screenshots skill): the
  settings UI for the new controls renders only after live-install; `preset
  auto` visual confirmation would require a fan write on a hot machine — not
  attempted. The T2 race itself is covered in-gate by `panel-slider.test.sh`
  (26 assertions).
- `tests/hw-smoke.sh` / `integration-shell.sh`: opt-in only, never in the gate.

## Residual risks for the done summary

1. Tree was moving under T5 (three observed concurrent landings); the evidence
   above is pinned to the 02:39 IST gate run — re-run `tests/run-all.sh` before
   any ship commit.
2. R9 is still PROVISIONAL and uncommitted; T3's enum-vs-boolean fallback
   (`poll_custom`) is decided only by the pending live settings-UI check.
3. `panel-slider.test.sh` is structural (no QML runtime in the gate): a panel
   refactor fails it loudly by design — assertions must move with the code.
4. `effectivePollSeconds` rejects fractional input to 2 (ignore) rather than
   rounding — matches the plan ("whole seconds only (reject/ignore
   fractional…)"), but the word "clamped" in ARCHITECTURE §4.1 could mislead;
   worth one clarifying sentence if docs are touched again.
