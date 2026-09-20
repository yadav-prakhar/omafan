# Contributing to omafan

Thanks for looking. This repo is small, has one owner, and takes correctness over
volume: a patch that keeps the safety model intact beats a patch that adds a
feature. Read the two rules below before you start — everything else is detail.

## Two rules that override everything else

1. **omafan never writes `/sys`, never runs as root and never adds privilege.**
   The only privileged operation in the whole project is
   `pkexec /usr/bin/afanctl {hold <rpm>|observe}` through afanctl's own polkit
   rule. No udev rule, no sudoers entry, no root helper, no `/sys` access from
   any file in this repo. See [docs/SAFETY.md](docs/SAFETY.md).
2. **`DESIGN.md` is a frozen contract.** Behaviour changes that contradict it
   need an entry in [DEVIATIONS.md](DEVIATIONS.md) *first* (format below), and
   the design, the docs and the tests must land in the same change. A patch that
   silently diverges from `DESIGN.md` will be asked to rebase onto a ruling.

## Development setup

There is no build step and no package manager. A checkout *is* the plugin:

```sh
git clone https://github.com/yadav-prakhar/omafan.git
cd omafan
bash tests/run-all.sh          # the hardware-free gate
```

To exercise it in a live Omarchy session, put the working tree into the shell's
plugin directory (the shell only loads plugins from there):

```sh
rsync -a --delete --exclude .git ./ \
  ~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/
omarchy-shell shell rescanPlugins
```

> [!IMPORTANT]
> Enabling a plugin writes your **live** `shell.json` — back that file up first
> (`cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.bak`). Editing
> QML inside `~/.config/omarchy/plugins/` by hand also works; the shell
> hot-reloads on save, but it can keep stale QML in memory, in which case
> `omarchy-shell shell rescanPlugins` — or, when that is not enough,
> `omarchy-restart-shell` — is required. The `dev` branch ships
> `orchestration/live-install.sh`, which wraps the same recipe with backups,
> `verify` and `remove`.

Do **not** add symlinks to the plugin tree: `omarchy plugin validate` rejects
them, and the shell copies the tree on install.

Requirements: Omarchy `4.0.0.alpha` (Quattro), `afanctl` ≥ 0.1.0 installed and
running, `jq`, and Node only if you want to run the `Model.js` suite.

## The gates

Every change must pass the hardware-free gate:

```sh
bash tests/run-all.sh                     # 8 suites: plugin-validate, manifest, model, ctl, keybindings, qml-lint, panel-slider, panel-refresh
bash tests/run-all.sh --list              # the suite names
bash tests/qml-lint.sh                    # QML lint (SKIPs cleanly without qmllint/shell tree)
bash -n bin/omafan-ctl bin/omafan-keybindings
omarchy plugin validate .
```

Suites that need a live shell or real hardware are opt-in and must never be
added to `run-all.sh`:

```sh
OMAFAN_LIVE=1 tests/integration-shell.sh   # live shell IPC; only write is the intentional error path
OMAFAN_HW=1   tests/hw-smoke.sh            # moves the fan; attended only, asks for a typed yes
```

Nothing in the gate may touch `/sys`, `/run/afanctl`, your real `$HOME`, the
network, or require root, a daemon or a compositor. Fixtures pin the daemon
contract; when the contract changes, update the fixture, `fake-afanctl` and the
expectation together rather than editing an assertion to fit.

## Branch naming

`<type>/<short-slug>`, lower-case, hyphenated, one topic per branch:

| Type | Use for | Example |
|---|---|---|
| `feat/` | new user-visible behaviour | `feat/slider-shift-step` |
| `fix/` | a defect fix | `fix/exit5-on-daemon-down` |
| `docs/` | documentation only | `docs/keybinding-evidence` |
| `test/` | tests, fixtures, gate plumbing | `test/undercooling-fixture` |
| `chore/` | tooling, housekeeping, non-code | `chore/contributing-guide` |
| `refactor/` | no behaviour change | `refactor/model-guard-split` |

Long-lived or contract-level work may use a short slug of its own
(`feat/undercooling-guard`); the slugs already on record are in
[CHANGELOG.md](CHANGELOG.md) and the `dev` branch's build record.

## Commit conventions

[Conventional Commits](https://www.conventionalcommits.org/), imperative mood,
subject 72 characters or less, no trailing period:

```
<type>(<scope>): <subject>

<why this change is needed; what the old behaviour was>

<falsifiable evidence: the command you ran and what it printed>
```

Scopes follow file ownership, so `git log --oneline -- bin/` stays useful:

`panel` · `bar` · `model` · `ctl` · `keybindings` · `manifest` · `docs` ·
`tests` · `design` · `release` · `repo`

```text
fix(keybindings): drop "off" from the floor chord description

DESIGN.md §7, docs/KEYBINDINGS.md and bin/omafan-keybindings all say
"omafan: fans floor", but tests/keybindings.test.sh still asserted the
pre-rename string, so the gate failed on a clean tree.

  bash tests/keybindings.test.sh   ->  PASS 71 / FAIL 0  (was PASS 70 / FAIL 1)
```

Rules that keep the log honest:

- One logical change per commit; rebase rather than merging `master` in, so the
  history stays linear.
- Say what you **ran** and what it printed. "Tests pass" is not evidence.
- Never commit `.recon/`, `.omo/` or test scratch — they are gitignored on
  purpose.
- Version bumps and changelog entries belong in the release commit, not in
  feature commits; use the `Unreleased` section while you work (see
  [CHANGELOG.md](CHANGELOG.md), Keep a Changelog format).
- Changes to a frozen contract carry the `DEVIATIONS.md` entry id in the body.

## Changing a frozen contract

1. Write the entry in [DEVIATIONS.md](DEVIATIONS.md) using its own format:
   `D<n> — <item> — old → new — why — affected tickets — ruling`.
2. Update `DESIGN.md` (the contract) in the same change.
3. Chase every mirror of the fact: `docs/*`, `README.md`, `PRD.md`,
   `CHANGELOG.md` and the tests that assert the old value.
4. Re-run the gate.

The typical failure mode is exactly step 3: a constant that lives in code, in a
doc table and in a test assertion gets updated in two places out of three.

## Code conventions

- **QML** (`BarWidget.qml`, `Panel.qml`, `KeyboardHelp.qml`) — `Panel.qml` owns
  every side effect (polling, `Process` gates, IPC). `BarWidget.qml` is a thin
  label plus gestures and must stay I/O-free. Use array-form commands, never a
  shell string. Keyboard handling goes through `PanelKeyCatcher` signals, not
  raw key events.
- **Model.js** — pure logic only: ES5 syntax (`var`, `function`), no `import`,
  no I/O, no Qt types. It is imported by QML *and* evaluated by
  `tests/model.test.mjs`, so an ES6-ism or a Qt import breaks the Node harness
  silently.
- **bash** (`bin/*`, `tests/*`) — `set -euo pipefail` (test suites: `set -uo
  pipefail`), quote everything, no `eval`; build JSON with `jq -cn --arg`,
  never by string interpolation. Every external call is bounded by a timeout —
  a hung polkit prompt must never freeze a caller.
- **Docs** — operator language, no marketing. If the UI says `Floor (hardware
  floor)`, the docs say the same and never claim the fan can be stopped.

- **Dependencies and runtime** — nothing beyond what is already on the machine:
  bash, coreutils, `jq`, `awk`/`sed`/`grep`, `procps`, `pkexec`, `notify-send`.
  No new packages, no network at runtime, no `curl`. Node and `qmllint` are
  test-time only.
- **Errors** — every failure prints one human line naming the problem *and* the
  fix, plus the JSON error object of `DESIGN.md §4.3` for `--json` verbs. Never
  exit 0 on a failure, never swallow afanctl's stderr.
- **Style** — 2-space indent in QML/JS, 4 in shell; ~100 columns; no trailing
  whitespace; files end with a newline; comments explain why, not what; no emoji.

## Development notes live on the `dev` branch

The default branch is what a user installs, so it carries the plugin, its tests
and the operator documentation only. Everything that exists to *develop* omafan
is on the [`dev` branch](https://github.com/yadav-prakhar/omafan/tree/dev):

| On `dev` | What it is |
|---|---|
| `AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md` | the local invariants for the root, `bin/` and `tests/` |
| `skills/` | task-shaped procedures: running the gates, verifying in a live shell, changing a frozen contract, capturing screenshots, cutting a release |
| `PLAN.md`, `QUESTIONS.md`, `docs/BUILD-LOG.md` | the build plan, worker questions and the build audit trail |
| `orchestration/` | the full build record: tickets, ledger, adversarial reviews, and the `dispatch.sh` / `live-install.sh` tools |

```sh
git fetch origin dev
git show dev:AGENTS.md | less
git show dev:skills/run-the-gates/SKILL.md | less
```

Contributors — human or agent — are held to the same rules as a human patch:
real evidence, no invented output, no hardware writes in the gate.

## Pull requests

Fill in the template — it is short and it is the review checklist. A PR is ready
when the gate is green, the diff is one topic, docs and tests moved with the
code, and the description states what you ran. For anything that changes
behaviour on real hardware, include the output of:

```sh
bin/omafan-ctl doctor --human
```

## Scope

Out of scope, and PRs for these will be closed: T2 Macs (they use `t2fanrd`),
Apple Silicon, bundling or vendoring afanctl, adding privilege (udev/polkit/
sudoers/root helper), and anything that writes `/sys` from this repository.

## Licence

By contributing you agree your work is licensed under GPL-3.0-only, the licence
of this project ([LICENSE](LICENSE)).
