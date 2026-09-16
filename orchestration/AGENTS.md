# orchestration/

## OVERVIEW
Build history, not runtime: the record of how this repo was built by dispatched worker subagents. Nothing here ships with or runs in the plugin.

## STRUCTURE
```
tickets/        one card per build ticket (T01..T16 plus lettered sub-tickets)
instructions/   WORKER.md, the briefing every worker subagent read first
LEDGER.md       distilled flight recorder, one line per dispatch/verify/ruling/commit
REVIEW-R*.md    adversarial review verdicts (T15, T16)
TRIAGE-R*.md    disposition of each review finding (accepted, fixed, open)
QUESTIONS.md    worker objections and cross-file change requests
dispatch.sh     orchestrator tool: ran one OpenCode worker per ticket in parallel
live-install.sh orchestrator tool: install/verify/remove the working tree in the live shell
logs/           raw worker transcripts (gitignored)
backups/        shell.json backups made by live-install.sh (gitignored)
```

## WHERE TO LOOK
| Question | File |
|---|---|
| What happened, condensed | `LEDGER.md` (newest first) |
| What a ticket asked | `tickets/<ID>.md`, the card is authoritative |
| How a review finding was handled | `TRIAGE-R1.md` / `TRIAGE-R2.md` |
| What reviewers rejected | `REVIEW-R1.md` / `REVIEW-R2.md` |
| Worker rules of engagement | `instructions/WORKER.md` |
| Why a contract changed | `DEVIATIONS.md` (repo root), then the ticket card |

## CONVENTIONS
- Ticket ids: `TNN`; sub-tickets append a letter (`T02b`, `T04b/c/d`, `T05b`, `T06b`, `T09b/c`). A lettered card is a follow-up fixing or extending its parent.
- Numbering gap: T14 landed as orchestrator-owned work with no card; `tickets/` having no `T14.md` is expected.
- Log naming mirrors the card: `logs/<TICKET>.log`; `logs/_summary.txt` holds one verdict line per dispatch run.
- LEDGER line format: `<time> <actor> <event> — <evidence command> — <result>` (em dashes), newest first; rulings referenced by id (R1..R8, defined in root `DEVIATIONS.md`).
- `dispatch.sh` usage form: `TICKET:MODEL[:VARIANT]`; it refuses nothing itself, so ownership discipline came from the orchestrator, not the script.
- `live-install.sh` verbs: `install|verify|remove|revert`; backs up the operator's `shell.json` into `backups/` before any change and rsync-excludes `logs/` from the installed copy.

## ANTI-PATTERNS
- NEVER treat tickets as live work orders. The build is done; cards are history, not a backlog.
- NEVER read `logs/` unless diagnosing a specific past build step; `LEDGER.md` is the distilled record and answers first.
- NEVER ship `logs/` or `backups/`: both are gitignored, and `live-install.sh` already excludes logs from the plugin copy.
- NEVER edit a ticket card retroactively; corrections belong in `LEDGER.md` or root `DEVIATIONS.md`.
- NEVER run `dispatch.sh` or `live-install.sh` during normal development; they are build-era orchestrator tools, and `live-install.sh` touches the operator's live `shell.json`.
- Do not add new tickets here; new work follows the repo's normal flow, not this directory.
