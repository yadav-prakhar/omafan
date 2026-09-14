# TRIAGE-R1 — disposition of every REVIEW-R1 finding

`orchestration/REVIEW-R1.md` (T15, glm 5.3, snapshot 04:40 IST) is the
reviewer's contribution and is left unedited. Its line numbers and md5s refer to
the tree at 04:40; this file records what happened to each finding afterwards.

**Headline:** the review found a genuine **runtime-fatal blocker that every
automated gate had passed** (R1-1: `Panel.qml` assigned `root.statusStale` without
declaring it, so `applyStatus` threw on every poll and no status document was ever
applied). That is the single most valuable finding of the night, and it is fixed
and verified live below.

| Finding | Severity | Disposition | Evidence |
|---|---|---|---|
| **R1-1** `statusStale` used but never declared — every poll threw mid-function | **BLOCKER** | **Fixed** (orchestrator): `property bool statusStale: false` declared next to the comment that announced it | Live: plugin re-synced, shell restarted, panel opened over IPC and the screenshot transcribes live numbers — `CPU 57 °C · Fan 3,859 rpm`, `Uptime 1 h 59 m · Polls 7198`. Before the fix no document was applied at all. `qs log` shows no `TypeError`/`statusStale` lines. |
| **R1-2** staleness floor was a flat 5 s, not `max(5 s, 3 × interval)` | should-fix | **Fixed**: `is_state_stale` takes an optional limit, `stale_threshold()` computes `max(5, 3 × interval_s)` from the limits cache, and `write_prereqs` now calls `load_limits` first so the interval is actually available; `doctor`'s `state_fresh` uses the same limit | Verified with a stub daemon reporting `interval_s: 10`: a 6 s-old state is accepted (limit 30 s); the same state with a stub reporting `interval_s: 1` is refused with exit 5. On the reference machine the limit is 5 s either way. |
| **R1-3** `presets --human` printed raw JSON in the rpm column | should-fix | **Fixed**: `else tostring end` → `else (.rpm \| tostring) end` | `omafan-ctl presets --human` now prints `off  Off (hardware floor)  1200  hold` … `full  Full  7200  hold`. Still no automated assertion for the human path (see residual 2). |
| **R1-4** DESIGN §7 claimed `tests/keybindings.test.sh` reproduces the free-chord analysis; it cannot (it runs against stubs) | should-fix | **Contract corrected** (see `DEVIATIONS.md` R8): the sentence now attributes the analysis to orchestration-time evidence (PRD §2.7 + the install record + the live `hyprctl binds -j` check) and says the suite is the stub-based regression guard | `docs`/`DESIGN.md` wording; the live eight-chord check is recorded in `orchestration/LEDGER.md` (04:20Z) |
| **R1-5** no automated gate exercises QML *behaviour* — three semantic mutations and the R1-1 blocker all pass every gate | should-fix (systemic) | **Accepted, open**: this is the real gap the night exposed. The reviewer's own method (Qt 6.11.2 `qmltestrunner` headless cases, mutation-checked) is the recommended remedy and is written up as residual 1 below; `tests/integration-shell.sh` is the only behavioural gate and is opt-in | `REVIEW-R1.md` R1-5; this triage's residual list |
| **R1-6** two post-freeze contract changes unmirrored | nit | **Fixed** — `DESIGN.md` §4/§4.4/§8 and `DEVIATIONS.md` R1–R8 now carry them | `DEVIATIONS.md` |
| **R1-7** extra positional arguments silently ignored on every verb | nit | **Accepted** — lenient parsing is deliberate for a chord-driven CLI; recorded here so it is a decision rather than an oversight | — |
| **R1-8** offline panel chips render a fabricated `0 rpm` | nit | **Accepted, low impact** — the offline banner and stale marker are visible in the same view; a polish item | — |
| **R1-9** `docSlider` when-clause can never fire | nit | **Accepted** — dead clause, no user-visible effect; polish item | — |
| **R1-10** `assert_band` dead code + a fallback to a nonexistent field | nit | **Accepted** — dead code only; polish item | — |
| **R1-11** IPC return strings and rpm snapping diverge from §6.2 | nit | **Accepted** — the strings are human-facing and the panel ignores them; recorded | — |
| **R1-12** `KeyboardHelp.qml` renders 12 of §6.3's 13 rows | nit | **Accepted** — the missing row is the mouse row, which the overlay deliberately omits; `DESIGN.md` §6.3 lists pointer input separately | — |
| **R1-13** missing `jq` → undocumented exit 127 | nit | **Fixed** earlier the same night (REVIEW-R2 R2-8): a start-up guard fails in the documented style, `version` still works without jq | `bin/omafan-ctl` guard; transcript in the ledger |
| **R1-14** a write refused because the panel is busy is invisible | nit | **Accepted** — T09c D4 made busy-presses ignored by design; a "wait" hint is a polish item | — |
| **R1-15** the presets grid is 2×3, not §6.2's "single horizontal row of 6" | nit | **Contract corrected** — the rendered grid is the better UI at this panel width; §6.2 amended | `DESIGN.md` §6.2 |

## Residual items (the operator's call)

1. **Add a headless QML behaviour suite** (`qmltestrunner`, Qt 6.11.2 is
   installed): assert `applyStatus` applies a fixture document, that the release
   net arms once per hold and fires, and that a status timeout leaves
   `statusStale` true. This is the gate that would have caught R1-1 and the three
   QML mutations.
2. **Assert the human output paths** (`presets --human`, `status --human`) in
   `tests/ctl.test.sh` — R1-3 shipped precisely because only the JSON path was
   asserted.
3. **Pin the two night-fixes with tests**: the stale-state write refusal (exit 5)
   and the `max(5, 3 × interval)` threshold (needs a stub daemon whose
   `config.interval_s` is controllable).
4. Unchanged from `TRIAGE-R2.md`: one supervised `OMAFAN_HW=1 tests/hw-smoke.sh`
   run below 60 °C, and the marketplace issue in `docs/PUBLISHING.md`.
