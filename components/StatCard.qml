import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Compact metric tile: title, big value, caption, optional extra
// (weekday dots, hour histogram).
BorderSurface {
  id: metric

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string title: ""
  property string value: ""
  property string meta: ""
  property string glyph: ""
  property color glyphColor: Color.accent
  default property alias extra: extraSlot.data

  radius: Style.cornerRadius
  color: Style.normalFillFor(panel.foreground, Color.accent)
  borderSpec: Border.controlSpec("normal", panel.foreground, Color.accent)
  implicitHeight: metricCol.implicitHeight + Style.spacing.controlPaddingY * 2

  Column {
    id: metricCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.topMargin: Style.spacing.controlPaddingY
    spacing: Style.space(4)

    Row {
      spacing: Style.space(5)

      Text {
        visible: metric.glyph !== ""
        textFormat: Text.PlainText
        text: metric.glyph
        color: metric.glyphColor
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        textFormat: Text.PlainText
        text: metric.title
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      textFormat: Text.PlainText
      text: metric.value
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      visible: metric.meta !== ""
      textFormat: Text.PlainText
      text: metric.meta
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      width: parent.width
    }
    Column {
      id: extraSlot
      width: parent.width
      spacing: Style.space(6)
    }
  }
}
