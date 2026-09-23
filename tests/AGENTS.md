# tests/

## OVERVIEW
Hardware-free gate: 9 hermetic suites driven by run-all.sh, plus 2 guarded live suites that never run by default.

## STRUCTURE

### Gate suites (run-all.sh)
| Suite | File | Run alone | Needs |
|---|---|---|---|
| plugin-validate | plugin-validate.sh | `bash tests/plugin-validate.sh` | `omarchy` on PATH, else FAILs (no skip) |
| manifest | manifest.test.sh | `bash tests/manifest.test.sh` | jq |
| model | model.test.mjs | `node tests/model.test.mjs` | node only; evals Model.js via `new Function` |
| ctl | ctl.test.sh | `bash tests/ctl.test.sh` | fixtures/fake-afanctl, jq |
| keybindings | keybindings.test.sh | `bash tests/keybindings.test.sh` | stub hyprctl, sandboxed HOME |
| qml-lint | qml-lint.sh | `bash tests/qml-lint.sh` | qmllint + `$OMARCHY_PATH/shell`; prints SKIP and exits 0 when either is absent |
| panel-slider | panel-slider.test.sh | `bash tests/panel-slider.test.sh` | none; structural Panel.qml assertions for the T2 Auto-reset guards |
| panel-refresh | panel-refresh.test.sh | `bash tests/panel-refresh.test.sh` | none; structural Panel.qml assertions for the T5 in-panel refresh row |
| branch-model | branch-model.test.sh | `bash tests/branch-model.test.sh` | a `master` (or `origin/master`) ref; reads its tree and asserts no denylisted path (R13). Lists live in `lib/shipped-paths.sh`. No such ref = a printed SKIPPED line, not a silent pass |

`tests/run-all.sh --list` prints the 9 gate names. A missing suite file is a SKIP, never a FAIL.

branch-model is the one suite asserting a repository property rather than plugin behaviour: users clone the whole repo into `~/.config/omarchy/plugins/<id>`, so a shipped branch carrying `AGENTS.md`/`worknotes/`/`skills/` is a broken plugin, not a stale note (R11's guarantee, R13's mechanism).

### Live suites (never in run-all.sh; both print SKIP and exit 0 without the guard)
- `OMAFAN_LIVE=1 tests/integration-shell.sh`: live omarchy-shell IPC. Only write is the intentional `preset bogus` error path.
- `OMAFAN_HW=1 tests/hw-smoke.sh`: real hardware, also demands an interactive `yes`.

### fixtures/
| File | Role |
|---|---|
| fake-afanctl | Executable afanctl stand-in (`status`, `hold`, `observe`/`curve`, `--version`). Refuses to run without a caller runtime dir; refuses /run/afanctl, /sys, /etc, /usr. Writes argv to `$RUN/argv.log`, cmd doc to `$RUN/cmd.json` |
| status-observe.json | afanctl.status.v1, running, mode observe |
| status-hold.json | afanctl.status.v1, running, mode hold |
| state-hold.json | afanctl.state.v1; setup_case copies it to `$RUN/state.json` |
| state-monitor-only.json | state variant with the monitor_only latch |

`FAKE_AFANCTL_MODE`: `observe` (default) | `hold` | `monitor-only` | `absent` | `error`. monitor-only and absent docs are derived from the two status fixtures with jq; add a mode by extending fake-afanctl's validate_mode + render case, not by adding a third status fixture. `AFANCTL_FAKE_FAIL=1` makes every write exit 1.

## WHERE TO LOOK
| Task | Location |
|---|---|
| Assertion helpers | tests/lib/harness.sh (source it, never execute from a suite) |
| Case plumbing | ctl.test.sh: `setup_case`, `seed_state`, `ctl`, `run_mode` |
| Privileged-argv proof | ctl.test.sh: `in_default_runtime` (unshare -rm bind-mounts `$RUN` over /run/afanctl inside the namespace only), `expected_argv` |
| Stub compositor | keybindings.test.sh: `stub_hyprctl` derives binds from the sandboxed bindings.lua; `OMAFAN_STUB_MEM` seeds memory-only binds |
| FATAL vs REPORTED qmllint split | qml-lint.sh header comment |
| Model.js assertions | model.test.mjs: append the export name to NAMES (or GUARD_NAMES); suite stays table-driven |

## CONVENTIONS
- Source the harness once (`source "$repo/tests/lib/harness.sh"`), end the suite with `summarize`: prints `PASS n / FAIL m`, removes the harness temp root, exits non-zero on any failure.
- Assert fns: `assert_eq`, `assert_ne`, `assert_contains`, `assert_exit_code <rc> <cmd...>`, `assert_json_eq` (semantic jq compare). A failed assert returns 0 so `set -e` never aborts a suite mid-run; record everything, let summarize decide.
- Per case in ctl.test.sh: `setup_case [state-fixture]` builds fresh `$CASE`/`$RUN`/`$XDG`, redirects XDG_RUNTIME_DIR, and copies the fixture to `$RUN/state.json` (no arg = daemon-absent case). Mutate state with `seed_state '<jq-filter>'`, never by editing fixtures.
- Invoke the CLI only via `ctl <args>` (appends `--afanctl $FAKE --pkexec none --runtime-dir $RUN`) or `run_mode <mode> <args>`. Never call bin/omafan-ctl bare in a test.
- Add a case: new block in the right suite after its own setup_case, using the shared helpers. Add a suite: new file + one `run_suite` line in run-all.sh + its name in the `--list` line.
- Harness changes: prove them with `bash tests/lib/harness.sh` (self-test block at the bottom).
- Bash suites run `set -uo pipefail` (no `-e`); `plugin-validate.sh` and the opt-in `hw-smoke.sh` use `set -euo pipefail`. Assertions record failures instead of aborting, so every suite reaches `summarize`.
- An expectation that mirrors a source constant (a chord description, a version string) changes in the same commit as the constant — the gate asserts them verbatim.

## ANTI-PATTERNS
- NEVER touch /run/afanctl, real $HOME, real XDG_RUNTIME_DIR, /sys, or the network from a gate suite. The sole /run/afanctl access is the namespace bind-mount in `in_default_runtime`.
- NEVER let a gate suite require hardware, root, a running daemon, omarchy-shell, or a compositor; that belongs in the two guarded live suites.
- NEVER add a live suite to run-all.sh; the `OMAFAN_LIVE=1` / `OMAFAN_HW=1` guards must keep skipping clean (exit 0) when unset.
- NEVER edit fixtures to fit a failing assertion; fixtures pin the daemon contract. If the contract changed, change fixture, fake-afanctl, and the expectation together.
- NEVER bypass the harness counters with ad-hoc `exit 1` mid-suite; record through the assert fns so summarize reports every failure.
- NEVER leave an expectation on an old constant. The floor chord description was renamed in `bin/omafan-keybindings`, `DESIGN.md` §7 and `docs/KEYBINDINGS.md`, but `keybindings.test.sh` kept `omafan: fans off (floor)` and the suite failed on an otherwise clean tree.
- Keep the skip asymmetry: plugin-validate FAILs when `omarchy` is absent, qml-lint SKIPs when qmllint or the shell tree is absent.
