import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// omafan panel (DESIGN.md 6.2, 6.3): the single control surface.
//
// This file owns every side effect the shell side performs: one Process polls
// `bin/omafan-ctl status --json` and one runs each write verb. It never touches
// /sys and never talks to afanctl directly — every write goes through
// sendCommand(argv) so the busy lock, the degraded/offline refusals, the 300 ms
// slider debounce and the error surface all live in exactly one place.
Panel {
  id: root
  moduleName: "io.github.yadav-prakhar.omafan"
  ipcTarget: "omafan"
  // The panel owns the one IpcHandler the target permits (DESIGN.md 1).
  manageIpc: false

  // Injected by BarWidget.injectPanel(); declared so the properties exist
  // (`"anchorItem" in target` must be true for the injection to land).
  property Item anchorItem: null
  property QtObject hostWidget: null

  // ------------------------------------------------------------------ state
  // status: the parsed omafan.status.v1 document, or null while unknown.
  property var status: null
  // The last raw stdout of the status verb, verbatim; `state()` IPC hands this
  // back untouched so scripts see exactly what the CLI printed.
  property string rawStatusText: ""
  property string lastError: ""
  // omafan#4: the single quiet line shown when the daemon or the document is a
  // newer schema than this plugin understands. Set from a successful parse;
  // empty when everything is understood.
  property string schemaNotice: ""
  property bool busy: false
  property var pendingRpm: null
  // T2: true after a release-type write (preset auto / release verb) is SENT
  // until a fresh status confirms hold inactive; while true, a stale hold doc
  // must never repopulate pendingRpm. Cleared only by that confirmation, by a
  // failed release, or by a superseding manual write — never by a bare write
  // exit 0 (an exit code is not a daemon state).
  property bool expectingAuto: false
  // T2: true while the in-flight write (if any) is a release; lets onExited
  // and the command deadline void the Auto expectation on failure without
  // touching the truthful prior pendingRpm.
  property bool lastWriteWasRelease: false
  // T09c D3: true when a status poll failed or was killed at its deadline —
  // the previous document stays rendered but is visibly marked as stale.
  property string focusSection: "presets"   // "presets" | "slider" (DESIGN.md 6.2)
  // T09c D3 (declaration restored by REVIEW-R1 R1-1): true when a status poll
  // failed or was killed at its deadline. This property was *used* by
  // applyStatus/statusDeadline/the stale banner but never declared, so every
  // poll threw a TypeError mid-function and the panel never applied a status
  // document — a runtime-fatal defect that was green on every automated gate.
  property bool statusStale: false
  // REVIEW-R2 R2-2: true while a hold has been seen and the release net armed,
  // so the net arms on the rising edge instead of being restarted every poll.
  property bool holdSeen: false
  property int selectedIndex: 0             // slider uses the -1 sentinel
  property bool cursorActive: false
  property bool helpOpen: false
  // Panel refresh control (T5): error line for the settings-write path. Kept
  // separate from lastError (the fan banner) because a failed settings write
  // is fan-neutral and must survive the next good status poll clearing
  // lastError.
  property string settingsError: ""
  // True while an `omarchy bar set` write is in flight. Deliberately NOT
  // root.busy: settings writes never touch the fan, so they stay available
  // while a fan write or a degraded daemon holds the fan lock.
  property bool settingsBusy: false

  // D4: full documents (--with the per-sensor list) are requested on panel open
  // and every tenth poll; the flag survives a refresh refused while busy so no
  // full round is silently dropped.
  property int pollCount: 0
  property bool fullPending: false

  // Undercooling guard (DESIGN.md 5.1): the preset awaiting its confirming
  // second Enter within 10 s.
  property string armedPresetId: ""

  // Orchestrator ruling R4: resolve the CLI from the plugin directory at
  // runtime, never a hardcoded absolute path.
  readonly property string ctlPath: {
    var resolved = Qt.resolvedUrl("bin/omafan-ctl").toString()
    return resolved.replace(/^file:\/\//, "")
  }

  // Global CLI flags shared by every invocation, driven by OMAFAN_* env so the
  // same QML is testable against the fixture without touching the fan. Flags
  // are added only when set (ruling R4: never invent arguments).
  function withGlobalFlags(args) {
    var out = args.slice()
    var names = ["OMAFAN_AFANCTL", "OMAFAN_RUNTIME_DIR", "OMAFAN_PKEXEC"]
    var flags = ["--afanctl", "--runtime-dir", "--pkexec"]
    for (var i = 0; i < names.length; i++) {
      var value = Quickshell.env(names[i])
      if (typeof value === "string" && value !== "") out = out.concat([flags[i], value])
    }
    return out
  }

  readonly property var statusArgv: {
    var args = [root.ctlPath, "status", "--json"]
    if (root.fullPending) args.push("--full")
    return root.withGlobalFlags(args)
  }

  // Advanced polling control (T3): how often omafan re-reads daemon status,
  // never how often the daemon samples the SMC. Mode auto (the default) is
  // exactly 2 s regardless of any leftover poll_seconds; mode custom uses
  // poll_seconds in whole seconds 1-10. The mode math lives in
  // Model.effectivePollSeconds so it is covered by tests/model.test.mjs.
  readonly property string pollMode: String(root.setting("poll_mode", "auto"))
  readonly property int pollSeconds: Model.effectivePollSeconds(root.pollMode, root.setting("poll_seconds", 2))
  readonly property int releaseAfterMinutes: Math.max(0, Math.round(Number(root.setting("release_after_minutes", 0)) || 0))

  // ------------------------------------------------------- derived from doc
  readonly property var statusDoc: root.status
  readonly property string modeTone: root.statusDoc === null ? "offline" : Model.modeTone(root.statusDoc)
  readonly property bool writesRefused: root.modeTone === "degraded" || root.modeTone === "offline"

  readonly property var hardware: root.statusDoc && root.statusDoc.hardware ? root.statusDoc.hardware : null
  readonly property int fanMinRpm: root.hardware ? Math.round(Number(root.hardware.fan_min_rpm)) : 0
  readonly property int fanMaxRpm: root.hardware ? Math.round(Number(root.hardware.fan_max_rpm)) : 0
  readonly property bool haveBand: root.fanMaxRpm > root.fanMinRpm && root.fanMinRpm > 0

  readonly property var holdDoc: root.statusDoc && root.statusDoc.hold ? root.statusDoc.hold : null
  readonly property bool holdActive: root.holdDoc ? root.holdDoc.active === true : false

  readonly property var docSlider: root.statusDoc && root.statusDoc.slider ? root.statusDoc.slider : null
  readonly property int sliderStepRpm: root.docSlider && root.docSlider.step_rpm
    ? Math.max(1, Math.round(Number(root.docSlider.step_rpm))) : 100

  // The chip ladder: the document's own presets when present (their rpms come
  // from the live hardware band via the CLI), else an rpm-less fallback so the
  // row still renders before the first good poll.
  readonly property var presetList: {
    if (root.statusDoc && root.statusDoc.presets && root.statusDoc.presets.length)
      return root.statusDoc.presets
    return Model.presetsFor(root.haveBand ? root.fanMinRpm : 0,
                            root.haveBand ? root.fanMaxRpm : 0)
  }

  // One banner slot with strict precedence: degraded/offline reasons from the
  // daemon's own fields first (never optimistic), then a fresh command error,
  // then the armed undercooling confirmation.
  readonly property string bannerText: {
    if (root.lastError !== "") return root.lastError
    var reason = Model.degradedReason(root.statusDoc)
    if (reason) return reason
    if (root.armedPresetId !== "") {
      var target = Model.presetRpm(root.armedPresetId, root.fanMinRpm, root.fanMaxRpm)
      var warning = Model.undercoolingWarning(root.statusDoc, target)
      if (warning) return warning
    }
    if (root.schemaNotice !== "") return root.schemaNotice
    return ""
  }

  readonly property var recentErrorLines: {
    var doc = root.statusDoc
    var out = []
    if (!doc || !doc.recent_errors) return out
    for (var i = 0; i < doc.recent_errors.length && out.length < 3; i++) {
      var entry = doc.recent_errors[i]
      if (entry && entry.message) out.push(String(entry.message))
      else if (typeof entry === "string") out.push(entry)
    }
    return out
  }

  // D1: the header reads "CPU <temp> · Fan <rpm>" with an em dash for any
  // unknown value — never a fabricated number, never a dangling separator such
  // as "CPU · Fan..." (T04c stops the CLI emitting null t_eff_c on the fast
  // path; until then the panel renders the gap honestly).
  function headerText() {
    var doc = root.statusDoc
    var temp = doc && doc.thermal ? doc.thermal.t_eff_c : null
    var rpm = doc && doc.fan ? doc.fan.rpm : null
    var tempStr = Model.formatTemp(temp)      // "64 °C" or "—"
    var rpmStr = Model.formatRpm(rpm)         // "6,078 rpm" or "—"
    return "CPU " + tempStr + " · Fan " + rpmStr
  }

  // D2: the daemon's verified flag from state.json (state.v1 carries it; the
  // fast-path document exposes it in fan.verified). Unknown is neither a pass
  // nor a fault, so it renders as "not verified" only while a hold is active.
  function holdVerified() {
    var doc = root.statusDoc
    if (!doc || !doc.fan) return false
    return doc.fan.verified === true
  }

  // D2: "Uptime <value> · Polls <n>" always (em dash for anything unknown);
  // the verification clause appears only while a hold is on, because with no
  // hold nothing is being written and "Verified: no" would read as a fault.
  function footerText() {
    var doc = root.statusDoc
    var daemon = doc && doc.daemon ? doc.daemon : null
    var uptime = daemon ? Model.formatUptime(daemon.uptime_s) : "—"
    var polls = daemon && daemon.polls !== null && daemon.polls !== undefined
      ? String(daemon.polls) : "—"
    var text = "Uptime " + uptime + " · Polls " + polls
    if (root.holdActive) {
      text += root.holdVerified() ? " · verified" : " · not verified"
    }
    return text
  }

  // D4: sensor rows from a --full document; empty on the fast path, which is
  // exactly when the footer/header carries the load alone.
  readonly property var sensorRows: {
    var doc = root.statusDoc
    var out = []
    if (!doc || !doc.thermal || !doc.thermal.sensors) return out
    for (var i = 0; i < doc.thermal.sensors.length; i++) {
      var s = doc.thermal.sensors[i]
      if (s && s.label !== undefined && s.temp_c !== null && s.temp_c !== undefined)
        out.push({ label: String(s.label), temp: Model.formatTemp(s.temp_c) })
    }
    return out
  }

  // ----------------------------------------------------------- cursor model
  // DESIGN.md 6.2: exactly two sections; presets is a single horizontal row,
  // the slider is a lone row with the -1 sentinel.
  readonly property var visibleSections: ["presets", "slider"]

  function moveSection(dir) {
    var idx = root.visibleSections.indexOf(root.focusSection)
    if (idx < 0) { root.focusSection = "presets"; root.selectedIndex = 0; return }
    var next = idx + dir
    if (next < 0 || next >= root.visibleSections.length) return
    root.focusSection = root.visibleSections[next]
    root.selectedIndex = root.focusSection === "presets" ? 0 : -1
    root.cursorActive = true
  }

  function moveCursorH(delta) {
    if (root.focusSection !== "presets") return
    var next = root.selectedIndex + delta
    var max = root.presetList.length - 1
    if (next < 0) next = 0
    if (next > max) next = max
    root.selectedIndex = next
    root.cursorActive = true
  }

  // Keyboard on the slider: one press is one step (100 rpm), Shift gives five
  // (DESIGN.md 3, 6.3).
  function sliderStepKey(deltaSteps) {
    var base = root.currentSliderBase()
    var next = Model.snapRpm(Number(base) + deltaSteps * root.sliderStepRpm,
                            root.fanMinRpm, root.fanMaxRpm, root.sliderStepRpm)
    root.setPendingRpm(next)
  }

  // Where the knob sits when nothing is pending: the daemon's target while a
  // hold is on, else the current fan rpm snapped to the grid, else Medium.
  function currentSliderBase() {
    if (root.holdActive && root.holdDoc && root.holdDoc.rpm !== null && root.holdDoc.rpm !== undefined)
      return root.holdDoc.rpm
    if (root.statusDoc && root.statusDoc.fan && root.statusDoc.fan.rpm !== null
        && root.statusDoc.fan.rpm !== undefined)
      return Model.snapRpm(Number(root.statusDoc.fan.rpm), root.fanMinRpm, root.fanMaxRpm, root.sliderStepRpm)
    return root.haveBand ? Model.presetRpm("med", root.fanMinRpm, root.fanMaxRpm) : null
  }

  function setPendingRpm(rpm) {
    if (rpm === null || rpm === undefined) return
    root.pendingRpm = rpm
    sliderSend.restart()
  }

  function setPendingRpmQuiet(rpm) {
    // Drag feedback without sending: a write happens on the debounced timer or
    // an explicit release (F5), never on every mousemove.
    if (rpm === null || rpm === undefined) return
    root.pendingRpm = rpm
  }

  // ---------------------------------------------------------------- actions
  // The single write gate (DESIGN.md 6.2): refuse while busy or while the
  // daemon is degraded/offline, naming the cause and its fix. The CLI enforces
  // the same rules; refusing here keeps the banner truthful instead of relying
  // on an error round-trip.
  function sendCommand(args) {
    if (!args || !args.length) return
    if (root.busy) return
    if (root.writesRefused) {
      root.lastError = Model.degradedReason(root.statusDoc)
        || "The fan daemon is unavailable. Fix: systemctl restart afanctl"
      return
    }
    if (cmdProc.running) return
    root.lastError = ""
    root.busy = true
    cmdProc.timedOut = false
    // T2: every release path (preset auto, IPC release(), the release timer)
    // funnels through here, so the funnel owns the Auto expectation. A queued
    // manual write must not land after the release that superseded it, hence
    // the debounce cancel; a newer manual write supersedes a pending Auto
    // expectation. Refusals above return before this point, so a refused write
    // never mutates the expectation.
    var isRelease = args[0] === "release"
      || (args[0] === "preset" && args.length > 1 && args[1] === "auto")
    root.lastWriteWasRelease = isRelease
    if (isRelease) {
      sliderSend.stop()
      root.expectingAuto = true
    } else {
      root.expectingAuto = false
    }
    cmdProc.command = root.withGlobalFlags([root.ctlPath].concat(args))
    cmdProc.running = true
    commandDeadline.restart()
    // REVIEW-R2 R2-2: every genuine user action restarts the release net's
    // countdown, which is what "release after N minutes without interaction"
    // promises. The timer is not started here — applyStatus owns arming.
    if (root.releaseAfterMinutes > 0 && root.holdActive) releaseTimer.restart()
  }

  // The undercooling confirmation (DESIGN.md 5.1): a hot-machine preset below
  // the current fan speed is sent only when the same preset is requested again
  // within 10 s. The second attempt carries the narrow --force-undercooling
  // (REVIEW-R2 R2-6) because the panel has confirmed deliberately — it is not a
  // silent override, and it must not double as an override for the degraded
  // latch or the band check.
  function applyPreset(id) {
    // T09c D4: a preset press while a write is in flight is ignored, not
    // stacked, and not allowed to re-arm the undercooling confirmation.
    if (root.busy || cmdProc.running) return
    var rpm = Model.presetRpm(id, root.fanMinRpm, root.fanMaxRpm)
    if (rpm !== null && root.haveBand && Model.isUndercoolingHot(root.statusDoc, rpm)) {
      if (root.armedPresetId !== id) {
        root.armedPresetId = id
        armedExpire.restart()
        root.selectedIndex = root.chipIndexFor(id)
        return
      }
      root.armedPresetId = ""
      armedExpire.stop()
      root.sendCommand(["preset", id, "--force-undercooling"])
      return
    }
    root.sendCommand(["preset", id])
  }

  function chipIndexFor(id) {
    for (var i = 0; i < root.presetList.length; i++) {
      if (root.presetList[i] && root.presetList[i].id === id) return i
    }
    return root.selectedIndex
  }

  function applyFocusedPreset() {
    if (root.focusSection !== "presets") return
    var preset = root.presetList[root.selectedIndex]
    if (preset && preset.id) root.applyPreset(preset.id)
  }

  function applyFocusedSlider() {
    if (root.focusSection !== "slider") return
    if (root.pendingRpm === null || root.pendingRpm === undefined) return
    root.sendCommand(["rpm", String(Math.round(Number(root.pendingRpm)))])
  }

  function activateCursor() {
    if (root.focusSection === "presets") { root.applyFocusedPreset(); return }
    if (root.focusSection === "slider") { root.applyFocusedSlider(); return }
  }

  // DESIGN.md 4.5: a custom hold cycles to off, otherwise one step forward
  // through the ladder with wraparound.
  function cycle() {
    var current = root.holdActive && root.holdDoc && root.holdDoc.preset
      ? String(root.holdDoc.preset) : "auto"
    var next = current === "custom" ? "off" : Model.cyclePreset(current, 1)
    root.applyPreset(next)
  }

  // ------------------------------------------------------- panel refresh row
  // T5: the in-panel Auto/Custom chips and the ±1 s stepper write poll_mode /
  // poll_seconds through the shell's own `omarchy bar set` — the same write
  // path the bar-settings UI uses, so no new privilege and no direct
  // shell.json editing. A settings-only write is patched into the running
  // widgets in place (Bar.applySettingsDelta) and BarWidget re-injects the
  // settings into this panel, so pollSeconds re-evaluates live without a
  // reload. These writes are fan-neutral: allowed even while the daemon is
  // degraded/offline, which is exactly when a slower or faster re-read
  // cadence is most useful.
  function setPollMode(mode) {
    var next = mode === "custom" ? "custom" : "auto"
    if (root.settingsBusy || next === root.pollMode) return
    root.settingsBusy = true
    root.settingsError = ""
    settingsProc.timedOut = false
    settingsProc.cmdErr = ""
    settingsProc.command = [settingsProc.omarchyBin, "bar", "set",
                            root.moduleName, "poll_mode", next]
    settingsProc.running = true
    settingsDeadline.restart()
  }

  function stepPollSeconds(delta) {
    if (root.settingsBusy) return
    // Clamp through the same mode math the cadence itself uses, so the
    // stepper can never land outside whole seconds 1-10.
    var next = Model.effectivePollSeconds("custom", root.pollSeconds + delta)
    if (next === root.pollSeconds) return
    root.settingsBusy = true
    root.settingsError = ""
    settingsProc.timedOut = false
    settingsProc.cmdErr = ""
    settingsProc.command = [settingsProc.omarchyBin, "bar", "set",
                            root.moduleName, "poll_seconds", String(next), "--json"]
    settingsProc.running = true
    settingsDeadline.restart()
  }

  function refresh() {
    if (statusProc.running || root.busy) return
    if (cmdProc.running) return
    statusProc.timedOut = false
    statusProc.command = root.statusArgv
    statusProc.running = true
    statusDeadline.restart()
    // One full document per request: the flag is consumed here so a poll that
    // lands mid-doctor does not keep re-asking afanctl for sensors.
    root.fullPending = false
  }

  function applyStatus(text) {
    if (statusProc.timedOut) return // killed at its deadline: content is not a status document
    root.rawStatusText = String(text || "").trim()
    var parsed = Model.parseStatus(root.rawStatusText)
    if (parsed.ok) {
      root.status = parsed.status
      root.statusStale = false
      root.lastError = ""
      // The one quiet line for a newer schema (omafan#4): either the document
      // itself is newer than the panel understands, or the CLI flagged the
      // daemon's schema in warnings[]. Never a blank panel, never a hard error.
      root.schemaNotice = parsed.notice
        ? String(parsed.notice)
        : (Model.statusNotice(parsed.status) || "")
      // T2: a release is confirmed only by a fresh status reporting hold
      // inactive (hold.active derives from daemon mode == "hold", DESIGN
      // §4.1) — never by a bare write exit 0. On confirmation the queued
      // debounce is cancelled and pendingRpm is nulled, so the slider falls
      // back to its base/min rendering (null renders "—" at fan_min_rpm, the
      // hardware floor — never the last manual rpm, never a stopped fan).
      if (root.expectingAuto && !root.holdActive) {
        root.expectingAuto = false
        sliderSend.stop()
        root.pendingRpm = null
      } else if (!root.expectingAuto && !sliderSend.running && !rpmSlider.dragging
          && root.holdActive && root.holdDoc
          && root.holdDoc.rpm !== null && root.holdDoc.rpm !== undefined) {
        // Track the daemon's own target while a hold is on — the footer renders
        // that truth, so the knob must not lag behind it. Never while the user
        // is mid-drag, a debounced write is about to land, or a release is
        // awaiting its confirming status (a stale hold doc must not resurrect
        // a manual target after Auto).
        root.pendingRpm = root.holdDoc.rpm
      }
      // release_after_minutes: arm on the hold's RISING EDGE only. Arming on
      // every poll (the original implementation) restarted a one-shot timer
      // every <=10 s, so an interval of >=1 minute could never elapse and the
      // safety net never fired — the only state it exists to catch
      // (REVIEW-R2 R2-2). `holdSeen` makes the arming edge-triggered, and
      // sendCommand() restarts the countdown on genuine user interaction, which
      // is what "without interaction" means.
      if (root.releaseAfterMinutes > 0 && root.holdActive) {
        if (!root.holdSeen) {
          root.holdSeen = true
          releaseTimer.restart()
        }
      } else {
        root.holdSeen = false
        releaseTimer.stop()
      }
    } else {
      // T09c D3: a failed poll keeps the previous document rendered but marks
      // it stale, so the numbers are visibly old and the poll timer keeps
      // running — the panel recovers by itself once omafan-ctl answers again.
      root.statusStale = true
      if (root.lastError === "") {
        root.lastError = "Cannot read the fan state: " + parsed.error +
          ". Fix: run bin/omafan-ctl status --json by hand, then systemctl restart afanctl"
      }
    }
  }

  // Text-key handler for keys PanelKeyCatcher forwards (digits, c, r, ? and
  // the uppercase Shift+h/l arriving on the slider section only).
  function handleTextKey(t) {
    if (t === "r") { root.refresh(); return }
    if (t === "c") { root.cycle(); return }
    if (t === "?") { root.helpOpen = !root.helpOpen; return }
    if (t === "H") { if (root.focusSection === "slider") root.sliderStepKey(-5); return }
    if (t === "L") { if (root.focusSection === "slider") root.sliderStepKey(5); return }
    var digit = "123456".indexOf(t)
    if (digit >= 0 && digit < root.presetList.length) root.applyPreset(root.presetList[digit].id)
  }

  // ------------------------------------------------------------ IPC (8 methods)
  IpcHandler {
    target: "omafan"

    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }

    function preset(name: string): string {
      var preset = Model.presetById(root.presetList, String(name))
      if (!preset) return "error: unknown preset: " + String(name)
      root.applyPreset(preset.id)
      return preset.rpm === null
        ? "ok: " + preset.label
        : "ok: " + preset.label + " " + Model.formatRpm(preset.rpm)
    }

    function rpm(value: string): string {
      var n = Number(value)
      if (!isFinite(n)) return "error: not an integer rpm: " + String(value)
      var next = Model.snapRpm(n, root.fanMinRpm, root.fanMaxRpm, root.sliderStepRpm)
      root.sendCommand(["rpm", String(next)])
      return "ok: " + Model.formatRpm(next)
    }

    function release(): string {
      root.sendCommand(["release"])
      return "ok: firmware auto"
    }

    function refresh(): void { root.refresh() }

    function state(): string {
      return root.rawStatusText !== "" ? root.rawStatusText : ""
    }
  }

  // ------------------------------------------------------------- processes
  // T5: the settings-write Process (panel refresh row). Runs `omarchy bar
  // set` — a plain session command, no pkexec — through the same IPC-backed
  // write path the bar-settings UI uses. Success reports only through the
  // shell pushing the new settings into the widgets (pollSeconds re-evaluates
  // live); failure surfaces in the refresh row's own error line.
  Process {
    id: settingsProc
    // The shell Process inherits the compositor session's PATH, where
    // `omarchy` always lives; no pinning needed and none invented.
    property string omarchyBin: "omarchy"
    property string cmdErr: ""
    property bool timedOut: false

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: settingsProc.cmdErr = String(text || "")
    }

    onExited: function(code) {
      root.settingsBusy = false
      if (code !== 0 && !settingsProc.timedOut) {
        var fix = settingsProc.cmdErr.trim().split("\n")[0]
        root.settingsError = "Could not save the refresh setting." +
          (fix !== "" ? " " + fix : "") +
          " Fix: set poll_mode / poll_seconds in the bar layout editor instead"
      } else if (code === 0) {
        root.settingsError = ""
      }
    }
  }

  Timer {
    id: settingsDeadline
    interval: root.commandDeadlineMs
    // Same never-frozen guarantee as the fan-write deadline: a hanging
    // settings write releases the lock and names the symptom.
    onTriggered: {
      if (!settingsProc.running) return
      settingsProc.timedOut = true
      settingsProc.running = false // kills the process
      root.settingsBusy = false
      root.settingsError = "omarchy bar set did not answer within 20 s — the refresh setting was not saved; try again"
    }
  }

  // --------------------------------------------------------------- processes
  // T09c D1: (20 s) — the panel must never be frozen by a runner that never
  // answers (e.g. an unanswered polkit password prompt). All three deadlines
  // are started whenever their process is started.
  readonly property int commandDeadlineMs: 20000
  readonly property string commandTimeoutMessage: "omafan-ctl did not answer within 20 s — a polkit password prompt may be waiting (run `omafan-ctl doctor`); the fan's last verified state is shown below"
  readonly property string statusTimeoutMessage: "omafan-ctl status did not answer within 20 s — the panel is showing the last state it received. Fix: run `omafan-ctl doctor`, then `systemctl restart afanctl`"

  Process {
    id: statusProc
    property bool timedOut: false
    command: root.statusArgv
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: cmdProc
    property string cmdOut: ""
    property string cmdErr: ""
    property bool timedOut: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cmdProc.cmdOut = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: cmdProc.cmdErr = String(text || "")
    }

    // Every write is followed by a status re-read (DESIGN.md 5 / F5): the UI
    // renders what the daemon reports, never what it was asked for.
    // StdioCollector with waitForEnd completes before the exit handler runs,
    // so both captures above are final here.
    onExited: function(code) {
      root.busy = false
      if (code !== 0 && !cmdProc.timedOut) {
        // A dead runner killed at its deadline already has the better message;
        // never overwrite it with the generic failure line (T09c D2: the kill
        // is also never rendered as success — no text here claims a write).
        var fix = cmdProc.cmdErr.trim().split("\n")[0]
        root.lastError = "omafan-ctl failed." + (fix !== "" ? " " + fix : "") +
          " Fix: run bin/omafan-ctl doctor"
        // T2: a failed release voids the Auto expectation but keeps the
        // truthful prior pendingRpm. Success clears nothing here — only a
        // fresh status reporting hold inactive confirms Auto (applyStatus).
        if (root.lastWriteWasRelease) root.expectingAuto = false
      }
      root.lastWriteWasRelease = false
      Qt.callLater(root.refresh)
    }
  }

  Timer {
    id: commandDeadline
    interval: root.commandDeadlineMs
    // T09c D1: a never-answering write must not hold `busy` forever. Kill it,
    // release the lock, name the symptom and the fix; the kill's own onExited
    // (nonzero, timedOut) deliberately keeps this message.
    onTriggered: {
      if (!cmdProc.running) return
      cmdProc.timedOut = true
      cmdProc.running = false // kills the process
      root.busy = false
      root.pendingRpm = null
      // T2: a killed release never confirmed Auto; void the expectation so the
      // next fresh hold status can resync the truthful target (the null above
      // already renders base/min until then).
      if (root.lastWriteWasRelease) root.expectingAuto = false
      root.lastWriteWasRelease = false
      root.lastError = root.commandTimeoutMessage
    }
  }

  Timer {
    id: statusDeadline
    interval: root.commandDeadlineMs
    // T09c D3: a never-answering status poll keeps the previous document but
    // marks it stale; the poll timer itself never stops, so the panel recovers
    // on its own when omafan-ctl answers again.
    onTriggered: {
      if (!statusProc.running) return
      statusProc.timedOut = true
      statusProc.running = false // kills the process
      root.statusStale = true
      root.lastError = root.statusTimeoutMessage
    }
  }

  // ---------------------------------------------------------------- timers
  // Polling starts on load, not on open (ticket T09): the bar widget reads the
  // panel's status while the panel is invisible.
  Timer {
    id: pollTimer
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    onTriggered: {
      // D4: one full (per-sensor) document every tenth poll; the 2 s fast
      // cadence is kept for the hero/footer values.
      root.pollCount++
      if (root.pollCount % 10 === 0) root.fullPending = true
      root.refresh()
    }
  }

  Timer {
    id: sliderSend
    interval: 300 // F5: slider writes are debounced by ~300 ms
    onTriggered: root.sendCommand(["rpm", String(Math.round(Number(root.pendingRpm)))])
  }

  Timer {
    id: armedExpire
    interval: 10000 // 5.1: the confirmation self-disarms after 10 s
    onTriggered: root.armedPresetId = ""
  }

  Timer {
    id: releaseTimer
    // REVIEW-R2 R2-2: one-shot, started/stopped only from applyStatus (rising
    // edge) and sendCommand (user interaction). The interval is clamped to at
    // least a minute so a mis-set 0 can never fire an immediate release.
    repeat: false
    interval: root.releaseAfterMinutes > 0
      ? Math.max(60000, root.releaseAfterMinutes * 60000)
      : 0
    onTriggered: {
      root.holdSeen = false
      if (root.holdActive) root.sendCommand(["release"])
    }
  }

  // ------------------------------------------------------------- lifecycle
  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (!opened) return
    root.lastError = ""
    root.helpOpen = false
    root.armedPresetId = ""
    root.focusSection = "presets"
    root.selectedIndex = 0
    root.cursorActive = false
    // D4: sensors are fetched when the panel opens, not only on the tenth poll.
    root.fullPending = true
    root.refresh()
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  // ------------------------------------------------------------ keyboard UI
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveSection(dy); return }
        if (dx === 0) return
        if (root.focusSection === "presets") root.moveCursorH(dx)
        else if (root.focusSection === "slider") root.sliderStepKey(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        // Esc closes the help overlay before the panel (DESIGN.md 6.3).
        if (root.helpOpen) { root.helpOpen = false; return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height
          ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // ---------- hero: glyph, temperature, fan rpm, mode ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              // Nerd Font md-fan (U+F0210) — the same glyph the bar widget uses.
              text: "\udb80\ude10"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: root.headerText()
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.statusDoc === null
                  ? "OFFLINE" : Model.statusLabel(root.statusDoc).toUpperCase()
                color: root.modeTone === "degraded" || root.modeTone === "offline"
                  ? Color.urgent
                  : root.modeTone === "hold" ? Color.accent
                  : Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }

              // T09c D3: the stale badge — old numbers are rendered, never
              // silently passed off as live.
              Text {
                visible: root.statusStale
                textFormat: Text.PlainText
                text: "STATUS STALE — showing the last state omafan-ctl answered with"
                color: Color.urgent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- banner ----------
          Rectangle {
            visible: root.bannerText !== ""
            width: parent.width
            implicitHeight: bannerLabel.implicitHeight + Style.space(12)
            radius: 6
            color: Color.urgent
            opacity: 0.18

            Text {
              id: bannerLabel
              textFormat: Text.PlainText
              // Daemon and CLI strings render verbatim; never as markup.
              text: root.bannerText
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              width: parent.width - Style.space(16)
              x: Style.space(8)
              y: Style.space(6)
            }
          }

          // ---------- presets ----------
          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "PRESETS"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Grid {
              id: presetRow
              width: parent.width
              columns: Math.min(3, Math.max(1, root.presetList.length))
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.presetList

                PresetChip {
                  required property var modelData
                  required property int index

                  presetData: modelData
                  chipIndex: index
                  width: presetRow.cellWidth
                }
              }
            }

            // The legend (DESIGN.md 3): presets are floors, never quieter
            // modes; Floor is the hardware floor, not a stopped fan.
            Text {
              textFormat: Text.PlainText
              text: "Preset rpms are floors, not quieter-than-firmware modes. " +
                    "'Floor' stops at the hardware floor; only Auto returns the fan to firmware."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              opacity: 0.8
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              width: parent.width
            }
          }

          // ---------- slider ----------
          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(sliderHeader.implicitHeight, sliderValue.implicitHeight)

              PanelSectionHeader {
                id: sliderHeader
                text: "RPM"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: sliderValue
                textFormat: Text.PlainText
                text: root.pendingRpm === null || root.pendingRpm === undefined
                  ? "—" : Model.formatRpm(root.pendingRpm)
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: sliderRow
              width: parent.width
              height: rpmSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "slider" && root.selectedIndex === -1
              foreground: root.barForeground
              outline: true

              PanelSlider {
                id: rpmSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: root.fanMinRpm
                maximum: root.fanMaxRpm
                step: root.sliderStepRpm
                integer: true
                value: root.pendingRpm !== null && root.pendingRpm !== undefined
                  ? Number(root.pendingRpm) : root.fanMinRpm
                onMoved: function(v) {
                  root.setPendingRpmQuiet(Model.snapRpm(v, root.fanMinRpm, root.fanMaxRpm, root.sliderStepRpm))
                }
                onReleased: function(v) {
                  root.setPendingRpm(Model.snapRpm(v, root.fanMinRpm, root.fanMaxRpm, root.sliderStepRpm))
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "slider"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- refresh ----------
          // Mouse-only control (T5): it sits OUTSIDE the keyboard cursor
          // sections, whose two-section contract DESIGN.md 6.2 freezes. The
          // chips and stepper write through setPollMode/stepPollSeconds.
          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(refreshHeader.implicitHeight, refreshValue.implicitHeight)

              PanelSectionHeader {
                id: refreshHeader
                text: "REFRESH"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: refreshValue
                textFormat: Text.PlainText
                // The effective cadence: mode auto is exactly 2 s regardless
                // of any stored poll_seconds (Model.effectivePollSeconds).
                text: root.pollSeconds + " s · " + (root.pollMode === "custom" ? "custom" : "auto")
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              spacing: Style.spacing.xs

              RefreshChip {
                label: "Auto"
                isActive: root.pollMode !== "custom"
                enabled: !root.settingsBusy
                onActivated: root.setPollMode("auto")
              }

              RefreshChip {
                label: "Custom"
                isActive: root.pollMode === "custom"
                enabled: !root.settingsBusy
                onActivated: root.setPollMode("custom")
              }

              // Stepper, meaningful only in custom mode: auto is pinned to 2 s.
              Row {
                visible: root.pollMode === "custom"
                spacing: Style.spacing.xs

                RefreshChip {
                  label: "−"
                  enabled: !root.settingsBusy
                  onActivated: root.stepPollSeconds(-1)
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.pollSeconds + " s"
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                RefreshChip {
                  label: "+"
                  enabled: !root.settingsBusy
                  onActivated: root.stepPollSeconds(1)
                }
              }
            }

            Text {
              visible: root.settingsError !== ""
              textFormat: Text.PlainText
              text: root.settingsError
              color: Color.urgent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "How often omafan re-reads the daemon's status — the daemon still samples the sensors itself."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              opacity: 0.8
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              width: parent.width
            }
          }

          // ---------- footer ----------
          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              text: root.footerText()
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }

            // D4: the per-sensor rows a --full document provides (the 2 s fast
            // path carries none, so nothing is invented in between). Each row
            // is daemon data rendered verbatim as plain text.
            Repeater {
              model: root.sensorRows

              Text {
                required property var modelData
                textFormat: Text.PlainText
                text: modelData.label + " " + modelData.temp
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Repeater {
              model: root.recentErrorLines

              Text {
                required property string modelData
                textFormat: Text.PlainText
                text: "Recent error: " + modelData
                color: Color.urgent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                width: parent.width
              }
            }
          }
        }
      }

      // The "?" key-map overlay (T08), covering the card; the panel owns ?/Esc.
      KeyboardHelp {
        anchors.fill: parent
        open: root.helpOpen
        foreground: root.barForeground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onCloseRequested: root.helpOpen = false
      }
    }
  }

  // ---------------------------------------------------------- sub-components
  // T5: a mode/stepper chip for the mouse-only refresh row. Same visual
  // language as PresetChip (CursorSurface-style fills) but plain Rectangle +
  // MouseArea because it is not part of the keyboard cursor model.
  component RefreshChip: Rectangle {
    id: refreshChipRoot
    required property string label
    property bool isActive: false
    signal activated()

    width: refreshChipLabel.implicitWidth + Style.space(18)
    height: refreshChipLabel.implicitHeight + Style.space(8)
    radius: 6
    color: refreshChipRoot.isActive
      ? Style.selectedFillFor(root.barForeground, Color.accent)
      : Style.hoverFillFor(root.barForeground, Color.accent)

    Text {
      id: refreshChipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: refreshChipRoot.label
      color: root.barForeground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: refreshChipRoot.activated()
    }
  }

  component PresetChip: CursorSurface {
    id: chip
    required property var presetData
    required property int chipIndex

    readonly property string presetId: chip.presetData && chip.presetData.id
      ? String(chip.presetData.id) : ""

    hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === chip.chipIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(chip)
    current: root.holdActive && root.holdDoc ? root.holdDoc.preset === chip.presetId : false
    foreground: root.barForeground
    fill: Style.hoverFillFor(root.barForeground, Color.accent)
    currentFill: Style.selectedFillFor(root.barForeground, Color.accent)
    implicitHeight: chipInner.implicitHeight + Style.spacing.sm
    opacity: root.writesRefused ? 0.45 : 1.0

    Column {
      id: chipInner
      anchors.centerIn: parent
      width: parent.width
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        // D3: the full "Off (hardware floor)" label overflows the chip's third
        // of the content width and renders truncated on screen; the short form
        // is honest because the floors footnote carries the full wording.
        text: chip.presetId === "off" ? "Floor" : (chip.presetData ? (chip.presetData.label || chip.presetId) : "—")
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: chip.presetData && chip.presetData.rpm !== null && chip.presetData.rpm !== undefined
          ? Model.formatRpm(chip.presetData.rpm) : (chip.presetId === "auto" ? "release" : "—")
        color: Qt.darker(root.barForeground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        width: parent.width
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "presets"
        root.selectedIndex = chip.chipIndex
      }
      onClicked: if (chip.presetId !== "") root.applyPreset(chip.presetId)
    }
  }
}
