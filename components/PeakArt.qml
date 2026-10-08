import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Ui
import qs.Commons

// A Peak Pro drawn the way the Puffco app pictures it: the glass sitting in
// a flared base finished in this Peak's own colorway, and the light ring
// round the foot glowing the active profile's colour onto the desk.
//
// Drawn on a 100 x 160 grid and scaled, so it stays crisp at any size.
Item {
  id: art

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string colorway: ""
  property color tint: Color.accent
  // 0 dark, 1 full glow; the host animates it (breathing while preheating).
  property real glow: 0.6
  // Vapour in the glass while the chamber is hot.
  property bool vapor: false
  property bool asleep: false
  readonly property bool live: panel ? panel.opened : false

  implicitWidth: Style.space(70)
  implicitHeight: implicitWidth * 1.6
  readonly property real u: width / 100

  // Base finish per colorway: [top, bottom], from Puffco's product shots.
  readonly property var finishes: ({
    "onyx": ["#3a3a3c", "#0c0c0d"],
    "og": ["#333335", "#0e0e0f"],
    "pearl": ["#f6f3ee", "#c9c2b6"],
    "opal": ["#f4f1f7", "#c5bdd2"],
    "desert": ["#d2b08a", "#8d6a47"],
    "flourish": ["#5a8a66", "#284431"],
    "storm": ["#77808c", "#363c45"],
    "daybreak": ["#f2bc94", "#bf7350"],
    "plasma": ["#7a3aa3", "#2b1043"],
    "glacier": ["#d8ecf6", "#8eb3c7"],
    "indiglow": ["#33459e", "#131a47"],
    "guardian": ["#4a5840", "#1d2618"]
  })
  readonly property var finish: finishes[String(colorway).toLowerCase()] || finishes["onyx"]
  readonly property bool lightFinish: Qt.color(finish[0]).hslLightness > 0.6
  readonly property color ringColor: asleep ? Util.alpha(panel.foreground, 0.25) : tint

  // The glow on the desk, under everything: a soft radial pool squashed
  // flat, brightest under the ring.
  Shape {
    id: pool
    anchors.horizontalCenter: parent.horizontalCenter
    // Centred on the ring once squashed.
    y: art.u * 147 - height / 2
    width: art.u * 190
    height: width
    opacity: art.glow
    transform: Scale { origin.x: pool.width / 2; origin.y: pool.height / 2; yScale: 0.22 }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: pool.width / 2; centerY: pool.height / 2; centerRadius: pool.width / 2
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.0; color: Util.alpha(art.ringColor, 0.75) }
        GradientStop { position: 0.35; color: Util.alpha(art.ringColor, 0.3) }
        GradientStop { position: 1.0; color: Util.alpha(art.ringColor, 0) }
      }
      startX: 0; startY: 0
      PathLine { x: pool.width; y: 0 }
      PathLine { x: pool.width; y: pool.height }
      PathLine { x: 0; y: pool.height }
      PathLine { x: 0; y: 0 }
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // ---- glass: mouthpiece, bubble and neck, one outline
    ShapePath {
      strokeColor: Util.alpha(art.lightFinish ? "#000000" : "#ffffff", art.asleep ? 0.18 : 0.42)
      strokeWidth: Math.max(1, art.u * 1.6)
      fillGradient: LinearGradient {
        x1: 0; y1: art.u * 10; x2: 0; y2: art.u * 80
        GradientStop { position: 0; color: Util.alpha("#ffffff", 0.07) }
        GradientStop { position: 1; color: Util.alpha(art.tint, art.vapor ? 0.22 : 0.06) }
      }
      startX: art.u * 40; startY: art.u * 14
      PathQuad { x: art.u * 60; y: art.u * 14; controlX: art.u * 50; controlY: art.u * 10 }
      PathLine { x: art.u * 60; y: art.u * 28 }
      PathCubic { x: art.u * 88; y: art.u * 60; control1X: art.u * 80; control1Y: art.u * 31; control2X: art.u * 89; control2Y: art.u * 44 }
      PathCubic { x: art.u * 72; y: art.u * 84; control1X: art.u * 88; control1Y: art.u * 72; control2X: art.u * 81; control2Y: art.u * 80 }
      PathLine { x: art.u * 28; y: art.u * 84 }
      PathCubic { x: art.u * 12; y: art.u * 60; control1X: art.u * 19; control1Y: art.u * 80; control2X: art.u * 12; control2Y: art.u * 72 }
      PathCubic { x: art.u * 40; y: art.u * 28; control1X: art.u * 11; control1Y: art.u * 44; control2X: art.u * 20; control2Y: art.u * 31 }
      PathLine { x: art.u * 40; y: art.u * 14 }
    }

    // ---- glass highlight down the left of the bubble
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.asleep ? 0.12 : 0.35)
      strokeWidth: Math.max(1, art.u * 2.2)
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      startX: art.u * 26; startY: art.u * 44
      PathQuad { x: art.u * 21; y: art.u * 66; controlX: art.u * 19; controlY: art.u * 54 }
    }

    // ---- base: a squat body that flares toward the foot
    ShapePath {
      strokeColor: Util.alpha(art.lightFinish ? "#000000" : "#ffffff", 0.16)
      strokeWidth: Math.max(1, art.u)
      fillGradient: LinearGradient {
        x1: 0; y1: art.u * 82; x2: 0; y2: art.u * 152
        GradientStop { position: 0; color: art.finish[0] }
        GradientStop { position: 1; color: art.finish[1] }
      }
      startX: art.u * 24; startY: art.u * 82
      PathLine { x: art.u * 76; y: art.u * 82 }
      PathQuad { x: art.u * 82; y: art.u * 88; controlX: art.u * 81; controlY: art.u * 82 }
      PathCubic { x: art.u * 90; y: art.u * 146; control1X: art.u * 84; control1Y: art.u * 112; control2X: art.u * 90; control2Y: art.u * 132 }
      PathQuad { x: art.u * 84; y: art.u * 152; controlX: art.u * 90; controlY: art.u * 152 }
      PathLine { x: art.u * 16; y: art.u * 152 }
      PathQuad { x: art.u * 10; y: art.u * 146; controlX: art.u * 10; controlY: art.u * 152 }
      PathCubic { x: art.u * 18; y: art.u * 88; control1X: art.u * 10; control1Y: art.u * 132; control2X: art.u * 16; control2Y: art.u * 112 }
      PathQuad { x: art.u * 24; y: art.u * 82; controlX: art.u * 19; controlY: art.u * 82 }
    }

    // ---- sheen down the base's left shoulder
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.lightFinish ? 0.5 : 0.14)
      strokeWidth: Math.max(1, art.u * 2.4)
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      startX: art.u * 22; startY: art.u * 92
      PathCubic { x: art.u * 17; y: art.u * 136; control1X: art.u * 19; control1Y: art.u * 108; control2X: art.u * 16; control2Y: art.u * 124 }
    }
  }

  // The light ring itself, a bright band just above the foot.
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: art.u * 141
    width: art.u * 76
    height: Math.max(2, art.u * 4.5)
    radius: height / 2
    color: art.ringColor
    opacity: 0.3 + 0.7 * art.glow
    Behavior on color { ColorAnimation { duration: 300 } }

    // Hot core of the band.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.8
      height: Math.max(1, parent.height * 0.4)
      radius: height / 2
      color: Qt.lighter(art.ringColor, 1.6)
      opacity: art.glow
    }
  }

  // Vapour curling up inside the glass.
  Repeater {
    model: 3
    Rectangle {
      id: puff
      required property int index
      x: art.u * (42 + index * 4)
      y: art.u * 70
      width: art.u * 14
      height: width
      radius: width / 2
      color: Util.alpha("#ffffff", 0.5)
      opacity: 0
      visible: art.vapor

      SequentialAnimation {
        running: art.vapor && art.live
        loops: Animation.Infinite
        PauseAnimation { duration: puff.index * 500 }
        ParallelAnimation {
          NumberAnimation { target: puff; property: "y"; from: art.u * 70; to: art.u * 22; duration: 1500; easing.type: Easing.OutSine }
          NumberAnimation { target: puff; property: "x"; from: art.u * (36 + puff.index * 6); to: art.u * (44 + (puff.index % 2 ? 8 : -6)); duration: 1500; easing.type: Easing.InOutSine }
          NumberAnimation { target: puff; property: "scale"; from: 0.6; to: 1.9; duration: 1500 }
          SequentialAnimation {
            NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.45; duration: 300 }
            NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 1200; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }
}
