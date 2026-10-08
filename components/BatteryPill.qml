import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Mini battery: a body that fills to the charge, a nub, and the label.
Row {
  id: pill

  // The QuickPuff panel: palette, state and actions.
  property var panel

  readonly property real level: Math.max(0, Math.min(1, Number(panel.statusData.battery) / 100 || 0))
  readonly property color fill: level <= 0.15 && !panel.pluggedIn ? panel.urgent
    : panel.pluggedIn ? Color.accent
    : Util.alpha(panel.foreground, 0.85)

  spacing: Style.space(5)

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Rectangle {
      width: Style.space(22)
      height: Style.space(11)
      radius: Math.min(3, Style.space(3))
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(panel.foreground, 0.55)

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 2
        width: Math.max(0, (parent.width - 4) * pill.level)
        radius: 1
        color: pill.fill

        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // Shimmers while it's taking a charge.
        SequentialAnimation on opacity {
          running: panel.pluggedIn && pill.level < 1 && panel.opened
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
        }
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 2
      height: Style.space(5)
      radius: 1
      color: Util.alpha(panel.foreground, 0.55)
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: panel.batteryLabel
    color: pill.level <= 0.15 && !panel.pluggedIn ? panel.urgent : panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }
}
