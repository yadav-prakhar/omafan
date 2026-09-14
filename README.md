# omafan

Fan control for pre-T2 Intel Macs on Omarchy: firmware auto, five presets and
an RPM slider on top of [afanctl](https://github.com/yadav-prakhar/afanctl),
with live temperature and RPM in the bar.

omafan is an Omarchy shell plugin (Quickshell / Omarchy 4.0.0.alpha "Quattro")
for the single fan of a pre-T2 Intel MacBook (`applesmc`, verified on
MacBookPro14,1 "A1708"). It never touches `/sys` itself: the installed
**afanctl** daemon owns the fan, and omafan is a control surface over that
daemon's documented command channel.

- **Bar widget** — live CPU temperature and/or fan RPM, tinted whenever the fan
  is held off the firmware curve.
- **Panel** — `Auto · Off (hardware floor) · Low · Medium · High · Full`, an RPM
  slider, live status, banners for degraded/offline states, and an in-panel key
  map on `?`.
- **Keyboard-first** — the whole panel works without a pointer, and eight global
  chords for the panel plus every preset were verified free against the live
  compositor bindings.
- **CLI** — `bin/omafan-ctl` exposes the same surface headlessly with JSON output
  and documented exit codes.
- **Zero new privilege surface** — no udev rule, no sudoers entry, no root-owned
  helper, no `/sys` writes. omafan reuses afanctl's existing auditable polkit
  rule.

## Requirements

| Requirement | Detail |
|---|---|
| Omarchy | `4.0.0.alpha` (Quattro); `omarchy-shell` is the only shell |
| afanctl | `>= 0.1.0`, installed **and running** (`/usr/bin/afanctl`) |
| Hardware | pre-T2 Intel Mac with `applesmc` (T2 Macs use `t2fanrd` and are out of scope) |
| Group | your user must be in group `wheel` for the passwordless pkexec writes afanctl's polkit rule grants |
| Node | only to run the test suite; not needed at runtime |

omafan **does not bundle afanctl**. It drives the afanctl binary already
installed on the machine and renders the version it reports, so the plugin and
the daemon cannot drift apart. Install or upgrade afanctl from its own
packaging first ([INSTALL.md](docs/INSTALL.md)).

## Install

1. Install and start **afanctl** (once), from its repository's `packaging/`:

   ```sh
   git clone https://github.com/yadav-prakhar/afanctl.git
   cd afanctl/packaging
   makepkg -si
   sudo systemctl enable --now afanctl
   afanctl status --json
   ```

2. Add omafan from git and enable it:

   ```sh
   omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable
   ```

   The widget's default section is the right-hand side of the bar. If it does
   not appear:

   ```sh
   omarchy plugin enable io.github.yadav-prakhar.omafan --section right
   ```

3. Verify the setup (the plugin is installed under its id):

   ```sh
   OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
   "$OMAFAN_DIR/bin/omafan-ctl" doctor
   "$OMAFAN_DIR/bin/omafan-ctl" status
   omarchy plugin list --json
   ```

   `doctor` prints one line per check (`PASS`/`WARN`/`FAIL`) and names the fix
   for anything it fails; exit code 0 means no `FAIL`. `omarchy plugin list
   --json` should list `io.github.yadav-prakhar.omafan` with `"enabled": true`.

4. Optional but recommended — install the global chords:

   ```sh
   "$OMAFAN_DIR/bin/omafan-keybindings" install
   ```

   See [Global keyboard shortcuts](#global-keyboard-shortcuts).

Full details, including updates and non-standard setups, are in
[docs/INSTALL.md](docs/INSTALL.md).

## Using it

### The bar widget

| Gesture | Action |
|---|---|
| Left click | toggle the panel |
| Right click | if a hold is active, release the fan to firmware auto; otherwise open the panel |
| Wheel up / down | hold ±100 rpm from the current target, or from Medium when nothing is held |
| Hover | tooltip: `Fan 4200 rpm · CPU 64 °C · hold` (state-appropriate) |

The widget text is tinted whenever a hold is active, so a forgotten manual
setting is visible at a glance. It shows one of `icon`, `temp` (default),
`rpm` or `temp+rpm` — see [Settings](#settings).

### The panel

Open it by clicking the widget or running `omarchy-shell omafan toggle`. Six
preset chips sit above an RPM slider; banner rows appear only when something is
wrong, always with the exact fix command. The panel polls the daemon every
`poll_seconds` (default 2) and re-reads status after every write, so it shows
what the daemon reports, never what it asked for.

### Presets

Presets are derived from the live hardware band `[fan_min_rpm, fan_max_rpm]`,
so they stay correct on other pre-T2 Macs. On the reference machine
(`fan1_min=1200`, `fan1_max=7200`):

| Preset | Label | rpm | afanctl verb |
|---|---|---|---|
| `auto` | Auto (firmware) | — | `observe` |
| `off` | Off (hardware floor) | 1200 | `hold 1200` |
| `low` | Low | 2700 | `hold 2700` |
| `med` | Medium | 4200 | `hold 4200` |
| `high` | High | 5700 | `hold 5700` |
| `full` | Full | 7200 | `hold 7200` |

`auto` is the only quiet option. The firmware idles near 1787 rpm on the
reference machine, so `low` (2700 rpm) is **louder** than auto: presets are
floors, not quieter-than-firmware modes. A hold at an rpm that matches no preset
renders as `custom`. The slider covers `fan_min_rpm..fan_max_rpm` in 100 rpm
steps (500 rpm with `Shift`).

### Settings

Three per-widget settings, editable from the shell's bar layout
(`omarchy bar set io.github.yadav-prakhar.omafan show temp+rpm`, or the same
keys in `shell.json`):

| Key | Values | Default | Meaning |
|---|---|---|---|
| `show` | `icon`, `temp`, `rpm`, `temp+rpm` | `temp` | what the bar label renders |
| `poll_seconds` | `1`–`10` | `2` | status refresh interval |
| `release_after_minutes` | `0`–`240` | `0` (never) | return the fan to firmware auto after N idle minutes |

## Keyboard

Everything the pointer can do, a key can do.

### In the panel

| Key | Action |
|---|---|
| `j` / `↓` · `k` / `↑` | move the cursor down / up a section |
| `h` / `←` · `l` / `→` | presets: previous / next preset · slider: −1 / +1 step |
| `Shift` + `h` / `l` | slider: ±500 rpm |
| `Enter` / `Space` | presets: apply the focused preset · slider: apply the current value |
| `1` … `6` | apply `auto, off, low, med, high, full` directly |
| `c` | cycle presets (`auto → off → low → med → high → full → auto`) |
| `r` | refresh status now |
| `?` | toggle the key-map overlay |
| `Esc` | close the key map if open, else close the panel |
| `Tab` / `Shift+Tab` | switch to the next / previous bar panel |
| mouse | hover = cursor, click = apply, wheel on the slider = ±1 step |

On a hot machine (`t_eff_c >= 80 °C`) a preset that would hold the fan *below
its current speed* needs a deliberate second `Enter` or click within 10 s — see
[Safety](#safety-model).

### Global keyboard shortcuts

`bin/omafan-keybindings install` writes one managed block into
`~/.config/hypr/bindings.lua`. Preset and cycle chords call `omafan-ctl`
directly, so they keep working while `omarchy-shell` restarts; only the panel
toggle goes through shell IPC.

| Chord | Action |
|---|---|
| `SUPER + ALT + T` | toggle the fan panel |
| `SUPER + ALT + A` | fans auto (firmware) — the release escape hatch |
| `SUPER + ALT + O` | fans off (hardware floor) |
| `SUPER + ALT + L` | fans low |
| `SUPER + ALT + M` | fans medium |
| `SUPER + ALT + H` | fans high |
| `SUPER + ALT + X` | fans full |
| `SUPER + ALT + C` | cycle presets |

```sh
"$OMAFAN_DIR/bin/omafan-keybindings" status    # installed | not-installed | conflict
"$OMAFAN_DIR/bin/omafan-keybindings" install   # refuses if any chord is already bound
"$OMAFAN_DIR/bin/omafan-keybindings" remove    # restores bindings.lua
"$OMAFAN_DIR/bin/omafan-keybindings" print     # print the block, touch nothing
```

`install` refuses (exit 1) and writes nothing if any of the eight chords is
already bound elsewhere, naming the conflict. `remove` restores the pre-install
file byte-identically when nothing else changed. The first install keeps a
timestamped backup under `~/.local/state/omafan-keybindings/`. All eight chords
were verified free against the live compositor (`hyprctl binds -j`) and the
Omarchy default Lua sources; every `SUPER+digit` combination is taken, so omafan
avoids digits. Origins are recorded in
[docs/KEYBINDINGS.md](docs/KEYBINDINGS.md).

## Safety model

The one-sentence version: **omafan never owns the fan.** It sends the already
installed `afanctl` daemon the same two commands a person would type, and
renders whatever the daemon reports afterwards. The full model is in
[docs/SAFETY.md](docs/SAFETY.md); the operator-facing rules are:

- **"Off" is not off.** The SMC floor is `fan_min_rpm` (1200 rpm on the
  reference machine); the fan cannot be stopped through this interface. Every
  surface says `Off (hardware floor)` and never claims the fan is stopped.
- **Presets are floors, not quiet modes.** `low` is louder than firmware auto;
  `auto` is the quiet option. The panel says so in its legend.
- **The fan is never left unowned.** Control is delegated to afanctl, whose
  documented model fails toward the firmware: per-poll verify/re-assert, an
  async-signal-safe AUTO restore on daemon death, a systemd watchdog, sensor
  loss returns to AUTO, and startup reconciliation restores AUTO out of any
  foreign manual owner. A failed release is surfaced as `auto_restore_pending`
  rather than reported as success.
- **Degraded means read-only.** While the daemon reports `monitor_only`, a
  pending auto-restore, or stale state, the panel disables writes and shows the
  cause plus the exact `systemctl` fix. `--force` exists on the CLI only.
- **Undercooling needs a deliberate override.** A preset below the current rpm
  while the CPU is at or above 80 °C is refused the first time; the warning
  names the temperature, the current rpm, the requested rpm and a safe
  alternative. `--force` (CLI) or a second `Enter` (panel) overrides.
- **A forgotten hold can expire.** `release_after_minutes` (default 0 = never)
  returns the fan to firmware auto after N minutes without interaction.
- **No new privilege surface.** omafan installs nothing privileged and never
  runs as root. Writes go through
  `pkexec /usr/bin/afanctl {hold <rpm>|observe}` using afanctl's own polkit rule
  (`/usr/share/polkit-1/rules.d/49-afanctl.rules`). Read verbs never call
  `pkexec`.
- **Everything is reversible.** The only things omafan writes outside its own
  directory are the managed `bindings.lua` block, its backup, a 24 h hardware
  cache, and the shell's own plugin entry.

There is always a keyboard-only way back to firmware auto, even if
`omarchy-shell` is dead: `SUPER + ALT + A`, or `omafan-ctl release`.

## Command line

`bin/omafan-ctl` is the only component that talks to afanctl. Run it from the
plugin directory:

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
"$OMAFAN_DIR/bin/omafan-ctl" status --json      # omafan.status.v1
"$OMAFAN_DIR/bin/omafan-ctl" presets --human    # the ladder and slider band
"$OMAFAN_DIR/bin/omafan-ctl" doctor --json      # omafan.doctor.v1, names the fixes
"$OMAFAN_DIR/bin/omafan-ctl" preset med --notify
"$OMAFAN_DIR/bin/omafan-ctl" cycle --notify
"$OMAFAN_DIR/bin/omafan-ctl" rpm 3000 --notify
"$OMAFAN_DIR/bin/omafan-ctl" release            # alias of `preset auto`
"$OMAFAN_DIR/bin/omafan-ctl" --help
```

Exit codes: `0` success · `1` runtime failure · `2` usage error ·
`3` authorisation denied/cancelled · `4` afanctl missing · `5` daemon not
running · `6` daemon degraded (writes refused) · `7` rpm out of band ·
`8` undercooling risk. `--dry-run` prints the argv it would run without
executing. `--force` overrides refusals 6, 7 and 8. `status` still prints a
document when the daemon is down (it then exits 5 with
`daemon.running: false`), so scripts should read the document, not just the
exit code. The `--afanctl`, `--runtime-dir` and `--pkexec none` globals are for
tests and development only; see [docs/TESTING.md](docs/TESTING.md).

Shell IPC mirrors the panel: `omarchy-shell omafan toggle|open|close|refresh`,
`omarchy-shell omafan preset med`, `omarchy-shell omafan rpm 3000`,
`omarchy-shell omafan release`, `omarchy-shell omafan state`.

## Uninstall

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
"$OMAFAN_DIR/bin/omafan-ctl" release                    # hand the fan to firmware
"$OMAFAN_DIR/bin/omafan-keybindings" remove             # cut the chord block
omarchy plugin remove io.github.yadav-prakhar.omafan
```

`release` verifies the daemon returns to `mode: observe`, `manual: false`. If
you never installed the chords, skip `remove` (it exits 0 with nothing to do).
The optional backup under `~/.local/state/omafan-keybindings/` and the runtime
cache under `$XDG_RUNTIME_DIR/omafan/` may be deleted afterwards; both are
copies, not state. afanctl itself is untouched by the uninstall — remove it
separately only if you no longer want it.

## Troubleshooting

`"$OMAFAN_DIR/bin/omafan-ctl" doctor` is the first response: it checks afanctl
presence and version, the daemon, state freshness, pkexec, the polkit rule,
`applesmc`, `coretemp`, the hardware band, shell IPC and the keybindings, and
names the fix for each `FAIL`.

| Symptom | Fix |
|---|---|
| No bar widget after install | `omarchy plugin enable io.github.yadav-prakhar.omafan --section right`, then `omarchy-shell shell rescanPlugins` |
| Bar shows the fan glyph, no temperature | daemon stopped or state stale: `systemctl restart afanctl`, then re-run `doctor` |
| Banner: "afanctl is missing" | install afanctl from its `packaging/`; reads report exit 4 |
| Banner: monitor-only | repeated verified-write failures; `systemctl restart afanctl` |
| Write refused, exit 3 | polkit rule missing or no active local session; check `/usr/share/polkit-1/rules.d/49-afanctl.rules` |
| Write refused, exit 8 | hot machine, requested hold below current airflow; pick a higher preset, or override deliberately |
| A chord does nothing | the installed block may point at a moved helper: `"$OMAFAN_DIR/bin/omafan-keybindings" status`, then re-run `install` |
| `omafan-keybindings install` exits 1 | a chord is already bound; it names the conflict and writes nothing |

The full table, with causes and exact commands, is in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## How it differs from the other Mac fan plugins

The marketplace already lists Mac fan plugins. The two closest siblings (both
MIT) and the other entries below require the user to run a root installer —
udev rules, polkit rules, sudoers entries or a root helper — and then read and
write `/sys` themselves or drive a third-party daemon.

| Plugin | Repository | Class |
|---|---|---|
| `benekuehn.macbook-fans` | [benekuehn/omarchy.mac-fans](https://github.com/benekuehn/omarchy.mac-fans) | T2 Macs (`t2fanrd`) |
| `io.github.moerdowo.fan` | [moerdowo/omarchy-mac-fan-control](https://github.com/moerdowo/omarchy-mac-fan-control) | Apple SMC manual control |
| `io.github.deadjoe.mbpfan` | [deadjoe/omarchy-mbpfan](https://github.com/deadjoe/omarchy-mbpfan) | `mbpfan` daemon |
| `io.github.endijs.t2-fan-control` | [Endijs/omarchy-t2-fan-control](https://github.com/Endijs/omarchy-t2-fan-control) | T2 Macs (`t2fanrd`) |
| `kshatriya-abhay.nbfc` | [kshatriya-abhay/omarchy-nbfc-linux-plugin](https://github.com/kshatriya-abhay/omarchy-nbfc-linux-plugin) | `nbfc-linux` |
| `nate.framework.fan-control` | [njhoersch/omarchy-framework-fan-control](https://github.com/njhoersch/omarchy-framework-fan-control) | Framework (`cros_ec`) |

omafan's four differentiators, each a requirement of the build:

1. **Zero new privilege surface.** omafan installs no udev rule, no polkit rule,
   no sudoers entry and no root-owned helper, and never writes `/sys`. It
   reuses afanctl's existing, auditable polkit rule.
2. **The fan is never left unowned.** Control is delegated to afanctl, whose
   documented model fails toward the firmware (per-poll verify/re-assert, the
   async-signal-safe AUTO restore on death, the systemd watchdog, sensor-loss
   AUTO, startup reconcile).
3. **Keyboard-first.** The panel is fully operable without a pointer, and the
   six presets plus a cycle action have global chords proven free against the
   live binding set. None of the siblings documents global shortcuts.
4. **Truthful UI.** Presets are floors; "Off" cannot stop the fan and says so;
   degraded and offline states are rendered from the daemon's own fields, never
   optimistically.

The full survey, with licences and mechanisms, is in
[docs/PRIOR-ART.md](docs/PRIOR-ART.md).

## Documentation

| Document | Contents |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | the full install, verify, update and removal procedure |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | failure modes and their fixes |
| [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) | the key maps and the free-chord evidence |
| [docs/SAFETY.md](docs/SAFETY.md) | the safety model in operator language |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | data flow, file roles, polling, failure surface |
| [docs/TESTING.md](docs/TESTING.md) | the hardware-free gate and the opt-in live suites |
| [docs/PRIOR-ART.md](docs/PRIOR-ART.md) | the sibling survey and the differentiation matrix |
| [docs/PUBLISHING.md](docs/PUBLISHING.md) | the marketplace submission package |
| [CHANGELOG.md](CHANGELOG.md) | release history |

## Licence

GPL-3.0-only, Copyright (C) 2026 Prakhar Yadav, matching afanctl. The full text
is in [LICENSE](LICENSE). None of the sibling projects above is vendored or
combined with this code.
