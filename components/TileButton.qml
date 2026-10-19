import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Borderless nudge/rename target that only resolves into a control under
// the cursor, so the profile grid reads as four tiles, not a dozen buttons.
Item {
  id: tap

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string glyph: ""
  property bool canTap: true
  // When set, the button only paints once the row it belongs to is hovered.
  property var tooltipHot: undefined

  signal activated()

  readonly property bool hovered: tapMouse.containsMouse
  readonly property bool hot: canTap && hovered
  readonly property bool revealed: tooltipHot === undefined || tooltipHot === true

  implicitWidth: Style.space(18)
  implicitHeight: Style.space(18)
  opacity: (canTap ? 1 : 0.35) * (revealed ? 1 : 0)

  Behavior on opacity { NumberAnimation { duration: 120 } }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: tap.hot ? Style.hoverFillFor(panel.foreground, Color.accent) : "transparent"

    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: tap.glyph
    color: tap.hot ? Color.accent : panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // A press pops it and sends a ring of light out from it.
  property real popT: 1
  NumberAnimation { id: popAnim; target: tap; property: "popT"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
  scale: tapMouse.pressed ? 0.9 : 1
  Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Rectangle {
    anchors.centerIn: parent
    width: parent.width * (1 + 0.9 * tap.popT)
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, Style.space(1.5))
    border.color: Util.alpha(Color.accent, 0.7 * (1 - tap.popT))
    visible: tap.popT < 1
  }

  MouseArea {
    id: tapMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: tap.canTap ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (tap.canTap) { if (!panel.calm) popAnim.restart(); tap.activated() }
  }
}
