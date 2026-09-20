# worknotes/ — the development record

Everything done *to* omafan is recorded here, in the repository, on the `dev`
branch. One folder per piece of work; four fixed files inside it.

This tree is development material. It is **never** merged into the default
branch: `omarchy plugin add` clones the whole repository into a user's
`~/.config/omarchy/plugins/<id>`, so the default branch carries the plugin, its
tests and the operator documentation only (ruling R11 in
[DEVIATIONS.md](../DEVIATIONS.md), extended by R12).

## The rule

| Belongs here | Never here |
|---|---|
| plans, tickets, scoping decisions | anything a user of the plugin needs (that is `README.md` and `docs/`) |
| evidence: commands run and what they printed | secrets, tokens, credentials |
| findings, review verdicts, dispositions | secrets-adjacent machine detail (serial numbers, MACs) |
| completion summaries and open items | the frozen build-era record (that is `orchestration/`) |
| the roadmap ([BACKLOG.md](BACKLOG.md)) | personal scratch that does not concern omafan |

`worknotes/` **supplements** repository documentation, tests, `CHANGELOG.md` and
`DEVIATIONS.md` rulings — it never replaces them. A contract change still needs
its `DEVIATIONS.md` entry; a behaviour change still needs its test.

## Layout

```
worknotes/
├── README.md      # this file — the contract
├── INDEX.md       # one row per feature: the entry point
├── BACKLOG.md     # the roadmap: what is done, what is next
├── TEMPLATE/      # copy this to start a feature folder
└── <YYYY-MM-DD>-<slug>/
    ├── PLAN.md
    ├── LOG.md
    ├── REVIEW.md      # optional
    ├── SUMMARY.md
    └── ASK.md         # optional — the operator's verbatim ask
```

Folder names are dated by when the work started, so a file listing sorts
chronologically. Repeated work on one feature appends to that feature's folder;
it does not open a second one.

| File | Holds | Written |
|---|---|---|
| `PLAN.md` | scope, decisions, tickets, acceptance criteria, out-of-scope | before implementation |
| `LOG.md` | chronological evidence: commands and their real output, decisions with their reason, dead ends | as the work happens |
| `REVIEW.md` | findings, verdicts, dispositions of review or recon | when reviewing |
| `SUMMARY.md` | what shipped, the commit, gates run, open items | at the end |
| `ASK.md` | the operator's verbatim ask | at the start, when the ask is a note |

## Frontmatter

Every file starts with it. `status` uses one vocabulary repo-wide so the state of
work is greppable and never ambiguous:

```yaml
---
feature: advanced-polling      # the folder slug, without the date
status: active                 # planned | active | blocked | done | unverified
branch: dev                    # the branch the work is on
opened: 2026-09-17             # when the feature folder was opened
updated: 2026-09-17            # last touch of this file
related:                       # what a reader should open next
  - DESIGN.md
  - DEVIATIONS.md (R9)
---
```

`unverified` is a real status, not a euphemism for `done`: use it when the work
exists but its verification did not happen (no hardware run, no live check).

## Conventions

- **Evidence or it did not happen.** Quote the command and its output. "Tests
  pass" is not evidence; `PASS 26 / FAIL 0` is.
- **Distinguish planned, active, blocked, done, unverified.** Never let a plan
  read as if it landed.
- **Links are relative** to the file that contains them, and they must resolve.
  `docs/` exists on both branches, so worknotes may link into it; the reverse is
  not true — shipped docs may *name* `worknotes/` in prose but must never link
  relatively into it (the link would 404 on the default branch).
- **No absolute home paths.** A path that only exists on the maintainer's machine
  is not documentation; it is also what R11 had to purge from `DESIGN.md §9`.
- **One topic per file.** If a `LOG.md` grows past a few screens, the feature was
  probably two features.
- Sections are appended under `## <what happened> — <date>`; new material goes at
  the bottom of `LOG.md`, so the file reads as a timeline.

## Starting a new piece of work

```sh
cp -r worknotes/TEMPLATE worknotes/$(date +%F)-<slug>
$EDITOR worknotes/INDEX.md      # add the row
```

Then keep `LOG.md` current while you work and finish with `SUMMARY.md`. If the
work changes behaviour a user can see, it also needs its `CHANGELOG.md` entry; if
it contradicts `DESIGN.md`, it needs a ruling first — see
[skills/change-a-frozen-contract](../skills/change-a-frozen-contract/SKILL.md).

## What is not here, and why

- `orchestration/` is the build-era record (ticket cards, ledger, the two
  adversarial reviews, the dispatch tools). It is frozen: its own `AGENTS.md`
  forbids retroactive edits. Work after the build belongs in `worknotes/`.
- `orchestration/BUILD-LOG.md` is the phase-by-phase audit trail of that build,
  which is why it lives with the build record and not in `docs/`.
- The maintainer's external note vault was retired for this repository on
  2026-09-20. Its omafan notes were migrated here with their content unedited —
  each section names the archive path it came from — and nothing was left behind
  as a pointer.
