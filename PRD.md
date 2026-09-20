# PRD — omafan: an Omarchy shell plugin for the A1708 single-fan Intel Mac

**Author:** Prakhar Yadav, with the build run by an orchestrating agent.
**Date:** 2026-09-15 (IST)
**Status:** approved by the operator's instruction ("make it, test it, run it,
ensure nothing breaks or collides with something else"); implementation is
governed by `DESIGN.md` (the build plan itself is on the `dev` branch).
**Reader:** anyone auditing or extending omafan — contributor, reviewer or
coding agent. This
document is self-contained: nothing here depends on a chat session, and every
environmental claim was re-verified live on the target machine during this
build (see §2). Where a fact came from an external source it is cited.

---

## 1. Goal and scope

Build **omafan**, a public Omarchy (Quattro, `omarchy-shell`) plugin that gives an
interactive, keyboard-first control surface for the single fan of a pre-T2 Intel
MacBook (MacBookPro14,1 "A1708", `applesmc`), by driving the already-installed
**afanctl** daemon.

Shipped as:

1. a **bar widget** — live CPU temperature and fan rpm, tinted whenever the fan is
   held off the firmware curve;
2. a **panel** — Auto/Floor/Low/Med/High/Full presets, an rpm slider, live status,
   banners for degraded/offline states, an in-panel key map (`?`);
3. **global keyboard shortcuts** on chords verified free against every binding
   the machine actually has (see §6);
4. a `bin/omafan-ctl` CLI (the only thing that talks to afanctl) and a
   `bin/omafan-keybindings` installer/remover for the shortcut block;
5. this documentation set, a GPL-3.0 licence, and a **public GitHub repository**
   prepared for listing on `plugins.omarchy.org`.

**Out of scope (explicitly):** writing `/sys` directly; bundling or installing
`afanctl`; T2 Macs (`t2fanrd`) or other laptops; fan curves/internal control
policy (that is afanctl's job); a second Quickshell process; any Omarchy system
package change; publishing/submitting to the marketplace (prepared, not
submitted — the operator sends the issue).

### 1.1 Why this is not a duplicate

The marketplace already lists Mac fan plugins (`benekuehn.macbook-fans` for T2,
`io.github.moerdowo.fan` for Apple SMC, `io.github.deadjoe.mbpfan`,
`io.github.endijs.t2-fan-control`, `kshatriya-abhay.nbfc`,
`nate.framework.fan-control`). Research on 2026-09-15 (§2.6) shows the two
closest siblings (both MIT) require the user to run a root installer that writes
`/etc/udev/rules.d/*`, `/etc/polkit-1/rules.d/*`, sudoers entries or a
`/usr/local/libexec` helper, and then read/write `/sys` themselves.

omafan's differentiators, each a requirement below:

- **R1 — zero new privilege surface.** omafan installs no udev rule, no sudoers
  entry, no root-owned helper, and never writes `/sys`. It reuses afanctl's
  existing, auditable polkit rule.
- **R2 — the fan is never left unowned.** Control is delegated to afanctl, whose
  documented model fails toward the firmware (per-poll verify/re-assert, an
  async-signal-safe AUTO restore on death, a systemd watchdog, "sensor loss →
  AUTO", startup reconcile out of any foreign manual owner).
- **R3 — keyboard-first.** The panel is fully operable without a pointer, and
  the six presets plus a cycle action have machine-verified-free global chords.
- **R4 — truthful UI.** Presets are floors, not quieter-than-firmware modes;
  "Floor" cannot stop the fan and must say so; degraded/offline states are rendered
  from the daemon's own fields, never optimistically.

## 2. Verified environment facts (re-checked live during this build)

| # | Fact | Evidence |
|---|---|---|
| 2.1 | Omarchy `4.0.0.alpha` ("Quattro"); `/usr/share/omarchy/version` contains `4.0.0.alpha`; `omarchy-shell` is the single Quickshell host; plugin kinds are `bar-widget, panel, overlay, menu, service, bar` | `/usr/share/omarchy/shell/README.md`, `omarchy plugin --help` |
| 2.2 | **afanctl 0.1.0 is installed and running**: `/usr/bin/afanctl`, unit `afanctl.service` enabled + active (`mode=observe`), `/etc/afanctl/afanctl.toml` present, `/run/afanctl/state.json` present (mode 0644, world-readable), polkit rule `/usr/share/polkit-1/rules.d/49-afanctl.rules` present | `systemctl status afanctl`, `ls -l /run/afanctl`, `afanctl status --json` |
| 2.3 | Hardware band on this machine: `fan1_min = 1200`, `fan1_max = 7200` rpm; live fan 1787 rpm at `t_eff 64 °C`; `afanctl status --json` works **without root** | `afanctl status --json` |
| 2.4 | afanctl's control channel is `cmd.json` (`schema afanctl.cmd.v1`) written by the `observe`/`curve`/`hold` verbs, with a byte-identity freshness gate; `state.json` (`afanctl.state.v1`) is the render feed (`mode`, `t_eff_c`, `target_rpm`, `last_written_rpm`, `actual_rpm`, `verified`, `monitor_only`, `auto_restore_pending`, `polls`, `recent_errors`) | afanctl `src/cli.rs`, `src/supervisor.rs`, `README.md` |
| 2.5 | The polkit rule grants passwordless `pkexec /usr/bin/afanctl` for exactly `status [--json]`, `observe`, `curve`, `hold <u32>` to `wheel` in a local active session — so omafan needs **no** installer of its own | `/usr/share/polkit-1/rules.d/49-afanctl.rules` (read in full) |
| 2.6 | Marketplace prior art as of 2026-09-14T21:41Z (3153 listings): the Mac/SMC fan plugins named in §1.1; all require root installers and/or talk to `/sys` directly; none of them document global keyboard shortcuts | `https://plugins.omarchy.org/catalog.json` |
| 2.7 | Free-chord analysis: 175 distinct chords are bound live (`hyprctl binds -j`) and the Omarchy defaults bind workspaces and panel toggles through `code:` keycodes (digits), so **all `SUPER+digit`, `SUPER+SHIFT+digit`, `SUPER+ALT+digit`, `SUPER+CTRL+digit` chords are taken**; `SUPER + ALT + {T,A,O,L,M,H,X,C}` are free | `hyprctl binds -j` + `default/hypr/bindings/*.lua` (see `tests/keybindings.test.sh`) |
| 2.8 | Toolchain present: `jq`, `node v26.8.2`, `/usr/lib/qt6/bin/qmllint` (not on `PATH`), `pkexec`, `notify-send`, `omarchy plugin validate`, `omarchy-shell`, `hyprctl`; `gh` is authenticated as `yadav-prakhar` (repo scope) | `which`/`--version` checks |
| 2.9 | Third-party plugin IPC works: `omarchy-shell omaplug refresh` exits 0; panels may own their single `IpcHandler` with `manageIpc: false` and take string arguments (see `omarchy.monitor`'s `IpcHandler`) | live call, `plugins/panels/monitor/Panel.qml:220` |
| 2.10 | `omarchy plugin validate` enforces: `schemaVersion == 1`, required fields, non-reserved id (`omarchy.*` is reserved), one entry point per kind, entry points safe+existing, **no symlinks anywhere in the plugin folder** | `/usr/share/omarchy/bin/omarchy-plugin-validate` |
| 2.11 | The repo name `omafan` is free on GitHub under `yadav-prakhar` | `gh repo view yadav-prakhar/omafan` → not found |

## 3. Requirements

### 3.1 Functional

- **F1** Bar widget shows live CPU temperature (default), or rpm, or both —
  configurable; tinted when a hold is active.
- **F2** Panel lists `Auto · Floor (hardware floor) · Low · Medium · High · Full`
  with the rpm each maps to, plus the rpm slider (`fan_min..fan_max`, step 100).
- **F3** `Auto` releases the fan to the SMC firmware (`afanctl observe`) —
  byte-for-byte the "as if nothing was controlling the fans" behaviour the
  original request asked for. `afanctl`'s own software `curve` mode is *not*
  wired to any preset (documented as a CLI-only extra).
- **F4** Presets are `afanctl hold <rpm>` where the rpm is derived from the live
  hardware band (DESIGN.md §3), so the plugin stays correct on other pre-T2 Macs.
- **F5** Slider writes are debounced (≈300 ms) and every write is followed by a
  status re-read; the UI shows the daemon's `target_rpm`, `actual_rpm`, `verified`
  and any `recent_errors`.
- **F6** Degraded/offline/degraded-latch states (`monitor_only`,
  `auto_restore_pending`, daemon stopped, afanctl missing, stale `state.json`)
  disable writes and show the cause plus the exact fix command.
- **F7** Optional `release_after_minutes` safety net returns the fan to auto after
  N minutes without interaction (default 0 = never).
- **F8** `omafan-ctl` exposes the same surface head-lessly (`status`, `presets`,
  `doctor`, `preset`, `rpm`, `release`) with machine-readable JSON and documented
  exit codes; `omafan-keybindings` installs/removes the shortcut block.

### 3.2 Keyboard accessibility (explicit operator requirement)

- **K1** Every action available by mouse is available by keyboard in the panel
  (cursor model, Enter/Space, digits 1-6, `c` cycle, `r` refresh, `?` key map,
  `Esc`, `Tab` popout switch).
- **K2** Global chords exist for panel toggle + all six presets + cycle, all
  verified free against the live binding set (§2.7, DESIGN.md §7).
- **K3** The chord installer refuses to install on a conflict and reports the
  colliding description; `remove` restores `bindings.lua` byte-identically.
- **K4** A keyboard-only path to "return to firmware auto" exists even if
  `omarchy-shell` is dead (`omafan-ctl release` / `SUPER+ALT+A`),
  because the presets are invoked through the CLI, not the shell.

### 3.3 Safety and non-collision (explicit operator requirement)

- **S1** No destructive action anywhere: no removal of system components, no
  changes outside the plugin directory, the managed `bindings.lua` block, the
  shell's own `shell.json` plugin entry, and `$XDG_RUNTIME_DIR/omafan/`.
- **S2** No new privileged surface (R1). The plugin never runs as root and never
  writes `/sys`.
- **S3** Automated tests never touch hardware; hardware writes are confined to an
  explicitly opt-in smoke test (`tests/hw-smoke.sh`, `OMAFAN_HW=1`) plus the
  operator's own supervised check, and every hardware write path ends with a
  verified return to `observe`.
- **S4** No collision with other Omarchy/plugin config: unique plugin id, unique
  IPC target (`omafan`), chords proven free, no shared file names in
  `~/.config/omarchy/plugins/`, no port, no service, and no writes to paths
  owned by other plugins.
- **S5** Every change to this machine is reversible and its undo is written down
  and executed at least once (skill convention for this box).

### 3.4 Documentation and publishing

- **D1** `README.md`: what it is, requirements, install (with the afanctl
  dependency spelled out), using it, keyboard map, safety model, how it differs
  from the siblings, troubleshooting, removal, licence.
- **D2** `docs/`: `ARCHITECTURE.md`, `KEYBINDINGS.md`, `SAFETY.md`, `INSTALL.md`,
  `TROUBLESHOOTING.md`, `TESTING.md`, `PUBLISHING.md`, `PRIOR-ART.md`.
- **D3** `CHANGELOG.md` (Keep-a-Changelog shape), GPL-3.0 `LICENSE` with the
  author's copyright line, `manifest.json` valid for the marketplace
  (`schemaVersion 1`, namespaced id, version, author, description, kinds,
  entryPoints).
- **D4** Marketplace submission prepared but **not** sent: the exact issue body
  (category, tags, repo link, description) is left in `docs/PUBLISHING.md` for
  the operator to paste.
- **D5** The build trail is auditable in the repository: requirements (`PRD.md`),
  the frozen contract (`DESIGN.md`) and its change channel (`DEVIATIONS.md`) ship
  on the default branch, and the development record (`PLAN.md`, `QUESTIONS.md`,
  `orchestration/`) is kept on the `dev` branch, together with `worknotes/` — one
  folder per piece of post-build work, holding its plan, its evidence, its review
  and its summary (rulings R11, R12).

### 3.5 Licences of referenced work

GPL-3.0-only for omafan (operator's standing choice, matching afanctl).
Referenced projects are **not** vendored: earlier work is studied and cited, not
copied (the marketplace holds only descriptions of the siblings, and reading
their READMEs on 2026-09-15 informed the differentiation and the troubleshooting
list only). Their licences are recorded in `docs/PRIOR-ART.md`.

## 4. Acceptance gate (what "done" means)

Every line below must be demonstrated with real output, not asserted:

| # | Gate | How |
|---|---|---|
| G1 | `omarchy plugin validate .` exits 0 | real run |
| G2 | `qmllint -I $OMARCHY_PATH/shell` is clean on every shipped QML file | real run |
| G3 | `tests/run-all.sh` → all suites PASS (manifest, Model.js via node, ctl via fake afanctl, keybindings via tempdir+stub hyprctl, qml lint, plugin validate) | real run |
| G4 | The plugin loads in the live shell: `omarchy-shell shell rescanPlugins`, `omarchy plugin list --json` shows it enabled, `qs log` shows no QML errors | real run |
| G5 | IPC round-trip: `omarchy-shell omafan toggle` / `preset med` / `state` return success with the panel loaded; `omarchy-shell shell toggle <id>` also opens it | real run |
| G6 | The bar widget renders live temperature/rpm (verified by a real screenshot of the bar) | real run |
| G7 | Keybindings install cleanly, appear in `hyprctl binds` with omafan descriptions, fire the right action, and `remove` restores the file byte-identically | real run |
| G8 | A real hardware write (one preset at a time, short) moves the fan as commanded and a verified return to `observe` follows; the machine is left in `observe` with `manual=false` | real run, logged |
| G9 | `docs/` complete; README covers install/use/keys/safety/removal; CHANGELOG present; licence correct | review |
| G10 | Public GitHub repo `yadav-prakhar/omafan` exists with the pushed tree, GPL-3.0 detected, and a README that a stranger can follow | `gh repo view` |
| G11 | Publishing inputs prepared in `docs/PUBLISHING.md` (issue body + checklist) | review |
| G12 | An adversarial review round (independent model, read-only) has been answered: every raised defect is either fixed or recorded as an accepted deviation | the review record on the `dev` branch (`orchestration/REVIEW-*.md`) |

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The shell's QML API drifts from the docs (`Ui/*` components) | every component used is one already used by a shipping built-in panel (`omarchy.monitor`, `omarchy.audio`); `qmllint` against the installed shell + a live load test are gates |
| A preset left holding the fan overnight while the operator sleeps | hardware gate G8 ends with a verified `observe`; `release_after_minutes` exists as a user-facing net; the bar glyph tints on any active hold so it is visible in the morning |
| The A1708's fan at 7200 rpm is loud/hot to test late at night | G8 tests `low`/`med` first and touches `full` for ≤2 s only if the machine is cool (`t_eff < 70 °C`), then returns to observe immediately |
| Ambiguity in `monitor_only` re-arm semantics (a byte-identical re-issue of `cmd.json` is ignored by afanctl's freshness gate) | the plugin renders the latch and points at the documented recovery (`systemctl restart afanctl`); a "re-arm" button is deferred, not faked |
| Polkit prompt spam if pkexec ever requires auth (e.g. the rule is missing) | `doctor` reports the rule; the panel shows an auth banner with the fix (`doctor` output verbatim); writes are debounced; the polkit rule grants the four verbs without a password on this machine (§2.5) |
| QML written blind by subagents does not render perfectly | three-stage verification: `qmllint` → live shell load with `qs log` checked for errors → real screenshot review; the orchestrator reads every shipped file |
| Subagent drift from the frozen contracts | single source of truth `DESIGN.md`; strict per-file ownership; `DEVIATIONS.md` is the only change channel; the orchestrator re-runs every gate itself |
| Repo publish accidents (wrong name, wrong licence, secrets) | `omafan` verified free; pre-push `grep` for secrets/emails; push only after G1-G8 |

## 6. References

- afanctl (sibling repo, installed): https://github.com/yadav-prakhar/afanctl
  (`README.md` = CLI + preset mapping, `DESIGN.md` = contracts, `PRD.md` = the
  full requirement set this plugin consumes).
- Omarchy plugin development: `https://plugins.omarchy.org/develop.html`;
  publishing: `https://plugins.omarchy.org/publish.html`;
  marketplace: `https://plugins.omarchy.org/catalog.json`.
- In-tree shell references read in full during recon:
  `/usr/share/omarchy/shell/README.md`, `shell/plugins/README.md`,
  `shell/Ui/{Panel,KeyboardPanel,PanelKeyCatcher,PanelSlider,WidgetButton,BarWidget,PanelActionButton,ButtonGroup,ToggleSwitch}.qml`,
  `shell/Commons/{Style,Color}.qml`, `shell/plugins/panels/monitor/Panel.qml`,
  `/usr/share/omarchy/bin/omarchy-plugin-validate`.
- Operator's original intent note: kept with the project's own working notes, now
  inside the repository — `worknotes/2026-09-17-advanced-polling/ASK.md` (ruling
  R12) — and never shipped to the default branch.
