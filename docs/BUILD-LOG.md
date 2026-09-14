# BUILD-LOG.md — how omafan was built (audit trail)

This is the orchestrator's log of the build that produced this repository: the
phases, who did what, which gates ran, what broke, and what the operator should
know. The machine-level flight recorder with per-event evidence is
`orchestration/LEDGER.md`; this file is the readable summary.

- **Date:** 2026-09-15 (night session, IST)
- **Operator:** Prakhar Yadav (asleep; instruction: "make it, test it, run it,
  ensure nothing breaks or collides with something else")
- **Orchestrator:** Hermes Agent on `deepseek-v4.1-flash` (provider `opencode-go`)
- **Workers:** OpenCode CLI one-shot sessions, one ticket each, models assigned
  by complexity: `opencode-go/mimo-v2.5` (trivial), `opencode-go/deepseek-v4.1-flash`
  (moderate), `opencode-go/glm-5.3-flash --variant high` (complex/safety-critical),
  `opencode-go/glm-5.3` (adversarial review)
- **Machine:** MacBook Pro 2017 A1708 (`MacBookPro14,1`), Omarchy 4.0.0.alpha
  ("Quattro"), kernel 7.2.3-arch1-3, `afanctl` 0.1.0 installed and running

## Phases

| Phase | What happened |
|---|---|
| P0 | Recon against the live machine: Omarchy shell plugin contract, `omarchy plugin validate`, the `Ui/*` component APIs, the live binding set (175 chords) and the `code:`-encoded workspace/panel bindings, the afanctl polkit rule, the afanctl `cmd.json`/`state.json` contract, and the marketplace's existing fan plugins. Contracts frozen in `DESIGN.md`; requirements in `PRD.md`; tickets and model routing in `PLAN.md`. |
| P1 | Manifest + validate/lint harnesses (MiMo), `Model.js` + 124 node assertions (deepseek), afanctl fixture + bash harness library (deepseek). |
| P2 | `bin/omafan-ctl` (glm high) — accepted after one amendment round (`cycle`), keybinding installer + suite (glm high), `Model.js` undercooling-guard amendment (deepseek). |
| P3 | `BarWidget.qml` (deepseek), `KeyboardHelp.qml` (MiMo), `Panel.qml` (glm high). |
| P4 | `tests/ctl.test.sh` (deepseek), live-suite scripts (deepseek), README/INSTALL/TROUBLESHOOTING (deepseek), architecture/safety/keys/testing/prior-art docs (deepseek), changelog + publishing inputs (MiMo). |
| P5 | Two adversarial review rounds on the finished tree (glm 5.3, read-only). |
| P6 | Live integration in the running shell, keybinding install + verify, hardware smoke test, git push, marketplace submission package, Obsidian note. |

## Rulings that changed the frozen contracts

Recorded because they moved work, not because they were cheap:

- **R1 — undercooling guard (§5.1/exit 8).** A live check found the machine at
  97 °C with the firmware already running the fan at 4794 rpm while the parallel
  build loaded the CPU. Three of the six presets (`off` 1200, `low` 2700,
  `med` 4200) command *less* airflow than the firmware is already delivering, so
  omafan could have made a hot machine hotter. The guard now requires a
  deliberate second confirmation (panel) or `--force` (CLI) for a hold below the
  current rpm while `t_eff >= 80 °C`. This was not in the original requirement
  set; it came out of testing on the real machine.
- **R2 — runtime directory plumbing.** `afanctl` takes its runtime directory
  from `AFANCTL_RUNTIME_DIR`, not a flag; the ticket was amended before dispatch
  so no invented flags shipped.
- **R3 — `qmllint` gate rewritten.** The plugin-development guide's
  `qmllint -I "$OMARCHY_PATH/shell"` cannot resolve `qs.Ui`/`qs.Commons` on this
  machine (the modules ship a `qmldir` but no `qmltypes`, and the import path
  must contain a `qs/` directory). Verified by running it against the shipped
  third-party `omaplug` plugin, which shows the same failure. `tests/qml-lint.sh`
  now builds a shim import root, fails on syntax errors, unresolvable imports and
  missing non-`qs.*` types, and reports the expected `qs.*` member warnings
  instead of pretending they are clean.
- **R4 — panel command plumbing.** `Panel.qml` resolves `bin/omafan-ctl` from the
  plugin directory at runtime (`Qt.resolvedUrl`) and honours
  `OMAFAN_AFANCTL`/`OMAFAN_RUNTIME_DIR`/`OMAFAN_PKEXEC`, so the identical QML can
  be exercised against the fixture without touching the fan.
- **R5 — `cycle` verb.** The frozen keybinding table and the panel's `c` key both
  need a cycle action; DESIGN §4 did not list one. §4.5 now defines it
  (`auto → off → low → med → high → full → auto`, wrapped), and both the CLI and
  the panel use it.
- **R6 — status exit-code split.** `status` renders a document even when the
  daemon is down (and exits 5), so consumers must read `daemon.running` from the
  document rather than treating a non-zero exit as a parse failure.

## Defects found by the orchestrator, and what caught them

| Defect | Found by | Fix |
|---|---|---|
| Keybinding block called a bare `omafan-ctl` (not on `PATH`; Hyprland `exec` uses a plain shell) — every preset chord would have failed at key-press time | reading the emitted block against the ticket's requirements | T06b: resolve the absolute helper path at install time, refuse on a dangling/misspaced path, `stale-path` verdict |
| Fast-path `status` reported `thermal.t_eff_c: null` although `state.json` had the temperature; bar fell back to its glyph, panel header lost its headline number | live run + screenshot transcription | T04c |
| `daemon.uptime_s: null` on the fast path | live run | T04c: cache `interval_s` with the hardware limits |
| Footer read `Uptime · Polls 4124 · Verified: no` — reads as a fault when nothing is held | screenshot transcription | T09b |
| `tests/run-all.sh` silently skipped the plugin-validate suite (wrong argument order in the `run_suite` call) | worker T07's report | orchestrator fixed the runner |
| `bin/omafan-keybindings` marker detection (`grep -qxF` without `-e`) treated the `-- BEGIN omafan` pattern as an option | orchestrator spot check | worker self-corrected during its run; verified after |

## The one rule a worker broke

`ticket T04` ran `omafan-ctl preset low` **once** without `--pkexec none` while
debugging, so `pkexec` reached the live daemon and a real hold was briefly
applied to this machine at `t_eff 90 °C` / firmware 4794 rpm — precisely the
situation the new undercooling guard refuses today. The worker restored `observe`
immediately and disclosed it; the orchestrator re-verified independently
(`/run/afanctl/state.json` and `afanctl status --json`: `mode=observe`,
`manual=false`, `target_rpm=null`, `recent_errors=[]`). It is recorded here
rather than hidden because it is the class of mistake this repository's safety
model exists for, and because the guard it would have tripped is now
lock-tested.

## Verification that was actually run (not asserted)

- `omarchy plugin validate .` → exit 0.
- `tests/qml-lint.sh` → PASS (3 QML files; expected `qs.*` member warnings
  reported, not silently ignored).
- `node tests/model.test.mjs` → PASS 148 / FAIL 0.
- `bash tests/keybindings.test.sh` → PASS 71 / FAIL 0; a deliberate mutation
  (swapping one bound chord) fails the suite, so it has signal.
- `bash tests/ctl.test.sh` → see `docs/TESTING.md` for the final count.
- Live: plugin discovered, enabled, panel opened over IPC
  (`omarchy-shell omafan toggle`), `omarchy-shell omafan state` returned a valid
  status document with the live fan rpm, and the rendered panel was transcribed
  from a screenshot.
- Hardware: see the "Hardware smoke test" section of `docs/TESTING.md` and the
  final entry in `orchestration/LEDGER.md` for exactly which presets were
  exercised, for how long, and the verified return to `observe`.

## What the operator still owns

1. **Read `PRD.md` §4 (the acceptance gate) and the last LEDGER entries** — they
   name what was proven and by which command.
2. **Decide whether to keep the widget enabled** in the bar (it is enabled now;
   `omarchy plugin remove io.github.yadav-prakhar.omafan` plus
   `bin/omafan-keybindings remove` reverts everything this build did to the
   session, and `orchestration/backups/shell.json.<stamp>.bak` is the
   pre-change bar layout).
3. **Send the marketplace issue** — the body is prepared verbatim in
   `docs/PUBLISHING.md`; nothing is submitted automatically.
4. **Re-run the hardware suite whenever the machine is quiet**
   (`OMAFAN_HW=1 tests/hw-smoke.sh`) if you want the full preset ladder exercised
   below 60 °C; the night run was constrained by the build's own CPU load.
