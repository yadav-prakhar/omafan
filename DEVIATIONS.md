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

- **R13 — `dev` is the integration branch; a release is a curated sync, never a
  merge (supersedes R11's *mechanism*, keeps its guarantee; issue #2,
  2026-09-21).** Old: the shipped branch was also the default branch, so work
  landed on `master` first and `dev` caught up one-way afterwards
  (`git checkout dev && git merge --ff-only master`). R11 and R12 kept
  development material off `master` by a prohibition — *never merge `dev` into
  the default branch* — enforced by `.githooks/pre-commit`, whose comments and
  message spoke of "the default branch". New: **`dev` is the integration branch
  and GitHub's default branch.** Feature branches `<type>/<slug>` cut from `dev`
  and merge into `dev`, which carries everything: runtime, operator docs and
  development material. `master` stays the shipped branch and is never merged
  into; it is updated only by a **curated sync** —
  `skills/publish-a-release/sync-master.sh` copies the shipped path allowlist
  from `dev` into a throwaway worktree on `master`, prunes every denylisted path
  the allowlist swept up, **refuses to write if any denylisted path survives**,
  prints the diff for review, and only with `--commit` writes it as one commit
  and (with `--tag`) tags it. Running it twice changes nothing. The two lists
  have one home, `tests/lib/shipped-paths.sh`, read by four consumers — the sync
  script, the pre-commit hook, the gate suite and CI — so there is no mirror to
  chase. The allowlist (`master` carries exactly): `BarWidget.qml`, `Panel.qml`,
  `Model.js`, `KeyboardHelp.qml`, `manifest.json`, `bin/`, `tests/`, `docs/`,
  `preview.png`, `README.md`, `PRD.md`, `DESIGN.md`, `DEVIATIONS.md`,
  `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `.github/`. The
  denylist (never on `master`): `AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md`,
  `orchestration/AGENTS.md`, `worknotes/`, `orchestration/`, `skills/`,
  `.githooks/`, `PLAN.md`, `QUESTIONS.md`, `.recon/` — plus two entries issue #2
  does not list, added here with their reason: `docs/agents/`, the agent
  instruction files that arrived inside `docs/` after R12 ruled that tree "100%
  shipped" (same class as `bin/AGENTS.md`, and inside an allowlisted directory),
  and `.omc/`, agent operational state, gitignored and denied at any depth as
  well so a force-added copy cannot ride along. Three denylist entries sit
  *inside* allowlisted directories, which is why the denylist is a filter applied
  after the copy and not merely the complement of the allowlist; any `AGENTS.md`
  at any depth matches, so the next one is caught before it ships rather than
  after someone updates the list. **`.githooks/pre-commit` now keys on the
  literal branch name `master`**, not on "the default branch": the default branch
  is now `dev`, the branch that carries this material on purpose, so a guard
  keyed on the default would refuse every normal commit — the single most likely
  way to get this change wrong. It checks the branch *before* it requires the
  lists, so a branch that predates them is never blocked, and fails closed only
  on `master`. Its install instruction changed with it: a **copy** into
  `.git/hooks/pre-commit`, because `git config core.hooksPath .githooks` — what
  R12 documented — goes inert exactly where it matters. `.githooks/` is denied on
  `master`, so checking `master` out removes the directory and git finds no hook
  to run; `.git/` belongs to no branch. Verified in a scratch clone: on `master`
  a staged `AGENTS.md` is refused, a shipped-only change commits, and a deleted
  list file refuses rather than guesses; on `dev` and on a feature branch the
  same staged development paths commit normally. Why: the guarantee R11 exists to protect is
  unchanged and is *not* tidiness — `omarchy plugin add` clones the whole
  repository into a user's `~/.config/omarchy/plugins/<id>`, so a root
  `AGENTS.md` on the shipped branch is content a stranger's coding agent can
  discover and act on inside their own installation, a prompt-injection surface.
  R11's *mechanism* had to go anyway: with `master` as the default branch there
  was nowhere to integrate work before it shipped, every feature branch started
  from the shipped tree, and the epic (#1) needs a branch that can hold
  unreleased contract changes. A plain `git merge dev` at release would ship
  `worknotes/`, `orchestration/`, `skills/`, `PLAN.md`, `QUESTIONS.md` and every
  `AGENTS.md` into every user's install; the sync's refusal and the new gate
  suite are the two places that now make that impossible rather than merely
  forbidden. Affected: `DESIGN.md §10` (nine gate suites), `AGENTS.md` (header,
  STRUCTURE, COMMANDS), `CONTRIBUTING.md` (branch naming, commit rules, the
  development-material section, a new release section, and an explicit statement
  that the sibling repo `afanctl` has **no** equivalent constraint — nothing
  clones it into a user's config, so there `dev` → `master` at release is an
  ordinary merge), `docs/PUBLISHING.md` (a new §2 release flow),
  `docs/TESTING.md` (the gate table), `README.md` and `tests/AGENTS.md` and
  `skills/run-the-gates` (suite count), `skills/README.md`,
  `skills/publish-a-release/SKILL.md` + the new `sync-master.sh`,
  `.githooks/pre-commit`, `.gitignore` (`.omc/`), `CHANGELOG.md` Unreleased, and
  the new `tests/lib/shipped-paths.sh`, `tests/branch-model.test.sh`,
  `tests/run-all.sh` 9th-suite line and `.github/workflows/ci.yml` — the
  repository's first CI workflow, which exists so the denylist is asserted
  somewhere a local hook cannot be skipped (the CI half of #8). Ruling: accepted
  — no runtime file, no privilege surface, no manifest change. The new gate suite
  is the one test allowed to assert a repository property rather than plugin
  behaviour, because a shipped branch carrying agent instructions **is** a broken
  plugin, not a stale note: it reads the tree of `master` (or
  `origin/master`), names every offender, and reports a visible `SKIPPED` line
  when no such ref exists in the clone rather than passing quietly — CI fetches
  the ref and asserts the `checked` line, so the skip cannot hide there.
  Deliberately not done here: making the CI gate a required status check, and
  running the two suites that need external tooling (`plugin-validate` needs
  `omarchy`, `qml-lint` needs `qmllint`) — the workflow names both as not run,
  with the reason, in its job summary, and #8 owns closing that.

- **R12 — work records live in the repository; `docs/` is shipped surface only
  (operator direction, 2026-09-20).** Old: the root `AGENTS.md` WORK RECORDS
  block told every agent to record all work in the maintainer's Obsidian vault at
  an absolute path outside the repository (`plans/`, `logs/`, `reviews/`,
  `done/`), and one piece of development material — the build audit trail
  `docs/BUILD-LOG.md` — sat inside the `docs/` tree that ships to the default
  branch. New: a top-level `worknotes/` tree on `dev`, one folder per piece of
  work named `<YYYY-MM-DD>-<slug>` holding fixed files (`PLAN.md` before the work,
  `LOG.md` while it happens, `REVIEW.md` for findings, `SUMMARY.md` at the end,
  `ASK.md` when the ask is a note), plus a repo-wide `INDEX.md` and the roadmap in
  `BACKLOG.md`, every file carrying `status: planned|active|blocked|done|unverified`
  frontmatter; the audit trail moved to `orchestration/BUILD-LOG.md`, leaving the
  `docs/` tree 100% shipped; the vault was retired for this repository, its 19
  omafan notes migrated with their content unedited and nothing left behind as a
  pointer; and `.githooks/pre-commit` refuses a commit on the default branch that
  touches any development-only path — there is no CI, so a local hook is the only
  mechanical guard available. Why: operator direction ("any work done should be
  notes within the repository … nothing irrelevant for deployment/end user should
  go there") + the R11 hazard that a clone carries development material into a
  stranger's installation + the failure mode of a record outside version control:
  it cannot be reviewed, diffed, bisected or cited from a commit. R11's
  affected-file list still names `docs/BUILD-LOG.md` because that was its path at
  that ruling. Affected: `AGENTS.md` (header, STRUCTURE, WHERE TO LOOK, WORK
  RECORDS), `CONTRIBUTING.md`, `README.md`, `PRD.md` (D5 + the reference list),
  `docs/ARCHITECTURE.md` §6, `CHANGELOG.md` Unreleased, `skills/README.md`,
  `skills/run-the-gates`, `skills/change-a-frozen-contract`,
  `skills/publish-a-release`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `orchestration/AGENTS.md`, and the new `worknotes/` + `.githooks/` trees.
  Migration mapping and its verification: `worknotes/2026-09-20-in-repo-worknotes/LOG.md`.
  Ruling: accepted — no runtime file, no privilege surface, no manifest change,
  and the hardware-free gate is deliberately untouched: `tests/` asserts nothing
  about `worknotes/`, because a red suite must mean the plugin is broken, not that
  a note is stale.

- **R11 — the distributed tree is the runtime plus documentation (marketplace
  review, 2026-09-17).** Old: the repository cloned and installed by users carried
  development material — root `AGENTS.md` (whose WORK RECORDS block told agents to
  write into the maintainer's Obsidian vault, outside the plugin), per-directory
  notes `bin/AGENTS.md` and `tests/AGENTS.md`, `skills/`, the build record
  (`PLAN.md`, `QUESTIONS.md`, `docs/BUILD-LOG.md`, `orchestration/`) and
  `DESIGN.md §9`, a conventions block written as a paste-verbatim subagent
  briefing that named the maintainer's absolute repo path. New: that material
  lives on the `dev` branch; the default branch ships the plugin, its tests and
  the operator documentation only. Why: `omarchy plugin add` clones the whole
  repository into `~/.config/omarchy/plugins/<id>`, so a root agent instruction
  file is content a stranger's coding agent can discover and act on inside their
  own installation. Affected: `AGENTS.md` (root, `bin/`, `tests/`), `skills/`,
  `PLAN.md`, `QUESTIONS.md`, `docs/BUILD-LOG.md`, `orchestration/`, `DESIGN.md`
  (header, §2 note, §7 provenance line, §9 retired), `PRD.md` (reader line, D5),
  `README.md`, `CONTRIBUTING.md` (setup, branch slugs, mirror chase, commit rules),
  `.github/PULL_REQUEST_TEMPLATE.md`, `docs/ARCHITECTURE.md`, `docs/SAFETY.md`,
  `docs/PUBLISHING.md`. Folded into the same ruling: `DESIGN.md §10`'s suite list
  caught up with the gate (eight suites, `run-all.sh` records every suite and
  exits non-zero if any failed), `README.md`'s stale "6 suites" line was
  corrected, the coding conventions that only lived in §9 (dependencies, error
  model, style) moved into `CONTRIBUTING.md`, and the sibling-project paths in
  `docs/SAFETY.md` and `PRD.md` now cite the public afanctl repository instead of
  the maintainer's local checkout. Ruling: accepted — no runtime file, no
  privilege surface, no manifest change; the hardware-free gate is unaffected.

- **R10 — In-panel refresh control (T5, 2026-09-17).** Old behaviour
  (`DESIGN.md §6.2`, `Panel.qml`): `poll_mode`/`poll_seconds` could only be
  changed outside the panel — the shell's bar-settings UI,
  `omarchy bar set`, or a hand-edited `shell.json` — and the panel content was
  exactly hero, banners, presets, slider, footer. New behaviour: the panel
  gains a mouse-only REFRESH row — `Auto`/`Custom` chips writing `poll_mode`
  and, in custom mode, a `−`/`+` stepper writing `poll_seconds` (`--json`, so
  the integer stays typed) in whole seconds 1–10 clamped through
  `Model.effectivePollSeconds`. The write goes through the shell's own
  `omarchy bar set` IPC path (source-read: `PluginRegistry.setBarWidget`
  mutates the config and `Bar.applySettingsDelta` patches the running widgets
  in place, no reload; `BarWidget.onSettingsChanged` re-injects settings into
  the panel, so `pollSeconds` re-evaluates live). Why: user ask ("i want the
  poll interval control in a way that it can be set from panel in the ui") —
  the T3 control existed only as a settings key, invisible unless the user
  opened the bar layout editor. Scope guards: the row is fan-neutral (its
  writes are allowed while the daemon is degraded/offline — that is exactly
  when a slower or faster re-read cadence matters), runs on a dedicated
  Process (`settingsProc`) with its own 20 s deadline and its own error line
  (`settingsError`), never takes the fan-write lock (`busy`), never pkexecs,
  and deliberately stays OUTSIDE the two-section keyboard cursor model —
  §6.2's frozen `visibleSections = ["presets","slider"]` is unchanged and the
  keyboard map (§6.3) gains no keys. Affected: `Panel.qml` (state, two
  functions, Process + deadline, REFRESH row, `RefreshChip` component),
  `DESIGN.md §6.2` (this paragraph), `tests/panel-refresh.test.sh` (new,
  structural — same pattern as `panel-slider.test.sh`), `tests/run-all.sh`
  (8th suite) + the suite-count mirrors (`CONTRIBUTING.md`, `tests/AGENTS.md`,
  root `AGENTS.md`), `README.md`, `docs/INSTALL.md` §6,
  `docs/TROUBLESHOOTING.md` §4, `docs/ARCHITECTURE.md` (§2 row + §4.1),
  `CHANGELOG.md` Unreleased. No `manifest.json` change: the schema keys
  already exist from R9; the panel now also writes them.
- **R9 — Advanced polling mode key (PROVISIONAL pending T3's live verification,
  2026-09-17) + T2 slider-reset clarification.** Old schema (`DESIGN.md §1`,
  `manifest.json`): three keys — `show` (enum, default `temp`), `poll_seconds`
  (int 1–10, default 2, the only refresh knob), `release_after_minutes` (int
  0–240, default 0); `Panel.qml` consumed `poll_seconds` directly with a 1–10
  clamp. New schema: `poll_seconds` is kept unchanged as the *custom* value
  (int 1–10, default 2, whole seconds only) **plus one toggle key** —
  primary variant `{ "key": "poll_mode", "type": "enum", "label": "Refresh
  mode", "options": ["auto", "custom"], "default": "auto" }` (recommended:
  the two states are visible and self-describing); fallback variant
  `{ "key": "poll_custom", "type": "boolean", "default": false }` if live
  verification rejects the enum. Semantics (either spelling): mode `auto`
  (default) ⇒ `pollSeconds` is exactly 2 s regardless of any leftover
  `poll_seconds` value, so existing users keep today's behaviour without
  touching anything; mode `custom` ⇒ `poll_seconds` clamped to whole seconds
  1–10 (fractional and out-of-band values clamped, never fatal). Why: user
  ask ("advanced toggle auto=current default/custom=user seconds", plan
  `2026-09-17-advanced-polling-slider-plan.md` T3) + scope ruling (the
  Advanced control governs how often **omafan re-reads the daemon's status**,
  never how often the daemon samples the SMC — afanctl's `[poll]
  interval_s = 1 s` is out of scope future work, evidence
  `logs/2026-09-17-afanctl-polling-evidence.md`) + review evidence that the
  shell's schema supports both spellings (built-in `boolean`/`enum` types)
  while `poll_seconds` persistence via `shell.json` already works, so the
  toggle is an addition on a working setting, not new plumbing. Affected:
  T3 (implements `Panel.qml` mode math + live `omarchy bar set` verification),
  T4 (this ruling + every mirror below, same changeset), T5 (extends
  `tests/manifest.test.sh` + mode-math regression). Ruling: **provisional** —
  T3 has not finished (no `poll_mode`/`poll_custom` key exists in the tree at
  ruling time), so T4 writes the `poll_mode` enum variant into `manifest.json`
  now and T3 must verify it live against the running shell before T5 closes;
  if the shell's settings UI rejects the enum spelling, T3 swaps to the
  `poll_custom` boolean variant and T4's mirrors move again in that same
  changeset — never half-updated (the floor-chord gate failure is the warning
  precedent). T4 does not edit `Panel.qml` poll/slider logic; the manifest
  advertises `poll_mode` before the panel consumes it, and the two land
  together. Mirrors moved with this ruling: `manifest.json`, `DESIGN.md §1`
  block, `README.md` Settings table + panel paragraph, `docs/INSTALL.md` §6,
  `docs/TROUBLESHOOTING.md` (§2 row + §4 frozen-temperature note),
  `docs/ARCHITECTURE.md` (§2 responsibility row + §4.1), `tests/manifest.test.sh`
  (keys, defaults, `poll_mode` options/default assertions; `poll_seconds`
  bounds unchanged), `CHANGELOG.md` Unreleased. — T2 slider part (same
  ruling, **bug fix, not a contract change**): a confirmed Auto must clear
  `pendingRpm` (slider falls back to the band minimum, inactive) and a stale
  hold document arriving after the Auto write must not repopulate it; no
  `DESIGN.md §6` sentence prescribes the old behaviour (§6.2 lists
  `pendingRpm` in state without reset semantics; the repopulation lives only
  in `Panel.qml applyStatus`), so nothing in §6 contradicts the fix.
  Proposed additive §6.2 wording for T2's changeset (not applied by T4):
  *"`pendingRpm` is cleared to null on a confirmed Auto/release write, and a
  status document is never allowed to repopulate it once cleared — the slider
  then renders the band minimum until the user acts."* Affected: T2, T4
  (changelog line), T5 (race regression).
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
