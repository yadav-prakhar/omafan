# WORKER.md — instructions every omafan subagent reads first

You are a **worker subagent** in a multi-agent build of `omafan`, an Omarchy
shell plugin. You implement **one ticket** and nothing else. The orchestrator
(Hermes Agent) will verify your work, re-run your gates, and merge it — so make
your claims falsifiable: end your final message with the evidence requested by
your ticket and by "Report format" below.

## Repo and reading order

Repo root: `/home/prakhar/Work/tries/2026-09-15-omafan`

1. `orchestration/instructions/WORKER.md` (this file)
2. `PRD.md` — why, requirements, acceptance gate
3. `DESIGN.md` — **frozen** interfaces, JSON schemas, key maps
4. `PLAN.md` — the ticket table, ownership, gates
5. `orchestration/tickets/<YOUR-TICKET>.md` — your card, authoritative

Read the *whole* of `DESIGN.md` before writing code; skim `PRD.md` for the
requirement ids your ticket cites.

## Hard rules

1. **Own your files only.** Your ticket lists the files you own; create/edit
   nothing else. Another worker owns every other file and may be editing it
   right now. If you need a change in a file you do not own, write it into
   `orchestration/QUESTIONS.md` as a request instead of doing it.
2. **Do not run git.** No `git add/commit/branch/stash/checkout`. The
   orchestrator commits.
3. **Do not install packages, do not use the network, do not call `sudo`.**
   Everything you need is already on the machine.
4. **Never write to real `/sys`, `/etc`, `/usr`, `/run/afanctl` or any
   `~/.config/omarchy` path.** Tests and manual checks use fixtures and
   `--runtime-dir`/`--afanctl` overrides. This is a safety-critical rule: the
   machine's fan is controlled by a live daemon.
5. **Contracts are frozen.** If you believe `DESIGN.md` is wrong, stop, write
   the objection in `orchestration/QUESTIONS.md`, and implement the contract as
   written unless your ticket says otherwise.
6. **No placeholders.** No `TODO`, no stub function that returns a canned value,
   no "left as an exercise". If a requirement is ambiguous, pick the reading that
   matches `DESIGN.md` and note the choice in your report.
7. **Run your gates and paste real output.** A gate you did not run is a gate
   that failed.

## Environment facts

| Thing | Where |
|---|---|
| Omarchy shell sources (read-only reference) | `/usr/share/omarchy/shell/` (`Ui/`, `Commons/`, `plugins/`) |
| Best structural references to copy patterns from | `shell/plugins/panels/monitor/Panel.qml`, `shell/plugins/panels/audio/Panel.qml`, `shell/Ui/{Panel,KeyboardPanel,PanelKeyCatcher,PanelSlider,WidgetButton,BarWidget,BarIconButton,PanelActionButton,ButtonGroup,ToggleSwitch,PanelHero,PanelSectionHeader,PanelSeparator}.qml`, `shell/Commons/{Style,Color}.qml` |
| Third-party plugin example (bar widget + panel + IpcHandler) | `~/.config/omarchy/plugins/omaplug/` (read-only; do not modify) |
| `qmllint` (not on `PATH`) | `/usr/lib/qt6/bin/qmllint`; run with `-I /usr/share/omarchy/shell` |
| Plugin validator | `omarchy plugin validate <dir>` |
| Live shell IPC | `omarchy-shell <target> <method> [args…]`, `omarchy-shell shell ping` |
| afanctl (the fan daemon this plugin drives) | `/usr/bin/afanctl`; docs in `/home/prakhar/Work/tries/2026-09-14-a1708-fanctl/README.md` |
| afanctl live state (read-only, safe) | `/run/afanctl/state.json`, `afanctl status --json` |
| `PATH` note | `node`, `jq`, `bash`, `notify-send` are available; do not rely on `qmllint` being on `PATH` |

## Conventions (verbatim from DESIGN.md §9 — obey all of it)

```
CONVENTIONS (omafan, frozen)
- Repo: /home/prakhar/Work/tries/2026-09-15-omafan. Do NOT run git commands; the
  orchestrator commits. Do not create or edit files you do not own (see your ticket).
- Read DESIGN.md before writing code; it is frozen. If you believe it is wrong,
  stop and write your objection into orchestration/QUESTIONS.md — never silently
  deviate.
- Language: shell is POSIX-ish bash (#!/usr/bin/env bash, set -euo pipefail is
  allowed; quote everything; no bash-isms that break on dash are needed since we
  require bash). QML targets Quickshell/Omarchy 4.0.0.alpha: import QtQuick,
  Quickshell, Quickshell.Io, qs.Ui, qs.Commons only. JS in Model.js is ES5-safe,
  no imports, no I/O, no side effects.
- Dependencies: none beyond what is present on the machine — bash, coreutils,
  jq, awk, sed, grep, find, procps, pkexec, notify-send, node (tests only),
  /usr/lib/qt6/bin/qmllint. No new packages, no network at runtime, no curl.
- Error model: every failure prints (a) a human line naming the problem AND the
  fix, (b) for --json verbs, the JSON error object of DESIGN.md §4.3. Never exit 0
  on a failure. Never swallow stderr from afanctl.
- Never write to real /sys, /etc, /usr or /run in code paths exercised by tests;
  tests use fixtures (tests/fixtures/fake-afanctl, --afanctl/--runtime-dir).
- Comments explain WHY (safety decisions especially), not what. British-neutral
  English. No emoji. No TODO left in shipped files.
- Gates you must run and paste the output of: bash -n <each shell file>;
  node tests/model.test.mjs (if Model.js is yours); tests/qml-lint.sh (if QML is
  yours); omarchy plugin validate . ; tests/run-all.sh once it exists.
- Style: 2-space indent in QML/JS, 4 in shell; max ~100 columns; no trailing
  whitespace; files end with a newline.
```

## QML gotchas that have already cost time on this shell

- A third-party plugin may have **exactly one** `IpcHandler` per target, and only
  the panel declares it (`Panel { manageIpc: false }` + your own
  `IpcHandler { target: "omafan" }`). Method arguments are typed `string`.
- A bar widget's panel must be reachable through the bar-widget root:
  `open`/`close`/`opened`/`closeForPopoutSwitch`/`popoutSwitchClosing` are
  forwarded from the `Loader`ed `Panel.qml`. See `omaplug/BarWidget.qml`.
- `KeyboardPanel` needs `anchorItem`, `owner`, `bar`, `open`, `focusTarget`;
  `KeyboardPanel` primes focus at open-time so an IPC summon lands focused.
- `PanelKeyCatcher` (`Keys.priority: BeforeItem`) swallows `h/j/k/l`, arrows,
  `Enter`, `Space`, `Esc`, `Tab`; anything else arrives via `onTextKey`.
  Set `blocked: true` only when an inline editor has focus (we have none).
- Use `Style.space()`, `Style.font.*`, `Style.spacing.*`, `Color.foreground`,
  `Color.accent`, `Color.urgent`, `root.barForeground` for theme fidelity; never
  hardcode colours other than fallbacks.
- `Quickshell.Io` `Process` + `StdioCollector` (or `Process.onExited` +
  `command`/`running` + a `SplitParser`) is the supported way to run a command;
  `Quickshell.execDetached` is for fire-and-forget only. Commands with arguments
  are `command: ["/path/bin/omafan-ctl", "preset", "med"]` (array form avoids
  shell quoting entirely) — see `omaplug`'s scripts for the pattern.
- Strings built into QML from user data must render with `Text.PlainText`.

## Report format (end of your final message)

```
TICKET: <id>
FILES: <path:line count> for each file you own
GATES: <exact command run> -> <observed result>
EVIDENCE: <the transcripts/outputs your ticket asked for>
DECISIONS: <any judgement call you made, and the DESIGN.md clause it follows>
OPEN: <anything you could not do, and why>
```

Keep it under ~60 lines. The orchestrator reads the code, not the prose.
