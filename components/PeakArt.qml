import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Ui
import qs.Commons

// A Peak Pro, drawn: the tall glass horn leaning up from the back, the
// sloped collar carrying the chamber and carb cap on its shelf, and the
// lower body tapering to an offset foot, finished in this Peak's own
// colorway. The light ring where the glass meets the base, the glow up the
// glass and the pool on the desk all take the active profile's colour.
//
// Drawn on a 100 x 160 grid (see the SVG paths) and scaled to fit.
Item {
  id: art

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string colorway: ""
  property color tint: Color.accent
  // 0 dark, 1 full glow; the host animates it (breathing while preheating).
  property real glow: 0.6
  // Vapour rising in the glass while the chamber is hot.
  property bool vapor: false
  property bool asleep: false
  readonly property bool live: panel ? panel.opened : false

  implicitWidth: Style.space(70)
  implicitHeight: implicitWidth * 1.6
  readonly property real u: width / 100

  // Base finish per colorway [lighter, darker], from Puffco's product shots.
  readonly property var finishes: ({
    "onyx": ["#3a3a3d", "#111113"],
    "og": ["#353537", "#0f0f10"],
    "pearl": ["#f7f4ef", "#cbc4b8"],
    "opal": ["#f3f0f7", "#c3bad0"],
    "desert": ["#d4b28c", "#8c6946"],
    "flourish": ["#5f8f6a", "#264030"],
    "storm": ["#7b8490", "#343a43"],
    "daybreak": ["#f3be96", "#c06f4c"],
    "plasma": ["#8a44b8", "#2a0f42"],
    "glacier": ["#dceef7", "#8bb0c4"],
    "indiglow": ["#3a4db0", "#121946"],
    "guardian": ["#4e5c43", "#1c2517"]
  })
  readonly property var finish: finishes[String(colorway).toLowerCase()] || finishes["onyx"]
  readonly property bool lightFinish: Qt.color(finish[0]).hslLightness > 0.6
  readonly property color ringColor: asleep ? Util.alpha(panel.foreground, 0.25) : tint
  readonly property color edge: lightFinish ? "#000000" : "#ffffff"

  // The pool of light on the desk, under everything.
  Shape {
    id: pool
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: art.u * 6
    // Centred on the foot once squashed.
    y: art.u * 156 - height / 2
    width: art.u * 120
    height: width
    opacity: art.glow
    transform: Scale { origin.x: pool.width / 2; origin.y: pool.height / 2; yScale: 0.14 }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: pool.width / 2; centerY: pool.height / 2; centerRadius: pool.width / 2
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.0; color: Util.alpha(art.ringColor, 0.7) }
        GradientStop { position: 0.4; color: Util.alpha(art.ringColor, 0.25) }
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
    width: 100
    height: 160
    transform: Scale { xScale: art.u; yScale: art.u }
    preferredRendererType: Shape.CurveRenderer

    // ---- glass horn, lit from below
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.asleep ? 0.2 : 0.45)
      strokeWidth: 1.2
      joinStyle: ShapePath.RoundJoin
      fillGradient: LinearGradient {
        x1: 0; y1: 5; x2: 0; y2: 104
        GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.05) }
        GradientStop { position: 0.65; color: Util.alpha(art.ringColor, 0.1 * art.glow + (art.vapor ? 0.08 : 0)) }
        GradientStop { position: 1.0; color: Util.alpha(art.ringColor, 0.55 * art.glow) }
      }
      PathSvg { path: "M51,3 L64,5 L82,108 L32,100 Z" }
    }
    // Highlight down the glass.
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.asleep ? 0.12 : 0.32)
      strokeWidth: 1.6
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M55,12 L44,86" }
    }

    // ---- lower body, tapering to the foot
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.12)
      strokeWidth: 0.8
      fillGradient: LinearGradient {
        x1: 8; y1: 114; x2: 85; y2: 156
        GradientStop { position: 0.0; color: art.finish[0] }
        GradientStop { position: 1.0; color: art.finish[1] }
      }
      PathSvg { path: "M8,114 L83,132 L85,150 Q85,156 79,156 L35,156 Q30,156 28,151 Z" }
    }
    // ---- collar, a shade lighter, carrying the chamber
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.14)
      strokeWidth: 0.8
      fillGradient: LinearGradient {
        x1: 6; y1: 100; x2: 83; y2: 132
        GradientStop { position: 0.0; color: Qt.lighter(art.finish[0], art.lightFinish ? 1.04 : 1.3) }
        GradientStop { position: 1.0; color: Qt.lighter(art.finish[1], art.lightFinish ? 1.02 : 1.5) }
      }
      PathSvg { path: "M6,101 Q6,99 8,99 L82,107 L83,132 L8,114 Z" }
    }
    // Swooshes across the body.
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.09)
      strokeWidth: 1
      fillColor: "transparent"
      PathSvg { path: "M14,122 L84,140 M19,131 L84,146" }
    }

    // ---- light ring where the glass meets the base
    ShapePath {
      strokeColor: art.ringColor
      strokeWidth: 2.4
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M33,100 L81,107" }
    }

    // ---- chamber: bowl with its coil, carb cap, knob
    ShapePath {
      strokeColor: "transparent"
      fillColor: Qt.darker(art.finish[0], art.lightFinish ? 1.15 : 1.2)
      PathSvg { path: "M12,85 H27 Q29,85 29,87 V97 Q29,99 27,99 H12 Q10,99 10,97 V87 Q10,85 12,85 Z" }
    }
    ShapePath {
      strokeColor: art.asleep ? "#7a6a5a" : "#c98a4b"
      strokeWidth: 1.1
      fillColor: "transparent"
      PathSvg { path: "M11,88 H28 M11,91 H28 M11,94 H28 M11,97 H28" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.12)
      strokeWidth: 0.8
      fillColor: Qt.lighter(art.finish[0], art.lightFinish ? 1.0 : 1.1)
      PathSvg { path: "M11,76 H28 Q31,76 31,79 V83 Q31,86 28,86 H11 Q8,86 8,83 V79 Q8,76 11,76 Z" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillColor: Qt.lighter(art.finish[0], art.lightFinish ? 0.95 : 1.3)
      PathSvg { path: "M17,70.5 H22 Q24,70.5 24,72.5 V76.5 H15 V72.5 Q15,70.5 17,70.5 Z" }
    }
  }

  // Vapour rising up the glass.
  Repeater {
    model: 3
    Rectangle {
      id: puff
      required property int index
      width: art.u * 10
      height: width
      radius: width / 2
      color: Util.alpha("#ffffff", 0.55)
      opacity: 0
      visible: art.vapor

      SequentialAnimation {
        running: art.vapor && art.live
        loops: Animation.Infinite
        PauseAnimation { duration: puff.index * 600 }
        ParallelAnimation {
          NumberAnimation { target: puff; property: "y"; from: art.u * 92; to: art.u * 14; duration: 2000; easing.type: Easing.OutSine }
          NumberAnimation { target: puff; property: "x"; from: art.u * (52 + puff.index * 4); to: art.u * (52 + (puff.index % 2 ? 5 : -3)); duration: 2000; easing.type: Easing.InOutSine }
          NumberAnimation { target: puff; property: "scale"; from: 0.6; to: 1.6; duration: 2000 }
          SequentialAnimation {
            NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.45; duration: 300 }
            NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 1700; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }
}
