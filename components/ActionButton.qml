import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Outlined chip: neutral at rest, tinted on hover/press, softly filled while
// it's the action the current state calls for. `tint` makes Stop read as
// destructive (urgent) and Heat as primary (accent). `tall` stacks the glyph
// over the label, `pulse` makes it glow for attention, `spinning` turns the
// glyph, and every press sends a ripple out from the cursor.
BorderSurface {
  id: chip

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string label: ""
  property string glyph: ""
  property color tint: panel.foreground
  property bool emphasized: false
  property bool tall: false
  property bool pulse: false
  property bool spinning: false

  signal activated()

  readonly property bool hot: chipMouse.containsMouse
  readonly property bool lit: hot || emphasized

  implicitHeight: tall
    ? Math.max(Style.space(50), chipBody.implicitHeight + Style.spacing.controlPaddingY * 2)
    : Math.max(Style.spacing.controlHeight, chipBody.implicitHeight + Style.spacing.controlPaddingY * 2)
  radius: Style.cornerRadius
  clip: true
  scale: chipMouse.pressed ? 0.96 : 1

  Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

  color: chipMouse.pressed ? Style.pressedFillFor(tint, tint)
    : hot ? Style.hoverFillFor(tint, tint)
    : emphasized ? Style.selectedFillFor(tint, tint)
    : Style.normalFillFor(tint, tint)

  borderSpec: hot || pulse
    ? Border.flat(Util.alpha(tint, hot ? 0.8 : 0.6), Math.max(1, Style.normalBorderWidth))
    : Border.controlSpec("normal", tint, tint)

  Behavior on color { ColorAnimation { duration: 120 } }

  // Attention glow.
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: chip.tint
    opacity: 0
    visible: chip.pulse

    SequentialAnimation on opacity {
      running: chip.pulse && panel.opened
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 0; to: 0.16; duration: 800; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.16; to: 0; duration: 800; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    id: ripple
    property real cx: 0
    property real cy: 0
    width: 0
    height: width
    radius: width / 2
    x: cx - width / 2
    y: cy - height / 2
    color: chip.tint
    opacity: 0
  }

  ParallelAnimation {
    id: rippleAnim
    NumberAnimation { target: ripple; property: "width"; from: 0; to: Math.max(chip.width, chip.height) * 2.2; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { target: ripple; property: "opacity"; from: 0.3; to: 0; duration: 520; easing.type: Easing.InQuad }
  }

  Grid {
    id: chipBody
    anchors.centerIn: parent
    columns: chip.tall ? 1 : 2
    spacing: chip.tall ? Style.space(3) : Style.spacing.md
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    Text {
      id: chipGlyph
      textFormat: Text.PlainText
      visible: chip.glyph !== ""
      text: chip.glyph
      color: chip.lit || chip.tall ? chip.tint : panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: chip.tall ? Style.font.heading : (chip.label === "" ? Style.font.icon : Style.font.iconSmall)

      Behavior on color { ColorAnimation { duration: 120 } }

      RotationAnimation on rotation {
        running: chip.spinning && panel.opened
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 1000
        onRunningChanged: if (!running) chipGlyph.rotation = 0
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: chip.label !== ""
      text: chip.label
      color: chip.lit ? chip.tint : panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: chip.emphasized

      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      ripple.cx = mouse.x
      ripple.cy = mouse.y
      rippleAnim.restart()
      chip.activated()
    }
  }
}
