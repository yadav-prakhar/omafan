---
feature: in-repo-worknotes
status: active
branch: dev
opened: 2026-09-20
updated: 2026-09-20
related:
  - PLAN.md
  - LOG.md
  - ../../DEVIATIONS.md (R12)
---

# Summary — the development record lives in the repository

The work record for omafan is now a first-class part of the repository and only
ever exists on `dev`: a top-level `worknotes/` tree with one folder per piece of
work, the four fixed files inside it, an index and a roadmap; the retired
external note vault migrated into it with content unedited; the last piece of
development material removed from the shipped `docs/` tree; and a pre-commit hook
that refuses to let any of it reach the default branch.

## Shipped

- `worknotes/README.md` — the contract: what belongs in the record, what never
  does, the status vocabulary (`planned | active | blocked | done | unverified`)
  and the frontmatter schema.
- `worknotes/INDEX.md` — every piece of work, one row each; the entry point.
- `worknotes/BACKLOG.md` — the roadmap, migrated from the archive.
- `worknotes/TEMPLATE/{PLAN,LOG,REVIEW,SUMMARY}.md` — copy to open a folder.
- `worknotes/2026-09-15-build/`, `2026-09-16-marketplace-submission/`,
  `2026-09-17-advanced-polling/`, `2026-09-17-in-panel-refresh/` — 19 archive
  notes migrated into 12 files, each section naming the archive path it came from.
- `orchestration/BUILD-LOG.md` — the audit trail moved out of `docs/`, so the
  shipped documentation tree no longer carries development material at all.
- `AGENTS.md` — WORK RECORDS rewritten (in-repo record, no external vault, no
  absolute home paths), structure and entry-point rows added, revalidated.
- `DEVIATIONS.md` **R12** — the ruling this change needed, since it contradicts
  R11's standing text about where the record lives.
- `.githooks/pre-commit` — the guard; `git config core.hooksPath .githooks` to
  enable it per clone.
- Mirrors moved in the same change: `CONTRIBUTING.md`, `README.md`, `PRD.md`,
  `docs/ARCHITECTURE.md` §6, `CHANGELOG.md`, `skills/README.md`,
  `skills/run-the-gates` (also caught up with the eighth suite), `skills/change-a-frozen-contract`,
  `skills/publish-a-release`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `orchestration/AGENTS.md`.

## Evidence

```text
$ bash tests/run-all.sh
PASS suites 8 / FAIL suites 0 / SKIP 0
```

```text
$ bash tests/run-all.sh --list        # unchanged: no suite added, none removed
plugin-validate manifest.test.sh model.test.mjs ctl.test.sh keybindings.test.sh
qml-lint.sh panel-slider.test.sh panel-refresh.test.sh
```

Fidelity of the migration (19 sources) and link integrity of the new tree:

```text
mismatches: NONE — all 19 source notes present verbatim (links normalised)
relative links checked: 59 | broken: none | leftover wikilinks: 0
```

The hook, exercised in a scratch repository: refused a development path on the
default branch, allowed an unrelated file on the default branch, allowed
development paths on `dev`, and honoured the `OMAFAN_ALLOW_DEV_PATHS=1` override.
Full transcript in [LOG.md](LOG.md).

## Open items

- The retired vault folder is deleted on disk; the deletion itself is left
  uncommitted in the vault's own repository for the operator to review.
- `docs/` now has no development-only file: keep it that way. A future dev-only
  file belongs in `worknotes/` (or `orchestration/` if it is build history), not
  in the shipped documentation tree.
- No test asserts any of this, by design — a red gate must mean the plugin is
  broken, never that a note is stale. The hook is the only mechanical guard.
