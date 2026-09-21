---
feature: branch-model
status: done
branch: chore/branch-model
opened: 2026-09-21
updated: 2026-09-21
related:
  - PLAN.md
  - LOG.md
  - DEVIATIONS.md (R13)
---

# Summary — `dev` as integration branch, filtered release to `master`

Issue #2 is implemented on `chore/branch-model` in nine commits. `dev` is the
GitHub default branch, `master` is updated only by a scripted curated sync, and
the property ruling R11 exists to protect is now asserted by a gate suite and by
CI instead of only being forbidden in prose. Ruling **R13** records the change.
`master` in this repository is untouched: the release mechanism was exercised
end to end in a scratch clone, because shipping is the maintainer's call.

One acceptance criterion is **unverified**: `omarchy plugin validate .` on the
synced tree. `omarchy` does not exist on this machine (macOS). See `LOG.md` §8.

## Shipped

- `DEVIATIONS.md` — ruling **R13**: supersedes R11's *mechanism*, restates its
  guarantee, records both path lists and the two additions beyond issue #2's
  denylist with their reason.
- `tests/lib/shipped-paths.sh` — new. One home for the allowlist and the
  denylist, read by four consumers. POSIX sh, under `tests/` because the suite
  that asserts them also runs on `master`.
- `skills/publish-a-release/sync-master.sh` — new. The curated sync: copy the
  allowlist, prune the denylist, refuse if any denylisted path survives, show
  the diff, then commit and tag. Writes nothing without `--commit`, idempotent.
- `tests/branch-model.test.sh` + `tests/run-all.sh` — the gate's 9th suite:
  `master`'s tree carries no development path.
- `.github/workflows/ci.yml` — new, the repository's first CI workflow: the
  branch-model guard where it cannot be skipped, plus the hardware-free suites a
  runner can run.
- `.githooks/pre-commit` — keys on the branch **name** `master`, checks the
  branch before requiring the lists, fails closed only on `master`, and is now
  installed as a copy into `.git/hooks/` rather than via `core.hooksPath`.
- `.gitignore` — `.omc/` at any depth.
- Docs: `AGENTS.md` header/STRUCTURE/COMMANDS, `CONTRIBUTING.md` (a new Branch
  model section, a new Cutting a release section, and the explicit statement that
  `afanctl` has no equivalent constraint), `docs/PUBLISHING.md` §2,
  `README.md`, `DESIGN.md §10`, `docs/TESTING.md`, `tests/AGENTS.md`,
  `skills/README.md`, `skills/run-the-gates`, `skills/publish-a-release`,
  `CHANGELOG.md` Unreleased.
- `docs/agents/` and the `AGENTS.md` "Agent skills" section, carried in from the
  previous session, committed on `dev` where they belong — and denylisted.

Commits (`chore/branch-model`, oldest first):

- `d9394ed` — chore(repo): ignore .omc/ agent operational state
- `4e177a5` — docs(agents): note the issue tracker, triage labels and domain layout
- `1ef9d29` — docs(design): ruling R13 — dev integrates, releases sync to master
- `c73109c` — chore(repo): one home for the shipped and denied path lists
- `217c6b4` — test(tests): assert master carries no development material
- `1a17326` — fix(repo): key the pre-commit guard on the master branch name
- `1bfb237` — feat(release): curated dev-to-master sync script
- `7e54557` — chore(repo): first CI workflow — branch-model guard and the gate
- `ff8c0d6` — docs(repo): describe the dev-integrates branch model and release flow

## Evidence

```text
$ bash tests/run-all.sh
PASS suites 6 / FAIL suites 3 / SKIP 0
failed: plugin-validate ctl keybindings
```

Those three fail identically on pristine `dev` on this machine — the macOS
baseline in `LOG.md` §1, where five passed instead of six. The sixth pass is the
new suite.

```text
$ bash tests/branch-model.test.sh
branch-model: checked refs/heads/master (48 paths, 57d5f63)
PASS 42 / FAIL 0
```

Full command output for every claim is in `LOG.md`.

- Live check: not applicable. No runtime file, no QML, no manifest change.
- `omarchy plugin validate .`: **not run** — `omarchy` is not on this machine.

## Open items

| Item | Owner |
|---|---|
| `omarchy plugin validate .` on a clone of the synced `master` | needs a machine with the Omarchy shell; `docs/PUBLISHING.md` §1 now says to run it against the synced tree |
| Make the CI gate a required status check | issue #8 |
| Provision or formally waive `plugin-validate` and `qml-lint` in CI | issue #8 — the workflow names both as not run, with the reason, in its job summary |
| Positioning and copy changes | issue #8, deliberately last |
| The actual release sync onto `master` | the maintainer; the mechanism is built and exercised, nothing has shipped |
