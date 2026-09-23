# worknotes — index

Every piece of work on omafan, newest last. Each folder holds fixed files:
`PLAN.md`, `LOG.md`, `REVIEW.md` (optional), `SUMMARY.md`, `ASK.md` (optional).
What belongs here and what does not: [README.md](README.md).

| Work | Folder | Status | Opened | Updated |
|---|---|---|---|---|
| The one-night build — what shipped and what was verified | [2026-09-15-build](2026-09-15-build/SUMMARY.md) | done | 2026-09-15 | 2026-09-15 |
| Marketplace submission #7174 — validation, security flags, the `dev`-branch split (R11) | [2026-09-16-marketplace-submission](2026-09-16-marketplace-submission/SUMMARY.md) | active — awaiting maintainer | 2026-09-16 | 2026-09-20 |
| Slider Auto-reset + Advanced polling control (R9) | [2026-09-17-advanced-polling](2026-09-17-advanced-polling/SUMMARY.md) | done | 2026-09-17 | 2026-09-17 |
| In-panel refresh row — Auto/Custom + stepper (R10) | [2026-09-17-in-panel-refresh](2026-09-17-in-panel-refresh/SUMMARY.md) | done | 2026-09-17 | 2026-09-17 |
| The development record moves into the repository (R12) | [2026-09-20-in-repo-worknotes](2026-09-20-in-repo-worknotes/SUMMARY.md) | done | 2026-09-20 | 2026-09-20 |
| `dev` as integration branch, filtered release to `master` (R13, issue #2) | [2026-09-21-branch-model](2026-09-21-branch-model/SUMMARY.md) | done | 2026-09-21 | 2026-09-21 |
| Schema negotiation instead of string equality (R14, issue #4) | [2026-09-24-schema-negotiation](2026-09-24-schema-negotiation/SUMMARY.md) | active | 2026-09-24 | 2026-09-24 |

The roadmap — what is done and what is next — is [BACKLOG.md](BACKLOG.md).

## Where to look

| Question | File |
|---|---|
| What is the state of the current work? | the folder's `LOG.md`, bottom section |
| What did we decide and why? | the folder's `PLAN.md`, then `DEVIATIONS.md` for the ruling |
| What exactly was run, and what did it print? | the folder's `LOG.md` |
| What shipped, and what is still open? | the folder's `SUMMARY.md` |
| Why is the code shaped like this? | `DESIGN.md` (frozen), `docs/ARCHITECTURE.md`, `orchestration/` for the build |
| How do I run the gates? | [skills/run-the-gates](../skills/run-the-gates/SKILL.md) |

## Standing rulings that bind new work

- **Polling scope.** The Advanced polling control governs how often **omafan
  re-reads the daemon's status** (`poll_seconds` → `Panel.qml` timer). afanctl's
  own hardware poll interval (`[poll] interval_s`) is **out of scope, future
  work** — the two are never conflated. Evidence: [the afanctl polling
  survey](2026-09-17-advanced-polling/LOG.md).
- **`DESIGN.md` is frozen.** Contradicting behaviour needs a `DEVIATIONS.md`
  entry *before* the code moves, with the ruling id in the commit body.
- **Never claim an unrun check.** `unverified` is a legitimate status; a green
  claim without output is not.
- **Nothing on the shipped branch.** `master` carries the runtime, its tests and
  the operator documentation only; `dev` is the integration and default branch,
  and a release is a curated sync, never a merge. See [README.md](README.md) and
  rulings R11 (the guarantee) and R13 (the mechanism).
