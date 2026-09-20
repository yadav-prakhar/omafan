---
feature: marketplace-submission
status: active
branch: dev
opened: 2026-09-16
updated: 2026-09-20
related:
  - 2026-09-16-marketplace-submission/SUMMARY.md
  - DEVIATIONS.md
---

# Log — marketplace submission

Chronological, newest last. Each entry is the migrated evidence note.

## marketplace submission #7174: snapshot refresh (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-17-marketplace-7174-snapshot-refresh.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Issue: omacom/omarchy-plugin-marketplace#7174 (omafan submission).

## Maintainer comment (HANCORE-linux, 2026-09-16)

Validation + security baseline were bound to `c37fa5a` while the default
branch had moved (`484fb4d`, then our `fd62b55`); fresh validation was
required against the current full SHA before approval could proceed.

## Actions taken

1. Committed the working tree as `fd62b55`
   (`feat(panel): advanced polling control and in-panel refresh row`) and
   pushed to origin/master.
2. Read the marketplace workflows to find the re-trigger:
   `route-issue-automation.yml` fires on issue **edited** (among others) and
   routes `[Plugin]:`-titled issues to `validate-submission` (workflow_call)
   which re-scans the default-branch HEAD and posts/updates the two bot
   reports in place.
3. Edited the submission body (added §3 "Validation snapshot" describing
   `fd62b55` and why no new privilege surface exists) — this re-ran
   validation (run 35197931817: RESULT=validated, BASELINE=review-required).
4. Commented on the thread twice: once with the fresh snapshot summary for
   the maintainer, once after the reports refreshed.

## Result (verified by reading the issue back)

- ✅ Marketplace validation: "Quattro compatibility passed at commit
  `fd62b55`" — Ready for listing review.
- 🟡 Security baseline re-scanned at `fd62b55`: Manual review required —
  same four capability flags as before (service-management strings,
  privilege mentions, package-manager string, orchestration installer); our
  clarification comment covers them.
- Labels now: `submission`, `validated`, `security-review-required`.
- Waiting on: maintainer's capability review → `approved-and-verified` →
  listing.

## marketplace submission #7174: root `AGENTS.md` objection → `dev` branch split (2026-09-20)

*Migrated from the pre-`worknotes/` archive note `logs/2026-09-20-marketplace-7174-agents-md-and-dev-branch.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Issue: omacom/omarchy-plugin-marketplace#7174 (omafan submission).
Follows: [the snapshot-refresh log](LOG.md).

## Where the thread stood

Both bot reports had already been re-run and were bound to `fd62b55`
(updated 2026-09-17 14:36Z): ✅ validation, 🟡 security baseline
(`privilege`, `package-manager`, `service-management`, `installer` capabilities).
The verify-plugin form attempt (#7366) dead-ended — "the plugin ID does not
identify an existing community listing" — so the open submission issue is the
only route.

## The blocking comment (HANCORE-linux, 2026-09-17T23:42Z, collaborator)

> `AGENTS.md:65-80` is a root-level agent instruction file in the plugin
> checkout and directs agents to create and maintain work records under
> `/home/prakhar/Documents/...`, outside the plugin. Because the marketplace
> installs the repository tree, agent tooling that discovers root `AGENTS.md`
> can automatically interpret these instructions, causing unintended external
> writes and instruction injection from installed plugin content. Please remove
> the root `AGENTS.md` (and any agent instruction files/skills that are not
> required runtime plugin assets) from the distributed plugin tree, or package
> an allowlisted runtime-only subtree that excludes them, then trigger
> validation for the new commit.

## Premises checked before acting

| Claim / assumption | Verdict |
|---|---|
| Install copies the whole tree | **True.** `/usr/share/omarchy/bin/omarchy-plugin-add:120-146` — `git clone <url>` into `~/.config/omarchy/plugins/<id>` |
| `omarchy plugin validate` polices extra files | **No** — manifest schema only; this is a listing policy, not a mechanical gate |
| The automated baseline flagged the md files | **No.** `security-baseline-scope.mjs` scans code extensions only and excludes `.github`, `docs`, `tests`, `fixtures`, `spec*`, `node_modules`; `*.md` is never scanned. The objection is human judgment — arguing the scanner verdict was pointless |
| A runtime-only subtree inside one repo is possible | **No.** Marketplace requires `manifest.json` at the repo root and installs default-branch HEAD, so that option means a second repo or a non-default branch |
| Something in the repo consumes the flagged files | **No.** No test, QML or script reads `AGENTS.md` or `skills/` — the 8-suite gate is unaffected |

## Decision (operator, 2026-09-20)

Keep the development material on a **`dev` branch**; the default branch ships
the runtime plus user documentation. Nothing was rewritten in history — the
objection is about the distributed working tree, and rewriting would break the
validation-SHA binding.

## What changed

`master` — commit `57d5f63` `docs(repo): ship the runtime and docs, keep
development material on `dev`` (48 tracked files: QML, `Model.js`, `bin/`,
`tests/`, `docs/`, `manifest.json`, `README.md`, `LICENSE`, `PRD.md`,
`CONTRIBUTING.md`, `SECURITY.md`, `DESIGN.md`, `DEVIATIONS.md`, `CHANGELOG.md`,
`.github/`, `preview.png`):

- removed `AGENTS.md`, `bin/AGENTS.md`, `tests/AGENTS.md`, `skills/`,
  `PLAN.md`, `QUESTIONS.md`, `docs/BUILD-LOG.md`, `orchestration/`;
- `DESIGN.md` §9 (the paste-verbatim subagent briefing that carried an absolute
  `/home/prakhar/...` path) retired; header/§2/§7 provenance retargeted; §10's
  suite list corrected to the real eight suites. Recorded as **ruling R11** in
  `DEVIATIONS.md`;
- `README.md`, `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`: the branch
  split documented, references to removed files dropped, the §9 conventions that
  were still useful (dependencies, error model, style) folded into
  `CONTRIBUTING.md` §"Code conventions", stale "6 suites" line fixed;
- `docs/ARCHITECTURE.md`, `docs/SAFETY.md`, `docs/PUBLISHING.md`, `PRD.md`:
  build-record pointers to `dev`, public afanctl URL instead of the local
  checkout path, no operator/agent-directed leftovers.

`dev` — commit `e24c33a` `chore(dev): keep the development record and agent
notes on this branch` (= `master` + exactly 46 dev-only paths, listed by
`git diff --name-only master dev`). Its `AGENTS.md` now states the branch
contract and the one-way sync `git checkout dev && git merge --ff-only master`.

## Evidence

`bash tests/run-all.sh` on both branches — 8/8, no SKIP (plugin-validate and
qml-lint both real, not skipped):

```
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

Also verified: no `AGENTS.md`/`CLAUDE.md`/`SKILL.md`/copilot/cursor file remains
on `master`; no setup- or install-named script remains on `master` (so the
`installer` capability that `orchestration/live-install.sh` triggered should
disappear from the next baseline); no stale commit SHAs anywhere in either tree.

## Status

- **Done locally, unverified publicly:** `master` is 1 commit ahead of
  `origin/master`; `dev` exists locally only. Nothing pushed, no comment posted
  (operator instruction).
- Not yet done: push, re-trigger validation, maintainer reply.

## Next actions (operator)

1. `git push origin master` then `git push origin dev`.
2. Edit the submission body §3 with the new full SHA
   `57d5f6302bec082a99cb9460408f86cb53aad554` to re-trigger validation + baseline.
3. Read the refreshed bot reports back (validation should still pass; the
   `installer` capability should be gone).
4. Reply to HANCORE-linux once: list what left the tree, name the new SHA and the
   `dev` branch, note that no runtime file, privilege surface or manifest entry
   changed.

## Open follow-ups

- The `spike/modular-daemon-support` worktree (`~/Work/tries/omafan-modular-daemon-support`,
  at `fd62b55`) still contains the dev material in its tree — do not merge it into
  `master` as-is.
- `dev`'s `AGENTS.md` still names the Obsidian vault path (the operator's own
  working convention). It is public on GitHub, though not installed; genericise it
  if that is unwanted.
- `PRD.md` stayed on `master` deliberately: shipped docs cite requirement ids
  (`PRD F5`, `PRD §2.7`, …). If the reviewer wants requirements off the listed
  tree too, moving it means retargeting ~20 references.
- Hermes skill `omafan-repo-work` created so the branch contract, the gate and the
  vault work-record rule survive the loss of the in-repo `AGENTS.md`.
