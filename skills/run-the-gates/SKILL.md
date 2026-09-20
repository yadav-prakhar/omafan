---
name: run-the-gates
description: Use when you need to know whether an omafan change actually works, or when adding a test case or a whole suite. Runs the hardware-free gate, explains SKIP vs FAIL, and keeps live/hardware suites opt-in.
---

# Run the gates

The gate is eight hardware-free suites. It is the only thing that counts as proof
in this repo: "it looks right" is not evidence, and neither is a suite you did
not run.

## Run everything

```sh
bash tests/run-all.sh          # PASS suites n / FAIL suites m / SKIP k
bash tests/run-all.sh --list   # plugin-validate manifest.test.sh model.test.mjs ctl.test.sh keybindings.test.sh qml-lint.sh panel-slider.test.sh panel-refresh.test.sh
```

A single suite, while iterating:

```sh
bash tests/manifest.test.sh      # manifest.json shape and settings schema (jq)
node tests/model.test.mjs        # Model.js pure functions (Node, no Qt)
bash tests/ctl.test.sh           # omafan-ctl verbs against fixtures/fake-afanctl
bash tests/keybindings.test.sh   # keybinding block via a stub hyprctl
bash tests/qml-lint.sh           # QML lint through a shim import root
bash tests/panel-slider.test.sh  # Panel.qml slider Auto-reset guards (structural)
bash tests/panel-refresh.test.sh # Panel.qml REFRESH row (structural)
bash tests/plugin-validate.sh    # omarchy plugin validate .
bash -n bin/omafan-ctl bin/omafan-keybindings    # shell syntax
omarchy plugin validate .                        # the shell's own structural gate
```

Expect `qml-lint` to pass with a line like
`PASS qml-lint: 3 file(s) clean; N expected non-fatal warning(s)` — those warnings
are `qs.*` singleton member accesses that `qmllint` cannot resolve without
`qmltypes`. They are REPORTED, not FATAL; see the header of `tests/qml-lint.sh`
for the classification rule.

## SKIP is not PASS

- `plugin-validate.sh` **FAILs** when `omarchy` is not on `PATH` (it prints a
  SKIP line and then a FAIL line — read both).
- `qml-lint.sh` **SKIPs and exits 0** when `qmllint` or the shell tree is absent.
- A missing suite file is a SKIP in `run-all.sh`, never a FAIL.

So a green `run-all.sh` on a machine without Omarchy proves less than it looks.
When the change touches QML, run the lint on a box that has the shell.

## Never add these to the gate

```sh
OMAFAN_LIVE=1 tests/integration-shell.sh   # live shell IPC; only write is an intentional error path
OMAFAN_HW=1   tests/hw-smoke.sh            # moves the real fan; attended, asks for a typed yes
```

Both print SKIP and exit 0 without their guard — keep it that way. A gate suite
must not need hardware, root, a running daemon, `omarchy-shell`, or a compositor.

## Adding a case

Inside an existing suite: add the case after its own `setup_case`, and use the
shared helpers only (`ctl`, `run_mode`, `seed_state`, `assert_eq`,
`assert_contains`, `assert_json_eq`, `assert_exit_code`, `summarize`). Assertions
record instead of aborting, so `set -e` never truncates a run — let `summarize`
decide the exit code.

Adding a suite: new file, one `run_suite` line in `tests/run-all.sh`, and its name
in the `--list` line. Change `tests/lib/harness.sh` only with proof:

```sh
bash tests/lib/harness.sh      # harness self-test block at the bottom
```

## Record the evidence

A green run that lives only in a terminal is a claim. Paste it into the feature's
`worknotes/<slug>/LOG.md` — the command and the summary line, verbatim:

```text
$ bash tests/run-all.sh
PASS suites 8 / FAIL suites 0 / SKIP 0
```

Keep the note current as you work and close the folder with a `SUMMARY.md` when
the work lands (`worknotes/README.md` is the contract). The gate stays out of
`worknotes/` on purpose: `tests/` must fail when the **plugin** is broken, never
because a note is stale.

## Traps that have already cost time here

- **Fixtures pin the daemon contract.** If an assertion fails, fix the code or
  change fixture + `fake-afanctl` + expectation together. Never edit an
  expectation to make a red suite green.
- **A constant can live in three places.** Chord descriptions live in
  `bin/omafan-keybindings`, the `DESIGN.md` §7 table and
  `tests/keybindings.test.sh`; the version lives in `manifest.json`,
  `bin/omafan-ctl` (twice: the variable and the usage header) and two test
  assertions. Update all of them or the gate fails on a clean tree.
- **The gate must stay hermetic.** No `/sys`, `/run/afanctl`, real `$HOME`,
  real `XDG_RUNTIME_DIR`, network, or `unshare` outside the single namespace
  bind-mount in `ctl.test.sh`'s `in_default_runtime`.
