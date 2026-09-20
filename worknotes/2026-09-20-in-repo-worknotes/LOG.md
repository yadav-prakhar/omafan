---
feature: in-repo-worknotes
status: done
branch: dev
opened: 2026-09-20
updated: 2026-09-20
related:
  - PLAN.md
  - ../README.md
  - ../../AGENTS.md
---

# Log — the development record moves into the repository

Chronological, oldest first. Read [PLAN.md](PLAN.md) for the decisions; this file
is the evidence.

## Where the record lived before — 2026-09-20

Every note for this repository was written into an Obsidian vault outside it
(`/home/prakhar/Documents/Default/Workspace/omarchy plugin development/omafan`),
organised by purpose (`plans/`, `logs/`, `reviews/`, `done/`), with the root
`AGENTS.md` WORK RECORDS block naming that absolute path and telling agents to
write there. 20 files, 128 KB. Operator direction on 2026-09-20: the work record
belongs in the repository, and nothing about it may reach the default branch.

## The archive, and what happened to each note

`19` of the 20 files were migrated; the archive's `INDEX.md` was the
folder-policy note and is superseded by [../README.md](../README.md) (the
contract) and [../INDEX.md](../INDEX.md) (the index), so it was not copied.

| Archive note (path) | Now |
|---|---|
| `build-writeup.md` | [2026-09-15-build/SUMMARY.md](../2026-09-15-build/SUMMARY.md) |
| `2026-09-16-marketplace-submission.md` | [2026-09-16-marketplace-submission/SUMMARY.md](../2026-09-16-marketplace-submission/SUMMARY.md) |
| `logs/2026-09-17-marketplace-7174-snapshot-refresh.md` | [2026-09-16-marketplace-submission/LOG.md](../2026-09-16-marketplace-submission/LOG.md) |
| `logs/2026-09-20-marketplace-7174-agents-md-and-dev-branch.md` | 〃 (same `LOG.md`) |
| `plans/2026-09-17-advanced-polling-slider-plan.md` | [2026-09-17-advanced-polling/PLAN.md](../2026-09-17-advanced-polling/PLAN.md) |
| `reviews/2026-09-17-settings-api-recommendations.md` | [2026-09-17-advanced-polling/REVIEW.md](../2026-09-17-advanced-polling/REVIEW.md) |
| `logs/2026-09-17-afanctl-polling-evidence.md` | [2026-09-17-advanced-polling/LOG.md](../2026-09-17-advanced-polling/LOG.md) |
| `logs/2026-09-17-t1-policy-verification.md` | 〃 |
| `logs/2026-09-17-t2-slider-evidence.md` | 〃 |
| `logs/2026-09-17-t3-polling-evidence.md` | 〃 |
| `logs/2026-09-17-t4-docs-evidence.md` | 〃 |
| `logs/2026-09-17-t5-gate-evidence.md` | 〃 |
| `done/2026-09-17-planning-session-summary.md` | [2026-09-17-advanced-polling/SUMMARY.md](../2026-09-17-advanced-polling/SUMMARY.md) |
| `done/2026-09-17-implementation-summary.md` | 〃 |
| `prompt.md` | [2026-09-17-advanced-polling/ASK.md](../2026-09-17-advanced-polling/ASK.md) |
| `plans/2026-09-17-t5-panel-refresh-control.md` | [2026-09-17-in-panel-refresh/PLAN.md](../2026-09-17-in-panel-refresh/PLAN.md) |
| `logs/2026-09-17-t5-panel-refresh-evidence.md` | [2026-09-17-in-panel-refresh/LOG.md](../2026-09-17-in-panel-refresh/LOG.md) |
| `done/2026-09-17-t5-panel-refresh-control.md` | [2026-09-17-in-panel-refresh/SUMMARY.md](../2026-09-17-in-panel-refresh/SUMMARY.md) |
| `todos for omafan.md` | [../BACKLOG.md](../BACKLOG.md) |

Transformations applied to the migrated text, and nothing else:

1. the note's `# H1` became a `## ` section heading inside the target file, with
   the redundant `Log — ` / `Done — ` / `Plan — ` / `Review — ` prefix dropped
   (the filename already says which file it is);
2. archive wikilinks (`[[../plans/…]]`, `[[todos for omafan]]`) became relative
   links resolved against the target file, so every link works in the repository
   and none points at the retired archive;
3. a `*Migrated from …*` provenance line above each section, naming the archive
   path it came from;
4. two path references to the audit trail inside the build writeup now read
   `orchestration/BUILD-LOG.md`, because that file moved in this same change
   (see below).

### Fidelity check

Each source's text was compared against its target file — links normalised to a
token, whitespace collapsed — so a truncated or reworded section would fail:

```text
mismatches: NONE — all 19 source notes present verbatim (links normalised)
checked: 19
```

Link integrity across the new tree (every relative link resolves; no wikilink
left alive):

```text
relative links checked: 59 | broken: none | leftover wikilinks: 0
```

## The shipped docs tree becomes shipped-only

`docs/` was 99% shipped surface with exactly one development-only file in it —
the build audit trail — which made "everything in `docs/` ships" a rule with a
hole in it. It moved to the build record it belongs to:

```text
$ git mv docs/BUILD-LOG.md orchestration/BUILD-LOG.md
```

Every live reference was updated in the same change: `AGENTS.md` (header,
STRUCTURE), `CONTRIBUTING.md`, `README.md`, `PRD.md` (D5), `docs/ARCHITECTURE.md`
§6, `CHANGELOG.md` (the still-unreleased R11 bullet), `orchestration/AGENTS.md`
(structure + where-to-look). References inside *historical* records were left
exactly as written — `orchestration/LEDGER.md`, `orchestration/TRIAGE-R2.md`,
`PLAN.md`'s T14 card and R7/R11's text in `DEVIATIONS.md` — because those record
what was true then; R12 states the path change and where the file is now.

```text
$ grep -rn "docs/BUILD-LOG" --include="*.md" . | grep -v "^./orchestration/logs/"
orchestration/LEDGER.md:20,31   orchestration/TRIAGE-R2.md:17   PLAN.md:44
DEVIATIONS.md:65,106,114        (all historical: LEDGER/TRIAGE are the build
                                flight recorder and R7/R11's rulings)
CHANGELOG.md:94                 (the new R12 bullet: "moved from … to …")
worknotes/2026-09-20-in-repo-worknotes/*  (this folder's own record)
```

## The guard: `.githooks/pre-commit`

There is no CI in this repository, so a stray `worknotes/` or `AGENTS.md` commit
on the default branch would only be noticed after a user cloned it. The hook
refuses the commit when `HEAD` is the default branch and a staged path is
development-only (`AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md`, `skills/`,
`worknotes/`, `orchestration/`, `PLAN.md`, `QUESTIONS.md`, `.githooks/`), and
stays silent on a detached `HEAD` so rebases and cherry-picks are unaffected.
Enabled per clone with `git config core.hooksPath .githooks`.

Verified in four directions in a scratch repository (real hook, real commits):

```text
1) master, dev path, hook installed:   refused (correct)
2) master, unrelated file:             accepted (correct)
3) dev branch, dev path:               accepted (correct)
4) master, dev path, override env:     accepted (correct)
```

and the refusal names the files and the fix:

```text
pre-commit: refusing to commit development material on master

  .githooks/pre-commit
  worknotes/note.md

    git switch dev      # land the change there instead
```

## Gate

The change touches no runtime file, but the gate is run anyway — it is the only
proof this repository accepts:

```text
$ bash tests/run-all.sh
omafan test suite — 2026-09-20T12:44:43+05:30
repo: /home/prakhar/Work/omafan

RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS
RUN   panel-refresh          PASS

PASS suites 8 / FAIL suites 0 / SKIP 0
```

```text
$ bash -n bin/omafan-ctl bin/omafan-keybindings
bash -n clean
```

`omarchy plugin validate .` is the `plugin-validate` suite and passed as part of
the run above; the new `worknotes/` and `.githooks/` directories do not trip it.

## Open

- `orchestration/` is untouched and stays frozen — expected, not an open item.
- The archived vault folder is retired; its deletion in the vault's own git
  repository is left uncommitted there for the operator to review and commit.
- No new suite was added, deliberately: `tests/` asserts nothing about
  `worknotes/`, so a red gate keeps meaning "the plugin is broken".

## Landed — 2026-09-20

```text
$ git log --oneline -1
5d18d7a chore(repo): keep the development record in the repository (worknotes/)
```

Re-run on the committed tree, after this folder's status was moved to `done`:

```text
$ bash tests/run-all.sh
PASS suites 8 / FAIL suites 0 / SKIP 0
```

The operator's vault copy of these notes was deleted the same day; the deletion
is left uncommitted in the vault's own repository for the operator to review and
commit there.
