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
  readonly property color fill: panel.pluggedIn ? Color.accent : panel.batteryColor(level)

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

        clip: true
        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // A light runs through it while it's taking a charge.
        Rectangle {
          id: chargeSheen
          visible: panel.pluggedIn && pill.level < 1
          property real k: 0
          width: parent.width * 0.6 + 4
          height: parent.height
          x: -width + (parent.width + width) * k
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
            GradientStop { position: 0.5; color: Util.alpha("#ffffff", 0.6) }
            GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0) }
          }
          NumberAnimation on k {
            running: chargeSheen.visible && panel.opened
            loops: Animation.Infinite
            from: 0
            to: 1
            duration: 1400
            easing.type: Easing.InOutQuad
          }
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
