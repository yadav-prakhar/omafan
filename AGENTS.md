# PROJECT KNOWLEDGE BASE — `dev` branch

> **`dev` is the integration branch and the default branch; `master` is the
> shipped plugin.** Feature branches `<type>/<slug>` cut from `dev` and merge
> into `dev`, which carries everything: runtime, operator docs and development
> material. Work lands here, never on `master`.
>
> **`master` is never merged into.** `omarchy plugin add` clones the whole
> repository into a user's `~/.config/omarchy/plugins/<id>`, so a root
> `AGENTS.md` on the shipped branch is content a stranger's coding agent can
> discover and act on inside their own installation — a prompt-injection surface,
> not untidiness. A release is therefore a **curated sync**: only the shipped
> path allowlist is copied from `dev` onto `master`, as one commit, then tagged.
>
> ```sh
> skills/publish-a-release/sync-master.sh --from dev            # review the diff
> skills/publish-a-release/sync-master.sh --from dev --commit    # then write it
> ```
>
> Everything that exists *only* here — this file, `bin/AGENTS.md`,
> `tests/AGENTS.md`, `docs/agents/`, `skills/`, `worknotes/`, `PLAN.md`,
> `QUESTIONS.md`, `orchestration/`, `.githooks/` — is development material and is
> denied on `master`. Both lists live in one place, `tests/lib/shipped-paths.sh`,
> read by the sync script, the two git hooks, the `branch-model` gate suite and
> CI.
>
> **The guarantee is the gate suite and CI, not the hooks.** `tests/branch-model.test.sh`
> reads the tree of `master` and names every offender, and
> `.github/workflows/ci.yml` runs it where it cannot be skipped. The hooks catch
> the mistake earlier and locally, and they are genuinely partial: a
> fast-forward merge creates no commit so **no hook runs at all**, `--no-verify`
> skips them, a copy in `.git/hooks/` goes stale, and a fresh clone has none
> until someone installs them. Install both, as copies — `.githooks/` is denied
> on `master`, so checking `master` out removes the directory and
> `core.hooksPath` then finds nothing, while `.git/` belongs to no branch:
>
> ```sh
> for h in pre-commit pre-merge-commit guard.sh; do
>     cp .githooks/$h .git/hooks/$h && chmod +x .git/hooks/$h
> done
> ```
>
> `pre-merge-commit` is not optional: git never runs `pre-commit` for a merge
> commit, so without it `git merge dev` onto `master` succeeds and lands every
> denylisted path.
>
> Rulings: R11 (the guarantee), R12, R13 (this mechanism) in `DEVIATIONS.md`.
> The conventions block `DESIGN.md §9` used to carry is retired with the rest;
> its technical rules now live in `CONTRIBUTING.md` §"Code conventions".

**Generated:** 2026-09-16
**Revalidated:** 2026-09-20 against the tree at commit `57d5f63`, plus the
in-repo work-records migration ([`worknotes/2026-09-20-in-repo-worknotes/`](worknotes/2026-09-20-in-repo-worknotes/PLAN.md))
**Commit:** 57d5f63
**Branch:** dev

## OVERVIEW
omafan: Omarchy shell plugin (Quickshell, Omarchy 4.0.0.alpha) — fan control
for pre-T2 Intel Macs (`applesmc`). Control surface over the installed afanctl
daemon; never touches `/sys` itself.

## STRUCTURE
```
./
├── BarWidget.qml      # bar entry (thin; no I/O)
├── Panel.qml          # panel UI; owns ALL QML side effects
├── Model.js           # pure logic (shared QML + tests)
├── KeyboardHelp.qml   # passive keymap overlay
├── manifest.json      # plugin manifest (entry + settings schema)
├── bin/               # omafan-ctl (sole afanctl interface) + keybindings installer
├── tests/             # hardware-free gate (bash harness + fixtures)
├── docs/              # operator docs (ARCHITECTURE, SAFETY, TESTING, ...) + docs/images/
│   └── agents/        # dev-only: issue tracker, triage labels, domain layout
├── skills/            # task-shaped procedures for agents (run-the-gates, live-verify-*)
├── worknotes/         # the development record: one folder per piece of work
├── .githooks/         # pre-commit + pre-merge-commit guards (+ shared guard.sh)
├── .github/           # PR template + issue templates + workflows/ci.yml (the gate)
├── orchestration/     # build-era record: tickets, ledger, reviews, BUILD-LOG.md
├── DESIGN.md          # FROZEN contract; changes need DEVIATIONS.md ruling
├── CONTRIBUTING.md    # branch naming, commit conventions, gates, PR flow
├── SECURITY.md        # threat surface, reporting, supported versions
├── CHANGELOG.md       # Keep a Changelog; Unreleased section while working
└── .recon/            # gitignored recon evidence (ignore)
```

Generated artifacts worth knowing: `preview.png` (README hero, real capture of
the current build) and `docs/images/*` (bar widget, `?` overlay).

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Bar/panel UI | `BarWidget.qml`, `Panel.qml` | Panel polls via `omafan-ctl status --json`, re-reads after every write |
| Pure logic | `Model.js` | preset ladder, `parseStatus`, undercooling guard |
| CLI verbs/exit codes | `bin/omafan-ctl` | reads never pkexec; writes via `pkexec afanctl hold\|observe` |
| Global chords | `bin/omafan-keybindings` | managed block in `~/.config/hypr/bindings.lua` |
| Test gate | `tests/run-all.sh` | 9 suites; all hardware-free |
| Data flow/failure modes | `docs/ARCHITECTURE.md` | daemon-first diagram |
| Contract | `DESIGN.md` + `DEVIATIONS.md` | 14 deviation rulings (R1–R14) |
| How to contribute | `CONTRIBUTING.md` | branches `<type>/<slug>` off `dev`, Conventional Commits with a scope |
| Branch model / release | `tests/lib/shipped-paths.sh`, `skills/publish-a-release/` | the shipped/denied path lists and the curated sync (R13) |
| Task procedures for agents | `skills/<name>/SKILL.md` | gates, live verify, frozen-contract change, screenshots, release |
| Development record | `worknotes/INDEX.md` | one folder per piece of work; inside: `PLAN.md`, `LOG.md`, `REVIEW.md`, `SUMMARY.md` |
| The build record | `orchestration/` | frozen: tickets, `LEDGER.md`, `BUILD-LOG.md`, reviews, dispatch tools |

## CODE MAP
No LSP/codegraph coverage for QML+bash (centrality unmeasured; from reads).

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `BarWidget` | QML entry | `BarWidget.qml` | label + gestures; reads `panelItem.status`, zero I/O |
| `Panel` | QML surface | `Panel.qml` | Timer poll, 2 Process gates, IPC target `omafan` |
| `presetRpm/presetsFor` | JS pure | `Model.js` | ladder from live `(minRpm,maxRpm)` band |
| `parseStatus` | JS pure | `Model.js` | `omafan.status.v1` → `{ok,status}` wrapper |
| `parseSchemaId/selectSchema` | JS pure | `Model.js` | family+version parse and highest-mutual selection (R14) |
| `isUndercoolingHot` | JS pure | `Model.js` | `t≥80°C` + lower hold → refuse (exit 8) |
| `run_status/run_doctor` | bash verb | `bin/omafan-ctl` | status doc always emitted, even daemon-down |
| `write_prereqs` | bash gate | `bin/omafan-ctl` | degraded/stale/absent refusals before any write |
| `install/remove/status` | bash verb | `bin/omafan-keybindings` | 8 chords `SUPER+ALT+{T,A,O,L,M,H,X,C}` |
| `fake-afanctl` | fixture | `tests/fixtures/` | hardware-free daemon stand-in |

## WORK RECORDS (MANDATORY)
- Record all work for this repository in `worknotes/`, in the repository: one
  folder per piece of work, `<YYYY-MM-DD>-<slug>`, holding fixed files —
  `PLAN.md` before the work, `LOG.md` while it happens (the commands and their
  real output), `REVIEW.md` for findings, `SUMMARY.md` at the end, and `ASK.md`
  when the ask is a note. `worknotes/README.md` is the contract;
  `worknotes/INDEX.md` lists every folder and is the entry point.
- A folder is opened when the work starts and listed in `INDEX.md` in the same
  change. Frontmatter carries `status: planned|active|blocked|done|unverified`;
  keep it true, and distinguish planned from done. Never claim a check passed
  without evidence — quote the command and its output.
- Notes supplement, and never replace, repository documentation, tests,
  `CHANGELOG.md`, and required `DEVIATIONS.md` rulings: a contract change still
  needs its ruling, a behaviour change still needs its test.
- `orchestration/` is the frozen build-era record; do not edit it or add tickets
  there. New work goes in `worknotes/`.
- Never write an absolute home path into a tracked file — the record must be
  readable on a machine that is not the maintainer's.
- The Advanced polling control is scoped to omafan status refresh only. afanctl
  hardware polling control is future work; do not conflate the two. If future
  work changes afanctl, record it in that project's own repository.

## CONVENTIONS
- Fan command never originates in QML: QML → `omafan-ctl` → `pkexec afanctl`.
  Panel renders what daemon reports, never what was asked.
- `Model.js` ES5-only (`var`/function); no imports, no I/O, no side effects —
  QML imports it AND `tests/model.test.mjs` evals it via `new Function`.
- CLI JSON envelope: `{schema, ok, ...}`; errors `{schema, ok:false, error, message, exit_code}`.
  Default output JSON; `--human` for lines. `--dry-run` writes nothing.
- Exit codes: 0 ok · 1 runtime · 2 usage · 3 auth · 4 afanctl missing ·
  5 daemon down · 6 degraded · 7 out-of-band · 8 undercooling.
- Privileged argv exactly `[<runner>, <afanctl>, verb, args]` — no `env` wrapper
  (polkit pins argv). Custom `--runtime-dir`/`--config` refused on writes (exit 2).
- Keybindings: refuse-on-conflict, byte-identical install/remove, timestamped
  backup under `~/.local/state/omafan-keybindings/`.
- Tests isolate per-case: fresh tempdir, `XDG_RUNTIME_DIR` redirected, sandboxed
  `HOME`, stub `hyprctl`; never touch `/run/afanctl`, real HOME, or `/sys`.
- Branch/commit conventions live in `CONTRIBUTING.md`; scopes follow file
  ownership (`panel bar model ctl keybindings manifest docs tests design
  release repo`).
- Facts with mirrors must move together: chord descriptions live in
  `bin/omafan-keybindings` + DESIGN §7 + `docs/KEYBINDINGS.md` +
  `tests/keybindings.test.sh`; the version lives in `manifest.json` +
  `bin/omafan-ctl` (variable and usage header) + `CHANGELOG.md` +
  two test assertions.

## ANTI-PATTERNS (THIS PROJECT)
- NEVER write `/sys`, `/etc`, `/usr`, `/run/afanctl` from omafan code.
- Reads NEVER pkexec; only write verbs use the runner.
- NEVER claim "Floor" stops the fan — label is `Floor (hardware floor)`.
- NEVER hardcode RPMs in UI/logic — derive from `[fan_min_rpm, fan_max_rpm]`.
- NEVER `as any`-style coercion of missing readings: null rpm/temp is not 0.
- NEVER import Qt/Quickshell in `Model.js` (breaks the Node harness silently).
- NEVER add symlinks to plugin tree (`omarchy plugin validate` fails).
- Contract changes without a `DEVIATIONS.md` ruling entry.
- NEVER edit a mirrored constant in one place only — the gate asserts chord
  descriptions and the version verbatim, so a half-updated rename turns the
  suite red on a clean tree (already happened once with the floor chord).

## UNIQUE STYLES
- `DESIGN.md` frozen; `DEVIATIONS.md` records old→new→why→tickets→ruling.
- QML key handling via `PanelKeyCatcher` signals (`onMoveRequested`,
  `onTextKey`, …), not raw key events; `KeyboardHelp.qml` is passive.
- Staleness = `max(5s, 3×poll interval)`; interval cached in hw.json.
- Polling: fast path every `poll_seconds` (default 2s), every 10th `--full`;
  post-write `Qt.callLater(refresh)`; 20s process deadlines.
- Undercooling guard: hot (`t_eff_c≥80`) + below-current hold needs `--force`
  (CLI) or second `Enter` within 10s (panel).

## COMMANDS
```bash
tests/run-all.sh                          # full hardware-free gate (9 suites)
bash tests/qml-lint.sh                    # QML lint (qmllint + qs.* shim)
bash -n bin/omafan-ctl bin/omafan-keybindings  # shell syntax
omarchy plugin validate .                 # shell's structural gate
bin/omafan-ctl doctor                     # first response to any failure
OMAFAN_LIVE=1 tests/integration-shell.sh  # opt-in live (excluded from gate)
OMAFAN_HW=1 tests/hw-smoke.sh             # opt-in hardware (interactive yes)
```

## NOTES
- Deps (not bundled): afanctl ≥0.1.0 running, `omarchy-shell`, `pkexec`,
  `jq`; Node only for tests. No build step — `omarchy plugin add <git-url>`.
- `status` exits 5 with `daemon.running:false` when down — read the doc, not
  just the code. `doctor` names the fix per FAIL line.
- `orchestration/logs|backups`, `.recon/`, `.omo/` gitignored — ignore them.
- No Makefile or package.json exists in this repo. `.github/` holds the PR
  template, the issue templates and `workflows/ci.yml` — the gate plus the
  branch-model guard, which runs on PRs to `dev` and `master` (R13). Two suites
  are deliberately not run there (`plugin-validate` needs the `omarchy` CLI,
  `qml-lint` needs `qmllint`); the workflow says so in its job summary.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (yadav-prakhar/omafan), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (CONTEXT.md + docs/adr/ at repo root; neither exists yet). See `docs/agents/domain.md`.

