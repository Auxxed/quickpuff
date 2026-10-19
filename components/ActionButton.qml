import QtQuick
import QtQuick.Shapes
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
  // Energy running round the edge: continuously while this is the thing
  // under way (heating, connecting), and once round on hover for the big
  // buttons.
  property bool charging: false
  // A lightning bolt cracks across it when pressed (Boost).
  property bool zaps: false

  signal activated()

  readonly property bool hot: chipMouse.containsMouse
  readonly property bool lit: hot || emphasized

  // 0-1 round the edge, clockwise from the top left.
  property real orbit: 0
  readonly property bool orbiting: charging || orbitOnce.running
  onHotChanged: if (hot && tall && !charging && panel.opened) orbitOnce.restart()
  NumberAnimation { id: orbitOnce; target: chip; property: "orbit"; from: 0; to: 1; duration: 820; easing.type: Easing.InOutCubic }
  NumberAnimation on orbit {
    running: chip.charging && panel.opened
    loops: Animation.Infinite
    from: 0
    to: 1
    duration: 1700
  }
  // A point on the edge, `t` of the way round.
  function edgePoint(t) {
    var w = width, h = height, d = (((t % 1) + 1) % 1) * 2 * (w + h)
    if (d < w) return Qt.point(d, 0)
    if (d < w + h) return Qt.point(w, d - w)
    if (d < 2 * w + h) return Qt.point(w - (d - w - h), h)
    return Qt.point(0, h - (d - 2 * w - h))
  }

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

  // The energy on the edge: a spark with a fading tail (two, opposite
  // each other, while charging).
  Repeater {
    model: chip.orbiting ? (chip.charging ? 20 : 10) : 0
    Rectangle {
      required property int index
      readonly property int tailStep: index % 10
      readonly property real at: chip.orbit + (index >= 10 ? 0.5 : 0) - tailStep * 0.009
      readonly property point p: chip.edgePoint(at)
      width: Style.space(8) * (1 - tailStep * 0.075)
      height: width
      radius: width / 2
      x: p.x - width / 2
      y: p.y - height / 2
      color: tailStep === 0 ? Qt.tint(chip.tint, Util.alpha("#ffffff", 0.6)) : Util.alpha(Qt.lighter(chip.tint, 1.3), 0.42 * (1 - tailStep / 10))
      opacity: chip.charging ? 1 : Math.sin(Math.PI * Math.min(1, chip.orbit * 1.1))
    }
  }

  // Boost's lightning: a jagged bolt across the chip, cracking on and off.
  property real zap: 0
  property var boltPoints: []
  property var branchPoints: []
  function crack() {
    var pts = [], n = 12
    for (var i = 0; i <= n; i++) {
      var f = i / n
      pts.push(Qt.point(f * width, height * (0.5 + (i === 0 || i === n ? 0 : (Math.random() - 0.5) * 0.85))))
    }
    // A fork off the bolt, down toward a corner.
    var at = pts[3 + Math.floor(Math.random() * 5)], side = Math.random() < 0.5 ? -1 : 1
    var fork = [at]
    for (var j = 1; j <= 4; j++)
      fork.push(Qt.point(at.x + j * width * 0.06 + (Math.random() - 0.5) * width * 0.05, at.y + side * j * height * 0.11))
    boltPoints = pts
    branchPoints = fork
    zapAnim.restart()
  }
  SequentialAnimation {
    id: zapAnim
    NumberAnimation { target: chip; property: "zap"; from: 0; to: 1; duration: 40 }
    NumberAnimation { target: chip; property: "zap"; to: 0.35; duration: 60 }
    NumberAnimation { target: chip; property: "zap"; to: 0.9; duration: 40 }
    NumberAnimation { target: chip; property: "zap"; to: 0; duration: 380; easing.type: Easing.OutCubic }
  }
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Qt.lighter(chip.tint, 1.6)
    opacity: 0.22 * chip.zap
    visible: chip.zap > 0
  }
  Shape {
    anchors.fill: parent
    visible: chip.zap > 0 && chip.boltPoints.length > 1
    opacity: chip.zap
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Util.alpha(Qt.lighter(chip.tint, 1.4), 0.4)
      strokeWidth: Style.space(7)
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathPolyline { path: chip.boltPoints }
    }
    ShapePath {
      strokeColor: Qt.tint(chip.tint, Util.alpha("#ffffff", 0.88))
      strokeWidth: Style.space(2.2)
      fillColor: "transparent"
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.RoundCap
      PathPolyline { path: chip.boltPoints }
    }
    ShapePath {
      strokeColor: Qt.tint(chip.tint, Util.alpha("#ffffff", 0.7))
      strokeWidth: Style.space(1.3)
      fillColor: "transparent"
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.RoundCap
      PathPolyline { path: chip.branchPoints.length > 1 ? chip.branchPoints : [Qt.point(0, 0), Qt.point(0, 0)] }
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
      if (chip.zaps) chip.crack()
      chip.activated()
    }
  }
}
