import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// One fault: category glyph, what happened, and when.
BorderSurface {
  id: faultCard

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property var fault: ({})

  radius: Style.cornerRadius
  color: Style.normalFillFor(Color.urgent, Color.urgent)
  borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)
  implicitHeight: cardRow.implicitHeight + Style.spacing.controlPaddingY * 2

  Item {
    id: cardRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    implicitHeight: Math.max(cardGlyph.implicitHeight, cardText.implicitHeight)

    Text {
      id: cardGlyph
      width: Style.space(20)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: panel.faultGlyph(Number(faultCard.fault.code))
      color: Color.urgent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.iconSmall
    }

    Column {
      id: cardText
      anchors.left: cardGlyph.right
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(faultCard.fault.label || "")
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: panel.formatFaultTime(faultCard.fault.ts)
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
