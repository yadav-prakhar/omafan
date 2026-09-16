# omafan keybindings

omafan is keyboard-first: everything the pointer can do, a key can do, both
inside the panel and from anywhere on the desktop. This document mirrors the
frozen map in DESIGN.md §6.3 (in-panel) and §7 (global), records where the
"these chords are free" claim comes from, and explains how to install, remove
and rebind.

## 1. In-panel keys

The panel is a Quickshell `KeyboardPanel` with a `PanelKeyCatcher`; it is fully
operable without a pointer. The table below is also what `?` renders in-panel
(`KeyboardHelp.qml`), and both are generated from the same DESIGN.md §6.3 map.

| Key | Action |
|---|---|
| `j` / `↓` | cursor down (section) |
| `k` / `↑` | cursor up (section) |
| `h` / `←` | presets: previous preset · slider: −1 step (100 rpm) |
| `l` / `→` | presets: next preset · slider: +1 step |
| `Shift` + `h` / `l` | slider: ±500 rpm |
| `Enter` / `Space` | presets: apply focused preset (a second press confirms an undercooling-risk preset, §5.1) · slider: apply the current value now |
| `1` … `6` | apply `auto, floor, low, med, high, full` directly |
| `c` | cycle presets forward (`auto → floor → low → med → high → full → auto`; a custom hold cycles to `floor`) |
| `r` | refresh status now |
| `?` | toggle the key-map overlay (`KeyboardHelp.qml`) |
| `Esc` | close the help overlay if open, else close the panel |
| `Tab` / `Shift+Tab` | switch to the next/previous bar panel |
| mouse | hover = cursor, click = apply, wheel on the slider = ±1 step |

`PanelKeyCatcher` consumes `h/j/k/l`, the arrows, `Enter`, `Space`, `Esc` and
`Tab`, and forwards every other printable key as `onTextKey` — that is how the
digits, `c`, `r` and `?` reach the panel. `?` is not swallowed before the help
overlay opens, and `Esc` closes help before it closes the panel.

## 2. Global chords

Installed by `bin/omafan-keybindings install` as one managed block in
`~/.config/hypr/bindings.lua`. Preset and cycle chords call `omafan-ctl`
**directly**, so they keep working while `omarchy-shell` is restarting; only
the panel toggle goes through shell IPC (DESIGN.md §7).

| Chord | Description | Command |
|---|---|---|
| `SUPER + ALT + T` | omafan: toggle fan panel | `omarchy-shell omafan toggle` |
| `SUPER + ALT + A` | omafan: fans auto (firmware) | `omafan-ctl preset auto --notify` |
| `SUPER + ALT + O` | omafan: fans floor | `omafan-ctl preset off --notify` |
| `SUPER + ALT + L` | omafan: fans low | `omafan-ctl preset low --notify` |
| `SUPER + ALT + M` | omafan: fans medium | `omafan-ctl preset med --notify` |
| `SUPER + ALT + H` | omafan: fans high | `omafan-ctl preset high --notify` |
| `SUPER + ALT + X` | omafan: fans full | `omafan-ctl preset full --notify` |
| `SUPER + ALT + C` | omafan: cycle fan presets | `omafan-ctl cycle --notify` |

The command column is the frozen table. When `bin/omafan-keybindings install`
emits it, the `omafan-ctl` token is replaced by the **absolute path** of the
plugin's `bin/omafan-ctl` (`OMAFAN_CTL` overrides it). Hyprland runs a bind
through a plain non-login shell where the plugin's `bin/` is not on `PATH`, so
a bare `omafan-ctl` would fail at every key press while looking installed;
install refuses instead of emitting an unusable helper path.

`SUPER + ALT + A` is the deliberate escape hatch: it reaches firmware auto
through `omafan-ctl` even if `omarchy-shell` is dead (PRD K4).

## 3. Provenance of the free-chord analysis

The chords were chosen as free, not assumed free. The evidence chain:

1. **Live compositor read.** `hyprctl binds -j` on the reference machine
   (`MacBookPro14,1`, Omarchy 4.0.0.alpha) reported **175 distinct bound
   chords** (PRD §2.7; captured to `.recon/binds.json` and
   `.recon/bound-chords.txt` during recon).
2. **The digit trap.** Omarchy's defaults bind workspaces and panel toggles
   through `code:` keycodes (digits), so inspecting only symbol names hides
   them. The analysis checks `code:` aliases too. Consequence: **all
   `SUPER+digit`, `SUPER+SHIFT+digit`, `SUPER+ALT+digit` and `SUPER+CTRL+digit`
   chords are taken**, and omafan avoids digits entirely (PRD §2.7).
3. **Result.** `SUPER + ALT + {T, A, O, L, M, H, X, C}` are free on the
   reference machine, for both symbolic keys and their `code:` keycodes.
4. **Reproduction.** `tests/keybindings.test.sh` reproduces the claim against
   a sandboxed HOME, a stub `hyprctl` and a stub Hypr config tree. It asserts
   that the emitted block carries all eight chords in table order, and that the
   installer refuses (writes nothing) when any chord is already bound in the
   live bind list **or** in the Lua sources under
   `$OMARCHY_PATH/default/hypr/bindings/` and `~/.config/hypr/`, including
   `code:` spellings. The XKB keycodes of the eight letters
   (`X=27 T=28 O=32 A=38 H=43 L=46 M=50 C=54`) are matched so a `code:` chord
   counts only when it aliases one of ours; digit `code:` chords (10–19 on
   Omarchy) never collide.

## 4. Installing, checking, removing

```sh
bin/omafan-keybindings install   # write/refresh the block; refuses on conflict
bin/omafan-keybindings status    # installed | not-installed | conflict, per chord
bin/omafan-keybindings remove    # cut the block; exit 0 when absent
bin/omafan-keybindings print     # print the block to stdout; touches nothing
```

Behaviour (DESIGN.md §7, PRD K3):

- `install` writes **exactly one** `-- BEGIN omafan` … `-- END omafan` block,
  is idempotent (a second install leaves the file byte-identical), backs the
  original file up once under `~/.local/state/omafan-keybindings/`, then runs
  `hyprctl reload` and re-reads `hyprctl binds -j` to confirm every chord
  carries its omafan description.
- If **any** chord is already bound elsewhere, `install` exits 1, writes
  nothing, and names the conflicting chord and its current description.
- `remove` deletes the block, rests on the backup for a byte-identical
  restore when the rest of the file is unchanged, reloads, and exits 0 when
  there is nothing to remove.
- `status` reports `installed|not-installed|conflict` plus a per-chord verdict,
  and prints `stale-path` when the installed block calls a helper path that no
  longer resolves (the plugin moved) — with the fix, `re-run install`.
- The block is commented with the plugin path and an uninstall hint, and uses
  the Omarchy `o.bind("<CHORD>", "<description>", "<shell command>")` helper
  form. Nothing else in `bindings.lua` is ever touched, and its newline style
  is preserved.

## 5. Rebinding

The chord set is frozen by DESIGN.md §7; there is no rebind flag, and
`omafan-keybindings` will not install over a chord you already use. To use
different chords:

1. `bin/omafan-keybindings remove` — restores `bindings.lua`.
2. Add your own `o.bind("SUPER + ALT + <key>", "omafan: …", "<command>")` lines
   to `bindings.lua`, using the commands from §2 above with the absolute path
   to `bin/omafan-ctl`.
3. Do not re-run `install`: it would refuse, because your chords now conflict
   with the block it wants to write. Use `status` to see the verdict.

Other supported adjustments:

- **Move the helper.** Re-run `install` after moving or reinstalling the
  plugin; the block is refreshed to the new absolute path. `status` flags a
  stale path before you press a key.
- **Non-standard config location.** Set `OMAFAN_HYPR_CONFIG` to the target
  file (default `~/.config/hypr/bindings.lua`).
- **Tests/other compositors.** `OMAFAN_HYPRCTL` overrides `hyprctl`,
  `OMAFAN_STATE_DIR` overrides the backup directory,
  `OMAFAN_DEFAULT_BINDINGS_DIR` overrides the Omarchy default Lua tree, and
  `OMAFAN_CTL` overrides the helper the block will call.

None of these overrides is needed on a stock Omarchy install.
