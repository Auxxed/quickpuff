import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Item {
  id: info

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string label: ""
  property string value: ""

  visible: value !== ""
  implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

  // As the row comes into view its value decodes: the characters flicker
  // through random ones and lock in from the left, like a readout finding
  // its signal. Rows further down start a beat later.
  property bool decoding: false
  property string scrambled: ""
  property int locked: 0
  readonly property string glyphs: "0123456789ABCDEFHKMNPRSTXZ#%&*+=<>"
  function scramble() {
    var out = ""
    for (var i = 0; i < value.length; i++) {
      var c = value.charAt(i)
      out += i < locked || " ·().,:-/~%".indexOf(c) >= 0 ? c : glyphs.charAt(Math.floor(Math.random() * glyphs.length))
    }
    scrambled = out
  }
  function decode() {
    decodeTimer.stop()
    var now = Date.now()
    if (!panel || panel.calm || value === "" || (now - panel.lastDecodeAt > 1500 && now - panel.lastDecodeAt < panel.introGapMs)) {
      decoding = false
      decodeDelay.stop()
      return
    }
    // The first row to decode opens the window; the rest join it.
    if (now - panel.lastDecodeAt >= panel.introGapMs) panel.lastDecodeAt = now
    locked = 0
    scramble()
    decoding = true
    decodeDelay.interval = 120 + Math.min(10, Math.round(y / Math.max(1, height))) * 28
    decodeDelay.restart()
  }
  onVisibleChanged: if (visible && panel && panel.opened) decode()
  Connections {
    target: info.panel
    function onOpenSerialChanged() { if (info.visible) info.decode() }
  }
  Timer { id: decodeDelay; onTriggered: decodeTimer.restart() }
  Timer {
    id: decodeTimer
    interval: 34
    repeat: true
    onTriggered: {
      info.locked += Math.max(1, Math.ceil(info.value.length / 12))
      if (info.locked >= info.value.length) { stop(); info.decoding = false; return }
      info.scramble()
    }
  }

  Text {
    id: infoLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: info.label
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: infoValue
    anchors.left: infoLabel.right
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: info.decoding ? info.scrambled : info.value
    color: info.decoding ? Qt.tint(panel.foreground, Util.alpha(Color.accent, 0.55)) : panel.foreground
    Behavior on color { ColorAnimation { duration: 240 } }
    // Values in the display face, a touch larger than the label.
    font.family: panel.displayFamily
    font.pixelSize: Math.round(Style.font.bodySmall * panel.displayScale)
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }
}
