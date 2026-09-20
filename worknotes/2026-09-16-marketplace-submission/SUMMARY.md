---
feature: marketplace-submission
status: active
branch: dev
opened: 2026-09-16
updated: 2026-09-20
related:
  - README.md
  - docs/PUBLISHING.md
  - AGENTS.md
---

# Marketplace submission

omafan's submission to the Omarchy plugin marketplace:
[omacom/omarchy-plugin-marketplace#7174](https://github.com/omacom/omarchy-plugin-marketplace/issues/7174).
Status: submitted 2026-09-16, validation green and security baseline yellow
(four flagged capabilities, all false positives, explained in a comment);
awaiting maintainer review.

| File | What it is |
|---|---|
| `SUMMARY.md` | what was submitted and the bot results |
| [LOG.md](LOG.md) | the thread: validation refresh after the default branch moved, then the root-`AGENTS.md` objection and the `dev`-branch split (ruling R11) |

## 2026-09-16 — Marketplace submission

*Migrated from the pre-`worknotes/` archive note `2026-09-16-marketplace-submission.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

**Status:** submitted, awaiting maintainer approval
**Issue:** https://github.com/omacom/omarchy-plugin-marketplace/issues/7174

## What was submitted

`[Plugin]: omafan — fan control for pre-T2 Intel Macs` via the `submit-plugin.yml` form (recreated as an issue body through `gh issue create` — fields: Repository URL, Category, Tags, notes, checklist).

- **Category:** Hardware
- **Tags:** Power management, Bar, Quickshell
- **Suggested tag:** Hardware (none covers fan/thermal)
- **Notes covered:** afanctl ≥ 0.1.0 as documented prerequisite (not bundled), install/remove commands, privilege surface (reads unprivileged, writes via afanctl's existing polkit rule, no new surface), undercooling guard, hardware scope (pre-T2 Intel Macs / applesmc), validation evidence. Cross-referenced omacom/omarchy-pkgs#476 (afanctl packaging PR, still OPEN) so reviewers know step 1 will shorten.

## Verified before filing

- `omarchy plugin validate .` → exit 0
- `tests/run-all.sh` → 6/6 suites PASS
- Repo public, GPL-3.0, manifest at root, README documents install (`omarchy plugin add … --enable`, line 61) and removal (`omarchy plugin remove …`, line 293), afanctl dependency, privilege boundary
- Local HEAD == origin/master (c37fa5a), clean tree — the marketplace validates the current commit

## Automated results (both green/yellow, same day)

- **Marketplace validation:** all checks passed, "Ready for listing review" (commit c37fa5a).
- **Security baseline 🟡:** `manual review required` — four capability flags, all false positives:
  - service-management: Model.js error hints *mention* `systemctl restart afanctl`; never invoked
  - privilege: README + Panel.qml:76 (an argv flag-name list the CLI *refuses* on writes); real writes ride afanctl's polkit rule
  - package-manager: omafan-ctl:1309 error hint "install jq (pacman -S jq)"; pacman never run
  - installer: `orchestration/live-install.sh` — build-era orchestrator tool, never executed by the plugin
- Posted clarifying comment: https://github.com/omacom/omarchy-plugin-marketplace/issues/7174#issuecomment-5696227629 — explains each flag, offers to move `orchestration/` if reviewers prefer.

## Next steps

- Wait for maintainer review of the baseline flags; comment already preempts the questions.
- If omarchy-pkgs#476 merges first, update the submission notes so the afanctl step can become a package install.
- After listing: README badge/hero already reference the plugin; no repo changes needed unless a reviewer asks.
