import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Item {
  id: stepper

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string label: ""
  property string valueText: ""
  property bool canLower: true
  property bool canRaise: true

  signal lower()
  signal raise()

  implicitHeight: Math.max(Style.space(24), stepperLabel.implicitHeight)

  Text {
    id: stepperLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: stepper.label
    color: panel.foreground
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    TileButton {
      panel: stepper.panel
      anchors.verticalCenter: parent.verticalCenter
      glyph: "−"
      canTap: stepper.canLower
      onActivated: stepper.lower()
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: stepper.valueText
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    TileButton {
      panel: stepper.panel
      anchors.verticalCenter: parent.verticalCenter
      glyph: "+"
      canTap: stepper.canRaise
      onActivated: stepper.raise()
    }
  }
}
