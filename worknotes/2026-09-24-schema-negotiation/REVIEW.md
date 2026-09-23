---
feature: schema-negotiation
status: active
branch: feat/schema-negotiation
opened: 2026-09-24
updated: 2026-09-24
---

# REVIEW — schema negotiation (omafan#4)

Two-axis review (`/code-review`) of `git diff dev`, run as two parallel
sub-agents: Standards (repo conventions + Fowler smell baseline) and Spec (issue
#4 + afanctl#8).

## Findings and dispositions

| # | Axis | Finding | Disposition |
|---|---|---|---|
| 1 | both | The doctor write-path probe used a third, inline regex comparison instead of `schema_check`, contradicting R14's "one helper" and accepting `afanctl.status.v0`/`.v99` as PASS. | **Fixed.** The probe now calls `schema_check` with the same family/min/max; an unsupported schema is a distinct FAIL. |
| 2 | spec | "Select the highest mutually understood version from `schema_supported`" was only applied when the emitted schema was newer; an older emitted default advertising a newer supported version was refused without a re-request. | **Fixed.** The mutual id is computed and re-requested whenever it differs from the emitted one. `fake-afanctl` gained `v0-compat` and ctl.test.sh 22e-bis pins it. |
| 3 | standards | The new re-request had no timeout, against "every external call is bounded". | **Fixed.** Both the status read and the re-request are bounded with `PROBE_TIMEOUT_S`. |
| 4 | standards | Model.js returned `none` where the CLI said `unknown` for the same state (name drift). | **Fixed.** Model.js now returns `unknown`; tests updated. |
| 5 | spec | The state-schema refusal did not name the fix the way the status one does. | **Fixed.** An older `afanctl.state.v*` now refuses with "update afanctl". |
| 6 | spec | `parseStatus`'s `notice` was never consumed; the panel rendered neither it nor the CLI's `warnings[]`, so the "single quiet notice" was not shown. | **Fixed.** New pure `Model.statusNotice` (the first schema warning) plus a low-precedence panel banner line; `parseStatus`'s notice feeds the same property. |
| 7 | spec | `parseStatus` passes only the emitted schema, never `schema_supported`. | **Accepted as designed.** The panel has no request channel, so the emitted document governs; the comment in `parseStatus` records why. |
| 8 | standards | Adding v2 requires editing several mirrored bash constants. | **Accepted.** This is the existing two-language mirror (as the preset ladder is); a shared data file cannot be imported by both bash and QML. Noted, not changed. |
| 9 | standards | Duplicated notice wording / Data Clumps in `schema_check`'s params. | **Accepted.** The CLI and panel word the notice for different surfaces; the params are a small positional signature, not a type worth inventing in bash. |

## Gates after the fixes

```
$ node tests/model.test.mjs      → PASS 208 / FAIL 0
$ bash tests/ctl.test.sh         → PASS 279 / FAIL 0
$ tests/run-all.sh               → PASS suites 9 / FAIL suites 0 / SKIP 0
```
