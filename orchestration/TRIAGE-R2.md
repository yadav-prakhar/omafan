# TRIAGE-R2 — disposition of every REVIEW-R2 finding

Written by the orchestrator after acting on the review. The reviewer's file
(`orchestration/REVIEW-R2.md`) is the contribution and is left unedited; its
"open" markers reflect the tree **at review time**, not the published tree.

| Finding | Severity | Disposition | Evidence |
|---|---|---|---|
| **R2-1** privileged argv could never match afanctl's polkit rule | blocker | **Fixed** (T04d, landed while the review ran; the reviewer verified the fix itself) | `preset full --dry-run --json` → `["/usr/bin/pkexec","/usr/bin/afanctl","hold","7200"]`; a real write completed in **0.210 s** and moved the fan 7198 → 5741 rpm; `doctor` → `pkexec_write_path PASS (23 ms)` |
| **R2-2** `release_after_minutes` could never fire | blocker | **Fixed** (orchestrator, ruling R7) — the net arms on the hold's rising edge (`holdSeen`) and is restarted only by genuine user interaction; the interval is clamped to ≥60 s; DESIGN §8's old sentence, which prescribed the bug, is corrected | `tests/qml-lint.sh` clean; six-suite gate green; `DEVIATIONS.md` R7 |
| **R2-3** writes succeeded untruthfully on a stale `state.json` | should-fix (borderline blocker) | **Fixed** (orchestrator, ruling R7) — a stale state now refuses the write with exit 5 unless `--force`; DESIGN §4 records it | transcript: state touched 2 min ago → exit 5, **no** `argv.log`; `--force` writes; fresh state writes |
| **R2-4** the build gate was red at the audited HEAD | blocker (gate) | **Closed by T05b** (the reviewer verified) | `tests/run-all.sh` → 6/6 suites PASS; `ctl` at 238 assertions |
| **R2-5** T04d/T09c behaviour drift un-mirrored in the contracts | should-fix | **Fixed** (orchestrator) | `DESIGN.md` §4 (runner argv, bounded calls, stale refusal), §4.4 (twelfth check id `pkexec_write_path`), §8 (edge-triggered net) and `DEVIATIONS.md` R1–R7 |
| **R2-6** the heat confirmation sent blanket `--force` | nit | **Fixed** — new narrow `--force-undercooling`; the panel sends only that | at 90 °C/4794 rpm: `preset low` → 8, `--force-undercooling` → 0, but exit **7** out-of-band and exit **6** on the degraded latch still refuse; plain `--force` overrides all three |
| **R2-7** `--config` silently dropped on the privileged path | nit | **Fixed** — refused with exit 2 alongside the runtime-dir refusal, naming both fixes | `preset med --config /etc/afanctl/afanctl.toml` → exit 2 |
| **R2-8** missing `jq` produced raw interpreter errors | nit | **Fixed** — a start-up guard fails in the documented style; `omafan-ctl version` still works without jq | `PATH=<empty> omafan-ctl status --json` → `jq is required … Fix: install jq (pacman -S jq)`, exit 1 |
| **R2-9** no REVIEW-R1 and no LEDGER entry for T15 | process | **Open, recorded** — the code-vs-contracts review produced no report; `docs/BUILD-LOG.md` P5 says so and `orchestration/dispatch.sh T15:opencode-go/glm-5.3:high` re-runs it | `ls orchestration/REVIEW-R*.md` → R2 only |

## Residual items the operator may want to pick up

1. **Re-run T15** (code-vs-contracts review) and triage its report the same way.
2. **Add the R2-3 regression case** to `tests/ctl.test.sh` (stale state → exit 5,
   empty `argv.log`, `--force` override). The behaviour is transcript-verified but
   not yet pinned by a test.
3. **`release_after_minutes` has no automated test** — the edge-triggered arming
   was verified by reading the code and by lint, not by exercising a real
   N-minute countdown. A cheap future test: set the setting to 1 minute against
   the fixture and assert the release command is issued once.
4. **`tests/hw-smoke.sh` still wants a supervised run** on a cool machine to
   exercise the full ladder below 60 °C (`OMAFAN_HW=1 tests/hw-smoke.sh`); the
   night run was limited to holds at or above the firmware's current speed because
   the build itself kept the CPU at 85–97 °C.
