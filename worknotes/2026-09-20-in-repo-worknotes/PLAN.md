---
feature: in-repo-worknotes
status: active
branch: dev
opened: 2026-09-20
updated: 2026-09-20
related:
  - AGENTS.md
  - CONTRIBUTING.md
  - DEVIATIONS.md (R12)
---

# The development record moves into the repository (2026-09-20)

Ask: "any work done should be notes within the repository … all work will happen
in `dev` branch but it'll not be the default branch … a new folder in this branch
named worknotes … any feature level work or any work basically should be written
in its specific subfolder in that worknotes folder."

## Decisions taken by the operator (2026-09-20)

| # | Question | Decision |
|---|---|---|
| 1 | Location | top-level `worknotes/` (not `docs/worknotes/`) |
| 2 | Filenames inside a feature folder | fixed — `PLAN.md`, `LOG.md`, `REVIEW.md`, `SUMMARY.md` |
| 3 | The external note vault | retired for this repository — engineering notes live here only, no pointer notes, no duplicates |
| 4 | `docs/BUILD-LOG.md` (the one dev-only file inside the shipped `docs/` tree) | moved out, so `docs/` is 100% shipped surface |

## Why top-level, not `docs/`

- The branch split is enforced by hand (no CI, no sync script): what keeps dev
  material off the default branch is a known list of paths. `docs/` shipped
  entirely except for `BUILD-LOG.md`, and that single exception was the only
  wart in the split.
- Everything dev-only is already top-level except that one file
  (`AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md`, `skills/`, `PLAN.md`,
  `QUESTIONS.md`, `orchestration/`).
- Sync is one-way and fast-forward (`master` → `dev`), so a new dev-only
  top-level directory costs nothing to keep.

## Deliverables

1. `worknotes/README.md` — the contract: what belongs here, what never does.
2. `worknotes/INDEX.md` — one row per feature, the entry point.
3. `worknotes/TEMPLATE/` — the four fixed files to copy.
4. Feature folders, migrated from the retired archive with content unedited:
   `2026-09-15-build`, `2026-09-16-marketplace-submission`,
   `2026-09-17-advanced-polling`, `2026-09-17-in-panel-refresh`, plus
   `BACKLOG.md` (the roadmap note).
5. `orchestration/BUILD-LOG.md` — the build audit trail moves out of the shipped
   `docs/` tree, with every live reference updated.
6. `AGENTS.md` — WORK RECORDS block rewritten (in-repo, no vault), structure and
   entry-point rows added, revalidated.
7. Mirrors updated in the same change: `CONTRIBUTING.md`, `README.md`, `PRD.md`,
   `docs/ARCHITECTURE.md`, `CHANGELOG.md`, `skills/README.md`,
   `.github/PULL_REQUEST_TEMPLATE.md`, `orchestration/AGENTS.md`.
8. `DEVIATIONS.md` **R12** — the process change needs a ruling, otherwise it
   contradicts R11 standing text.
9. `.githooks/pre-commit` — the only mechanical guard available (there is no CI):
   refuse a commit on the default branch that touches a dev-only path.

## Verification

- every migrated note is present in its target file, checked by comparing the
  normalised text of each source against the target (19 sources);
- no Obsidian-style wikilink survives in `worknotes/` (verified by grep);
- `bash tests/run-all.sh` green, `omarchy plugin validate .` exit 0,
  `bash -n bin/omafan-ctl bin/omafan-keybindings` clean;
- the hook is exercised on a scratch clone in both directions (refuses on the
  default branch, allows on `dev`);
- no dangling `docs/BUILD-LOG.md` reference outside historical records.

## Out of scope

- `orchestration/` stays exactly as it is: it is the frozen build-era record and
  its own `AGENTS.md` forbids retroactive edits.
- afanctl's hardware poll interval (the standing scope ruling — see
  [INDEX.md](../INDEX.md)).
