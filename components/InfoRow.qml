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
    text: info.value
    color: panel.foreground
    // Values in the display face, a touch larger than the label.
    font.family: panel.displayFamily
    font.pixelSize: Math.round(Style.font.bodySmall * panel.displayScale)
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }
}
