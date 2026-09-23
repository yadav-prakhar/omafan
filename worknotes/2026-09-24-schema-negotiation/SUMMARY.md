---
feature: schema-negotiation
status: active
branch: feat/schema-negotiation
opened: 2026-09-24
updated: 2026-09-24
---

# SUMMARY — schema negotiation (omafan#4)

## What shipped

Hard string-equality schema checks are replaced by family+version negotiation
on both sides of the contract:

- `Model.js` — pure `parseSchemaId` / `selectSchema` / `statusNotice`, used by
  `parseStatus` for `omafan.status`. A newer emitted schema renders with a
  `notice`; an older one is refused; a missing/malformed one is refused.
- `bin/omafan-ctl` — one `schema_check` helper for the afanctl status document,
  `state.json` and the doctor probe. A newer schema degrades with one
  `warnings[]` notice; an older/missing/malformed one is refused (exit 1, and
  writes refuse with their existing `limits_unavailable`). A newer daemon that
  still advertises an understood version is re-asked with
  `status --json --schema <id>`.
- `omafan.status.v1` is emitted byte-for-byte unchanged.
- `tests/fixtures/fake-afanctl` gained `FAKE_AFANCTL_SCHEMA` and `--schema`;
  `tests/model.test.mjs` and `tests/ctl.test.sh` pin the matrix.

This is the change that unblocks afanctl's contract v2 (afanctl#8) without
breaking installed plugins.

## Acceptance criteria (issue #4)

| # | Criterion | Where proved |
|---|---|---|
| 1 | Pure parse/select in `Model.js`, ES5-only | `Model.js`; `tests/model.test.mjs` (204 pass, incl. the ES5 purity asserts) |
| 2 | `bin/omafan-ctl` uses the same rules, no second comparison | one `schema_check` used by status/state/doctor; `tests/ctl.test.sh` §22 |
| 3 | Fixtures: exact, older-but-supported, newer-unknown, far-older, missing, malformed | `fake-afanctl` schema switch + `model.test.mjs` matrix |
| 4 | `fake-afanctl` schema switch | `FAKE_AFANCTL_SCHEMA` |
| 5 | v2 doc with unknown fields still renders the recognised ones | `model.test.mjs` (v2 parse), `ctl.test.sh` 22c (band/sensors/temp render) |
| 6 | `omafan.status.v1` unchanged | `ctl.test.sh` 22a–22d assert the schema id; existing §1 tests unchanged |
| 7 | `DEVIATIONS.md` ruling | R14 |

## Gates run

```
$ tests/run-all.sh
PASS suites 9 / FAIL suites 0 / SKIP 0
```

`node tests/model.test.mjs` → `PASS 208 / FAIL 0`.
`bash tests/ctl.test.sh` → `PASS 279 / FAIL 0`.
`omarchy plugin validate .` (suite 1) → PASS.

## Open items

- Contract v2 is not landed; `fake-afanctl` models the proposed afanctl#8 shape.
  Real-daemon verification of the `--schema` request happens when afanctl#8
  lands, on this machine.
- The adaptive control widget (v2 `fans`/`control`) is a separate epic item.
- Commit/push/PR: left to the operator (branch `feat/schema-negotiation`).
