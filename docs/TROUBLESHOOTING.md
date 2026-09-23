# omafan troubleshooting

Symptom-to-fix lookup for omafan. The design reasons behind the fixes are in
[ARCHITECTURE.md](ARCHITECTURE.md) §5 and [SAFETY.md](SAFETY.md); this page is
the operator's side.

## 1. First response

Run these from the plugin directory. Define it once, and put its `bin/` on
`PATH` for this shell so the commands below are copy-pasteable:

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
export PATH="$OMAFAN_DIR/bin:$PATH"
```

```sh
omafan-ctl doctor                            # every check, with the fix per FAIL
omafan-ctl status                            # mode, temperature, fan rpm, band
omafan-ctl presets                           # the ladder the plugin derives
omarchy plugin list --json                   # is the plugin enabled?
omarchy-shell omafan state                   # is the panel's IPC live?
```

`doctor` checks eleven things: `afanctl_present`, `afanctl_version`,
`daemon_running`, `state_fresh`, `pkexec_present`, `polkit_rule`, `applesmc`,
`coretemp`, `hw_limits`, `shell_ipc` and `keybindings`. Any `FAIL` makes it exit
1; `WARN` does not. The detail string on a failing line is the fix.

To read the running shell's log for omafan QML errors:

```sh
qs log -i "$(qs list --all | awk '/^Instance /{print $2}' | tr -d ':')" --tail 200
```

Nothing in this document requires root, and none of the diagnostic commands
writes to the fan.

## 2. Quick reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `omarchy plugin add` fails | no network / `git` missing / already installed | see §3 |
| Plugin listed, no bar widget | not enabled, or no placement | `omarchy plugin enable io.github.yadav-prakhar.omafan --section right` |
| Bar shows the fan glyph, no temperature | daemon stopped or state stale | `systemctl restart afanctl` |
| Bar temperature frozen | poll too slow or daemon wedged | check `poll_mode`/`poll_seconds` (auto = 2 s); restart afanctl |
| `omarchy-shell omafan toggle` does nothing | plugin not active, or IPC target down | `omarchy-shell shell rescanPlugins`; `omarchy restart shell` |
| Banner: afanctl is missing | dependency not installed | install afanctl from its `packaging/` |
| Banner: daemon is not running / state stale | daemon stopped or wedged | `systemctl restart afanctl` |
| Banner: monitor-only | repeated verified-write failures | `systemctl restart afanctl` |
| Banner: returning to auto | a release is in progress or failing | wait; `status`; restart afanctl if stuck |
| Write refused, exit 3 | pkexec absent / polkit rule missing / no local active session | check the rule; `id -nG` includes `wheel` |
| Write refused, exit 6 | degraded latch | `systemctl restart afanctl` |
| Write refused, exit 7 | rpm outside the hardware band | pick a preset; `omafan-ctl presets` |
| Write refused, exit 8 | hot machine; hold below current airflow | pick a higher preset, or confirm deliberately |
| Preset applied, rpm unchanged | competing owner, or latch | see §7 |
| A chord does nothing | stale helper path after the plugin moved | `omafan-keybindings status`, then `install` |
| `omafan-keybindings install` exits 1 | a chord is already bound | read the named conflict; see §9 |
| No desktop notifications | `notify-send` missing | install `libnotify` (never changes exit codes) |
| `warnings: hardware limits cache not writable` | runtime dir not writable | none required; it degrades to querying afanctl |
| `warnings: afanctl reports schema … newer …` | afanctl is newer than the plugin understands | update the omafan plugin; the recognised fields still render |
| `warnings: afanctl status schema … older …` | afanctl is older than the plugin supports | update afanctl; writes are refused (exit 1) until then |

## 3. The plugin does not install or does not appear

**`omarchy plugin add` fails.** It needs network access and `git`. Check
`command -v git`, then retry with the exact URL. If the plugin is already
present, use `omarchy plugin update io.github.yadav-prakhar.omafan` (or
`omarchy plugin remove io.github.yadav-prakhar.omafan` first). Without network,
clone by hand into the plugin path:

```sh
git clone https://github.com/yadav-prakhar/omafan.git \
  ~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
omarchy plugin enable io.github.yadav-prakhar.omafan --section right
omarchy-shell shell rescanPlugins
```

**The widget does not appear on the bar.** Confirm the plugin is enabled and
placed, then reload:

```sh
omarchy plugin list --json     # expect "enabled": true for the omafan id
omarchy plugin enable io.github.yadav-prakhar.omafan --section right
omarchy-shell shell rescanPlugins
omarchy restart shell
```

The default placement is the right section, from the manifest's
`defaultSection`. To move it later:
`omarchy bar move io.github.yadav-prakhar.omafan --section center --index 0`.

**`omarchy plugin validate .` fails when run in the plugin directory.** It
reports the reason (a missing entry point, a reserved id, a symlink in the
tree); the manifest is the shell's own schema, so fix what it names rather than
bypassing it.

## 4. The bar widget shows the glyph instead of a value

The widget falls back to its fan glyph whenever the daemon did not report a
usable number. It never shows a fabricated `0`. So a glyph means the status
document had no temperature or rpm:

```sh
"$OMAFAN_DIR/bin/omafan-ctl" status --json | jq '.daemon, .fan, .thermal'
```

- `daemon.running: false` or `state_stale: true` → the daemon is stopped or
  wedged: `systemctl status afanctl` then `systemctl restart afanctl`.
- `afanctl.present: false` → the dependency is not installed (exit 4).
- Everything present but `thermal.t_eff_c: null` → the daemon has no valid
  sensor this poll; it returns the fan to AUTO after three such polls. Watch
  `recent_errors` in the document.

A frozen temperature with `state_stale: false` usually means the re-read
cadence is set slow: with `poll_mode` `auto` omafan re-reads every 2 s, with
`custom` it uses your `poll_seconds` (whole seconds 1–10). Check both keys,
then lower the interval — easiest from the panel itself: open the panel and
use the REFRESH row (Custom, then the − stepper), e.g. the equivalent of
`omarchy bar set io.github.yadav-prakhar.omafan poll_mode custom`
followed by
`omarchy bar set io.github.yadav-prakhar.omafan poll_seconds 2`.
This governs how often omafan re-reads status, never how often the daemon
samples the SMC — a wedged daemon still needs `systemctl restart afanctl`.

## 5. The panel does not open

Open it with the bar widget (left click) or `omarchy-shell omafan toggle`. If
nothing happens, the plugin is not active in the running shell:

```sh
omarchy plugin list --json            # enabled: true?
omarchy-shell shell listPlugins       # is the id listed and active?
omarchy-shell shell rescanPlugins
omarchy restart shell
omarchy-shell omafan state            # should return an omafan.status.v1 document
```

`omarchy-shell omafan state` returning a document is proof the panel loaded and
its single `IpcHandler` (target `omafan`) is live. If it returns nothing while
the plugin is enabled, take the shell log with the `qs log` command in §1 and
look for a QML error naming a `Panel.qml`, `BarWidget.qml` or `Model.js` line.

## 6. Writes are refused

Every write refusal has an exit code, a human line naming the fix, and (with
`--json`) an error object. The panel refuses locally with the same reason, so a
banner can appear without a round-trip.

| Exit | Meaning | Fix |
|---|---|---|
| `3` | authorisation denied or cancelled; pkexec missing | confirm the polkit rule exists at `/usr/share/polkit-1/rules.d/49-afanctl.rules`, that your user is in `wheel` (`id -nG`), and that the session is local and active. `omafan-ctl doctor --json` reports both `pkexec_present` and `polkit_rule`. |
| `4` | afanctl missing or not executable | install afanctl from its `packaging/`; check `afanctl --version` |
| `5` | daemon not running, runtime dir unreadable, or `state.json` absent | `systemctl status afanctl`, then `systemctl restart afanctl`. A write never happens in this state. |
| `6` | daemon degraded: `monitor_only` or `auto_restore_pending` | see §7. `--force` overrides, but read the cause first. |
| `7` | rpm outside `[fan_min_rpm, fan_max_rpm]` | use a preset, or a value inside the band from `omafan-ctl presets`. `--force` overrides. |
| `8` | undercooling risk | see §8. |
| `2` | usage error (unknown preset or flag, non-integer rpm) | `omafan-ctl --help`; preset ids are `auto, off, low, med, high, full` |

A read verb (`status`, `presets`, `doctor`) never fails this way and never calls
`pkexec`. `status` still prints a document when the daemon is down — it then
exits 5 with `daemon.running: false`, so read the document, not just the exit
code.

## 7. Degraded daemon and offline states

The panel renders the daemon's own fields; it never guesses.

**Monitor-only.** `daemon.monitor_only: true` means the daemon hit repeated
verified-write failures and is **observing only** — no fan writes are happening.
`recent_errors` names the cause. Reset it:

```sh
omafan-ctl status --json | jq '.daemon, .recent_errors'
systemctl restart afanctl
```

Re-issuing the same command does **not** clear the latch: afanctl ignores a
command whose bytes are identical to the last applied one (its freshness gate).
The documented recovery is to change the command or restart the daemon, which
is why there is no "re-arm" button.

**Returning to auto.** `daemon.auto_restore_pending: true` means the daemon is
still holding the fan while trying to release it. The pending flag is the truth:
the daemon's own `state.json` may already read `mode: observe` while the fan is
still in Manual. Wait a poll, then check `status`; if it is still pending after
a restart of the daemon, read `recent_errors` — a failed AUTO restore means the
write itself is failing, which usually points at the same cause as exit 3.

**A preset applies but the rpm does not change.** Check what the fan is actually
doing first:

```sh
omafan-ctl status --json | jq '.fan, .hold, .daemon'
afanctl status --json \
  | jq '{rpm: .fan.rpm, target_rpm: .fan.target_rpm, manual: .fan.manual,
         mode: .daemon.mode, monitor_only: .daemon.monitor_only}'
```

If the daemon reports `mode: hold` with a `target_rpm` but `.fan.rpm` does not
move toward it, the write is not reaching the hardware: the daemon may be
`monitor_only`, a competing fan owner may be fighting it, or the requested rpm
is outside the fan's live band. afanctl's startup reconcile reclaims AUTO from
any foreign manual owner, so if you run another fan daemon (for example
`mbpfan`), stop it — one fan supervisor should own the fan.

**`state_stale: true` with the daemon running.** The publish loop has stopped
advancing `state.json`. Restart the daemon. Writes are refused while the state
is stale, deliberately: acting on an unreadable state is riskier than waiting.

## 8. Undercooling refusals (exit 8, or a second Enter in the panel)

On a hot machine (`t_eff_c >= 80 °C`), a preset that would hold the fan **below
its current speed** commands less airflow than the firmware already delivers.
The first attempt is refused: the CLI exits 8 with a message naming the
temperature, the current rpm, the requested rpm and a safe alternative; the
panel shows the same warning and sends the preset only on a second `Enter` or
click within 10 s.

The right fix is usually to pick a preset at or above the current rpm (`high` or
`full` while the machine is hot), or `auto`. `auto` and any preset at or above
the current rpm are never blocked.

If you genuinely want the lower preset, the CLI offers
`omafan-ctl preset low --force`, and the panel's second confirmation sends the
same `--force`. This is the only override path; there is no setting that
disables the guard.

## 9. Global keyboard shortcuts

Check the installed block first:

```sh
"$OMAFAN_DIR/bin/omafan-keybindings" status
```

- `not-installed` → `"$OMAFAN_DIR/bin/omafan-keybindings" install`.
- `stale-path` → the plugin moved or was reinstalled after the block was
  written; the block still calls the old helper path. Re-run `install`; it
  rewrites the block with the current absolute path.
- `conflict` → another binding owns one of the eight chords. `install` exits 1,
  writes nothing and names the chord and its current description. Find the owner
  with `hyprctl binds -j`, then either free the chord or rebind by hand (see
  [KEYBINDINGS.md](KEYBINDINGS.md) §5). Do not re-run `install` until the
  conflict is gone.
- Installed and `ok`, but a chord still does nothing → the compositor has not
  picked the block up: `hyprctl reload`, then re-run `status`.

`install` also refuses if the helper path is missing, or if it contains
whitespace, a quote or a backslash (it is embedded in a Lua string Hyprland
hands to a shell). Move the plugin under a path without those characters and
re-run `install`.

`remove` cuts only the managed `-- BEGIN omafan` … `-- END omafan` block and
restores the pre-install file when nothing else changed; it exits 0 when there
is nothing to remove. If chords remain after `remove`, they are yours, outside
the block.

## 10. Notifications

`--notify` uses `notify-send` when it is present. A missing or failing
`notify-send` never changes the exit code and never blocks the action — the fan
command itself still runs. If you want the toasts, install `libnotify`. This is
the only part of a preset action that can silently do nothing, by design.

## 11. Diagnostics for developers

The plugin is testable without hardware or root, and the fixtures refuse the
live runtime directory. To point the CLI (and the panel, through its
`OMAFAN_AFANCTL`/`OMAFAN_RUNTIME_DIR`/`OMAFAN_PKEXEC` passthrough) at a fixture:

```sh
tmp="$(mktemp -d)"
cp tests/fixtures/state-hold.json "$tmp/state.json"
"$OMAFAN_DIR/bin/omafan-ctl" status --json \
  --afanctl tests/fixtures/fake-afanctl --pkexec none --runtime-dir "$tmp"
```

`--dry-run` prints the argv a write would use and executes nothing. The
hardware-free gate is `tests/run-all.sh`; the two live suites are opt-in
(`OMAFAN_LIVE=1`, `OMAFAN_HW=1`) and are documented in
[TESTING.md](TESTING.md). Never run the live hardware suite while the machine is
hot and never leave a hold in place: `omafan-ctl release` returns the fan to
firmware auto, and `afanctl status --json | jq '.daemon.mode, .fan.manual'`
proves it.

## 12. If nothing here helps

Collect the four outputs below — they contain everything needed to diagnose the
plugin without touching the fan — and attach them to a report:

```sh
"$OMAFAN_DIR/bin/omafan-ctl" doctor --json
"$OMAFAN_DIR/bin/omafan-ctl" status --json
afanctl status --json
omarchy plugin list --json
```

The first command's `FAIL` lines name the fix directly; the status documents
show whether the problem is the plugin, the daemon or the hardware.
