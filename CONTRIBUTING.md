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
bash tests/run-all.sh                     # 9 suites: plugin-validate, manifest, model, ctl, keybindings, qml-lint, panel-slider, panel-refresh, branch-model
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

## Branch model

`dev` is the integration branch and the default branch. `master` is the shipped
branch — what `omarchy plugin add` clones into a user's machine.

```
feature branch  ->  dev  ->  (curated sync at release)  ->  master
```

- **Cut every branch from `dev`, and open every PR against `dev`.** It is the
  default, so a new PR targets it already.
- **`master` is never merged into.** A release copies an allowlist of shipped
  paths from `dev` onto `master` as one commit, then tags it — see
  [Cutting a release](#cutting-a-release).
- `dev` carries everything: runtime, operator documentation *and* development
  material. `master` carries the plugin, its tests and the operator docs only.

Why a sync and not a merge: `omarchy plugin add` clones the **whole repository**
into `~/.config/omarchy/plugins/<id>`, so a root `AGENTS.md` on the shipped
branch is content a stranger's coding agent can discover and act on inside their
own installation. That is a prompt-injection surface, not untidiness
([DEVIATIONS.md](DEVIATIONS.md) R11, mechanism replaced by R13). A plain
`git merge dev` would put `worknotes/`, `orchestration/`, `skills/`, `PLAN.md`
and every `AGENTS.md` into every user's install.

> [!NOTE]
> The sibling project [`afanctl`](https://github.com/yadav-prakhar/afanctl) has
> **no equivalent constraint** — nothing clones it into a user's config
> directory, so there `dev` → `master` at release is an ordinary `git merge`.
> The two repositories share the same *branch flow* and have different *release
> mechanics*. Do not carry this repository's sync over to that one, and do not
> carry that one's merge over to here.

## Branch naming

`<type>/<short-slug>`, lower-case, hyphenated, one topic per branch, cut from
`dev`:

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

- One logical change per commit; rebase onto `dev` rather than merging it in, so
  the history stays linear.
- Say what you **ran** and what it printed. "Tests pass" is not evidence.
- Record the work in `worknotes/` as it happens: the feature folder's `LOG.md`
  carries the command output and `SUMMARY.md` closes it. A commit body summarises
  that evidence; it is not the place the evidence lives.
- Never commit `.recon/`, `.omo/`, `.omc/` or test scratch — they are gitignored
  on purpose. Development material never reaches the **shipped** branch
  (`worknotes/`, `skills/`, `orchestration/`, `docs/agents/`, the `AGENTS.md`
  files, `PLAN.md`, `QUESTIONS.md`); the full lists are in
  `tests/lib/shipped-paths.sh` and the `branch-model` gate suite asserts them.
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

`master` is what a user installs, so it carries the plugin, its tests and the
operator documentation only. Everything that exists to *develop* omafan is on
`dev`, the default branch:

| On `dev` | What it is |
|---|---|
| `AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md` | the local invariants for the root, `bin/` and `tests/` |
| `skills/` | task-shaped procedures: running the gates, verifying in a live shell, changing a frozen contract, capturing screenshots, cutting a release |
| `worknotes/` | the development record for everything after the build: one folder per piece of work, holding `PLAN.md`, `LOG.md`, `REVIEW.md` and `SUMMARY.md` |
| `PLAN.md`, `QUESTIONS.md`, `orchestration/` | the build-era record: plan, worker questions, ticket cards, ledger, adversarial reviews, `BUILD-LOG.md`, and the `dispatch.sh` / `live-install.sh` tools |
| `docs/agents/` | dev-only notes on the issue tracker, the triage labels and the domain doc layout |
| `.githooks/pre-commit` | refuses a commit on `master` that touches any path in this table |
| `tests/lib/shipped-paths.sh` | the one home of both path lists (shipped on `master` too, because the gate suite reads it there) |

```sh
git fetch origin dev
git show dev:AGENTS.md | less
git show dev:skills/run-the-gates/SKILL.md | less
git show dev:worknotes/README.md | less
```

Install the guards once per clone — **both hooks**, as copies, not via
`core.hooksPath`:

```sh
for h in pre-commit pre-merge-commit guard.sh; do
    cp .githooks/$h .git/hooks/$h && chmod +x .git/hooks/$h
done
```

`git config core.hooksPath .githooks` looks tidier and is what this repo used to
document, but it goes inert exactly where it matters: `.githooks/` is
development material, so checking out `master` removes the directory and git then
finds no hook to run. `.git/` belongs to no branch, so copies there survive the
switch — re-copy them when `.githooks/` changes.

`pre-commit` refuses a commit on `master` — the branch *name*, not "the default
branch", which is now `dev` and carries this material on purpose — that adds or
changes development material. `pre-merge-commit` refuses a merge onto `master`
whose resulting tree contains any, and it is **not** optional: git never runs
`pre-commit` for a merge commit, so without it `git merge dev` onto `master`
succeeds and lands every denylisted path. Both fail closed on `master` if they
cannot read `tests/lib/shipped-paths.sh`. On `dev` and on feature branches they
do nothing.

> [!IMPORTANT]
> **The hooks are a convenience, not the guarantee.** They cannot see a
> fast-forward merge at all — it creates no commit, so git runs no hook —
> `--no-verify` skips them, a copy in `.git/hooks/` goes stale when
> `.githooks/` changes, and a fresh clone has none until someone runs the loop
> above. The guarantee is the `branch-model` gate suite, which reads the tree of
> `master` and names every offender, and `.github/workflows/ci.yml`, which runs
> that suite on every PR where it cannot be skipped. If you are deciding what to
> trust, trust those two. The cost is not theoretical: users install this
> repository by cloning it.

## Cutting a release

A release is a curated sync, never a merge:

```sh
skills/publish-a-release/sync-master.sh --from dev              # review the diff
skills/publish-a-release/sync-master.sh --from dev --full-diff   # the whole diff
skills/publish-a-release/sync-master.sh --from dev --commit --tag vX.Y.Z
```

The script copies the shipped path allowlist into a throwaway worktree on
`master`, prunes every denylisted path the allowlist swept up (`bin/AGENTS.md`,
`tests/AGENTS.md` and `docs/agents/` all sit inside allowlisted directories),
**refuses to write if any denylisted path survives**, and prints the diff. Nothing
is written without `--commit`, and running it twice changes nothing. The version
bump, the changelog move and the marketplace steps are in
[`skills/publish-a-release/SKILL.md`](skills/publish-a-release/SKILL.md) and
[docs/PUBLISHING.md](docs/PUBLISHING.md).

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
