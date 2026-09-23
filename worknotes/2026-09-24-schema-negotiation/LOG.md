---
feature: schema-negotiation
status: active
branch: feat/schema-negotiation
opened: 2026-09-24
updated: 2026-09-24
---

# LOG — schema negotiation (omafan#4)

Chronological evidence. Commands are run from the repository root.

## 0. Baseline on `dev`

```
$ git checkout -b feat/schema-negotiation dev
Switched to a new branch 'feat/schema-negotiation'

$ tests/run-all.sh
PASS suites 9 / FAIL suites 0 / SKIP 0
```

This machine has `omarchy` and `qmllint`, so no suite is skipped (issue #13's
gap does not apply here).

## 1. TDD red — the pure rule (model.test.mjs)

Added `SCHEMA_NAMES = ["parseSchemaId", "selectSchema"]` and the matrix to
`tests/model.test.mjs` first. Before `Model.js` grew the functions:

```
$ node tests/model.test.mjs
FATAL: Model.js could not be evaluated: parseSchemaId is not defined
```

## 2. Green — `Model.js`

`parseSchemaId` splits `<family>.v<major>`; `selectSchema` returns
`match|newer|older|none`; `parseStatus` uses it for `omafan.status` (the emitted
version governs, because the panel has no request channel).

```
$ node tests/model.test.mjs
PASS 208 / FAIL 0
```

## 3. TDD red — the CLI rule (ctl.test.sh)

Added `run_schema <schema> <mode> <args...>` and section 22 to
`tests/ctl.test.sh`. The suite was red until `fake-afanctl` grew the
`FAKE_AFANCTL_SCHEMA` switch and `bin/omafan-ctl` grew `schema_parse` /
`schema_check`.

## 4. Green — the CLI

`fake-afanctl` now reports a schema selected by `FAKE_AFANCTL_SCHEMA`
(`v1 | v1-supported | v2-newer | v2-compat | v0-older | missing | malformed`),
derived from the existing v1 fixtures with jq (per `tests/AGENTS.md`: add a
render case, not a third fixture). It accepts `status --json --schema <id>` and
logs read argv to `$RUN/status-argv.log`.

`bin/omafan-ctl`:
- one `schema_check <family> <min> <max> <id>` helper used by the status read,
  the state read and the doctor probe;
- `query_afanctl_status` sets `$queried_status` instead of printing, so its
  `warnings[]` land in the caller (a command substitution would drop them —
  the same subshell hazard that once leaked scratch files);
- a newer daemon that advertises an understood version is re-asked with
  `status --json --schema <id>`;
- `add_warning` is now idempotent, so a run that negotiates twice shows one
  notice, not two.

```
$ bash tests/ctl.test.sh
PASS 279 / FAIL 0
```

The first run caught two wrong assertions, both my error, not the code's:
`fan.rpm` on the fast path comes from `state.json` (so the v2-render case needs
`--full` and asserts sensors/temperature), and jq prints `64.0`, not `64`.

## 5. Full gate

```
$ tests/run-all.sh
RUN   plugin-validate        PASS
RUN   manifest               PASS
RUN   model                  PASS
RUN   ctl                    PASS
RUN   keybindings            PASS
RUN   qml-lint               PASS
RUN   panel-slider           PASS
RUN   panel-refresh          PASS
RUN   branch-model           PASS

PASS suites 9 / FAIL suites 0 / SKIP 0
```

`omarchy plugin validate .` is suite 1 and passed.

## 6. Docs and ruling

R14 in `DEVIATIONS.md`; a `DESIGN.md §4.1` note; `docs/ARCHITECTURE.md` §3.3;
`docs/TESTING.md` rows 3–4; `docs/TROUBLESHOOTING.md` §2 rows; `AGENTS.md`
(ruling count, code map); `bin/AGENTS.md`; `tests/AGENTS.md`; `CHANGELOG.md`
Unreleased.

## 7. Review round

`/code-review` ran Standards and Spec sub-agents over `git diff dev`. Six
findings were fixed and recorded in `REVIEW.md`: the doctor probe now uses
`schema_check`; the highest-mutual re-request fires for an older emitted default
too (`v0-compat`); both reads are bounded; `none` became `unknown`; the state
refusal names the fix; and `Model.statusNotice` + a low-precedence panel banner
surface the notice. Two findings were accepted as designed and one as the
existing two-language mirror. After the fixes: model 208/0, ctl 279/0, gate 9/9.

## Open items

- The modern afanctl contract v2 is not landed and cannot be exercised against
  a real daemon here; `fake-afanctl` models the proposed shape from afanctl#8.
  The negotiated `--schema` request is the contract this change pins.
- The adaptive control widget that consumes v2's `fans`/`control` union is a
  separate epic item; this change only stops v2 from breaking a v1 plugin.
