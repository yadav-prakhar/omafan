# Security policy

## Scope

This policy covers the code in this repository: the Quickshell plugin
(`BarWidget.qml`, `Panel.qml`, `KeyboardHelp.qml`, `Model.js`) and the helpers in
`bin/`. The **afanctl** daemon and its polkit rule are a separate project and are
handled there — omafan only calls the daemon's documented command channel.

## What "security" means for this project

omafan's threat surface is unusual: it does not handle credentials or network
input, but it can command a fan, and it asks a system daemon to do it on the
user's behalf. The properties that must hold:

1. **No new privilege surface.** omafan installs no udev rule, no polkit rule, no
   sudoers entry, no setuid binary and no root-owned helper, and never runs as
   root. The only privileged call is `pkexec /usr/bin/afanctl {hold <rpm>|observe}`
   under afanctl's existing rule.
2. **Writes never touch `/sys`.** No file in this repository reads or writes
   `/sys`, `/etc`, `/usr` or `/run/afanctl`. The daemon owns the fan.
3. **The privileged argv is exact.** afanctl's polkit rule pins the program and
   the argv, so omafan never inserts a wrapper (`env …`) or extra flags between
   the runner and the daemon — that form is what causes a fallback to a password
   prompt, and a hanging prompt is treated as a refusal, never as success.
4. **Refusals fail closed.** Degraded daemon (`monitor_only`,
   `auto_restore_pending`), unreadable or stale state, an out-of-band rpm, and an
   undercooling risk (a preset below the current rpm at `t_eff_c ≥ 80 °C`) all
   refuse the write, with a documented exit code. Unreadable state is treated as
   stale, not as fresh.
5. **The fan is never left unowned.** Control is delegated to afanctl, whose
   model fails toward the firmware: per-poll verify and re-assert, an async
   AUTO restore if the daemon dies, a systemd watchdog, and startup reconcile.
6. **A hold is always reversible and visible.** A manual hold tints the bar
   widget, and `SUPER + ALT + A` (or `bin/omafan-ctl release`) returns the fan to
   firmware control even when the shell is dead.

## Reporting a vulnerability

Report through **GitHub's private vulnerability reporting** on this repository
(Security → *Report a vulnerability*). If the issue is not sensitive — for
example a documentation error — a normal issue is fine.

Please include:

- the exact command or interaction, and what happened;
- `bin/omafan-ctl doctor --human` output;
- Omarchy version (`cat /usr/share/omarchy/version`), afanctl version
  (`afanctl --version`) and the plugin version (`manifest.json`);
- your Mac model, if the report is hardware-dependent.

Redact anything personal from pasted output (absolute paths with your username,
serials, tokens). There is no bug bounty and no SLA — this is a
single-maintainer project, and reports are handled best-effort. Fixes ship in a
patch release with a `CHANGELOG.md` entry that credits the reporter unless you
ask otherwise.

## Out of scope

- The afanctl daemon, its polkit rule or its service unit — report those to
  [afanctl](https://github.com/yadav-prakhar/afanctl).
- Omarchy's shell, Quickshell itself, or the compositor.
- Anything requiring an attacker who already has your user account's privileges
  and can run arbitrary code, unless it grants *additional* privilege or persists
  across reboots.
- The fan behaving as the hardware limits dictate (for example `Floor` staying at
  the hardware minimum): that is documented behaviour, not a vulnerability.

## Supported versions

Fixes are produced for the latest `1.0.x` on `master`. Older releases are not
patched; upgrade with `omarchy plugin update io.github.yadav-prakhar.omafan`.
