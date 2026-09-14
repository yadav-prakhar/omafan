# REVIEW-R2 — adversarial review: safety, privilege, collisions, failure modes

**Ticket:** T16 · **Reviewer:** glm 5.3 high · **Date:** 2026-09-15 ~04:30 IST
**Tree audited** (it moved three times during the review; claims are pinned to):
`bin/omafan-ctl` md5 `c5bc8c7ca55d` (04:27:24, post-T04d) · `Panel.qml` `0cab89b11d6c`
(04:23:44, post-T09c) · `bin/omafan-keybindings` `f06dc7b9211d` · `BarWidget.qml`
`247982167b76` · `Model.js` `c5fa4954bb6d` · `KeyboardHelp.qml` `5decf6152f81` ·
`tests/ctl.test.sh` `7031d15c7f2d`. All omafan-ctl runs below used
`--afanctl tests/fixtures/fake-afanctl --pkexec none --runtime-dir <tempdir>` with
`XDG_RUNTIME_DIR` redirected into the tempdir (two zero-execution exceptions, disclosed
in R2-1). No git, no sudo, no writes outside `orchestration/REVIEW-R2.md`.

## Verdict

**REJECT at this commit — 2 blockers open, 1 gate red.** The blast radius is small and
the privilege boundary is now genuinely tight, but: the `release_after_minutes` safety
net can never fire (R2-2), writes on a stale `state.json` succeed untruthfully (R2-3),
and `tests/run-all.sh` exits 1 because T04d's correct code changes were never mirrored
into T05's frozen assertions or into `DESIGN.md` (R2-4/R2-5). The one true security
blocker this review found independently — the privileged argv `env`-indirection that
made every pkexec write unable to match afanctl's polkit rule — was fixed by T04d
*while this review was running*; the fix is verified below and the residual is the
un-mirrored contract, not the code.

## Findings

### R2-1 — blocker (FOUND by this review; FIXED in-tree by T04d during the review; fix verified)

**Privileged writes could never match afanctl's polkit rule.**
afanctl's rule (`cat /usr/share/polkit-1/rules.d/49-afanctl.rules`) returns
`NOT_HANDLED` unless `action.lookup("program") === "/usr/bin/afanctl"` **and** the
`command_line` splits as `["/usr/bin/afanctl", verb, …]` with exact shapes
(`hold <u32>` = 3 tokens, `observe` = 2, `status [--json]`). The pre-T04d ctl built
`argv = [<runner>, env, AFANCTL_RUNTIME_DIR=<dir>, <afanctl>, hold, <rpm>]` — pkexec's
program is then `/usr/bin/env`, both rule checks fail, and pkexec falls back to an
auth_admin prompt: a graphical password dialog no script, chord or panel can answer.
Every real write hung; only `--pkexec none` (the fixture path) ever worked, which is
why the suite was green. The orchestrator reproduced it live (LEDGER 04:22Z:
`pkexec /usr/bin/afanctl status --json` → 0.026 s; the `env` form → hangs, `timeout 6`
→ 124) and dispatched T04d.
**Verified fixed:** `bin/omafan-ctl:573-598` (`runner_argv`) builds exactly
`[<runner>, <afanctl>, <mode args>]`; my dry-run against the current ctl:
`preset med --dry-run --pkexec /bin/true` → `argv:["/bin/true","<afanctl>","hold","4200"]`
and `release --dry-run` → `["/bin/true","<afanctl>","observe"]` (runner `/bin/true` is a
zero-execution stand-in — dry-run prints argv without running anything). A custom
runtime dir with a real runner is now refused before any process spawns:
`preset med --pkexec /bin/true --runtime-dir <tmp>` → exit 2, message names the cause
and both fixes (observed). The doctor gained `pkexec_write_path`, which runs the
authorized read `[<runner>, <afanctl>, status, --json]` under a 3 s deadline (verified
failing loudly under a stub: `pkexec_write_path FAIL … fix: check the polkit rule …`).
**Residual:** the contract drift this fix created — see R2-4/R2-5.

### R2-2 — blocker (open)

**`release_after_minutes` can never fire; the advertised safety net is dead code.**
`Panel.qml:357`: `if (root.releaseAfterMinutes > 0 && root.holdActive)
releaseTimer.restart()` runs inside `applyStatus`, i.e. on *every* successful poll
(default every 2 s, max 10 s). `releaseTimer` (`Panel.qml:531-538`) is one-shot
(`repeat: false`, interval = N×60000 ms). A one-shot timer restarted every ≤10 s can
never reach an interval of ≥60 s, so the release never happens while the hold
persists — the only state the net exists to catch. The code implements DESIGN.md §8
("its timer restarts when a status poll discovers an active hold") to the letter; the
frozen wording itself defeats PRD F7 ("returns the fan to auto after N minutes without
interaction") and the README's "A forgotten hold can expire". This matters thermally:
afanctl faithfully re-asserts a hold forever, and the undercooling guard only checks
at write time — a `low` hold applied on a cool machine that heats up overnight has no
omafan-side mitigation once this net is dead (bar tint is the only signal left, and it
dies with the widget: see the hold-path table).
Repro (static, no hardware): restart count = successful polls while holdActive; any
N ≥ 1 min ≫ poll_seconds ⇒ zero firings.
**Smallest fix:** arm on the hold's *rising edge* only, e.g. guard with a
`holdSeen` boolean (false→true) or `if (… && !releaseTimer.running) releaseTimer.restart()`
(which also gives sane retry semantics when a release fails), plus restart on user
interaction if "without interaction" is to be honoured; add a ctl/panel test; update
DESIGN.md §8's sentence accordingly (via DEVIATIONS.md).

### R2-3 — should-fix (open; borderline blocker)

**Write verbs succeed untruthfully on a stale `state.json` (dead daemon).**
DESIGN §4 promises writes are refused with exit 5 when "afanctl daemon not running";
the daemon writes `state.json` every poll (interval 1 s default), so a file older than
the 5 s floor means a dead daemon. `write_prereqs` (bin/omafan-ctl:522-554) checks only
*readability* of state.json — staleness is never consulted — so:
```
state.json = hold fixture, mtime 10 min old:
  omafan-ctl preset med --afanctl fake --pkexec none --runtime-dir <tmp>
  -> exit 0, {"ok":true,"action":"preset","preset":"med","rpm":4200,
              "message":"Holding 4200 rpm (preset med)"}   [observed]
  fixture argv.log: "hold 4200"                             [observed]
```
A success envelope for a command nothing will apply; the K4 chord path (release/preset
without the shell) is exactly this path. A `hold` written into a dead daemon's
`cmd.json` also sits latent for whenever the daemon restarts (afanctl applies cmd.json
per poll; its README's freshness gate covers byte-identical *re-issues*, not a
leftover from before a crash — whether startup reconcile clears it is afanctl-side and
unconfirmed). The panel is protected (stale → degraded tone → writes refused); the
CLI/chords are not. `status` on the same state renders `running:true, state_stale:true`
and exits 0 — defensible, but the write side is the defect.
**Smallest fix:** in `write_prereqs`, after `read_state`, `if is_state_stale "$ST_AGE"`
and not `--force` → `fail_action 5 daemon_down "state.json is Ns stale — the daemon is
not reporting; $FIX_RESTART_AC"`; add a ctl.test.sh case (seed state, `touch -d '2
minutes ago'`, expect exit 5 and empty argv.log).

### R2-4 — blocker for the build gate (open; trivial fix)

**`tests/run-all.sh` is red at the audited HEAD: T04d changed behaviour T05's frozen
assertions still pin.**
```
bash tests/run-all.sh -> RUN ctl FAIL:  "doctor emits the eleven fixed checks:
  expected [11], got [12"; "the check id set is exactly section 4.4: … got […
  pkexec_write_path …]" (x2 shapes); "assert_exit_code: [run_denied preset med]
  exited 2, expected 3" (x2). PASS 187 / FAIL 4; "failed: ctl"; exit 1.  [observed]
```
Causes: doctor now has a 12th check (`pkexec_write_path`, T04d D4 — an intentional,
good change), and the D2 custom-runtime-dir refusal (exit 2) now precedes the
pkexec-denied path (exit 3) that `run_denied` exercises. T04d owned only
`bin/omafan-ctl`, so `tests/ctl.test.sh` (T05's file) was not updated; its own gate 6
("suite still passes") is not met. PRD G3 cannot pass until the suite is updated.
**Smallest fix:** in tests/ctl.test.sh, expected count 11→12, add `pkexec_write_path`
to the expected id set, and make `run_denied` keep the default runtime dir (or use
`--pkexec none` + a failing afanctl stub) so it still reaches the exit-3 path.

### R2-5 — should-fix (open; contract discipline)

**T04d/T09c behaviour changes are not mirrored into DESIGN.md/DEVIATIONS.md.**
`DESIGN.md` (mtime 03:50, unchanged) still says at line 146: "`status`/`presets`/
`doctor` never write, never call pkexec" — but the shipped doctor now invokes the
runner (`[<runner>, <afanctl>, status, --json]`, 3 s bound; bin/omafan-ctl:963-986).
§4.4's frozen check-id list (line 224) lacks `pkexec_write_path`. §4's flag table does
not document the D2 exit-2 refusal for `--runtime-dir` with a real runner, nor the
20 s runner bound with exit 3 `authorisation_timeout`. `Panel.qml`'s state list (§6.2)
lacks `statusStale`/deadline semantics T09c added. `DEVIATIONS.md` still reads
"(none yet)". The conventions and PLAN runbook §7 require behaviour-changing rulings to
be mirrored into DESIGN.md with a DEVIATIONS entry; the most safety-critical fix of
the build is currently the largest undocumented deviation. Risk: the next worker or
reviewer who trusts DESIGN.md "corrects" the doctor check back to contract and
re-breaks the write path.
**Smallest fix:** one DEVIATIONS entry (old→new→why→affected tickets: T04d, T05, T09,
T10) + the DESIGN.md edits above.

### R2-6 — nit (open)

**The panel's undercooling confirmation sends blanket `--force`.**
`Panel.qml:289`: the second press sends `["preset", id, "--force"]`. `--force` on the
CLI also suppresses the exit-6 degraded-latch and exit-7 band refusals, not just
exit 8. Harmless today (the panel refuses degraded states before sending, and afanctl
ignores writes while monitor-only), but the panel's confirm-override should be narrow
(e.g. a `--force-undercooling` flag) so a future refusal cannot be silently bypassed
by a confirmation that was only about heat.

### R2-7 — nit (open)

**`--config` is silently dropped on the privileged path.**
`runner_argv`'s pkexec branch necessarily omits `ac_args` (the polkit rule pins the
argv to exactly verb+arg). A user passing `--config <path>` with a real runner gets a
write against afanctl's default config with no notice — the same situation D2 refuses
loudly for `--runtime-dir`. Extend the D2-style exit-2 refusal to `--config` when the
runner is not `none`.

### R2-8 — nit (open)

**A missing jq produces raw interpreter errors, violating the error model.**
Farm probe (PATH with everything except jq): `status --json` → exit 127, stderr
`omafan-ctl: line N: jq: command not found` (×2), no JSON envelope, no human fix line;
the write verb still refuses safely (argv.log empty — verified). The conventions
require every failure to name the problem *and* the fix. Recoverable without root
(install jq). **Smallest fix:** startup guard `command -v jq >/dev/null || { printf
'omafan-ctl: jq is required but not on PATH. Fix: install jq' >&2; exit 1; }`.

### R2-9 — nit / process (open; not this review's file)

`orchestration/REVIEW-R1.md` (T15's deliverable, the code-vs-contracts round) is
absent (`ls orchestration/REVIEW-R*.md` → no match) and `LEDGER.md` contains no T15
entry, though `tickets/T15.md` and `logs/T15.log` exist. P5 requires both review
rounds triaged; R1 has either not landed or its output was lost. Flagged for the
orchestrator.

## Audit table 1 — every write path, classified

Grep over the tree (excl. `.git`, `orchestration/logs`, `docs/`) for `>`/`>>`/`tee`/
`mv`/`cp`/`rm`/`install`/`sed -i`/`mktemp`/`mkdir`/`chmod`/`ln`/`touch`/`truncate`/
`FileView`/`writeAdapter`; every hit read in context. QML/JS `>` hits are numeric
comparisons only (no QML file writes; `FileView`/`writeAdapter`: zero hits).

| Writer | Destination | Class | Can it leave the allowed set? |
|---|---|---|---|
| bin/omafan-ctl:67,845,862 | `mktemp "$TMPDIR/omafan-ctl.XXXXXX"` scratch, trap-removed | ephemeral | no |
| bin/omafan-ctl:319-397 | `$XDG_RUNTIME_DIR/omafan/hw.json` (fallback `/tmp/omafan-<uid>/hw.json`) | documented 24 h cache | no; unwritable → warning + fallback (probe F6) |
| bin/omafan-ctl:696-744 | tmpfile + `mv` onto hw.json | same cache, atomic | no |
| bin/omafan-ctl reads `/sys/…applesmc`, `/usr/share/polkit-1/rules.d/*`, `/run/afanctl/state.json` | reads only (`compgen -G`, `grep`, `jq`) | read-only | never a write |
| bin/omafan-keybindings:232-235,392-395 | `$target.omafan.XXXXXX` in the *target's dir*, then `mv -f` onto it; target `${OMAFAN_HYPR_CONFIG:-~/.config/hypr/bindings.lua}` | managed block, atomic | only if the *user* sets `OMAFAN_HYPR_CONFIG` elsewhere; default is `$HOME` |
| bin/omafan-keybindings:309-316 | `~/.local/state/omafan-keybindings/bindings.lua.<ns-stamp>` (first install, `cp -p`) | documented backup | no |
| bin/omafan-keybindings:276,331-335,398-399 | `mkdir -p` of target/state dirs; `hyprctl reload` (best-effort, never fatal) | config dirs / compositor | no |
| Panel.qml | no file writes; spawns `bin/omafan-ctl` only (array-form `Process`, 2 sites) | via CLI above | no |
| BarWidget.qml, KeyboardHelp.qml, Model.js | none (grep: no Process/FileView in BarWidget/KeyboardHelp; Model.js pure) | — | no |
| tests/fixtures/fake-afanctl:162-170 | caller-provided runtime dir only; refuses `/run/afanctl`, `/sys`, `/etc`, `/usr`, `/run`, `/` outright (lines 83-88) | fixture | no (refusal is stronger than asked) |
| tests/* (all suites) | harness temp root `mktemp -d /tmp/omafan-test.XXXXXX`, per-case dirs, sandbox `HOME`/`OMAFAN_HYPR_CONFIG`/`OMAFAN_STATE_DIR`/stub `hyprctl`; `XDG_RUNTIME_DIR` redirected into the case (ctl.test.sh:45) | sandboxed | no |
| tests/integration-shell.sh | tempdir copy of the repo for validation; **refuses to write `~/.config/omarchy`** (line 81-94 comment + code) | live, opt-in `OMAFAN_LIVE=1` | no |
| tests/hw-smoke.sh | no direct writes at all; every fan action via `omafan-ctl`; EXIT trap releases+verifies; opt-in `OMAFAN_HW=1` **plus** interactive `/dev/tty` "yes" (a piped "yes" cannot arm it) | live, opt-in | no |
| orchestration/live-install.sh (ships per PRD D5) | repo `orchestration/backups/` (shell.json .bak), install dir `~/.config/omarchy/plugins/<id>/` (rsync/tar; `rm -rf` on revert), `shell.json` via `omarchy plugin enable/remove` (the shell's own tooling) | orchestrator tooling | documented install surface; no system paths |
| orchestration/dispatch.sh | `orchestration/logs/` only | orchestrator tooling | (excluded from audit by the ticket) |

**Destinations outside {plugin dir, backup dir, runtime cache, shell.json via
`omarchy plugin enable`, managed bindings.lua block}: NONE found.** No `sed -i`, no
`install`, no `truncate`, no symlinks in the plugin dir (`omarchy plugin validate .`
exit 0 enforces that too). No writes to `/sys`, `/etc`, `/usr`, `/run/afanctl`
anywhere in shipped code.

## Audit table 2 — every pkexec invocation, exact argv, injection surface

| Site | Exact argv | Guard |
|---|---|---|
| bin/omafan-ctl `runner_argv`, pkexec branch (the only privileged execution) | `[<runner>, <afanctl_resolved>, "hold", "<rpm>"]` / `[<runner>, <afanctl_resolved>, "observe"]` | matches afanctl's rule shapes exactly (R2-1 fix verified by dry-run); rpm is digits-only; `timeout 20` bounds it; rc 124→exit 3 `authorisation_timeout`, 126/127→exit 3, "Not authorized"→exit 3 |
| same, `--pkexec none` branch (tests/dev only) | `[<afanctl_resolved>, verb, args]` under `env AFANCTL_RUNTIME_DIR=<dir>` | unprivileged; the privileged path never uses `env` |
| bin/omafan-ctl doctor `pkexec_write_path` (new, T04d D4) | `[<runner>, <afanctl_resolved>, "status", "--json"]`, 3 s deadline | a read the rule authorizes verbatim; FAIL names the fix (observed under a 99-exit stub) |
| Panel.qml / BarWidget.qml | never call pkexec; they spawn `bin/omafan-ctl` only | — |

Injection probes (all observed; fixture + `--pkexec none` + tempdir):
`rpm '4200; touch PWNED'` / `'4200 $(…)'` / backticks / inner space → exit 2, no
marker, argv.log empty; `preset 'med;evil'`, `'../../etc/passwd'` → exit 2;
`--afanctl '/tmp/x;evil'` → exit 4 (never executed); `--pkexec 'none; …'` /
`/nonexistent/pkexec` → exit 3 (runner not found, nothing executed);
`--runtime-dir '<dir with spaces, parens, $(), ;>'` → write lands in exactly that
directory (`cmd.json` mode=hold, argv.log `hold 4200`) — one argv element, no shell.
`set -euo pipefail` present in both shipped binaries and the fixture; zero `eval`,
`sudo`, `doas` in the tree; JSON only via `jq` (no hand-built strings). Read verbs
never touch the runner: `status`/`presets`/`doctor` with a 99-exit pkexec stub first
on PATH → stub called 0 times (observed; doctor exits 1 only because
`pkexec_write_path` legitimately FAILs under a broken runner). Nothing in the plugin
runs as root except afanctl itself under pkexec.

## Audit table 3 — every path that can end with the fan in a hold

Hold producers (all user-commanded; no automated path can *start* a hold):
panel chips/digits/`c`/`Enter` → `applyPreset` → `sendCommand` (busy/degraded gates,
§5.1 confirm on hot); slider (300 ms debounce / explicit release); bar wheel ±100 →
`panel.sendCommand` (never a direct write); IPC `preset`/`rpm`; CLI
`preset`/`rpm`/`cycle`; the eight chords → CLI directly.

| Scenario | What happens | Whose model covers it |
|---|---|---|
| Shell dies right after a write | Hold persists, daemon-owned and re-asserted every poll; bar tint reappears when the shell restarts; panel re-polls from scratch (no plugin-side persistence) | afanctl (L1 re-assert; README "Safety model") |
| afanctl daemon dies | One async-signal-safe write restores AUTO (L2); systemd restarts it (L3); startup reconcile restores AUTO out of any manual owner | afanctl |
| afanctl over-temp escalation moves a hold down (observed live: hold 7200 → target 6200 at 94 °C, LEDGER 04:22Z) | omafan renders the daemon's numbers; hold shows as `custom` at the new rpm | afanctl; omafan renders truthfully (R4) |
| `release` fails (CLI rc≠0) | exit 1/3/5 with fix line; if afanctl's own restore fails it re-asserts AUTO every poll and exposes `auto_restore_pending`, which omafan refuses writes on (exit 6, probe F5) and the panel banners | afanctl + omafan surface |
| Runner hangs (polkit prompt) | CLI: killed at 20 s → exit 3 with the rule/agent hint; panel: killed at 20 s, `busy` cleared, banner names the fix, no optimistic success (T04d D3/T09c D1-D2, code-verified) | omafan (new) |
| release_after_minutes: panel closed | net alive (panel is `Loader.active: true`, polls continue) | omafan |
| release_after_minutes: shell restarted | timer resets; fires ≤ N min after the restart | omafan (delay only) |
| release_after_minutes: setting changed mid-hold | re-evaluated live; `0` disables it (the user's explicit act) | omafan |
| release_after_minutes: widget removed from bar / plugin disabled | Panel never instantiated → **no net and no tint** until re-added; the hold stays daemon-owned; chords/CLI still release it | afanctl owns the fan; the missing net is inherent to a panel-side timer (DESIGN §8) |
| release_after_minutes: normal case | **never fires** (restarted every poll while the hold is active) — R2-2 | broken (omafan, blocker) |
| Undercooling: preset below current rpm at ≥80 °C | CLI exit 8 unless `--force`; panel arms a 10 s double-confirm (wheel-driven rpm writes are caught CLI-side, banner shows the refusal) | omafan §5.1 (both surfaces probed/read) |
| Forgotten low hold, machine heats later, user asleep | afanctl re-asserts it faithfully; the only omafan net is R2-2's dead timer | **uncovered — R2-2 is the fix** |

## Audit table 4 — collisions (all command-verified)

| Check | Command | Result |
|---|---|---|
| plugin id unique | `omarchy plugin list --json` and `omarchy-shell shell listPlugins` | `io.github.yadav-prakhar.omafan` appears exactly once in each, `enabled:true`; no other id contains "omafan" |
| IPC target unique | grep of every `IpcHandler target:` in `/usr/share/omarchy/shell/plugins` and `~/.config/omarchy/plugins` | shell targets: omarchy.bar/.monitor/.network/.power/.clock/.bluetooth/.indicators/.system-update, background, lock, notifications, osd, idle, media, nightlight; third-party: omaplug, omasettings, expose, jankeesvw…, omni(bak); `omafan` is ours alone |
| eight chords free/ours on the live set | `hyprctl binds -j` | modmask-72 set: A C H L M O T X all carry `omafan:` descriptions (our installed block, 1 marker in bindings.lua, content = DESIGN §7 verbatim with the absolute helper path); no foreign binding on those letters |
| chords free vs Lua sources incl. `code:` | installer's awk scan (keycodes 27 28 32 38 43 46 50 54) + `bash tests/keybindings.test.sh` | suite PASS (install/remove/conflict/code:28-alias cases); live install verified in LEDGER 04:20Z incl. byte-identical remove (md5) |
| filename collisions | plugin files live only inside the id-namespaced dir `~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/`; `qs.*` imports resolve from the shell config | no shadowing possible by construction; no symlinks (`omarchy plugin validate .` exit 0) |
| settings keys | `jq` of `shell.json` layout | entry is `{"id": …}`; keys are per-plugin-id namespaced (`show`, `poll_seconds`, `release_after_minutes` under our id) — cannot collide |
| service/unit/port/socket | grep shipped code | none (only `afanctl.service` strings inside fix messages); no Socket/listen/port anywhere |
| environment variables | grep `OMAFAN_` across shell + all plugins | the prefix is exclusively ours; `AFANCTL_RUNTIME_DIR` is afanctl's own documented var, reused by design |
| state/backup/cache paths | ls | `~/.local/state/omafan-keybindings/`, `$XDG_RUNTIME_DIR/omafan/`, `/tmp/omafan-<uid>/` — all omafan-specific |

## Audit table 5 — failure modes (each reproduced or command-verified)

| Mode | User sees / plugin does | Evidence | Recoverable without root? |
|---|---|---|---|
| afanctl missing | status: exit 4 **with** truthful doc (`present:false`, warning); writes: exit 4, fix names `packaging/` | probe F1 | yes (install afanctl) |
| daemon stopped (no state.json) | status: exit 5 with doc `running:false` + warning; writes: exit 5, **nothing executed** (argv.log empty) | probe F2 | yes (start afanctl) |
| state.json stale | status: exit 0, `state_stale:true`; panel degrades and refuses; **CLI writes succeed untruthfully — R2-3** | probe F3 | yes |
| `monitor_only` | rendered from the daemon's own field; writes exit 6 with `systemctl restart afanctl`; `--force` overrides (probe) | probe F4 | restart needs root; the fan is safe meanwhile (latch = no writes) |
| `auto_restore_pending` | writes exit 6; afanctl keeps re-asserting AUTO until verified | probe F5 | yes |
| runtime/cache dir read-only | cache degrades: warning in doc, `/tmp/omafan-<uid>` fallback, exit unchanged | probe F6 | yes |
| pkexec prompts instead of the rule matching | pre-T04d: every write (R2-1, fixed); now: 20 s bound → exit 3 `authorisation_timeout` naming the rule + agent; `doctor` FAILs `pkexec_write_path` naming the fix | code + stub probe + LEDGER live repro | yes (fix rule/session; no root needed to *diagnose*) |
| notify-send absent | exit code unchanged, write lands | probe F7 (farm PATH) | yes |
| jq absent | exit 127, raw `jq: command not found` lines, no envelope/fix line; writes still refused safely (argv.log empty) — R2-8 | probe F8 (farm PATH) | yes (install jq) |
| shell restart mid-hold | hold daemon-owned; panel cold-starts, first poll within `poll_seconds`, stale-status indicator covers a slow poll (T09c D3) | code + table 3 | yes |
| hw/integration suites by accident | both print SKIP and exit 0 without their gates; hw additionally requires an interactive `/dev/tty` "yes" | run transcripts above | n/a |

## Uninstall trace

Documented sequence: `release` → `omafan-keybindings remove` → `omarchy plugin remove
io.github.yadav-prakhar.omafan`. Verified pieces: the keybindings suite proves remove
restores `bindings.lua` byte-identically and exits 0 with nothing to remove; LEDGER
04:20Z records the same live (md5 before/after). `omarchy plugin remove [id] [--yes]`
(its own help) removes the plugin dir and shell entry — not executed by this review
(forbidden write to `~/.config/omarchy`); the shell's tooling owns it.
**Survivors enumerated on this machine** (read-only `ls`):
`~/.local/state/omafan-keybindings/bindings.lua.<stamp>` ×2 and the hw caches
`/run/user/1000/omafan/hw.json` + `/tmp/omafan-1000/hw.json` — all inert copies/caches,
documented in README as removable, none change behaviour.
**Leftover that changes behaviour: none** — with one load-bearing caveat: a hold
active at uninstall time persists (daemon-owned, tint and chords gone with the
plugin), which is exactly why the docs put `release` first in the sequence.

## What a stranger cannot break

- Cannot inject through any input: rpm is digit-validated, preset ids whitelisted,
  every value travels as one argv element, no shell, no eval (probe table above).
- Cannot escalate: the only privileged call is
  `pkexec /usr/bin/afanctl {hold <digits>|observe|status --json}` — pinned by afanctl's
  rule to one binary and three exact shapes; `--afanctl`/`--pkexec` substitutions run
  unprivileged or fail closed (exit 4/3); nothing in the plugin ever runs as root.
- Cannot make the plugin write outside its five documented homes (plugin dir at
  runtime: nothing; managed `bindings.lua` block + its backup; `$XDG_RUNTIME_DIR/omafan`
  hw cache; `TMPDIR` scratch) — table 1.
- Cannot leave the fan unowned: afanctl re-asserts holds, restores AUTO on death in one
  syscall, reconciles AUTO at startup, latches monitor-only/pending-restore visibly;
  omafan renders those fields and refuses writes on them (tables 3/5) — the open
  exceptions are R2-2 (dead release net) and R2-3 (stale-state write).
- Cannot silently undercool: exit 8 + 10 s double-confirm on both surfaces.
- Cannot collide: id, IPC target, chords, env prefix, files, settings keys all
  command-verified unique (table 4).
- Cannot be trapped by a hung write: 20 s bounds on the CLI runner, notify, and both
  panel processes.
- Cannot trip the hardware suites by accident: `OMAFAN_HW`/`OMAFAN_LIVE` gates plus an
  interactive `/dev/tty` consent a pipe cannot satisfy.
