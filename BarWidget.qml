import QtQuick
import qs.Ui
import "Model.js" as Model

// omafan bar entry point (DESIGN.md §6.1).
//
// This file is deliberately a thin surface: it paints the label and forwards
// every gesture to Panel.qml. It performs no I/O and spawns no child of its
// own, so the single integration point with afanctl stays inside the panel and
// the CLI, and a defect here cannot reach the fan or the filesystem.
BarWidget {
  id: root
  moduleName: "io.github.yadav-prakhar.omafan"

  // The panel owns polling, so the widget reads the panel's parsed state rather
  // than holding a second copy that could disagree with what the panel shows.
  // Both shapes are accepted because `status` is written by another file: the
  // raw omafan.status.v1 document, or Model.parseStatus()'s {ok,status}
  // wrapper. Normalising here keeps this widget correct either way.
  readonly property var panelStatus: root.panelItem ? root.panelItem.status : null
  readonly property var statusDoc: {
    var value = root.panelStatus
    if (value && value.status && value.status.schema === "omafan.status.v1") return value.status
    return value
  }

  readonly property var fanRpm: root.statusDoc && root.statusDoc.fan
    ? root.statusDoc.fan.rpm
    : null
  readonly property var cpuTemp: root.statusDoc && root.statusDoc.thermal
    ? root.statusDoc.thermal.t_eff_c
    : null

  // A value the daemon did not report must never be shown as a number; the
  // label then falls back to the glyph instead of claiming "0 rpm".
  readonly property bool hasRpm: root.isUsable(root.fanRpm)
  readonly property bool hasTemp: root.isUsable(root.cpuTemp)

  // Tinted whenever a hold is active, so a forgotten manual setting is visible
  // at a glance (DESIGN.md §6.1, PRD F1).
  readonly property bool holdActive: root.statusDoc && root.statusDoc.hold
    ? root.statusDoc.hold.active === true
    : false

  // Nerd Font md-fan (U+F0210): the bar family resolves through fontconfig to a
  // Nerd Font and the shell already paints its own icons from this range.
  readonly property string fanGlyph: "\udb80\ude10"

  readonly property string showMode: String(root.setting("show", "temp"))

  // Vertical bars fall back to the glyph, matching the shell's own text widgets.
  readonly property string barText: {
    if (root.vertical) return root.fanGlyph
    var mode = root.showMode
    if (mode === "icon") return root.fanGlyph
    if (mode === "rpm") return root.hasRpm ? Model.formatRpm(root.fanRpm) : root.fanGlyph
    if (mode === "temp+rpm") {
      if (root.hasTemp && root.hasRpm)
        return Model.formatTemp(root.cpuTemp) + " · " + Model.formatRpm(root.fanRpm)
      if (root.hasTemp) return Model.formatTemp(root.cpuTemp)
      if (root.hasRpm) return Model.formatRpm(root.fanRpm)
      return root.fanGlyph
    }
    // Unknown enum values degrade to the documented default (temp).
    return root.hasTemp ? Model.formatTemp(root.cpuTemp) : root.fanGlyph
  }

  readonly property string tooltip: root.statusDoc
    ? "Fan " + Model.formatRpm(root.fanRpm) + " · CPU " + Model.formatTemp(root.cpuTemp) +
      " · " + Model.modeTone(root.statusDoc)
    : "Fan control"

  readonly property bool opened: root.panelItem ? root.panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: root.panelItem
    ? root.panelItem.popoutSwitchClosing === true
    : false

  property var panelItem: null

  function isUsable(value) {
    if (value === null || value === undefined || value === "") return false
    return isFinite(Number(value))
  }

  function open() { if (root.panelItem) root.panelItem.open() }
  function close() { if (root.panelItem) root.panelItem.close() }
  function togglePanel() { if (root.panelItem) root.panelItem.toggle() }
  function closeForPopoutSwitch() { if (root.panelItem) root.panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    panelItem = target
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Ask the panel to apply something: the panel owns the locking, the debounce,
  // the error banners and the CLI path, so this widget never builds a command
  // itself (DESIGN.md §6.1). `args` are the omafan-ctl arguments after the
  // program name, the same list the panel's own writes pass.
  function applyToPanel(args) {
    var panel = root.panelItem
    if (!panel || typeof panel.sendCommand !== "function") return
    panel.sendCommand(args)
  }

  function releaseToAuto() { root.applyToPanel(["release"]) }

  // Wheel holds ±100 rpm from the current target, or from Medium when nothing
  // is held (DESIGN.md §6.1); the panel clamps and confirms against the daemon.
  function wheelStep(delta) {
    if (!delta) return
    var doc = root.statusDoc
    var hardware = doc && doc.hardware ? doc.hardware : null
    if (!hardware) return
    var lo = hardware.fan_min_rpm
    var hi = hardware.fan_max_rpm
    var base = null
    if (root.holdActive && doc.hold && doc.hold.rpm !== null && doc.hold.rpm !== undefined)
      base = doc.hold.rpm
    if (base === null) base = Model.presetRpm("med", lo, hi)
    if (base === null || base === undefined) return
    var next = Model.snapRpm(base + (delta > 0 ? 100 : -100), lo, hi, 100)
    root.applyToPanel(["rpm", String(next)])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // WidgetButton paints its label with Text.PlainText, and the bar's tooltip
  // does the same with tooltipText, so every string below is rendered verbatim
  // rather than interpreted as markup.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    tooltipText: root.tooltip
    active: root.holdActive
    activeColor: "#5a995a"
    useActiveColor: true
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // A hold is the only state where "release" is meaningful; otherwise the
        // click opens the detail view.
        if (root.holdActive) root.releaseToAuto()
        else root.open()
      } else {
        root.togglePanel()
      }
    }
    onWheelMoved: function(delta) { root.wheelStep(delta) }
  }
}
