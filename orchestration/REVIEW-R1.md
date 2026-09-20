# REVIEW-R1 — adversarial review: shipped code vs frozen contracts (ticket T15)

Reviewer: T15 worker. Snapshot: **2026-09-15 04:40 IST** — the tree was under
concurrent fix waves while this review ran (T10 landed 04:19, T11 04:14, T04d
04:27, T09c+orchestrator fixes 04:23–04:39, T05b suite amendment 04:35/04:38,
DESIGN/DEVIATIONS mirror updates 04:40). Findings below are verified against the
file versions named in each entry; anything fixed in-flight is reported as such
with the fix re-verified. Line numbers cite the snapshot versions:

| File | mtime | md5 (head) |
|---|---|---|
| Panel.qml | 04:39:59 | c8bf3ab923f903398559096a01ac4506 |
| bin/omafan-ctl | 04:39:44 | abdbcad8bca716b9c23f53151d20f926 |
| tests/ctl.test.sh | 04:38:49 | 33d1b9cc44eea41b5287cf7f7d41ee72 |
| Model.js / BarWidget.qml / KeyboardHelp.qml / manifest.json / bin/omafan-keybindings | unchanged since 03:2x–03:5x | — |

## Verdict

The bash and JS layers are strongly built and strongly tested: 17 of 20
mutation runs caught the deliberately broken behaviour — including
re-introduction of the exact `env`-wrapper argv the orchestrator found live;
the three that stayed green all targeted QML behaviour. The QML layer is the
weak flank: a runtime-fatal defect (R1-1) sits in
`Panel.qml` **green on every automated gate** as of this snapshot, and three
deliberate QML behaviour mutations also pass every gate — no automated test
exercises panel behaviour; only the opt-in live load does, and it has not run
since before the latest Panel.qml changes landed. One shipped CLI defect
(`presets --human`) and one contract divergence now write-blocking (the 5 s
staleness floor) also survive. The findings below are reproducible from the
quoted commands.

## Findings

### R1-1 — BLOCKER: `Panel.qml` assigns a property it never declares; every status poll throws mid-function
- **Where:** `Panel.qml` (04:39:59) — `root.statusStale` written at :353 and :382
  (inside `applyStatus`), :516 (`statusDeadline.onTriggered`), read at :699
  (`visible: root.statusStale`). `grep -n "property bool statusStale" Panel.qml`
  → no match. The comment at :37–38 ("T09c D3: true when a status poll
  failed …") announces the property; the declaration itself is missing.
- **Evidence (runtime, Qt 6.11.2):** a headless `qmltestrunner` case that assigns
  an undeclared property on an `Item` prints
  `ASSIGN RESULT: threw: Error: Cannot assign to non-existent property "statusStale"`
  and `READ RESULT: undefined` (transcript in the commands log below).
- **Effect:** the first assignment (`:353`, on the *successful*-poll path) throws,
  aborting `applyStatus` after `root.status = parsed.status` — so numbers do
  refresh (the panel looks alive) but: `lastError` is never cleared (an error
  banner sticks until the panel is reopened), the slider never tracks the
  daemon's hold target, the release-net arming block (:366–376, the R2-2 fix)
  never runs, and the failure branch (:382) plus the deadline handler (:516)
  throw before setting their banners — T09c's D1/D3 "status stale"/timeout
  messages and the stale badge (:699, reads `undefined`) are all unreachable.
  The R2-2 release-net fix is dead code until this is fixed.
- **Gates green with it present:** `bash tests/run-all.sh` at 04:35 →
  `PASS suites 6 / FAIL suites 0` on Panel.qml 04:23+, which already carried the
  defect. `qmllint` emits nothing for it (it cannot resolve `qs.Ui.Panel`
  members without qmltypes, and ruling R3's harness demotes member warnings on
  `qs.*` types anyway). The live load gate (G4) last ran at 04:01, pre-T09c.
- **Clause:** DESIGN §6.2 (banners, `status`/`lastError` state), §8 (degraded
  banners, release net), ticket T09c D1/D3.
- **Smallest fix:** add `property bool statusStale: false` beside the :37
  comment, then re-run the live G4 gate (the only gate that can prove it).

### R1-2 — should-fix: the staleness floor is a flat 5 s, not `max(5 s, 3 × poll interval)` — and it now blocks writes
- **Where:** `bin/omafan-ctl` :41 `readonly STALE_AFTER_S=5`, :320–326
  `is_state_stale`, write refusal at :549 (ruling R7.3 / REVIEW-R2 R2-3,
  applied 04:39). DESIGN §4.1 (line 194): stale when age
  "exceeds `max(5 s, 3 × poll interval)`".
- **Evidence:** `touch -d '2 minutes ago' state.json && …preset med` → rc=5,
  `--force` → rc=0 (fixture transcript below) — the refusal is real and the
  flat threshold gates it. The poll interval *is* available to the CLI
  (`afanctl status --json` → `config.interval_s`, persisted in `hw.json` as
  `interval_s`; my cache transcript shows `interval_s:1`), yet `is_state_stale`
  never uses it. `Model.isStateStale` (Model.js:272–276) has the same flat 5 s.
- **Effect:** on any afanctl config with `interval_s > ~1.6 s` (a legal,
  documented setting), `state.json` is legitimately older than 5 s between
  rewrites — every read reports `state_stale: true`, the panel renders
  "Status stale / restart afanctl" advice that is wrong, and every write is
  refused (exit 5) although the daemon is healthy. The reference machine
  (`interval_s = 1`) is unaffected, which is why nothing here has bitten yet.
- **Clause:** DESIGN §4.1 (the `max()` formula), §4 exit-code table (exit 5
  reserved for "daemon not running / runtime dir unreadable / state.json
  absent" — a merely-slow-polling healthy daemon is none of the three).
- **Smallest fix:** `threshold = max(5, 3 × interval)` wherever the cached
  interval is known (CLI `is_state_stale` caller and `run_doctor`'s
  `state_fresh` check); keep 5 s when the interval is unknown. `Model.isStateStale`
  already documents that a caller may pass a larger threshold.

### R1-3 — should-fix: `presets --human` prints raw JSON in the rpm column
- **Where:** `bin/omafan-ctl:883` —
  `jq -r '.[] | "\(.id)\t\(.label)\t\(if .rpm == null then "-" else tostring end)\t\(.kind)"'`:
  the `else tostring end` stringifies the whole item, not `.rpm`.
- **Evidence (current CLI, fixture):**
  ```
  $ omafan-ctl presets --human --afanctl tests/fixtures/fake-afanctl --pkexec none --runtime-dir <tmp>
  band: 1200..7200 (step 100)
  auto	Auto (firmware)	-	release
  off	Off (hardware floor)	{"id":"off","label":"Off (hardware floor)","rpm":1200,"kind":"hold"}	hold
  low	Low	{"id":"low","label":"Low","rpm":2700,"kind":"hold"}	hold
  ```
  `status --human`, `doctor --human` and `preset med --human` render correctly —
  only this filter is broken. No suite case covers `presets --human`
  (tests/ctl.test.sh asserts the JSON path only), which is how it shipped.
- **Clause:** DESIGN §4 (`presets [--json|--human]`); conventions ("every
  failure prints a human line" — here the *success* output is the unreadable
  one).
- **Smallest fix:** `else (.rpm|tostring) end`, plus one `presets --human`
  assertion in tests/ctl.test.sh.

### R1-4 — should-fix: DESIGN §7 still promises a free-chord reproduction that no artefact provides
- **Where:** DESIGN.md line 395: "Free-chord analysis is reproduced by
  `tests/keybindings.test.sh`." The shipped suite
  (tests/keybindings.test.sh, 423 lines) runs entirely against a stub `hyprctl`
  and a sandboxed Lua tree — no case consults the live compositor or the real
  `/usr/share/omarchy/default/hypr/bindings/` tree; it cannot, and stay
  hardware-free, reproduce PRD §2.7's 175-chord analysis.
- **Evidence:** read of the suite (no `hyprctl binds` case outside the stub);
  live half is only in the orchestrator's recon (PRD §2.7) and the 04:20
  install record. My own read-only check confirms the eight chords are
  installed and live (`hyprctl binds -j` shows all eight with `omafan:`
  descriptions, modmask 72), i.e. the analysis was right — but nothing
  *reproduces* it as a test.
- **Clause:** DESIGN §7 (the sentence); PRD K2.
- **Smallest fix:** strike the sentence via a DEVIATIONS entry (the claim is
  orchestration-time evidence, not a repeatable test), or add an
  `OMAFAN_LIVE`-gated live free-chord check to the suite.

### R1-5 — should-fix (systemic): no automated gate exercises QML behaviour — three semantic mutations and one blocker all pass every gate
- **Evidence (mutations on the current tree, each leaving
  qml-lint + model + ctl + keybindings + plugin-validate green):**
  - M17: `Esc` closes the panel before help (deleted the
    `if (root.helpOpen)` line, Panel.qml:620) — gates GREEN.
  - M19: bar wheel inverted (`delta < 0 ? 100 : -100`, BarWidget.qml:126) —
    gates GREEN.
  - M20: key-map row text vandalised (`"c", "DO NOTHING"`, KeyboardHelp.qml) —
    gates GREEN.
  - R1-1 itself (a fatal runtime defect) is gate-green today.
- **Why:** `tests/qml-lint.sh` is syntax/import-only; the R3 shim cannot see
  `qs.Ui`-rooted property typos; `run-all.sh` has no QML behavioural suite;
  the live load gate (G4) is opt-in and last ran 04:01, before the two most
  recent Panel.qml rewrites.
- **Clause:** PRD §4 G2/G4 (the QML quality model rests on a live check that
  is not being re-run per change); DESIGN §10 (the hardware-free gate set).
- **Smallest fix:** process rule — any `Panel.qml`/`BarWidget.qml` merge must
  re-run the live G4 load before acceptance (the orchestrator already owns
  this; make it a hard rule), and consider a `qmltestrunner` suite
  (Qt 6.11's runs headless here) for the Model-backed panel functions.

### R1-6 — nit: two post-freeze contract changes are still unmirrored in the frozen documents
- DESVIATIONS.md was populated at 04:40 (R1–R7 recorded; §4.4's id list now
  names `pkexec_write_path`) — verified. Two residues remain:
  a) DESIGN §4.1 line 191 still documents the hw-limit cache as
     `{"fan_min_rpm":…,"fan_max_rpm":…,"captured_at":…,"afanctl_version":…}`
     while `bin/omafan-ctl` also writes `interval_s` (T04c D2; my cache
     transcript: `…,"afanctl_version":"0.1.0","interval_s":1}`).
  b) PRD §4 G2 still specifies the literal `qmllint -I $OMARCHY_PATH/shell`
     gate, which cannot pass as written (my run emits
     `Failed to import qs.Ui` / `WidgetButton was not found` warnings);
     ruling R3 substituted the shim harness in DESIGN-adjacent docs but the
     PRD gate line was not updated.
- **Smallest fix:** extend the cache-shape line with `interval_s (ruling R7/T04c
  D2)`; reword G2 to name `tests/qml-lint.sh` as the gate.

### R1-7 — nit: extra positional arguments are silently ignored on every verb
- **Evidence (fixture invocations, T04c CLI — parse loop unchanged in T04d at
  :1223/:1263/:1269):** `preset med typo` → rc 0, argv.log `hold 4200`;
  `status junk` → rc 0; `rpm 3000 9` → rc 0, `hold 3000`; `release now` →
  rc 0. `cycle extra` correctly exits 2 (`cycle takes no arguments`).
- **Clause:** DESIGN §4 ("a bad flag never exits 0" is honoured for flags;
  positional junk is unspecified — surprising, not unsafe).
- **Smallest fix:** the same arity check `cycle` has, on preset/rpm and the
  read verbs.

### R1-8 — nit: offline panel chips render fabricated "0 rpm"
- **Where:** `Panel.qml:108–111` — the fallback
  `Model.presetsFor(root.haveBand ? … : 0, … : 0)`; `presetsFor(0,0)` yields
  rpm `0` for all five hold presets (node proof:
  `presetsFor(0,0) -> auto=null off=0 low=0 med=0 high=0 full=0`), and
  `PresetChip` renders `formatRpm(0)` = `"0 rpm"`.
- **Clause:** PRD R4/F6 truthfulness; the same file's own rule (T09b D1) that
  an unknown value renders as an em dash, never a fake number.
- **Smallest fix:** pass a null/NaN band into the fallback so `presetRpm`
  returns null (chips then render "—").

### R1-9 — nit: `docSlider` is a when-clause that can never fire (ticket step 5)
- **Where:** `Panel.qml:101–103` reads `statusDoc.slider.step_rpm` —
  `omafan.status.v1` (§4.1) has no `slider` member; the slider block lives in
  `omafan.presets.v1` (§4.2). `sliderStepRpm` is permanently the 100 fallback
  (harmless — 100 is the frozen step — but the code implies a document feed
  that never arrives).
- **Smallest fix:** delete `docSlider` (or source the step from a presets
  round-trip if variability is ever wanted).

### R1-10 — nit: dead code — `assert_band` and a fallback to a nonexistent field
- `bin/omafan-ctl:575` `assert_band()` is defined and never called (the band
  check is inlined in `do_write_rpm`:1167). `Model.js:153` falls back to
  `status.daemon.target_rpm`, a field that does not exist in
  `omafan.status.v1` (target rpm lives under `fan.`) — the fallback can only
  ever produce undefined.
- **Smallest fix:** delete both (behaviour is fully covered by the inline check
  and `hold.rpm`).

### R1-11 — nit: IPC return strings and rpm snapping diverge from §6.2
- `IpcHandler.preset(name)` returns `"ok: Medium 4,200 rpm"`
  (label + formatted rpm) where DESIGN §6.2 documents `"ok: med 4200 rpm"`
  (id + raw rpm) — a script matching the preset id breaks. `IpcHandler.rpm`
  silently snaps to the 100-grid (`rpm 3050` → holds 3100, disclosed only in
  the return string) while CLI `omafan-ctl rpm 3050` holds 3050 — the same
  verb, two snapping semantics.
- **Smallest fix:** return the id form; snap in both places or neither
  (snapping in the panel is defensible — document it in §6.2).

### R1-12 — nit: `KeyboardHelp.qml` renders 12 of §6.3's 13 rows
- The `mouse — hover = cursor, click = apply, wheel = ±1 step` row is absent
  (rows at KeyboardHelp.qml:20–33). T08's done-criterion said "one-for-one";
  a *key* map omitting the mouse row is defensible but is still a divergence.
- **Smallest fix:** add the row or record the exclusion in DEVIATIONS.md.

### R1-13 — nit: missing `jq` produces an undocumented exit 127 with no fix line
- **Evidence:** minimal-PATH run →
  `omafan-ctl: line 140: jq: command not found`, exit 127 (no human fix line,
  and 127 is not in §4's exit-code table). `notify-send` absence is handled
  (test 19); `jq` absence is not.
- **Smallest fix:** a `command -v jq` guard at startup with a fix line, or an
  explicit note that jq is a hard dependency.

### R1-14 — nit: a write refused because the panel is busy is invisible to the user
- `sendCommand` (:259/:265) and `applyPreset` (:284, T09c D4) silently drop presses
  while a command is in flight; §6.2 specifies "refuses while busy" but
  nothing on screen says the press did nothing, and the 20 s deadline makes
  the window noticeable.
- **Smallest fix:** set a transient `lastError`/hint ("command in flight —
  press again") on the busy refusal.

### R1-15 — nit: the presets grid is two rows of three, not the frozen "single horizontal row of 6"
- `Panel.qml:752` `columns: Math.min(3, …)` vs DESIGN §6.2 "presets is a
  single horizontal row of 6". The change is sensible at this panel width
  (T09b D3 authorised the shorter *label*, not the layout) but no DEVIATIONS
  entry covers it, and the cursor model (`h`/`l` across six chips) now wraps
  visually mid-row.
- **Smallest fix:** record it in DEVIATIONS.md, or restore one row with
  elided labels.

### Found independently and fixed in-flight while this review ran (verified)
- **release_after_minutes never fired** — the timer restarted on every
  2 s poll that saw a hold, so the N-minute interval could never elapse
  (PRD F7's exact scenario). Fixed at 04:39:59 via REVIEW-R2 R2-2: rising-edge
  arming (`holdSeen`, declared at Panel.qml:42), user-interaction restarts in
  `sendCommand`, interval clamped ≥ 60 s. Code re-read and verified; recorded
  in DEVIATIONS.md. **Note: this fix is unreachable until R1-1 is fixed** —
  the arming block sits after the `statusStale` throw in `applyStatus`.
- **`pkexec env` wrapper broke every real write** (orchestrator 04:22) — T04d
  fixed the argv (`["/usr/bin/pkexec","<afanctl>","hold","7200"]`, my dry-run
  transcript), added the D2 custom-runtime-dir refusal (exit 2, verified) and
  bounded runner/notify calls. T05b re-gated the suite (exit 3 via a
  mount-namespace helper that fails loudly if unavailable; the 04:27–04:35
  window where `tests/ctl.test.sh` was red on T04d is closed — 238/0 at
  04:40).
- **`rpm --dry-run` refused when limits were unavailable** (my T04c-era run:
  rc 1) — fixed in T04d (current CLI previews rc 0, verified).
- **Stale `state.json` now refuses writes** (exit 5, `--force` overrides) —
  applied as R7.3 after REVIEW-R2; verified by transcript. DEVIATIONS notes a
  missing regression case in `tests/ctl.test.sh` — still true at 04:40; see
  R1-2 for why the threshold behind it also needs fixing.

## Contract coverage (DESIGN §1–§7, §10 → code and proof)

Verdicts: **proved** = code + passing test; **impl-untested** = implemented,
no automated test (live/review evidence only); **missing/divergent**.

| # | Contract item | Implementation | Proof | Verdict |
|---|---|---|---|---|
| §1 | manifest exact | manifest.json:1–25 | tests/manifest.test.sh:35–67; `omarchy plugin validate .` → 0 | proved |
| §1 | kinds `["bar-widget"]`, one entry point | manifest.json:10–11 | manifest.test.sh:44–46; validate | proved |
| §1 | IPC target `omafan`, exactly one IpcHandler, in Panel.qml | Panel.qml:403 | grep (1 handler; BarWidget 0); live IPC 04:01 | proved (no automated one-handler gate — grep-only) |
| §1 | version 1.0.0, defaultSection right | manifest.json:5,17 | manifest.test.sh:38,47 | proved |
| §2 | file map present | repo tree (README landed 04:14; PREVIEW optional, absent) | manifest.test.sh:50–52 | proved |
| §3 | ladder + derived rpms (1200/2700/4200/5700/7200) | Model.js:37–49; bin/omafan-ctl `preset_rpm` | model.test.mjs:127–148; ctl.test.sh §3 | proved |
| §3 | labels incl "Off (hardware floor)" | Model.js:11–18; `preset_label` | model.test.mjs:135–137; ctl.test.sh:211–212 | proved |
| §3 | "off is not off" on every surface | chip "Off (floor)" (:954) + legend (:776–786) | T09b D3 authorises; live screenshot 04:01 | impl-untested |
| §3 | presets-are-floors legend | Panel.qml:776–786 | live screenshot | impl-untested |
| §3 | slider range/step 100; 1 key step, 5 with Shift | Panel.qml:221–226, 398–399; PanelSlider step | — | impl-untested |
| §3 | non-preset hold renders `custom` | CLI `cycle_current_preset`; chips compare `holdDoc.preset` | ctl.test.sh §15 | proved (CLI); impl-untested (chips) |
| §4 | verb set incl `cycle`/`release`/`version`/`--help` | parse loop :1159+ | ctl.test.sh §6, §21 | proved |
| §4 | globals + env table, order-insensitive | parse loop; `need_value` | my flag-order/missing-value runs (all rc 2/0 as specified); ctl() harness | proved |
| §4 | exit codes 0–8 | `write_prereqs`, `do_write_*` | ctl.test.sh §§5–14, §20; T05b exit-3 re-gate | proved |
| §4.1 | status document field-by-field | `run_status` | ctl.test.sh §1 (incl. R6 exit-5 document) | proved |
| §4.1 | state_stale = max(5, 3×poll) | flat 5 s (:41, :320) | — | **missing/divergent (R1-2)** |
| §4.1 | hw-limit cache path/fallback/warn | `load_limits` | ctl.test.sh §17 | proved |
| §4.1 | cache shape | writes `interval_s` too | — | missing/divergent, doc unmirrored (R1-6a) |
| §4.2 | presets JSON | `run_presets` | ctl.test.sh §3 | proved |
| §4.3 | action JSON + error envelope | `action_json`, `fail_action` | ctl.test.sh §§5, 12–14 | proved |
| §4.4 | fixed check id set | 12 ids (adds `pkexec_write_path`) | ctl.test.sh:219–231 | proved (DESIGN mirrored 04:40 via R7) |
| §4.5 | cycle semantics | `do_cycle`/`cycle_next_preset` | ctl.test.sh §21 | proved |
| §4 | dry-run prints argv, executes nothing | `run_write` dry-run branch | ctl.test.sh §7; M6 mutation caught | proved |
| §4 | reads never pkexec | `query_afanctl_status`, `load_limits` | ctl.test.sh §18 (stub exits 99); M8 caught | proved |
| §4 | notify never changes exit | `notify_user` (+ timeout guard, T04d) | ctl.test.sh §19 | proved |
| §5 | 19 functions, ES5, pure | Model.js | model.test.mjs (148 asserts) | proved |
| §5.1 | undercooling guard (CLI exit 8, panel confirm) | Model.js:283–324; `assert_undercooling`; Panel.qml:282–300 | model.test.mjs guard table; ctl.test.sh §14 | proved (CLI); impl-untested (panel arm/confirm) |
| §6.1 | bar forwards open/close/opened/popout | BarWidget.qml:73–88 (omaplug pattern, verified vs installed shell) | live load 04:01 | impl-untested |
| §6.1 | click/right-click/wheel semantics | BarWidget.qml:150–168 | M19 blind spot | impl-untested |
| §6.1 | tooltip format | BarWidget.qml:68–71 | — | impl-untested |
| §6.1 | tint while hold; no IpcHandler/Process/exec here | BarWidget.qml:156–157 | grep clean | proved (grep-only) |
| §6.2 | root props, manageIpc:false, 8 IPC methods | Panel.qml:16–21, 403–437 | live state/toggle 04:01 | impl-untested (preset/rpm/release round-trip not in ledger; strings diverge R1-11) |
| §6.2 | state machine (status/lastError/busy/pendingRpm/focusSection/…) | Panel.qml:30–52 | — | **missing/divergent (R1-1: `statusStale` undeclared)** |
| §6.2 | sendCommand gate: busy/degraded/debounce 300 ms/re-read | Panel.qml:257–274, 541–545, 478–488 | — | impl-untested |
| §6.2 | cursor model, presets single row of 6 | Panel.qml:196–214, 750–770 | — | missing/divergent (R1-15 layout); cursor impl-untested |
| §6.2 | banners for the five states, fix named | Panel.qml:118–128 + `Model.degradedReason` | — | impl-untested (and unreachable per R1-1 for stale/error cases) |
| §6.2 | release_after_minutes net | Panel.qml:366–376, 551+ | fixed via R2-2 (verified) but dead until R1-1 | impl-untested |
| §6.3 | key map (j/k/h/l/arrows/Enter/Space/Esc/Tab) | Panel.qml:613–627 — matches installed `PanelKeyCatcher.qml` signals; Shift+h/l arrives uppercase (shell source :81) | M17 blind spot | impl-untested |
| §6.3 | digits 1–6, c, r, ? | `handleTextKey` :394–402 | M20 blind spot | impl-untested |
| §6.3 | KeyboardHelp rows one-for-one | KeyboardHelp.qml:20–33 | — | missing/divergent (R1-12: 12 of 13) |
| §7 | 8 chords, exact table, o.bind form | bin/omafan-keybindings:55–68 | keybindings.test.sh §1/§9; M10 caught | proved |
| §7 | conflict refusal (live + Lua + code: alias) | :116–176 | tests §§4–6 | proved |
| §7 | idempotent install, byte-identical remove, backup, reload+verify | :272–402 | tests §§1–3, §7; live install/remove md5 (LEDGER 04:20) | proved |
| §7 | status installed/not-installed/conflict | :405–442 | test §8 | proved |
| §7 | free-chord analysis reproduced by the suite | — | — | missing/divergent (R1-4) |
| §8 | no /sys writes anywhere; reads never pkexec; --force CLI-only | grep; ctl.test.sh §18 | proved |
| §10 | run-all runs the six suites, exits non-zero on failure | tests/run-all.sh:50–60 | three observed runs (red at 04:11/04:29 for in-flight causes, green at 04:35) — note: it runs *all* suites then fails, rather than stopping at the first | proved |
| §10 | live/hw suites opt-in, never inside run-all | grep run-all.sh | proved |
| §10 | harness self-test | tests/lib/harness.sh:126–180 | `bash tests/lib/harness.sh` → PASS 12 / FAIL 0 | proved |

## Mutation results (step 2)

Base copies under `/tmp` (repo copied with `.git`/`.omo` excluded); one mutation
per copy; the named suite must fail. A green run is a blind-spot finding.

| # | Mutation (file: change) | Gate | Result |
|---|---|---|---|
| M1 | Model.js: low fraction 0.25→0.30 | model.test.mjs | CAUGHT |
| M2 | Model.js: STALE_AFTER_S 5→4 | model.test.mjs | CAUGHT |
| M3 | Model.js: undercooling 80→70 °C | model.test.mjs | CAUGHT |
| M4 | Model.js: drop thousands separator | model.test.mjs | CAUGHT |
| M15 | Model.js: parseStatus accepts any schema | model.test.mjs | CAUGHT |
| M5 | omafan-ctl: band refusal exit 7→5 | ctl.test.sh | CAUGHT |
| M6 | omafan-ctl: dry-run executes (no early return) | ctl.test.sh | CAUGHT |
| M7 | omafan-ctl: monitor_only check deleted | ctl.test.sh | CAUGHT |
| M8 | omafan-ctl: `pkexec --version` added to `status` (reads must never pkexec) | ctl.test.sh | CAUGHT |
| M14 | fake-afanctl: argv logging removed | ctl.test.sh | CAUGHT |
| M9 | keybindings: conflict check disabled | keybindings.test.sh | CAUGHT |
| M10 | keybindings: chord C→V in block | keybindings.test.sh | CAUGHT |
| M11 | keybindings: remove breaks byte-identity (separator undo deleted) | keybindings.test.sh | CAUGHT |
| M12 | Panel.qml: closing brace deleted (syntax) | qml-lint.sh | CAUGHT |
| M13/M13b | manifest.json: entry point → Missing.qml | plugin validate / manifest.test.sh | CAUGHT |
| M21 | omafan-ctl (current tree): band refusal exit 7→5 | ctl.test.sh (T05b) | CAUGHT |
| M22 | omafan-ctl (current tree): `env` re-inserted into privileged argv (the live T04d blocker) | ctl.test.sh (T05b) | CAUGHT (`assert_runner_argv` + argv JSON both fail) |
| M17 | Panel.qml: Esc closes panel before help | all six suites | **GREEN — blind spot (R1-5)** |
| M19 | BarWidget.qml: wheel direction inverted | all six suites | **GREEN — blind spot (R1-5)** |
| M20 | KeyboardHelp.qml: key-map text vandalised | all six suites | **GREEN — blind spot (R1-5)** |
| — | none: R1-1 is *present* in the current tree | all six suites + run-all | **GREEN — the standing blind spot (R1-1)** |

## Could not verify (and why)

- **Live shell load of the current Panel.qml** (`OMAFAN_LIVE` forbidden for this
  review): the one gate that would catch R1-1 at load time. The last live load
  (04:01) predates the two most recent Panel rewrites.
- **Real-runner behaviour/timings** (T04d gates 2, 3, 5): ticket rule — every
  `omafan-ctl` invocation here used
  `--afanctl tests/fixtures/fake-afanctl --pkexec none --runtime-dir <tmpdir>`
  (except `--dry-run` and pure-usage invocations, which execute nothing).
- **Chord key-press → command delivery**: not simulable on this Hyprland
  (LEDGER 04:20); registered-and-command-run is the accepted evidence.
- **tests/hw-smoke.sh** (`OMAFAN_HW` forbidden); **GitHub repo state** (network
  forbidden); **bar-widget screenshot artefact** for G6 (the 04:01 screenshot
  covered the panel; a bar render artefact is not in the trail I can read).
- **REVIEW-R2.md itself**: not present in `orchestration/` at snapshot time
  (T16 in flight); I saw only its applied effects (R2-2/R2-3, DEVIATIONS).

## PRD §4 acceptance-gate assessment (step 6)

| Gate | Verdict | Evidence |
|---|---|---|
| G1 validate exits 0 | verifiable-now, PASS | `omarchy plugin validate .` → exit 0 (04:11, 04:29) |
| G2 qmllint clean | verifiable-now, FAIL as written / PASS as harnessed | literal command emits `qs.Ui` import warnings (R3); `tests/qml-lint.sh` PASS |
| G3 run-all all PASS | verifiable-now, PASS at 04:35 (6/6); ctl re-verified 238/0 at 04:40 | was red 04:11 (README, T11 pending) and 04:29 (T04d/T05 mismatch) — both closed in-flight; orchestrator must re-run on the final tree |
| G4 live load, no `qs log` errors | unsupported for the current tree | last live load 04:01, pre-T09c/T04d; R1-1 predicts a failure now |
| G5 IPC round-trip | verifiable-in-principle (partially evidenced) | `state`/`toggle` live 04:01 (pre-T09c); `preset`/`rpm`/`release` round-trips not in the ledger |
| G6 bar widget render (screenshot) | unsupported by artefact | no bar-render artefact found in the readable trail |
| G7 keybindings install/live/remove | verifiable-now, PASS (one gap) | LEDGER 04:20 (install, `hyprctl binds` shows all eight, remove byte-identical md5); my read-only `status` confirms installed + `stale-path` detection works; key delivery not simulable |
| G8 real hardware write + verified observe | verifiable-in-principle | ledger records real writes with verified returns (04:22), but the scripted `hw-smoke.sh` run is pending |
| G9 docs complete | verifiable-now, PASS | README/INSTALL/TROUBLESHOOTING landed 04:14; manifest suite green |
| G10 public GitHub repo | unsupported by artefact (network forbidden here) | publish is post-G8 per plan |
| G11 PUBLISHING inputs | verifiable-now (existence) | docs/PUBLISHING.md present (T13 verified); content is T13/T16 territory |
| G12 adversarial review answered | in-progress by definition | this report + T16 in flight; triage in LEDGER pending |

## Commands run (method log — all read-only or /tmp/fixture-scoped)

Suite runs: `bash tests/run-all.sh` (04:11 red/manifest, 04:29 red/ctl, 04:35
green, plus `bash tests/ctl.test.sh` → `PASS 238 / FAIL 0` at 04:40);
`bash tests/lib/harness.sh` → `PASS 12 / FAIL 0`; `node tests/model.test.mjs`;
`bash tests/keybindings.test.sh`; `omarchy plugin validate .`.
CLI probes (fixture + `--pkexec none` + temp runtime dir unless noted):
flag-before-verb; extra-positionals; missing values; `--`; repeated flags;
env-only `OMAFAN_AFANCTL`; `--afanctl=`/`--pkexec=` empty; second identical
write; read-only runtime dir (exit 1 `write_failed`); unreadable runtime dir
(exit 5 + document); minimal-PATH-without-jq (exit 127); `LC_ALL` C vs
C.UTF-8 human output (identical md5); dry-run argv with the real runner
(prints only); D2 custom-runtime-dir refusal (exit 2, runner sentinel absent);
stale-state write refusal (exit 5 / `--force` 0); `presets --human` (broken
column). QML/shell verification: read of installed `Ui/{Panel, WidgetButton,
BarWidget, PanelSlider, KeyboardPanel, PanelKeyCatcher}.qml`, `Commons/{Style,
Color}.qml`, `omaplug/BarWidget.qml`, `monitor/Panel.qml`; DESIGN-literal
`qmllint -I /usr/share/omarchy/shell BarWidget.qml`; `QT_QPA_PLATFORM=offscreen
qmltestrunner` undeclared-property proof; `hyprctl binds -j` (read-only) and
`bin/omafan-keybindings status` (read-only). Prohibitions: `bash -n` on all
shell files; greps for `/sys` writes, TODO, trailing whitespace, EOF newlines,
`IpcHandler`/`Process`/`pkexec` in BarWidget.qml. Mutations: 19 runs in
`/tmp/omafan-mut-*` copies (table above). No git mutations, no writes outside
`orchestration/REVIEW-R1.md` and `/tmp`; one `git status --porcelain` was run
(read-only) while assessing tree churn.
