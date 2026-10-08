import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Thin rounded progress bar with a gradient fill that eases to its value.
Rectangle {
  id: meter

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real value: 0
  property color fill: Color.accent
  property bool throb: false
  readonly property real clamped: isFinite(value) ? Math.max(0, Math.min(1, value)) : 0

  implicitHeight: Style.space(6)
  height: implicitHeight
  radius: height / 2
  color: Util.alpha(panel.foreground, 0.1)

  Rectangle {
    height: parent.height
    radius: parent.radius
    width: meter.clamped > 0 ? Math.max(parent.height, parent.width * meter.clamped) : 0
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Util.alpha(meter.fill, 0.45) }
      GradientStop { position: 1.0; color: meter.fill }
    }

    Behavior on width { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }

    SequentialAnimation on opacity {
      running: meter.throb && panel.opened
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }
  }
}
