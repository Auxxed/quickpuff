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
  // Filled with `tint`, shaded darker toward the foot, like the Puffco app's
  // start button; its ink is whatever reads on the tint.
  property bool solid: false
  // A task under way (0-1): the chip fills behind its label up to here, its
  // leading edge lit and a sheen running over the fill. Below 0, none.
  property real progress: -1
  property real shownProgress: Math.max(0, progress)
  Behavior on shownProgress { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
  readonly property color ink: solid ? panel.inkOn(tint) : (lit || tall ? tint : panel.foreground)

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

  borderSpec: solid ? Border.flat(Util.alpha(tint, 0.9), Math.max(1, Style.normalBorderWidth))
    : hot || pulse
    ? Border.flat(Util.alpha(tint, hot ? 0.8 : 0.6), Math.max(1, Style.normalBorderWidth))
    : Border.controlSpec("normal", tint, tint)

  Behavior on color { ColorAnimation { duration: 120 } }

  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    visible: chip.solid
    gradient: Gradient {
      GradientStop { position: 0.0; color: chip.hot ? Qt.lighter(chip.tint, 1.15) : chip.tint }
      GradientStop { position: 1.0; color: Qt.darker(chip.tint, chip.hot ? 1.25 : 1.45) }
    }
  }

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

  Item {
    id: progressFill
    visible: chip.progress >= 0
    anchors.fill: parent

    Rectangle {
      id: fillBody
      width: parent.width * chip.shownProgress
      height: parent.height
      clip: true
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha(chip.tint, 0.1) }
        GradientStop { position: 1.0; color: Util.alpha(chip.tint, 0.32) }
      }

      Rectangle {
        property real k: 0
        visible: chip.shownProgress < 0.999
        width: Math.max(chip.height, fillBody.width * 0.45)
        height: parent.height
        x: -width + (fillBody.width + width) * k
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
          GradientStop { position: 0.5; color: Util.alpha("#ffffff", 0.13) }
          GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0) }
        }
        NumberAnimation on k {
          running: progressFill.visible && chip.shownProgress < 0.999 && panel.opened
          loops: Animation.Infinite
          from: 0
          to: 1
          duration: 1600
          easing.type: Easing.InOutQuad
        }
      }
    }

    // The leading edge, lit.
    Rectangle {
      visible: chip.shownProgress > 0.005 && chip.shownProgress < 0.995
      x: fillBody.width - width / 2
      width: Math.max(2, Style.space(2))
      height: parent.height
      color: Qt.lighter(chip.tint, 1.3)
      opacity: 0.85
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
      color: chip.ink
      font.family: panel.fontFamily
      font.pixelSize: chip.tall ? Style.font.heading : (chip.label === "" ? Style.font.icon : Style.font.iconSmall)
      scale: chip.hot && !chipMouse.pressed ? 1.14 : 1

      Behavior on color { ColorAnimation { duration: 120 } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

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
      color: chip.solid ? chip.ink : (chip.lit ? chip.tint : panel.foreground)
      // Tall buttons are the big session controls: Puffco's type, in capitals.
      font.family: chip.tall ? panel.displayFamily : panel.fontFamily
      font.pixelSize: chip.tall ? Math.round(Style.font.body * panel.displayScale) : Style.font.bodySmall
      font.weight: chip.tall ? Font.DemiBold : (chip.emphasized ? Font.Bold : Font.Normal)
      font.capitalization: chip.tall && panel.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
      font.letterSpacing: chip.tall && panel.hasDisplayFont ? 1.5 : 0

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
