---
feature: schema-negotiation
status: active
branch: feat/schema-negotiation
opened: 2026-09-24
updated: 2026-09-24
related:
  - DESIGN.md (frozen: §4.1 status document, §4.3 error envelope)
  - DEVIATIONS.md (new ruling)
  - https://github.com/yadav-prakhar/omafan/issues/4
  - https://github.com/yadav-prakhar/afanctl/issues/8
---

# Schema negotiation instead of string equality

GitHub issue [#4](https://github.com/yadav-prakhar/omafan/issues/4), P1 in the
epic [#1](https://github.com/yadav-prakhar/omafan/issues/1). It is the single
change that unblocks afanctl's contract v2
([afanctl#8](https://github.com/yadav-prakhar/afanctl/issues/8)): until it lands,
every installed plugin hard-fails on `.schema == "afanctl.status.v1"`.

The ask: replace hard string-equality schema checks with version negotiation, so
the contract can evolve without breaking installed plugins.

## The problem

Two independent `==` checks turn a schema bump into a hard failure:

- `bin/omafan-ctl:275` refuses an `afanctl.status.v1` daemon that emits
  `afanctl.status.v2`.
- `Model.js:214` refuses an `omafan.status.v1` document the moment the plugin's
  own schema moves.

A version bump on either side is a hard failure, not a negotiation.

## Decisions taken

| # | Question | Decision |
|---|---|---|
| 1 | Where does version parse/select live? | Pure functions in `Model.js` (`parseSchemaId`, `selectSchema`), ES5-only, no I/O, so `tests/model.test.mjs` exercises the whole matrix with no QML and no daemon. |
| 2 | Does `bin/omafan-ctl` get a second copy? | It mirrors the same rule in one bash helper (`schema_check`) used by both the status read and the `state.json` read, exactly as the preset ladder is already mirrored between `Model.js` and the CLI. There is no second, ad-hoc comparison left in the file. |
| 3 | How is "highest mutually understood" implemented for a real daemon? | If the emitted schema is newer than the plugin's maximum **and** the daemon advertises an understood id (`schema_supported`), re-request it with `status --json --schema <id>`. A failed re-request falls back to the emitted document with the newer-schema notice. |
| 4 | Newer-unknown vs older-unsupported | Newer than the plugin's max ⇒ accept, render every recognised field, add one `warnings[]` entry naming the plugin update. Older than the plugin's min ⇒ refuse (exit 1) naming the afanctl update. Missing/malformed ⇒ refuse naming the schema seen. |
| 5 | Does `omafan.status.v1` change? | No. The change is tolerance, not a bump. `parseStatus` tolerates a newer `omafan.status.v*` with a `notice`, but the CLI still emits v1 byte-for-byte. |
| 6 | Is `afanctl.state.v*` in scope? | Yes — the shared contract v2 bumps the state file too, and `read_state` is the other hard `==`. It uses the same helper and the same newer/older rules, so a v2 state degrades instead of failing `status` and every write. |

## Scope

- In scope: `Model.js` (`parseSchemaId`, `selectSchema`, `parseStatus`);
  `bin/omafan-ctl` (`query_afanctl_status`, `read_state`, the `doctor` write-path
  probe); `tests/fixtures/fake-afanctl` (schema-version switch and `--schema`);
  `tests/fixtures/status-*.json`; `tests/model.test.mjs`; `tests/ctl.test.sh`;
  `DEVIATIONS.md`; `DESIGN.md` §4.1 note; `CHANGELOG.md`; this worknote.
- Out of scope: the adaptive control widget that consumes the v2 `fans` array /
  `control` union (a separate epic item). This change does not teach omafan to
  *use* v2 fields; it stops a v2 daemon from breaking a v1 plugin.
- Out of scope: landing anything in the afanctl repository. afanctl#8 stays
  blocked until this merges.

## Tickets / steps

| # | Step | Done when |
|---|---|---|
| 1 | `Model.js` parse/select + `parseStatus` tolerance | `node tests/model.test.mjs` green with the matrix cases |
| 2 | `fake-afanctl` schema switch + `--schema` | `bash tests/ctl.test.sh` can select every schema case |
| 3 | `omafan-ctl` status/state negotiation | `bash tests/ctl.test.sh` green with the CLI matrix |
| 4 | Ruling, docs, changelog | R14 in `DEVIATIONS.md`; `DESIGN.md` §4.1 note; `CHANGELOG.md` Unreleased |
| 5 | Full gate | `tests/run-all.sh` 9/9; `omarchy plugin validate .` |

## Risks and traps

- `Model.js` is both QML-imported and `new Function`-eval'd; it must stay
  ES5-only (`var`/function, no arrow, no template literal, no `Object.assign`).
  The model suite asserts this — a helper that sneaks in a modern form turns the
  suite red.
- `omafan.status.v1` must stay byte-compatible: `tests/ctl.test.sh` asserts the
  schema id and every field. The negotiation must not add keys to the document.
- `fake-afanctl` fixtures pin the daemon contract. The schema switch must be
  additive; the existing `FAKE_AFANCTL_MODE` matrix and the default v1 output
  must not move.
- A re-request (`--schema`) must never turn a working v1 daemon into a failure:
  it only fires when the emitted schema is newer than the max, and a failed
  re-request falls back to what was emitted.
- `tests/ctl.test.sh` needs unprivileged user namespaces (issue #11); if they
  are missing the whole suite misdiagnoses. They work on this machine.

## Verification plan

- `node tests/model.test.mjs` — the pure matrix: exact, older-but-supported,
  newer-unknown, far-older, missing, malformed, plus the v2-with-unknown-fields
  render.
- `bash tests/ctl.test.sh` — the CLI against `fake-afanctl`'s schema switch,
  including `omafan.status.v1` still emitted unchanged.
- `tests/run-all.sh` — all 9 suites.
- `omarchy plugin validate .` — structural plugin gate.
- Hardware-free by construction: no `/sys`, no daemon, no root.
