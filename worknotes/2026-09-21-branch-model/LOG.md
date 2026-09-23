---
feature: branch-model
status: done
branch: chore/branch-model
opened: 2026-09-21
updated: 2026-09-21
related:
  - PLAN.md
  - DEVIATIONS.md (R13)
---

# Log — `dev` as integration branch, filtered release to `master`

Chronological. Every command below was run on the maintainer's macOS machine
against this repository; scratch clones live outside the repository and were
removed or left in the session scratchpad, never inside the tree.

## 1. Baseline: the gate on this machine — 2026-09-21

Three suites fail on macOS **before any change**, so they are not regressions.
Run in a detached worktree on pristine `dev`:

```text
$ bash tests/run-all.sh          # worktree at dev 48711c7
PASS suites 5 / FAIL suites 3 / SKIP 0
failed: plugin-validate ctl keybindings
```

`plugin-validate` fails because `omarchy` is absent (the suite hard-fails rather
than skipping, by design). `ctl` and `keybindings` fail for the same class of
reason — this repository targets Omarchy/Arch and the suites lean on GNU
userland. **Everything below is read against that baseline.**

After the change, on `chore/branch-model`:

```text
$ bash tests/run-all.sh
RUN   qml-lint               PASS
RUN   panel-slider           PASS
RUN   panel-refresh          PASS
RUN   branch-model           PASS

PASS suites 6 / FAIL suites 3 / SKIP 0
failed: plugin-validate ctl keybindings
```

Six pass instead of five — the extra is the new `branch-model` suite. The same
three suites fail, for the same pre-existing reasons.

## 2. The hook on `master` — 2026-09-21

Tested in a scratch clone, with the hook copied into `.git/hooks/pre-commit`
(see §3 for why not `core.hooksPath`). `master` in **this** repository was never
touched.

```text
$ git add -f AGENTS.md worknotes/INDEX.md ; git commit -m "should be refused"
pre-commit: refusing to commit development material on master

  AGENTS.md
  worknotes/INDEX.md

These paths exist to develop omafan and must never reach the shipped branch:
users clone it into ~/.config/omarchy/plugins/<id> (DEVIATIONS.md R11, R13).

    git switch dev      # land the change there instead

A release does not merge dev; it copies the shipped path allowlist:

    skills/publish-a-release/sync-master.sh --from dev

Deliberate override: OMAFAN_ALLOW_DEV_PATHS=1 git commit ...
>>> exit=1

$ git reset ; git add README.md ; git commit -m "shipped only"
>>> allowed: cd295a7 shipped only

$ git rm --cached tests/lib/shipped-paths.sh ; rm -f tests/lib/shipped-paths.sh
$ git add README.md ; git commit -m "lists gone"
pre-commit: cannot read .../tests/lib/shipped-paths.sh — refusing to guess on master.
  restore the file, or: OMAFAN_ALLOW_DEV_PATHS=1 git commit ...
>>> exit=1

$ git add -f AGENTS.md ; OMAFAN_ALLOW_DEV_PATHS=1 git commit -m "deliberate override"
>>> allowed with the documented override: 43aa668 deliberate override
```

## 3. The hook on `dev` and on a feature branch — 2026-09-21

This is the failure mode issue #2 singles out: a guard keyed on "the default
branch" starts refusing every normal commit once `dev` becomes the default.

```text
$ git checkout -B dev origin/dev
on dev; lists present: no
$ git add AGENTS.md worknotes/SCRATCH.md PLAN.md
  staged: .githooks/pre-commit
  staged: AGENTS.md
  staged: PLAN.md
  staged: tests/lib/shipped-paths.sh
  staged: worknotes/SCRATCH.md
$ git commit -m "dev material on dev"
>>> allowed on dev: 4b68f08 dev material on dev

$ git checkout -b feat/scratch ; git add QUESTIONS.md ; git commit -m "..."
>>> allowed on feat/scratch: b7aa95a dev material on a feature branch
```

Note the `lists present: no` line: `origin/dev` predates
`tests/lib/shipped-paths.sh`, and the commit still went through. That is why the
hook checks the branch **before** it requires the lists — an earlier draft
required them first and refused every commit on any branch without the file.

**The finding that changed the design.** The hook was first tested with
`git config core.hooksPath .githooks`, as R12 documented, and a deliberately
poisoned commit on `master` went straight through. The reason: `.githooks/` is
itself denylisted, so checking out `master` removes the directory and git finds
no hook to run — the guard was inert in the one place it exists for. `.git/`
belongs to no branch, so the install is now a copy into `.git/hooks/pre-commit`,
verified above. It can go stale, which is what §4 and the CI job are for.

## 4. The guard fails loudly on a poisoned tree — 2026-09-21

A throwaway detached commit off `master`, carrying three denylisted paths;
`master` itself untouched.

```text
$ OMAFAN_SHIPPED_REF=ad6d993 bash tests/branch-model.test.sh
FAIL: ad6d99396c9bd1a959253dc012f6fdb1e3652747 carries development material:
       AGENTS.md
       docs/agents/domain.md
       worknotes/INDEX.md
       a release is a curated sync, never a merge:
       skills/publish-a-release/sync-master.sh (DEVIATIONS.md R13)
branch-model: checked ad6d9939... (51 paths, ad6d993)
PASS 39 / FAIL 1
exit=1
```

And on the real tree:

```text
$ bash tests/branch-model.test.sh
branch-model: checked refs/heads/master (48 paths, 57d5f63)
PASS 42 / FAIL 0
```

## 5. The sync, review run against the current `master` — 2026-09-21

```text
$ skills/publish-a-release/sync-master.sh --from dev
sync-master: dev  ->  master
  source:   dev 48711c7 ("docs(worknotes): close the in-repo worknotes record at 5d18d7a")
  onto:     master 57d5f63

pruned (development material): bin/AGENTS.md
pruned (development material): tests/AGENTS.md

carried over untouched (outside the allowlist, not denied): .gitignore

--- what this release would change on master ---
 .github/PULL_REQUEST_TEMPLATE.md |  3 +++
 CHANGELOG.md                     | 13 ++++++++++++-
 CONTRIBUTING.md                  | 22 +++++++++++++++++++---
 DEVIATIONS.md                    | 34 ++++++++++++++++++++++++++++++++++
 PRD.md                           |  9 ++++++---
 README.md                        |  4 +++-
 docs/ARCHITECTURE.md             | 10 ++++++----
 7 files changed, 83 insertions(+), 12 deletions(-)
--- end of diff ---

Review run: nothing was written. master is unchanged.
$ git rev-parse --short master
57d5f63
```

Shipped files only. `.gitignore` is on `master` today but is not in issue #2's
allowlist, so the script reports it as carried over untouched rather than
silently deleting it — an unasked-for deletion from the shipped branch is the
maintainer's call, not the script's.

## 6. End to end in a scratch clone — 2026-09-21

`master` in this repository is deliberately left alone, so the whole release was
exercised in a clone. Source: `chore/branch-model` at `ff8c0d6`.

```text
$ skills/publish-a-release/sync-master.sh --from chore/branch-model
pruned (development material): bin/AGENTS.md
pruned (development material): docs/agents/domain.md
pruned (development material): docs/agents/issue-tracker.md
pruned (development material): docs/agents/triage-labels.md
pruned (development material): tests/AGENTS.md
carried over untouched (outside the allowlist, not denied): .gitignore
 14 files changed, 818 insertions(+), 34 deletions(-)
Review run: nothing was written. master is unchanged.
```

The three `docs/agents/` files are the reason that path was added to the
denylist: `docs/` is allowlisted wholesale, so without the entry those agent
instruction files would have shipped.

```text
$ skills/publish-a-release/sync-master.sh --from chore/branch-model --commit --tag v1.0.1-e2e
committed d298b01 on master
tagged v1.0.1-e2e at d298b01

$ skills/publish-a-release/sync-master.sh --from chore/branch-model      # again
master is already in sync with chore/branch-model — nothing to commit.

$ bash tests/branch-model.test.sh
branch-model: checked refs/heads/master (51 paths, d298b01)
PASS 42 / FAIL 0
```

Idempotent, and the guard is green against the synced tree.

## 7. What a user actually clones — 2026-09-21

```text
$ git clone --branch master --single-branch <scratch> shipped
$ ls -A shipped
.git  .github  .gitignore  BarWidget.qml  bin  CHANGELOG.md  CONTRIBUTING.md
DESIGN.md  DEVIATIONS.md  docs  KeyboardHelp.qml  LICENSE  manifest.json
Model.js  Panel.qml  PRD.md  preview.png  README.md  SECURITY.md  tests

$ git -C shipped ls-files | wc -l
51
```

No `AGENTS.md` at any level, no `worknotes/`, no `orchestration/`, no `skills/`,
no `.githooks/`, no `docs/agents/`, no `PLAN.md`, no `QUESTIONS.md`. Asserted,
not eyeballed:

```text
$ cd shipped && bash tests/branch-model.test.sh
branch-model: checked refs/heads/master (51 paths, d298b01)
branch-model: checked the working tree (HEAD on master)
PASS 41 / FAIL 0
```

41 rather than 42 assertions: the check on the hook's duplicated branch name is
skipped because `.githooks/` is not there — which is the point.

The installed shape too, a copy of that tree with `.git` stripped, as
`omarchy plugin add` leaves it:

```text
$ bash tests/branch-model.test.sh          # in the installed copy
branch-model: SKIPPED the tree check — no master ref in this clone.
  fetch it:  git fetch origin master:refs/remotes/origin/master
branch-model: checked this installed tree (no git metadata)
PASS 40 / FAIL 0
```

The skip is printed, not hidden, and the working-tree check still runs.

## 8. `omarchy plugin validate .` — NOT VERIFIED

```text
$ command -v omarchy
omarchy NOT on PATH — cannot be verified on this machine (macOS; omarchy is an
Arch/Omarchy tool)
```

**This acceptance criterion is unverified.** What is known: the synced tree
contains `manifest.json` (the sync refuses a tree without it), contains no
symlinks, and is a strict subset of the paths `master` already carried at
`57d5f63` plus new files under `tests/` and `.github/workflows/`. Nothing the
sync does removes a path the validator reads. It still has to be run on a
machine with the shell before a release ships, and `docs/PUBLISHING.md` §1 now
says to run it against the **synced** tree rather than `dev`.

## 9. The sync's refusal, proved by fault injection — 2026-09-21

The denylist prune should make the refusal unreachable, so it was made reachable
on purpose: in the scratch clone the prune's condition was replaced with
`if false`.

```text
$ skills/publish-a-release/sync-master.sh --from chore/branch-model --commit
sync-master: refusing to write development material to master

  bin/AGENTS.md
  docs/agents/domain.md
  docs/agents/issue-tracker.md
  docs/agents/triage-labels.md
  tests/AGENTS.md
sync-master: the denylist prune did not hold — this is a bug in this script
  lists: tests/lib/shipped-paths.sh
  guard: tests/branch-model.test.sh

$ git log --oneline -1 master
57d5f63 docs(repo): ship the runtime and docs, keep development material on `dev`
```

Nothing was written. The script was restored immediately afterwards.

## 10. Usage errors — 2026-09-21

```text
$ sync-master.sh --from dev --tag v9.9.9
sync-master: --tag needs --commit
  there is no commit to tag in a review run          exit=2
$ sync-master.sh --wat
sync-master: unknown argument: --wat                 exit=2
$ sync-master.sh --from nosuchref
sync-master: no such ref: nosuchref                  exit=2
$ sync-master.sh --from
sync-master: --from needs a ref                      exit=2
```

## 11. Syntax and the CI workflow — 2026-09-21

```text
$ bash -n bin/omafan-ctl bin/omafan-keybindings tests/run-all.sh \
      tests/branch-model.test.sh skills/publish-a-release/sync-master.sh
$ sh -n .githooks/pre-commit tests/lib/shipped-paths.sh
--- syntax clean ---

$ ruby -ryaml -e 'd=YAML.load_file(".github/workflows/ci.yml"); ...'
YAML ok
jobs: ["branch-model", "gate"]
steps(branch-model): 3
steps(gate): 4

$ bash -n <each embedded `run:` block, extracted>
syntax ok  (4 of 4)
```

The workflow itself has **not** run: nothing is pushed, by instruction. Its
first real execution will be on the PR the orchestrator opens.

## 12. The GitHub default branch — 2026-09-21

Done after the hook change was committed, so as not to strand work behind a
guard that blocks `dev`.

```text
$ gh repo view yadav-prakhar/omafan --json defaultBranchRef,deleteBranchOnMerge
{"defaultBranchRef":{"name":"master"},"deleteBranchOnMerge":false}

$ gh repo edit yadav-prakhar/omafan --default-branch dev
$ gh api -X PATCH repos/yadav-prakhar/omafan -f delete_branch_on_merge=true
{"default_branch":"dev","delete_branch_on_merge":true}

$ gh repo view yadav-prakhar/omafan --json defaultBranchRef,deleteBranchOnMerge
{"defaultBranchRef":{"name":"dev"},"deleteBranchOnMerge":true}

$ git remote set-head origin --auto
'origin/HEAD' has changed from 'master' and now points to 'dev'
```

**Open:** `omarchy plugin validate .` on the synced tree (§8) — unverifiable on
this machine. Making the CI gate a required status check, and the decision on
the two externally-tooled suites, belong to issue #8.
