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
    onToggled: switchRow.toggled()
  }
}
