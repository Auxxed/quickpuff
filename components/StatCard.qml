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
  property color glyphColor: tint
  // Accent for the glyph and wash: the active profile's colour.
  property color tint: panel.profileTint
  // Lifts the card with the profile cards' wash; keep it for the one
  // card on a row that has something to celebrate.
  property bool highlight: false
  default property alias extra: extraSlot.data

  radius: Style.cornerRadius
  color: highlight ? Util.alpha(tint, 0.06) : Style.normalFillFor(panel.foreground, Color.accent)
  borderSpec: highlight
    ? Border.flat(Util.alpha(tint, 0.6), Math.max(1, Style.normalBorderWidth))
    : Border.controlSpec("normal", panel.foreground, Color.accent)
  implicitHeight: metricCol.implicitHeight + Style.spacing.controlPaddingY * 2

  Rectangle {
    visible: metric.highlight
    anchors.fill: parent
    anchors.margins: Math.max(1, Style.normalBorderWidth)
    radius: Math.max(0, metric.radius - anchors.margins)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha(metric.tint, 0.12) }
      GradientStop { position: 1.0; color: Util.alpha(Qt.darker(metric.tint, 1.6), 0) }
    }
  }

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
      font.family: panel.displayFamily
      font.pixelSize: Math.round(Style.font.title * panel.displayScale)
      font.weight: Font.DemiBold
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
