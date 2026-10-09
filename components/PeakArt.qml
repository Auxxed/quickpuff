import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Ui
import qs.Commons

// A Peak Pro in side profile, traced from Puffco's own product renders: the
// glass horn leaning up from the angled hood, the chamber on the hood's flat
// shelf, and the dark pedestal flaring out to the foot. The hood and
// pedestal take this Peak's colorway; the light ring round the foot, the
// glow up the glass, the logo and the pool on the desk take the active
// profile's colour.
//
// Drawn on an 80 x 160 grid (the SVG paths below) and scaled to fit.
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
  // Extra light for big, close-up use (Showtime's stage): rim light from the
  // ring, beams up the glass, and a bloom round the ring.
  property bool hero: false
  readonly property bool live: panel ? panel.opened : false

  implicitWidth: Style.space(60)
  implicitHeight: implicitWidth * 2
  readonly property real u: width / 80

  // Per colorway: pedestal [light, dark], hood [light, dark], chamber cap.
  readonly property var finishes: ({
    "onyx": [["#1a1a1c", "#08080a"], ["#4c4c51", "#18181b"], "#1e1e20"],
    "og": [["#1a1a1c", "#08080a"], ["#45454a", "#161618"], "#1e1e20"],
    "pearl": [["#e9e4dc", "#c4bcae"], ["#ffffff", "#ddd6cb"], "#f2eee8"],
    "opal": [["#e6e1ee", "#bdb3cc"], ["#fbf9ff", "#d6cfe2"], "#efeaf5"],
    "desert": [["#b38d66", "#7a5a3a"], ["#e3c4a0", "#b08960"], "#c9a57e"],
    "flourish": [["#3f6a4b", "#1d3324"], ["#7fae88", "#3d6448"], "#4f7a5a"],
    "storm": [["#4d5560", "#262b32"], ["#9aa3ae", "#5a626d"], "#59616c"],
    "daybreak": [["#d9875f", "#9c5236"], ["#f8cfae", "#d88f68"], "#e9a07a"],
    "plasma": [["#8a4fd6", "#4b238f"], ["#f2a36f", "#c44f8f"], "#8a4fd6"],
    "glacier": [["#a9cde0", "#6d95ab"], ["#eef8fd", "#b6d6e6"], "#cfe6f2"],
    "indiglow": [["#2b3a8f", "#10163f"], ["#5c6fd0", "#27348a"], "#33459e"],
    "guardian": [["#38432f", "#171e12"], ["#68765b", "#323d29"], "#45523b"]
  })
  readonly property var finish: finishes[String(colorway).toLowerCase()] || finishes["onyx"]
  readonly property bool lightFinish: Qt.color(finish[1][0]).hslLightness > 0.7
  readonly property color ringColor: asleep ? Util.alpha(panel.foreground, 0.25) : tint
  readonly property color edge: lightFinish ? "#000000" : "#ffffff"

  // The pool of light on the desk, under everything.
  Shape {
    id: pool
    x: art.u * 35 - width / 2
    // Centred on the foot once squashed.
    y: art.u * 157.5 - height / 2
    width: art.u * 84
    height: width
    opacity: art.glow
    transform: Scale { origin.x: pool.width / 2; origin.y: pool.height / 2; yScale: 0.12 }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: pool.width / 2; centerY: pool.height / 2; centerRadius: pool.width / 2
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.0; color: Util.alpha(art.ringColor, 0.75) }
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
    width: 80
    height: 160
    transform: Scale { xScale: art.u; yScale: art.u }
    preferredRendererType: Shape.CurveRenderer

    // ---- glass horn, lit from below, and the cone inside it
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.asleep ? 0.22 : 0.5)
      strokeWidth: 1
      joinStyle: ShapePath.RoundJoin
      fillGradient: LinearGradient {
        x1: 0; y1: 1; x2: 0; y2: 108
        GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.04) }
        GradientStop { position: 0.55; color: Util.alpha(art.ringColor, 0.05 + (art.vapor ? 0.08 : 0)) }
        GradientStop { position: 1.0; color: Util.alpha(art.ringColor, 0.45 * art.glow) }
      }
      PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillGradient: LinearGradient {
        x1: 0; y1: 36; x2: 0; y2: 105
        GradientStop { position: 0.0; color: Util.alpha("#ffffff", art.asleep ? 0.08 : 0.18) }
        GradientStop { position: 1.0; color: Util.alpha(art.ringColor, 0.35 * art.glow) }
      }
      PathSvg { path: "M17.5,37 Q20,35.8 22.5,36.5 L35,97 L13,105 Z" }
    }
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.asleep ? 0.1 : 0.28)
      strokeWidth: 1.3
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M14.5,6 L11,100" }
    }

    // ---- pedestal, then the hood over it
    ShapePath {
      strokeColor: "transparent"
      fillGradient: LinearGradient {
        x1: 6; y1: 0; x2: 73; y2: 0
        GradientStop { position: 0.0; color: art.finish[0][0] }
        GradientStop { position: 1.0; color: art.finish[0][1] }
      }
      PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillGradient: LinearGradient {
        x1: 6; y1: 93; x2: 73; y2: 130
        GradientStop { position: 0.0; color: art.finish[1][0] }
        GradientStop { position: 1.0; color: art.finish[1][1] }
      }
      PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C52,116 24,136 6.5,151 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.14)
      strokeWidth: 0.7
      fillColor: "transparent"
      PathSvg { path: "M72.3,104.4 C52,116 24,136 6.8,150.6" }
    }
    ShapePath {
      strokeColor: Util.alpha("#ffffff", art.lightFinish ? 0.7 : 0.4)
      strokeWidth: 0.8
      fillColor: "transparent"
      PathSvg { path: "M46.5,93.2 L70,93.2 Q72.2,93.2 72.4,95.4" }
    }
    // Chrome seat the glass sits in.
    ShapePath {
      strokeColor: art.asleep ? "#8a8a8e" : "#d8d8dc"
      strokeWidth: 1.3
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.8,108.6 L45.8,93.1" }
    }

    // ---- hero light: beams up the glass and the ring's light on the body
    ShapePath {
      strokeColor: "transparent"
      fillGradient: LinearGradient {
        x1: 0; y1: 104; x2: 0; y2: 30
        GradientStop { position: 0.0; color: Util.alpha(art.ringColor, art.hero ? 0.32 * art.glow : 0) }
        GradientStop { position: 1.0; color: Util.alpha(art.ringColor, 0) }
      }
      PathSvg { path: "M20,104 L24,40 L27,40 L25,103 Z M30,101 L31,52 L33,52 L35,99 Z" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.ringColor, art.hero ? 0.55 * art.glow : 0)
      strokeWidth: 0.9
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M64.5,152 C63,140 60,126 56,113.5 M6.8,150.6 C24,136 52,116 72.3,104.4" }
    }

    // ---- the logo and the light ring round the foot
    ShapePath {
      strokeColor: "transparent"
      fillColor: Util.alpha(art.ringColor, 0.35 + 0.65 * art.glow)
      PathSvg { path: "M12,123 L14.6,121.6 L14.6,128.6 L12,130 Z" }
    }
    ShapePath {
      strokeColor: art.ringColor
      strokeWidth: 1.8
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.5,157 L61,157" }
    }
    // Bloom: the ring again, wider and fainter, twice over.
    ShapePath {
      strokeColor: Util.alpha(art.ringColor, art.hero ? 0.28 * art.glow : 0)
      strokeWidth: 5
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.5,157 L61,157" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.ringColor, art.hero ? 0.12 * art.glow : 0)
      strokeWidth: 11
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.5,157 L61,157" }
    }

    // ---- chamber on the shelf: chrome collar and knurled cap
    ShapePath {
      strokeColor: "transparent"
      fillColor: art.asleep ? "#8a8a8e" : "#c9c9ce"
      PathSvg { path: "M50.5,90.5 H69.5 V93.5 H50.5 Z" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.15)
      strokeWidth: 0.5
      fillColor: art.finish[2]
      PathSvg { path: "M51.5,80.5 H69 Q71,80.5 71,82.5 V89 Q71,91 69,91 H51.5 Q49.5,91 49.5,89 V82.5 Q49.5,80.5 51.5,80.5 Z" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.edge, 0.1)
      strokeWidth: 0.6
      fillColor: "transparent"
      PathSvg { path: "M52,82 L54,90 M55,82 L57,90 M58,82 L60,90 M61,82 L63,90 M64,82 L66,90 M67,82 L69,90" }
    }
  }

  // Vapour rising up the glass.
  Repeater {
    model: 3
    Rectangle {
      id: puff
      required property int index
      width: art.u * 8
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
          NumberAnimation { target: puff; property: "y"; from: art.u * 96; to: art.u * 8; duration: 2000; easing.type: Easing.OutSine }
          NumberAnimation { target: puff; property: "x"; from: art.u * (20 + puff.index * 4); to: art.u * (13 + (puff.index % 2 ? 4 : 0)); duration: 2000; easing.type: Easing.InOutSine }
          NumberAnimation { target: puff; property: "scale"; from: 0.6; to: 1.5; duration: 2000 }
          SequentialAnimation {
            NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.45; duration: 300 }
            NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 1700; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }
}
