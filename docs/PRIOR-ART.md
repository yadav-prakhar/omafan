# omafan prior art

This document records the fan-control plugins that already exist in the
Omarchy marketplace, their licences, what they do, and how omafan differs.
It exists so a reader can check the "not a duplicate" claim in PRD §1.1 and
so the licences of referenced work are on the record (PRD §3.5).

None of these projects is vendored. They were studied from their marketplace
listings and public repositories during recon on 2026-09-15; the findings
informed omafan's differentiation and troubleshooting list only. No code was
copied.

## 1. The survey

Marketplace snapshot: `https://plugins.omarchy.org/catalog.json`, captured to
`.recon/fan-plugins.json` (3153 listings at 2026-09-14T21:41Z, PRD §2.6).
The Mac/SMC fan plugins named in PRD §1.1:

| Plugin id | Name | Repository | Licence (catalog) | Class | What it does |
|---|---|---|---|---|---|
| `benekuehn.macbook-fans` | MacBook Fans | `github.com/benekuehn/omarchy.mac-fans` | MIT | T2 Mac fan profiles and live fan speeds | T2 fan profiles (`t2fanrd`) + live rpm |
| `io.github.moerdowo.fan` | Fan | `github.com/moerdowo/omarchy-mac-fan-control` | See repository | Apple SMC manual fan control | manual fan speed control for Apple SMC laptops |
| `io.github.deadjoe.mbpfan` | MBPFan | `github.com/deadjoe/omarchy-mbpfan` | MIT | Apple `mbpfan` daemon | CPU temperature, fan speeds, editable fan-control defaults |
| `io.github.endijs.t2-fan-control` | T2 Fan Control | `github.com/Endijs/omarchy-t2-fan-control` | MIT | T2 Macs (`t2fanrd`) | monitor and configure `t2fanrd` from the bar |
| `kshatriya-abhay.nbfc` | Fan Control | `github.com/kshatriya-abhay/omarchy-nbfc-linux-plugin` | MIT | `nbfc-linux` (generic laptop EC) | `nbfc-linux` fan control with live animated fan art |
| `nate.framework.fan-control` | Omarchy Framework Fan Control | `github.com/njhoersch/omarchy-framework-fan-control` | MIT | Framework laptops (`cros_ec` hwmon) | automatic and ten-step manual fan control |

Two further entries in the same recon snapshot are adjacent rather than
competing, and are listed for completeness:

| Plugin id | Name | Repository | Licence (catalog) | Note |
|---|---|---|---|---|
| `io.github.elynch303.fan-monitor` | Fan Monitor | `github.com/elynch303/fan-monitor` | See repository | read-only badge: polls `lm_sensors`, no control |
| `eduard.cooler-control` | Cooler Control | `github.com/eddygarcas/omarchy-cooler-control` | MIT | generic `pwm` fan curves for any hwmon device |

### Licence notes

- Licences above are the marketplace catalog's `license` field, captured
  verbatim during recon. "See repository" means the listing did not declare
  an SPDX licence; the project's own repository is the authority.
- PRD §1.1 characterises the two closest siblings as "both MIT". The catalog
  entry for the T2 `MacBook Fans` plugin is MIT; the catalog entry for
  `io.github.moerdowo.fan` reads "See repository", so its MIT status is
  asserted by PRD §1.1 (read from the repository during recon) rather than by
  the catalog. Where the two disagree, the repository governs.
- omafan itself is `GPL-3.0-only`, matching afanctl (PRD §3.5). The sibling
  projects are not combined with it and no licence compatibility question
  arises.

### Mechanism notes

Per PRD §1.1 and §2.6, the existing Mac fan plugins require the user to run a
root installer that writes `/etc/udev/rules.d/*`, `/etc/polkit-1/rules.d/*`,
sudoers entries or a `/usr/local/libexec` helper, and then read/write `/sys`
(or drive a third-party daemon such as `t2fanrd`, `mbpfan` or `nbfc-linux`)
themselves. PRD §2.6 records that **none of them documents global keyboard
shortcuts**. Those are the two facts the differentiation below turns on; the
per-plugin mechanism column is the marketplace description plus that recon
characterisation, not a per-repository audit.

## 2. Differentiation matrix

| Dimension | omafan | T2 plugins (`benekuehn`, `endijs`) | Apple SMC plugin (`moerdowo`) | `mbpfan` plugin (`deadjoe`) | `nbfc` (`kshatriya-abhay`) | Framework (`nate`) |
|---|---|---|---|---|---|---|
| Target machine | pre-T2 Intel Mac (`applesmc`, single fan) | T2 Macs (`t2fanrd`) | Apple SMC laptops | Apple SMC via `mbpfan` | generic laptop EC via `nbfc-linux` | Framework via `cros_ec` |
| Fan control path | delegates to installed `afanctl` (its own daemon) | drives `t2fanrd` | reads/writes `/sys` itself, per PRD §1.1 | drives `mbpfan` | drives `nbfc-linux` | reads/writes `cros_ec` hwmon |
| Privilege the plugin adds (R1) | none: no udev/polkit/sudoers/root helper; reuses afanctl's existing polkit rule | root installer and/or `/sys` access, per PRD §2.6 | root installer + `/sys`, per PRD §1.1 | root installer and/or `/sys`, per PRD §2.6 | root installer and/or `/sys`, per PRD §2.6 | root installer and/or `/sys`, per PRD §2.6 |
| Who owns the fan when omafan is idle (R2) | the firmware: afanctl fails toward AUTO on any fault | the third-party daemon | the plugin / user-written values | `mbpfan` | `nbfc-linux` | the plugin / kernel |
| Keyboard-first (R3) | in-panel full keyboard model, plus eight machine-verified global chords | none documented (PRD §2.6) | none documented | none documented | none documented | none documented |
| Truthful UI (R4) | "Off" is `Off (hardware floor)`; presets are floors; degraded/offline latches rendered from daemon fields; undercooling needs explicit override | not specified in the listing | not specified in the listing | not specified in the listing | not specified in the listing | not specified in the listing |
| Dependencies | `afanctl` ≥ 0.1.0 (installed, running, GPL-3.0) | `t2fanrd` | none beyond the installer | `mbpfan` | `nbfc-linux` | `cros_ec` hwmon |
| Presets derived from live band | yes (`fan_min_rpm`…`fan_max_rpm`, so it travels to other pre-T2 Macs) | n/a | n/a | n/a | n/a | n/a |

## 3. What is deliberately out of scope

PRD §1 names these as explicitly out of scope, and they are also what omafan
does **not** take from the prior art:

- T2 Macs (`t2fanrd`) and other laptop classes; omafan targets pre-T2 Intel
  Macs only.
- Bundling or installing `afanctl`; it is a prerequisite the operator installs
  from its own packaging.
- Fan curves and internal control policy; that is afanctl's job, not the
  plugin's. omafan offers presets and a slider, not a curve editor.
- Direct `/sys` writes of any kind.
- A second Quickshell process, any Omarchy system-package change, or any
  submission to the marketplace (prepared, not sent).

## 4. Why this is not a duplicate

The claim reduces to four facts, each traceable above and each a requirement
(PRD §1.1):

1. **Zero new privilege surface (R1).** omafan installs no udev rule, no
   sudoers entry, no root-owned helper and never writes `/sys`. It reuses the
   installed afanctl polkit rule. No sibling advertises this.
2. **The fan is never left unowned (R2).** Control is delegated to afanctl,
   whose documented model fails toward the firmware (per-poll verify, an
   async-signal-safe AUTO restore on death, a systemd watchdog, sensor-loss
   AUTO, startup reconcile). omafan renders those guarantees; it does not
   replace them.
3. **Keyboard-first (R3).** The panel is fully operable without a pointer, and
   the six presets plus a cycle action have global chords proven free against
   the live compositor and the default Lua sources (KEYBINDINGS.md §3). PRD
   §2.6 records that no sibling documents global shortcuts.
4. **Truthful UI (R4).** Presets are floors, "Off" cannot stop the fan and says
   so, degraded/offline states come from the daemon's own fields, and a hot
   machine's undercooling preset needs a deliberate second confirmation.

afanctl is a sibling project too, but not prior art in this market: it is the
daemon omafan drives, also GPL-3.0-only, and it is credited rather than
competed with (SAFETY.md §4).
