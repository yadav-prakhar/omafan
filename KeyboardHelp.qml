import QtQuick
import qs.Commons

// Keyboard help overlay — rendered as a two-column table of key/action pairs.
// The Panel owns `?` and `Esc` handling; this item never steals keys.
Item {
  id: root

  property bool open: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal closeRequested()

  visible: open
  anchors.fill: parent

  // Key map rows — JS literal evaluated once. Each entry is [key, action].
  // Must match DESIGN.md §6.3 one-for-one.
  readonly property var rows: [
    ["j / ↓", "cursor down (section)"],
    ["k / ↑", "cursor up (section)"],
    ["h / ←", "presets: previous · slider: −1 step"],
    ["l / →", "presets: next · slider: +1 step"],
    ["Shift+h/l", "slider: ±500 rpm"],
    ["Enter / Space", "apply focused preset or slider value"],
    ["1 … 6", "apply auto, off, low, med, high, full"],
    ["c", "cycle presets forward"],
    ["r", "refresh status now"],
    ["?", "toggle this key map"],
    ["Esc", "close help, or close panel"],
    ["Tab", "switch to next/previous bar panel"]
  ]

  // Semi-transparent backdrop so the panel content is readable.
  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: 0.45
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(4)

    // Header
    Text {
      text: "Keyboard shortcuts"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      renderType: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Repeater {
      model: root.rows

      Row {
        spacing: Style.space(16)

        Text {
          text: modelData[0]
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          renderType: Text.PlainText
          width: Style.space(140)
          horizontalAlignment: Text.AlignRight
        }

        Text {
          text: modelData[1]
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.PlainText
          opacity: 0.85
        }
      }
    }

    // Hint at the bottom
    Text {
      text: "Press ? or Esc to close"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.PlainText
      opacity: 0.5
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
}
