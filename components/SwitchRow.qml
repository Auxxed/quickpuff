import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Item {
  id: switchRow

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string label: ""
  property bool checked: false

  signal toggled()

  implicitHeight: Math.max(switchLabel.implicitHeight, switchControl.implicitHeight)

  Text {
    id: switchLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: switchRow.label
    color: panel.foreground
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  ToggleSwitch {
    id: switchControl
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: switchRow.checked
    cursorRing: false
    foreground: panel.foreground
    onToggled: {
      if (!switchRow.checked && !panel.calm) switchSparks.restart()
      switchRow.toggled()
    }
  }

  // Turning on throws a ring of sparks off the knob's new place, and a
  // flash of glow round it.
  property real sparkT: 0
  NumberAnimation { id: switchSparks; target: switchRow; property: "sparkT"; from: 0; to: 1; duration: 560; easing.type: Easing.OutCubic }
  Item {
    x: switchControl.x + switchControl.width - switchControl.height / 2
    y: switchControl.y + switchControl.height / 2
    visible: switchSparks.running

    Rectangle {
      width: switchControl.height * (1 + 1.3 * switchRow.sparkT)
      height: width
      radius: width / 2
      x: -width / 2
      y: -height / 2
      color: "transparent"
      border.width: Math.max(1, Style.space(1.5))
      border.color: Util.alpha(Color.accent, 0.8 * (1 - switchRow.sparkT))
    }
    Repeater {
      model: 8
      Rectangle {
        required property int index
        readonly property real ang: index / 8 * Math.PI * 2 + 0.3
        readonly property real reach: switchControl.height * (0.5 + 0.9 * switchRow.sparkT)
        width: Style.space(index % 2 ? 3 : 4)
        height: width
        radius: width / 2
        x: Math.cos(ang) * reach - width / 2
        y: Math.sin(ang) * reach - height / 2
        color: index % 3 === 0 ? "#ffffff" : Qt.lighter(Color.accent, 1.3)
        opacity: 1 - switchRow.sparkT
      }
    }
  }
}
