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

  Rectangle {
    visible: seg.selectedIndex >= 0
    x: seg.selectedIndex * (seg.cellWidth + seg.gap)
    width: seg.cellWidth
    height: parent.height
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.2)
    border.width: 1
    border.color: Color.accent

    Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    Behavior on width { NumberAnimation { duration: 200 } }
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

      Grid {
        anchors.centerIn: parent
        columns: seg.stacked ? 1 : 2
        spacing: seg.stacked ? Style.space(2) : Style.space(5)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        scale: cellMouse.pressed ? 0.92 : (cell.selected && seg.stacked ? 1.04 : 1)

        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        Text {
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
          font.bold: cell.selected

          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }

      Rectangle {
        visible: cell.modelData.badge === true
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(5)
        width: Style.space(6)
        height: width
        radius: width / 2
        color: panel.urgent

        SequentialAnimation on scale {
          running: parent.visible && panel.opened
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 1.4; duration: 600; easing.type: Easing.OutSine }
          NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InSine }
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
