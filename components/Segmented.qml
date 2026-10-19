import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Equal-width, mutually exclusive choice row with a highlight pill that
// slides to the picked option. Options may carry a `glyph` (stacked over
// the label on the full-size bar, inline on a compact one) and a `badge`.
Item {
  id: seg

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property var options: []
  property string value: ""
  property bool compact: false

  signal picked(string value)

  readonly property int count: options.length
  readonly property real gap: compact ? Style.space(3) : Style.space(4)
  readonly property real cellWidth: count > 0 ? (width - gap * (count - 1)) / count : 0
  readonly property bool stacked: !compact && count > 0 && options[0].glyph !== undefined
  readonly property int selectedIndex: {
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === value) return i
    return -1
  }

  implicitHeight: stacked ? Style.space(42) : (compact ? Style.space(24) : Style.spacing.controlHeight)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.normalFillFor(panel.foreground, Color.accent)
    border.width: 1
    border.color: Util.alpha(panel.foreground, 0.12)
  }

  // The pill's two edges travel separately: the edge heading for the new
  // choice leads and the other catches up, so the pill stretches toward it
  // and settles in. Placed directly (no animation) on first show and when
  // the row is resized.
  property real pillLeft: 0
  property real pillRight: 0
  property bool pillGlides: false
  property bool pillToRight: true
  property int pillFrom: -1

  function placePill(glide) {
    if (selectedIndex < 0) return
    pillGlides = glide && pillFrom >= 0 && pillFrom !== selectedIndex && panel && panel.opened
    pillToRight = selectedIndex > pillFrom
    pillFrom = selectedIndex
    // From a local: with a Behavior on it, pillLeft still reads its old
    // value straight after being set.
    var left = selectedIndex * (cellWidth + gap)
    pillLeft = left
    pillRight = left + cellWidth
  }
  onSelectedIndexChanged: {
    placePill(true)
    if (panel && panel.opened && !panel.calm) landAnim.restart()
  }
  onCellWidthChanged: placePill(false)
  Component.onCompleted: placePill(false)

  Behavior on pillLeft {
    enabled: seg.pillGlides
    NumberAnimation { duration: seg.pillToRight ? 380 : 230; easing.type: Easing.OutCubic }
  }
  Behavior on pillRight {
    enabled: seg.pillGlides
    NumberAnimation { duration: seg.pillToRight ? 230 : 380; easing.type: Easing.OutCubic }
  }

  // A flash of light as the pill lands on its new choice.
  property real land: 0
  SequentialAnimation {
    id: landAnim
    PauseAnimation { duration: 170 }
    NumberAnimation { target: seg; property: "land"; from: 1; to: 0; duration: 650; easing.type: Easing.OutCubic }
  }

  Rectangle {
    visible: seg.selectedIndex >= 0
    x: seg.pillLeft
    width: Math.max(height * 0.6, seg.pillRight - seg.pillLeft)
    height: parent.height
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.2 + 0.12 * seg.land)
    border.width: 1
    border.color: Color.accent

    // A neon tube along its foot.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Math.max(2, Style.space(3))
      height: Math.max(2, Style.space(2))
      radius: height / 2
      color: Qt.tint(Color.accent, Util.alpha("#ffffff", 0.35 * seg.land))
      opacity: 0.75 + 0.25 * seg.land
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + Style.space(4)
        height: parent.height + Style.space(5)
        radius: height / 2
        color: Util.alpha(Color.accent, 0.22 + 0.2 * seg.land)
        z: -1
      }
    }
  }

  Repeater {
    model: seg.options

    Item {
      id: cell
      required property var modelData
      required property int index
      readonly property bool selected: index === seg.selectedIndex
      readonly property bool hot: cellMouse.containsMouse
      readonly property color ink: selected ? Color.accent : (hot ? panel.foreground : panel.dim)

      x: index * (seg.cellWidth + seg.gap)
      width: seg.cellWidth
      height: seg.height

      // The glyph of a newly picked option hops as the pill arrives.
      onSelectedChanged: if (selected && panel && panel.opened && !panel.calm) glyphHop.restart()
      SequentialAnimation {
        id: glyphHop
        PauseAnimation { duration: 110 }
        NumberAnimation { target: cellGlyph; property: "scale"; to: 1.12; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: cellGlyph; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
      }

      Grid {
        anchors.centerIn: parent
        columns: seg.stacked ? 1 : 2
        spacing: seg.stacked ? Style.space(2) : Style.space(5)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        scale: cellMouse.pressed ? 0.94 : 1

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Text {
          id: cellGlyph
          visible: cell.modelData.glyph !== undefined
          textFormat: Text.PlainText
          text: String(cell.modelData.glyph || "")
          color: cell.ink
          font.family: panel.fontFamily
          font.pixelSize: seg.stacked ? Style.font.subtitle : Style.font.caption

          Behavior on color { ColorAnimation { duration: 160 } }
        }

        Text {
          textFormat: Text.PlainText
          text: String(cell.modelData.label)
          color: cell.selected ? panel.foreground : cell.ink
          font.family: panel.fontFamily
          font.pixelSize: seg.compact || seg.stacked ? Style.font.caption : Style.font.bodySmall

          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }

      // The attention dot beats three times as the panel opens (or as it
      // turns up), then sits still: noticed, without nagging every open.
      Rectangle {
        id: badgeDot
        visible: cell.modelData.badge === true
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(5)
        width: Style.space(6)
        height: width
        radius: width / 2
        color: panel.urgent

        function beat() { if (visible && panel.opened && !panel.calm) badgeBeat.restart() }
        onVisibleChanged: beat()
        Connections {
          target: seg.panel
          function onOpenSerialChanged() { badgeDot.beat() }
        }
        SequentialAnimation {
          id: badgeBeat
          loops: 3
          NumberAnimation { target: badgeDot; property: "scale"; to: 1.4; duration: 600; easing.type: Easing.OutSine }
          NumberAnimation { target: badgeDot; property: "scale"; to: 1.0; duration: 600; easing.type: Easing.InSine }
        }
      }

      MouseArea {
        id: cellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: seg.picked(String(cell.modelData.value))
      }
    }
  }
}
