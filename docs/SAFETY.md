# omafan safety model

This is DESIGN.md §8 written for an operator rather than a reviewer: what
omafan may change, what it may not, and which guarantees of the fan daemon it
depends on. Read it before installing.

The one-sentence version: **omafan never owns the fan.** It sends the
already-installed `afanctl` daemon the same two commands a person would type
(`observe` to hand the fan back to the firmware, `hold <rpm>` to hold a
speed), and it renders whatever the daemon reports afterwards.

## 1. The privilege boundary

omafan adds **no** privileged surface of its own:

- It installs no udev rule, no polkit rule, no sudoers entry, no setuid binary
  and no root-owned helper. It does not run as root and never asks to.
- It never writes `/sys`, never edits `/etc`, never installs a systemd unit,
  and never executes anything from the plugin directory as root.
- The only privileged operation it can perform is
  `pkexec /usr/bin/afanctl {hold <rpm>|observe}`, and it does so through
  afanctl's **existing, auditable** polkit rule
  `/usr/share/polkit-1/rules.d/49-afanctl.rules`. That rule — part of afanctl's
  own packaging (afanctl's `packaging/` directory, README §Install) — grants
  exactly
  `status [--json]`, `observe`, `curve` and `hold <integer-rpm>` to members of
  group `wheel` in a local, active session (sibling README §"Plugin surface
  (omafan presets)"). omafan uses only `status`, `hold` and `observe`; it never
  uses `curve`.
- Read verbs (`status`, `presets`, `doctor`) never run `pkexec` at all.
  `afanctl status --json` is world-readable, so diagnosis works without any
  privilege (PRD §2.3).

If the polkit rule is missing or the session is not local/active, the write
fails cleanly with exit code 3, a human line, and the JSON error envelope. It
does not fall back to anything privileged.

## 2. What omafan writes

Outside its own plugin directory, omafan writes only:

| Path | When | How to undo |
|---|---|---|
| `~/.config/hypr/bindings.lua` (a single `-- BEGIN omafan` … `-- END omafan` block) | `bin/omafan-keybindings install` | `bin/omafan-keybindings remove` (restores the pre-install file byte-identically when nothing else changed) |
| `~/.local/state/omafan-keybindings/bindings.lua.<stamp>` | first install, one backup | delete it; it is a copy of your file |
| `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback `/tmp/omafan-<uid>/hw.json`) | `status` learning the fan band | delete it; it is a 24 h cache |
| `~/.config/omarchy/shell.json` (the plugin's enable entry) | `omarchy plugin enable` — the shell's own command, not omafan code | `omarchy plugin remove io.github.yadav-prakhar.omafan` |
| the plugin directory itself | installer | `omarchy plugin remove io.github.yadav-prakhar.omafan` |

It writes nothing to `/run/afanctl` — that directory belongs to the root
daemon. In particular, `omafan-ctl` passes the runtime directory to afanctl as
the `AFANCTL_RUNTIME_DIR` environment variable; it never creates or edits
`cmd.json` itself.

## 3. What the plugin refuses to do

- **Degraded daemon → no writes.** While the daemon reports `monitor_only` or
  `auto_restore_pending`, the panel disables writes and renders the cause plus
  the exact fix; the CLI refuses with exit 6. The `--force` override exists on
  the CLI only, never as a panel default.
- **Out-of-band rpm → no writes.** An rpm outside the live
  `[fan_min_rpm, fan_max_rpm]` band is refused with exit 7.
- **Undercooling → deliberate confirmation.** On a hot machine
  (`t_eff_c >= 80 °C`), a preset that would hold the fan *below its current
  speed* commands less airflow than the firmware already delivers. The first
  attempt is refused (exit 8) and the panel requires a second `Enter`/click
  within 10 s; the warning names the temperature, the current rpm, the
  requested rpm and a safe alternative. This exists because the reference
  machine was observed at 97 °C with the firmware at 4794 rpm, where `floor`,
  `low` and `med` all reduce airflow (DESIGN.md §5.1).
- **"Floor" is not off.** The SMC floor is `fan_min_rpm` (1200 rpm on the
  reference machine); sysfs cannot stop the fan. Every surface renders
  `Floor (hardware floor)`, never "fan off" (DESIGN.md §3).
- **Presets are floors, not quiet modes.** Firmware auto idles near 1787 rpm
  on the reference machine, so `low` (2700 rpm) is *louder* than auto. `auto`
  is the only quiet option, and the panel says so in its legend.
- **A forgotten hold can expire.** `release_after_minutes` (setting, default 0
  = never) returns the fan to firmware auto after N minutes without
  interaction. The timer restarts whenever a poll discovers an active hold.
- **The bar shows a manual hold.** The widget is tinted whenever a hold is
  active, so a forgotten setting is visible at a glance.

## 4. The afanctl guarantees omafan leans on

omafan delegates fan ownership to afanctl, so its safety story is only as good
as afanctl's. The following are afanctl's documented behaviours, quoted or
paraphrased from the afanctl repository
(https://github.com/yadav-prakhar/afanctl, README §"Safety model" and
§"Plugin surface (omafan presets)"); afanctl itself is GPL-3.0-only and shipped
and hardware-verified (afanctl README, preamble).

- **Fail toward the firmware.** "afanctl is built around the principle *fail
  toward the firmware*." Every degradation path ends with the firmware running
  the fan again. omafan cannot prevent this; it only displays it.
- **L1 — per-poll verify/re-assert.** Every poll re-reads `fan1_manual` and
  `fan1_input`; a deviation is re-asserted, and only genuine write/verification
  failures feed the 3-strike ladder that degrades to AUTO + monitor-only. A fan
  that has stopped moving is caught by a separate stall detector. So a hold
  that cannot be maintained becomes a visible degraded state, not a silently
  ignored one.
- **L2 — death path.** At startup the daemon pre-opens a write fd on
  `fan1_manual`; a panic hook and raw signal handlers write `0` (AUTO) in one
  async-signal-safe syscall. If the daemon dies unexpectedly, the fan is
  released rather than left held.
- **L3 — systemd-first.** `Type=notify` with `WatchdogSec=15`, `Restart=always`
  and `StartLimitIntervalSec=0`, plus sandboxing (`ProtectSystem=strict`,
  `ReadWritePaths` pinned to the applesmc platform directory,
  `NoNewPrivileges`). A hang becomes a restart, and a crash-loop keeps
  restarting rather than dying in a held state.
- **Sensor loss → AUTO.** Three consecutive polls with no valid temperature
  and the supervisor returns the fan to the firmware. omafan's own writes are
  therefore not needed for thermal safety if a sensor fails.
- **Startup reconcile is unconditional.** At (re)start the daemon restores AUTO
  out of *any* manual owner it finds, including a live foreign program. This is
  why "restart afanctl" is a valid recovery from a stuck manual state.
- **A failed AUTO restore is never silent.** If releasing the fan does not
  verify, the daemon keeps trying and exposes `auto_restore_pending: true`
  until a verified read-back confirms AUTO. omafan renders that flag as a
  degraded banner and refuses writes while it is set — it never claims the fan
  was released before the daemon says so.
- **The `monitor_only` latch is the truth.** `true` means the daemon is
  observing only: no fan writes. omafan renders the latch, not the commanded
  `mode`, and points at the documented recovery.
- **The freshness gate.** A re-issued command whose bytes are byte-identical to
  the last applied one is ignored. That is why omafan does not offer a "re-arm"
  button: the documented recovery after a `monitor_only` latch is to change the
  command or restart the daemon (`systemctl restart afanctl`), and omafan says
  exactly that.
- **A present-but-broken config refuses to start** rather than silently
  selecting a different curve, so the daemon omafan talks to is either the
  configured one or absent — never a different policy.

omafan does **not** rely on afanctl's own preset mapping (`low 1200 / med 4000
/ high 5800`, sibling README table). It derives its ladder from the live
hardware band (`fan_min_rpm`, `fan_max_rpm`) so the same plugin is correct on
other pre-T2 Macs (DESIGN.md §3, PRD F4).

## 5. Recovery playbook

| Symptom | What it means | Do this |
|---|---|---|
| banner: "afanctl is missing" | dependency not installed | install afanctl; `systemctl restart afanctl` |
| banner: "daemon is not running" / "state is stale" | daemon stopped or wedged | `systemctl restart afanctl` |
| banner: "monitor-only" | repeated verified-write failures; no writes are happening | `systemctl restart afanctl` |
| banner: "returning the fan to firmware auto" | release in progress | wait; check `omafan-ctl status` |
| write refused, exit 3 | polkit rule missing / no active local session | check `/usr/share/polkit-1/rules.d/49-afanctl.rules`; `omafan-ctl doctor --json` |
| write refused, exit 8 | hot machine, requested hold below current airflow | pick a higher preset, or confirm deliberately |
| keybindings absent | block not installed | `bin/omafan-keybindings install` |

There is always a keyboard-only way back to firmware auto even if the shell is
dead: `omafan-ctl release`, or the `SUPER + ALT + A` chord, both of which call
`omafan-ctl` directly rather than going through `omarchy-shell` (DESIGN.md §7,
PRD K4).

## 6. Reversibility

Every change omafan makes to the machine can be undone, and the undo is
documented and exercised:

- **Plugin:** `omarchy plugin remove io.github.yadav-prakhar.omafan`.
- **Keybindings:** `bin/omafan-keybindings remove` restores `bindings.lua`
  byte-identically when nothing else changed; the first install also keeps a
  timestamped backup under `~/.local/state/omafan-keybindings/`.
- **Fan state:** `omafan-ctl release` (or `SUPER + ALT + A`) hands the fan
  back to the firmware; `afanctl status --json` confirms `mode: observe` and
  `manual: false`.
- **Cache:** delete `$XDG_RUNTIME_DIR/omafan/` — it is a cache, not state.

The plugin is not a background service, opens no port, and installs no unit.
Removing it leaves nothing running.
