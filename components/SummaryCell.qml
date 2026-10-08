import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BorderSurface {
  id: cell

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string title: ""
  property string value: ""
  property string glyph: ""
  property bool highlight: false
  // Highlight colour: the active profile's, like the Control tab.
  property color tint: panel.profileTint
  // Optional colour bar along the bottom (the factory heat presets).
  property string stripe: ""

  // Plain counts tick up to their value; anything else shows as given.
  readonly property bool numeric: /^\d+$/.test(value)
  property real shown: numeric ? Number(value) : 0
  Behavior on shown { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

  radius: Style.cornerRadius
  color: highlight ? Util.alpha(tint, 0.06) : Style.normalFillFor(panel.foreground, Color.accent)
  borderSpec: highlight
    ? Border.flat(Util.alpha(tint, 0.7), Math.max(1, Style.normalBorderWidth))
    : Border.controlSpec("normal", panel.foreground, Color.accent)
  implicitHeight: cellCol.implicitHeight + Style.spacing.controlPaddingY * 2 + (stripe !== "" ? Style.space(3) : 0)

  // Highlighted cells get the profile cards' wash: tint at the head,
  // fading out toward the foot.
  Rectangle {
    visible: cell.highlight
    anchors.fill: parent
    anchors.margins: Math.max(1, Style.normalBorderWidth)
    radius: Math.max(0, cell.radius - anchors.margins)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha(cell.tint, 0.12) }
      GradientStop { position: 1.0; color: Util.alpha(Qt.darker(cell.tint, 1.6), 0) }
    }
  }

  Column {
    id: cellCol
    anchors.centerIn: parent
    spacing: Style.space(2)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: cell.glyph !== ""
      textFormat: Text.PlainText
      text: cell.glyph
      color: cell.highlight ? cell.tint : panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: cell.numeric ? String(Math.round(cell.shown)) : cell.value
      color: cell.highlight ? cell.tint : panel.foreground
      font.family: panel.displayFamily
      font.pixelSize: Math.round(Style.font.title * panel.displayScale)
      font.weight: Font.DemiBold
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: cell.title
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    visible: cell.stripe !== ""
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.max(1, Style.normalBorderWidth)
    height: Style.space(3)
    color: cell.stripe !== "" ? cell.stripe : "transparent"
  }
}
