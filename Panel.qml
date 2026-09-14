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
  property bool busy: false
  property var pendingRpm: null
  // T09c D3: true when a status poll failed or was killed at its deadline —
  // the previous document stays rendered but is visibly marked as stale.
  property string focusSection: "presets"   // "presets" | "slider" (DESIGN.md 6.2)
  property int selectedIndex: 0             // slider uses the -1 sentinel
  property bool cursorActive: false
  property bool helpOpen: false

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

  // From inline shell.json (base Panel.setting()). Defaults mirror manifest.json.
  readonly property int pollSeconds: Math.min(10, Math.max(1, Math.round(Number(root.setting("poll_seconds", 2)) || 2)))
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
    cmdProc.command = root.withGlobalFlags([root.ctlPath].concat(args))
    cmdProc.running = true
    commandDeadline.restart()
  }

  // The undercooling confirmation (DESIGN.md 5.1): a hot-machine preset below
  // the current fan speed is sent only when the same preset is requested again
  // within 10 s. The second attempt carries --force because the panel has
  // confirmed deliberately — it is not a silent override.
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
      root.sendCommand(["preset", id, "--force"])
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
      // Track the daemon's own target while a hold is on — the footer renders
      // that truth, so the knob must not lag behind it. Never while the user
      // is mid-drag or a debounced write is about to land.
      if (!sliderSend.running && !rpmSlider.dragging && root.holdActive && root.holdDoc
          && root.holdDoc.rpm !== null && root.holdDoc.rpm !== undefined) {
        root.pendingRpm = root.holdDoc.rpm
      }
      // release_after_minutes: restart whenever a poll discovers a hold and
      // the setting is non-zero (DESIGN.md 8).
      if (root.releaseAfterMinutes > 0 && root.holdActive) releaseTimer.restart()
      else releaseTimer.stop()
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

  // --------------------------------------------------------------- processes
  // T09c D1: (20 s) — the panel must never be frozen by a runner that never
  // answers (e.g. an unanswered polkit password prompt). Both deadlines are
  // started whenever their process is started.
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
      }
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
    readonly property int minuteMs: root.releaseAfterMinutes > 0 ? root.releaseAfterMinutes * 60000 : 0
    interval: minuteMs
    running: minuteMs > 0
    repeat: false
    onTriggered: root.sendCommand(["release"])
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
            // modes; Off is the hardware floor, not a stopped fan.
            Text {
              textFormat: Text.PlainText
              text: "Preset rpms are floors, not quieter-than-firmware modes. " +
                    "'Off' stops at the hardware floor; only Auto returns the fan to firmware."
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
        text: chip.presetId === "off" ? "Off (floor)" : (chip.presetData ? (chip.presetData.label || chip.presetId) : "—")
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
