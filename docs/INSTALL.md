# Installing omafan

This guide takes a stock Omarchy 4.0.0.alpha machine to a working omafan
install: the **afanctl** dependency first, then the plugin, then (optionally)
the global keyboard shortcuts. It then covers settings, updates, removal and the
paths omafan writes.

Everything here is reversible, and the undo is written next to each step. If
something fails, [TROUBLESHOOTING.md](TROUBLESHOOTING.md) has the fix per
symptom; `bin/omafan-ctl doctor` is the first command to run.

## 1. Before you start

| Requirement | Check |
|---|---|
| Omarchy `4.0.0.alpha` (Quattro) with `omarchy-shell` | `cat /usr/share/omarchy/version` |
| afanctl `>= 0.1.0`, installed and running | `afanctl --version`, `systemctl status afanctl` |
| Pre-T2 Intel Mac with `applesmc` | `ls /sys/devices/platform/applesmc.768` |
| Your user is in group `wheel` | `id -nG` (the polkit rule grants writes to `wheel` in a local, active session) |
| `git`, `makepkg` and a Rust toolchain (afanctl build) | `command -v git makepkg cargo` |

T2 Macs (`t2fanrd`) and other laptop classes are out of scope: omafan targets
the pre-T2 `applesmc` single fan only.

omafan **does not bundle afanctl** and will not install it for you. It drives
whichever afanctl binary is installed, and `bin/omafan-ctl status` reports that
binary's path and version, so the plugin and the daemon cannot silently drift.
Upgrade afanctl through its own packaging, not through omafan.

## 2. Step 1 — install and start afanctl

afanctl is a separate project. Its packaging lives in `packaging/` in its own
repository and contains the `PKGBUILD`, the systemd unit, the default config and
the polkit rule.

```sh
git clone https://github.com/yadav-prakhar/afanctl.git
cd afanctl/packaging
makepkg -si
```

`makepkg -si` builds the package and installs it through `sudo` (run `makepkg`
itself as your user, never as root). The unit is installed **disabled**, and the
daemon starts in `observe` mode — nothing is changed until you enable it:

```sh
sudo systemctl enable --now afanctl
systemctl status afanctl
afanctl status --json
```

The package installs:

| Path | Purpose |
|---|---|
| `/usr/bin/afanctl` | the binary omafan drives |
| `/usr/lib/systemd/system/afanctl.service` | the unit (`Type=notify`, watchdog, restart-always) |
| `/etc/afanctl/afanctl.toml` | config (`pacman` `backup=`-protected) |
| `/usr/share/afanctl/afanctl.toml.default` | pristine default config |
| `/usr/share/polkit-1/rules.d/49-afanctl.rules` | the passwordless pkexec rule for `status`, `observe`, `curve` and `hold` |

afanctl starts in `observe`, so the fan is on the firmware curve and omafan's
read verbs work immediately. Writes (`hold`, `observe` through pkexec) are what
the polkit rule covers; reads never need privilege.

To undo this step: `sudo systemctl disable --now afanctl` and remove the
`afanctl` package. omafan does not depend on afanctl being removed with it.

## 3. Step 2 — install the plugin

```sh
omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable
```

This clones the repository to
`~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/` and enables the
`bar-widget`, which defaults to the right-hand section of the bar. Define the
directory once for the examples below:

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
```

If the widget does not appear, confirm the enable and its placement:

```sh
omarchy plugin enable io.github.yadav-prakhar.omafan --section right
omarchy-shell shell rescanPlugins
omarchy plugin list --json
```

`omarchy plugin list --json` must list `io.github.yadav-prakhar.omafan` with
`"enabled": true`. To place it elsewhere on the bar, pass a different section
(for example `--section left`), or move it later with
`omarchy bar move io.github.yadav-prakhar.omafan --section center --index 0`.

### If `omarchy plugin add` cannot run

The command needs network access and `git`. Without it, clone by hand into the
exact plugin path and enable it:

```sh
git clone https://github.com/yadav-prakhar/omafan.git \
  ~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
omarchy plugin enable io.github.yadav-prakhar.omafan --section right
omarchy-shell shell rescanPlugins
```

## 4. Step 3 — verify

```sh
"$OMAFAN_DIR/bin/omafan-ctl" doctor
"$OMAFAN_DIR/bin/omafan-ctl" status
omarchy-shell omafan state
```

- `doctor` runs eleven checks and prints `PASS`/`WARN`/`FAIL` per line, with the
  fix for every `FAIL` (exit 0 means no `FAIL`; `WARN` never fails the run).
- `status` prints a one-screen summary: mode, temperature, fan rpm and the
  hardware band. Add `--json` for the `omafan.status.v1` document.
- `omarchy-shell omafan state` returns that JSON document from the running
  panel. A response here proves the plugin loaded and its IPC target is live.

Also worth a look while the panel is open:

```sh
omarchy-shell omafan toggle     # open the panel
omarchy-shell omafan close
```

The plugin should also be visible in the bar as a temperature readout. If it is
not, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

To undo this step: `omarchy plugin remove io.github.yadav-prakhar.omafan`.

## 5. Step 4 — global keyboard shortcuts (optional, recommended)

```sh
"$OMAFAN_DIR/bin/omafan-keybindings" install
"$OMAFAN_DIR/bin/omafan-keybindings" status
```

`install` writes one managed `-- BEGIN omafan` … `-- END omafan` block into
`~/.config/hypr/bindings.lua`, reloads Hyprland and confirms the eight chords.
It is idempotent. If **any** chord is already bound to something else it refuses
(exit 1), writes nothing and names the conflict; `status` shows per-chord
verdicts plus `stale-path` if the installed block calls a helper that no longer
resolves. The first install keeps a timestamped backup in
`~/.local/state/omafan-keybindings/`.

| Chord | Action |
|---|---|
| `SUPER + ALT + T` | toggle the fan panel |
| `SUPER + ALT + A` | fans auto (firmware) |
| `SUPER + ALT + O` | fans floor |
| `SUPER + ALT + L` | fans low |
| `SUPER + ALT + M` | fans medium |
| `SUPER + ALT + H` | fans high |
| `SUPER + ALT + X` | fans full |
| `SUPER + ALT + C` | cycle presets |

The chord set is frozen and verified free against the live compositor and the
Omarchy default sources; there is no rebind flag. See
[KEYBINDINGS.md](KEYBINDINGS.md) for the evidence and for how to rebind by hand.

To undo this step: `"$OMAFAN_DIR/bin/omafan-keybindings" remove`.

## 6. Settings

Three per-widget settings live in the shell's bar layout. Change them with
`omarchy bar set` (use the plugin id as the widget id) or edit `shell.json`
directly:

```sh
omarchy bar set io.github.yadav-prakhar.omafan show temp+rpm
omarchy bar set io.github.yadav-prakhar.omafan poll_seconds 5
omarchy bar set io.github.yadav-prakhar.omafan release_after_minutes 30
```

| Key | Values | Default | Meaning |
|---|---|---|---|
| `show` | `icon`, `temp`, `rpm`, `temp+rpm` | `temp` | what the bar label renders |
| `poll_seconds` | `1`–`10` | `2` | status refresh interval |
| `release_after_minutes` | `0`–`240` | `0` (never) | return the fan to firmware auto after N minutes without interaction |

`release_after_minutes` is an optional safety net for a forgotten hold; its
timer restarts whenever a poll discovers an active hold.

## 7. Updating

afanctl and omafan update independently.

```sh
# afanctl: from its own checkout
cd afanctl && git pull
cd packaging && makepkg -si
sudo systemctl restart afanctl

# omafan: from git, then reload the shell
omarchy plugin update io.github.yadav-prakhar.omafan
omarchy restart shell
```

After updating omafan, re-run `"$OMAFAN_DIR/bin/omafan-keybindings" install`
once: it refreshes the managed block to the new absolute helper path. The
plugin is stateless; no migration is needed.

## 8. Uninstall

In this order, so the fan is handed back before the tool that can release it is
removed:

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
"$OMAFAN_DIR/bin/omafan-ctl" release                 # verify mode: observe below
"$OMAFAN_DIR/bin/omafan-keybindings" remove          # cut the chord block
omarchy plugin remove io.github.yadav-prakhar.omafan
```

`release` prints the daemon's mode; `"$OMAFAN_DIR/bin/omafan-ctl" status` or
`afanctl status --json` should show `mode: observe` and `manual: false`. If you
never installed the chords, skip `remove` — it exits 0 with nothing to do.

Optional cleanup (both are copies, not state):

```sh
rm -rf ~/.local/state/omafan-keybindings
rm -rf "$XDG_RUNTIME_DIR/omafan"
rm -rf "/tmp/omafan-$(id -u)"
```

The last two lines are the two possible locations of the hardware-limit cache
(`$XDG_RUNTIME_DIR/omafan/`, or `/tmp/omafan-<uid>/` when `XDG_RUNTIME_DIR` is
unset); removing the one that exists is enough.

Removing the plugin leaves nothing running: it is not a service and opens no
port. afanctl is left installed and running; remove it separately only if you no
longer want it.

## 9. What omafan writes

Outside its own plugin directory, omafan writes only:

| Path | When | Undo |
|---|---|---|
| `~/.config/hypr/bindings.lua` (one managed block) | `omafan-keybindings install` | `omafan-keybindings remove` |
| `~/.local/state/omafan-keybindings/bindings.lua.<stamp>` | first install (one backup) | delete the directory |
| `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback `/tmp/omafan-<uid>/hw.json`) | learning the fan band (24 h cache) | delete the directory |
| `~/.config/omarchy/shell.json` (the plugin's enable entry) | `omarchy plugin add/enable` — the shell's own command | `omarchy plugin remove io.github.yadav-prakhar.omafan` |
| the plugin directory itself | the installer | `omarchy plugin remove io.github.yadav-prakhar.omafan` |

It never writes `/sys`, `/etc`, `/usr`, or `/run/afanctl`, and it never runs as
root. The only privileged call it makes is
`pkexec /usr/bin/afanctl {hold <rpm>|observe}`, under afanctl's own polkit rule.
The full model is in [SAFETY.md](SAFETY.md).

## 10. Non-standard setups

These overrides exist for tests and unusual configurations; none is needed on a
stock Omarchy install.

| Variable | Effect |
|---|---|
| `OMAFAN_AFANCTL` | the afanctl binary the panel's CLI calls |
| `OMAFAN_RUNTIME_DIR` | the directory holding `state.json` (default `/run/afanctl`) |
| `OMAFAN_PKEXEC` | the privilege runner; `none` runs afanctl directly (tests/dev only) |
| `OMAFAN_HYPR_CONFIG` | the target file for `omafan-keybindings` |
| `OMAFAN_HYPRCTL` | the `hyprctl` command the installer calls |
| `OMAFAN_STATE_DIR` | the keybinding backup directory |
| `OMAFAN_CTL` | the helper the emitted binding block will call |
| `OMAFAN_DEFAULT_BINDINGS_DIR` | the Omarchy default Lua tree the conflict check scans |

Pointing the panel at a fake afanctl (a fixture, never the live daemon) is how
the plugin is tested without touching the fan; see [TESTING.md](TESTING.md).
Nothing here is required to use omafan normally.

## 11. Next steps

- [../README.md](../README.md) — what omafan is and how to use it.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — symptom-to-fix lookup.
- [KEYBINDINGS.md](KEYBINDINGS.md) — the full key map and rebinding.
- [SAFETY.md](SAFETY.md) — why "off is not off" and what the daemon guarantees.
