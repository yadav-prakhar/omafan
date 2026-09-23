---
feature: branch-model
status: done
branch: chore/branch-model
opened: 2026-09-21
updated: 2026-09-21
related:
  - DEVIATIONS.md (R11, R12, R13)
  - AGENTS.md
  - CONTRIBUTING.md
  - docs/PUBLISHING.md
  - tests/lib/shipped-paths.sh
---

# `dev` as integration branch, filtered release to `master`

GitHub issue [#2](https://github.com/yadav-prakhar/omafan/issues/2), P0 in the
epic [#1](https://github.com/yadav-prakhar/omafan/issues/1). It blocks every
other issue in that epic, because it changes where work lands.

The ask: adopt `feature branch -> dev -> release to master`, while preserving
the security property ruling R11 exists to protect.

## The conflict, and how it is resolved

The repository did the opposite, deliberately. R11's reasoning is not tidiness:
`omarchy plugin add` clones the **whole repository** into a user's
`~/.config/omarchy/plugins/<id>`, so a root `AGENTS.md` on the shipped branch is
content a stranger's coding agent can discover and act on inside their own
installation. That is a prompt-injection surface.

**Keep R11's guarantee; replace its mechanism.** A release stops being "the
branch work already landed on" and becomes a curated sync: only an allowlist of
shipped paths is copied from `dev` onto `master`, as one commit, then tagged. A
plain `git merge dev` would ship `worknotes/`, `orchestration/`, `skills/`,
`PLAN.md`, `QUESTIONS.md` and every `AGENTS.md` into every user's install.

## Decisions taken

| # | Question | Decision |
|---|---|---|
| 1 | Where do the two path lists live? | One home: `tests/lib/shipped-paths.sh`, read by the sync script, the hook, the gate suite and CI. Under `tests/` because the suite that asserts them must also run on `master`, where `skills/` and `.githooks/` do not exist. POSIX sh, because the hook is `/bin/sh`. |
| 2 | Where does the release script live? | `skills/publish-a-release/sync-master.sh`. `bin/` is on the shipped allowlist, so a release tool there would ship to every user — the thing the allowlist prevents. `orchestration/` is the frozen build-era record and takes no new tools (R12). `skills/` is denied on `master` and already holds the procedure the script implements. |
| 3 | Is the denylist exactly issue #2's list? | Issue #2's list verbatim, plus two entries with their reason recorded in R13: `docs/agents/` (agent instruction files that arrived inside `docs/` after R12 declared that tree 100% shipped — same class as `bin/AGENTS.md`) and `.omc/` (agent operational state). Both `AGENTS.md` and `.omc/` match at any depth, so the next one is caught before it ships. |
| 4 | Is the guard a gate suite, given R12 said `tests/` asserts nothing about notes? | Yes, the 9th. R12's principle is that a red suite must mean the plugin is broken — and a shipped branch carrying agent instructions **is** a broken plugin. `DESIGN.md §10` is frozen, so the suite list change is part of R13. |
| 5 | What happens in a clone with no `master` ref? | The tree check prints a visible `SKIPPED` line rather than passing quietly. CI fetches the ref and rejects that skip, so the assertion cannot hide there. |
| 6 | How is the hook installed? | As a copy into `.git/hooks/pre-commit`. See `LOG.md`: `core.hooksPath .githooks`, what R12 documented, goes inert on `master` because `.githooks/` is denied there. |

## Scope

- In scope: the R13 ruling; the path lists; the sync script; the pre-commit hook
  inversion; the gate suite; the first CI workflow; the GitHub default branch;
  and every document that described the old flow.
- Out of scope, and left to issue #8: making the CI gate a **required status
  check**, and provisioning or formally waiving the two suites that need
  external tooling (`plugin-validate` needs the `omarchy` CLI, `qml-lint` needs
  `qmllint`). The workflow names both as not run, with the reason, in its job
  summary rather than skipping them into a green result.
- Out of scope: performing an actual release sync onto `master`. The mechanism is
  built and exercised end to end in a scratch clone; shipping is the
  maintainer's call.

## Acceptance criteria

| # | Criterion | Where it is proved |
|---|---|---|
| 1 | A clone of `master` contains no denylisted file, asserted by a test | `tests/branch-model.test.sh`; `LOG.md` §4, §6, §7 |
| 2 | A clone of `master` still passes `omarchy plugin validate .` | **not verified** — `omarchy` is not installable on this machine (macOS). `LOG.md` §8 |
| 3 | `dev` is the default branch; a new PR defaults to it | `LOG.md` §12 |
| 4 | The release procedure is documented and scripted | `skills/publish-a-release/{SKILL.md,sync-master.sh}`, `docs/PUBLISHING.md` §2; `LOG.md` §5–§11 |
| 5 | The pre-commit hook works correctly on both branches | `LOG.md` §2, §3 |
