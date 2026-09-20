---
name: change-a-frozen-contract
description: Use when a change contradicts DESIGN.md, a documented exit code, the preset model, the chord table or the JSON schemas — the frozen contracts that require a DEVIATIONS.md ruling and a synchronised multi-file update.
---

# Change a frozen contract

`DESIGN.md` is the contract every implementation decision was measured against.
It is frozen: a behavioural change that contradicts it is not a bug fix, it is a
contract change, and it needs a ruling recorded **before** the code lands.

## Is it frozen?

| Item | Where the contract lives |
|---|---|
| Preset model (ids, labels, rpm derivation, slider steps) | `DESIGN.md` §3 |
| CLI verbs, flags, JSON schemas, exit codes | `DESIGN.md` §4 |
| `Model.js` function signatures | `DESIGN.md` §5 |
| Panel / bar semantics, IPC methods | `DESIGN.md` §6 |
| In-panel keys, global chords | `DESIGN.md` §6.3, §7 |
| Plugin-side safety model | `DESIGN.md` §8 |

If your change alters one of those, it is frozen work.

## The procedure

1. **Write the deviation entry** in `DEVIATIONS.md`, using the file's own format:

   ```text
   D<n> — <item> — old → new — why — affected tickets — ruling
   ```

   The existing entries (`R1`…`R8`) are the precedent: each states the old
   behaviour, the new one, the evidence that forced it, and which tickets were
   amended. Keep that shape; "why" is the part reviewers read.

2. **Update the contract** in `DESIGN.md` in the same change, and reference the
   ruling id in the commit body.

3. **Chase every mirror of the fact.** This is where these changes fail. A single
   constant typically lives in three or four places:

   | Fact | Mirrors |
   |---|---|
   | Chord descriptions | `bin/omafan-keybindings`, the `DESIGN.md` §7 table, `docs/KEYBINDINGS.md`, `tests/keybindings.test.sh` |
   | Exit codes | `DESIGN.md` §4, `docs/SAFETY.md`, `docs/TROUBLESHOOTING.md`, `README.md`, `bin/omafan-ctl` usage header, `tests/ctl.test.sh` |
   | Preset labels / derivation | `DESIGN.md` §3, `Model.js`, `README.md`, `docs/*`, `Panel.qml` legend, `tests/model.test.mjs` |
   | Version | `manifest.json`, `bin/omafan-ctl` (variable + usage header), `CHANGELOG.md`, `tests/manifest.test.sh`, `tests/ctl.test.sh` |
   | Directory invariants | the `AGENTS.md` in the affected directory |

4. **Re-run the gate** (`bash tests/run-all.sh`) and, for anything the UI renders,
   verify live — see the `live-verify-in-the-shell` skill.

## Evidence, not preference

Rulings in this repo were forced by measurements, and the next one should be too.
R7 exists because the `pkexec env AFANCTL_RUNTIME_DIR=… afanctl …` form made
afanctl's polkit rule return `NOT_HANDLED` and hang on a password prompt (bare
form: 0.026 s), and R1 exists because the machine was observed at 97 °C with the
firmware already at 4794 rpm. Quote the command and its output in the entry; a
nickname-change or a hunch is not a ruling.

## Do not

- Do not silently diverge and fix the docs later — the gate will not catch it,
  and the docs will be wrong in three places by then.
- Do not edit old deviation entries or ticket cards; corrections are new entries
  and `orchestration/LEDGER.md` lines.
- Do not change an assertion to match new behaviour without the mirror sweep —
  that is how the stale `omafan: fans off (floor)` expectation survived a rename
  and left the suite red on a clean tree.
