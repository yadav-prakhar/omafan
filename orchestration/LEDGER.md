# orchestration/LEDGER.md — flight recorder

One line per dispatch, verification, rejection, ruling and commit. Newest first.
Format: `<time> <actor> <event> — <evidence command> — <result>`

- 2026-09-15T03:15Z orchestrator P0 recon complete — `hyprctl binds -j`, `afanctl status --json`, `plugins.omarchy.org/catalog.json`, `omarchy plugin --help`, `omarchy-shell omaplug refresh` — 175 bound chords, afanctl 0.1.0 active in observe, 6 sibling fan plugins surveyed, third-party IPC confirmed working; contracts frozen in DESIGN.md.
- 2026-09-15T03:35Z orchestrator wave1 verified — `omarchy plugin validate .` (FAIL: BarWidget.qml missing, expected until P3), `node tests/model.test.mjs` → PASS 124 / FAIL 0, `bash -n` all shell OK, `tests/qml-lint.sh` → SKIP, fake-afanctl manual transcript (status/hold/observe/below-min/refuse-live-dir) correct — T01, T02, T03 ACCEPTED (T01's validate gate deferred to P3 by design; T03's fixture refuses the live /run/afanctl dir, which is stronger than asked).
- 2026-09-15T03:35Z orchestrator ruling R1 — added DESIGN.md §5.1 undercooling guard + exit code 8 (live finding: machine at 97 °C with firmware at 4794 rpm means presets off/low/med reduce airflow) — new ticket T02b (deepseek) and amendments to T05/T09/T10.
- 2026-09-15T03:36Z orchestrator ruling R2 — afanctl takes its runtime dir from AFANCTL_RUNTIME_DIR (no --runtime-dir flag); T04 card amended.
- 2026-09-15T03:36Z orchestrator wrote tests/manifest.test.sh and tests/run-all.sh (T14, orchestrator-owned) — manifest: PASS 22 / FAIL 3 (3 failures are the not-yet-written BarWidget.qml/Panel.qml/README.md, expected until P3/P4).
