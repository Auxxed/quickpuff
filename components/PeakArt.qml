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
  // The light ring as a gauge, 0-1: faint end to end, lit up to here, with a
  // bright head. Below 0 the ring is plain.
  property real progress: -1
  // Looking for its computer: Bluetooth waves out of the body and a light
  // running along the ring.
  property bool searching: false
  // Asleep and not being woken: a few z's drift up off the chamber.
  property bool dozing: false
  // Heating: arcs of electricity crackle off the chamber now and then.
  property bool crackle: false
  // Animating only while it can be seen: a running animation keeps the
  // window redrawing even when the item it moves is hidden.
  readonly property bool live: (panel ? panel.opened : false) && visible

  implicitWidth: Style.space(60)
  implicitHeight: implicitWidth * 2
  readonly property real u: width / 80

  // The ring's colour eases from one profile's light to the next, and the
  // gauge glides between readings.
  property color shownTint: tint
  // Off when the host animates the tint itself (a cycle preview).
  property bool tintGlides: true
  Behavior on shownTint {
    enabled: art.tintGlides
    ColorAnimation { duration: 480; easing.type: Easing.OutCubic }
  }
  property real shownProgress: Math.max(0, progress)
  Behavior on shownProgress { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

  // A flash of the ring (a new colour landing on it), and a glint up the
  // glass (the chamber reaching temperature).
  property real flash: 0
  function pulse() { flashAnim.restart() }
  SequentialAnimation {
    id: flashAnim
    NumberAnimation { target: art; property: "flash"; to: 1; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: art; property: "flash"; to: 0; duration: 650; easing.type: Easing.InOutSine }
  }
  property real glintY: -1
  function glint() { glintAnim.restart() }
  NumberAnimation {
    id: glintAnim
    target: art
    property: "glintY"
    from: 112
    to: -14
    duration: 820
    easing.type: Easing.InOutCubic
    onStopped: art.glintY = -1
  }

  // The arcs: one or two jagged sparks up off the chamber's cap, each
  // flickering on for a moment, at uneven intervals.
  property var arcs: []
  property real arcFlash: 0
  function strike() {
    var out = []
    var n = 1 + Math.floor(Math.random() * 2)
    for (var a = 0; a < n; a++) {
      var x = 52 + Math.random() * 17, y = 80.5
      var ang = -Math.PI / 2 + (Math.random() - 0.5) * 1.8
      var len = 13 + Math.random() * 15
      var pts = [Qt.point(x, y)]
      for (var k = 1; k <= 5; k++) {
        var f = k / 5
        pts.push(Qt.point(x + Math.cos(ang) * len * f + (Math.random() - 0.5) * 5,
                          y + Math.sin(ang) * len * f + (Math.random() - 0.5) * 5))
      }
      out.push(pts)
    }
    arcs = out
    arcAnim.restart()
  }
  Timer {
    interval: 600
    running: art.crackle && art.live
    repeat: true
    // On the panel's heartbeat: a half or a whole beat apart.
    onTriggered: { art.strike(); interval = Math.random() < 0.5 ? 800 : 1600 }
  }
  SequentialAnimation {
    id: arcAnim
    NumberAnimation { target: art; property: "arcFlash"; from: 1; to: 0.25; duration: 45 }
    NumberAnimation { target: art; property: "arcFlash"; to: 1; duration: 35 }
    NumberAnimation { target: art; property: "arcFlash"; to: 0; duration: 170; easing.type: Easing.InQuad }
  }

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
  readonly property color ringColor: asleep ? Util.alpha(panel.foreground, 0.25) : shownTint
  readonly property color edge: lightFinish ? "#000000" : "#ffffff"

  // The glass horn's left and right edges at height y, on the 80 x 160 grid,
  // for anything that has to stay inside the glass.
  function glassLeft(y) { return 12.5 + (9.5 - 12.5) * (y - 1.5) / (108 - 1.5) }
  function glassRight(y) { return 21.5 + (46 - 21.5) * (y - 0.8) / (93 - 0.8) }

  // Bluetooth waves out of the body while it's being looked for.
  Repeater {
    model: art.searching ? 3 : 0
    Rectangle {
      id: wave
      required property int index
      property real k: 0
      readonly property real r: art.u * (14 + 58 * k)
      x: art.u * 38 - r
      y: art.u * 118 - r
      width: r * 2
      height: r * 2
      radius: r
      color: "transparent"
      border.width: Math.max(1.5, art.u * 2.4 * (1 - 0.5 * k))
      border.color: Util.alpha(Qt.lighter(Color.accent, 1.2), 0.85 * Math.pow(1 - k, 1.3))
      SequentialAnimation on k {
        running: art.searching && art.live
        loops: Animation.Infinite
        PauseAnimation { duration: wave.index * 620 }
        NumberAnimation { from: 0; to: 1; duration: 1860; easing.type: Easing.OutCubic }
        PauseAnimation { duration: (2 - wave.index) * 620 }
      }
    }
  }

  // The pool of light on the desk, under everything.
  Shape {
    id: pool
    x: art.u * 35 - width / 2
    // Centred on the foot once squashed.
    y: art.u * 157.5 - height / 2
    width: art.u * 84
    height: width
    opacity: Math.min(1, art.glow + 0.5 * art.flash)
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
      fillColor: Util.alpha(art.ringColor, Math.min(1, 0.35 + 0.65 * art.glow + 0.3 * art.flash))
      PathSvg { path: "M12,123 L14.6,121.6 L14.6,128.6 L12,130 Z" }
    }
    // As a gauge the ring burns faint, and the lit part is drawn over it.
    ShapePath {
      strokeColor: art.progress >= 0 ? Util.alpha(art.ringColor, 0.3) : art.ringColor
      strokeWidth: 1.8
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.5,157 L61,157" }
    }
    // Bloom: the ring again, wider and fainter, twice over. A flash lights
    // it for a moment on any Peak.
    ShapePath {
      strokeColor: Util.alpha(art.ringColor, Math.min(1, (art.hero ? 0.28 * art.glow : 0) + 0.45 * art.flash))
      strokeWidth: 5
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      PathSvg { path: "M8.5,157 L61,157" }
    }
    ShapePath {
      strokeColor: Util.alpha(art.ringColor, Math.min(1, (art.hero ? 0.12 * art.glow : 0) + 0.2 * art.flash))
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

  // Overlays drawn on the same 80 x 160 grid.
  Item {
    id: grid
    width: 80
    height: 160
    transform: Scale { xScale: art.u; yScale: art.u }

    // The gauge: the lit run of the ring and its head.
    Rectangle {
      visible: art.progress >= 0
      x: 8.5 - 0.9
      y: 157 - 0.9
      height: 1.8
      radius: 0.9
      width: 1.8 + 52.5 * art.shownProgress
      color: art.ringColor
    }
    Rectangle {
      visible: art.progress >= 0 && art.shownProgress > 0.01 && art.shownProgress < 0.995
      x: 8.5 + 52.5 * art.shownProgress - width / 2
      y: 157 - height / 2
      width: 7
      height: 7
      radius: 3.5
      color: Util.alpha(art.ringColor, 0.32 * art.glow + 0.1)
      Rectangle {
        anchors.centerIn: parent
        width: 2.6
        height: 2.6
        radius: 1.3
        color: Qt.tint(art.ringColor, Util.alpha("#ffffff", 0.6))
      }
    }

    // While it's being looked for: a light running back and forth along
    // the ring.
    Rectangle {
      id: chase
      visible: art.searching
      property real k: 0
      x: 8.5 + (52.5 - width) * k
      y: 157 - height / 2
      width: 18
      height: 3.2
      radius: 1.6
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0) }
        GradientStop { position: 0.5; color: Qt.tint(Color.accent, Util.alpha("#ffffff", 0.5)) }
        GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0) }
      }
      SequentialAnimation on k {
        running: art.searching && art.live
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
      }
    }

    // The glint: a band of light sweeping up the inside of the glass.
    Shape {
      id: glintBand
      visible: art.glintY > -14
      width: 80
      height: 160
      preferredRendererType: Shape.CurveRenderer
      readonly property real bandTop: Math.max(1.5, art.glintY - 9)
      readonly property real bandBottom: Math.min(92, art.glintY + 9)
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: art.glintY - 9; x2: 0; y2: art.glintY + 9
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
          GradientStop { position: 0.5; color: Util.alpha("#ffffff", 0.5) }
          GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0) }
        }
        PathSvg {
          path: {
            var a = glintBand.bandTop, b = glintBand.bandBottom
            if (b <= a) return "M0,0 Z"
            return "M" + art.glassLeft(a) + "," + a + " L" + art.glassRight(a) + "," + a
              + " L" + art.glassRight(b) + "," + b + " L" + art.glassLeft(b) + "," + b + " Z"
          }
        }
      }
    }

    // The arcs off the chamber, glowing in the ring's colour.
    Repeater {
      model: art.arcFlash > 0 ? art.arcs.length : 0
      Shape {
        required property int index
        width: 80
        height: 160
        opacity: art.arcFlash
        preferredRendererType: Shape.CurveRenderer
        // Sized on screen, not in the drawing's units, so an arc reads as a
        // line of light at any size (about 1.6 px with a 4.5 px glow).
        ShapePath {
          strokeColor: Util.alpha(Qt.lighter(art.ringColor, 1.4), 0.35)
          strokeWidth: Math.max(3.2, 4.5 / art.u)
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: art.arcs[index] }
        }
        ShapePath {
          strokeColor: Qt.tint(art.ringColor, Util.alpha("#ffffff", 0.85))
          strokeWidth: Math.max(0.9, 1.6 / art.u)
          fillColor: "transparent"
          joinStyle: ShapePath.MiterJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: art.arcs[index] }
        }
      }
    }

    // Vapour: soft puffs off the bowl, lit from the ring below, curling up
    // the horn and thinning out past its lip.
    Repeater {
      model: art.vapor ? 5 : 0
      Shape {
        id: puff
        required property int index
        property real k: 0
        readonly property real sway: Math.sin(k * Math.PI * 2 + index * 1.7) * 2.2
        readonly property real cx: 25 + (index % 3) * 3 + (15.5 - 25 - (index % 3) * 3) * k + sway
        readonly property real cy: 96 - 104 * k
        readonly property real r: 3.4 + 7.5 * k
        x: cx - 50
        y: cy - 50
        width: 100
        height: 100
        opacity: Math.min(1, k / 0.12) * Math.pow(1 - k, 1.25) * 0.85
        transform: Scale { origin.x: 50; origin.y: 50; xScale: puff.r / 50; yScale: puff.r / 50 * 0.85 }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: 50; centerY: 50; centerRadius: 50
            focalX: 44; focalY: 56
            GradientStop { position: 0.0; color: Util.alpha(Qt.tint("#ffffff", Util.alpha(art.ringColor, 0.22)), 0.55) }
            GradientStop { position: 0.55; color: Util.alpha(Qt.tint("#f2f2f6", Util.alpha(art.ringColor, 0.15)), 0.22) }
            GradientStop { position: 1.0; color: Util.alpha("#f2f2f6", 0) }
          }
          PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
        }
        SequentialAnimation on k {
          running: art.vapor && art.live
          loops: Animation.Infinite
          PauseAnimation { duration: puff.index * 520 }
          NumberAnimation { from: 0; to: 1; duration: 2600; easing.type: Easing.OutSine }
          PauseAnimation { duration: (4 - puff.index) * 520 }
        }
      }
    }

    // Dozing: z's floating up off the chamber, each a little bigger.
    Repeater {
      model: art.dozing ? 3 : 0
      Text {
        id: zed
        required property int index
        property real k: 0
        x: 60 + 20 * k + Math.sin(k * Math.PI * 1.5 + index) * 3
        y: 72 - 58 * k
        scale: 0.6 + 0.65 * k
        opacity: Math.min(1, k / 0.18) * Math.pow(1 - k, 1.1) * 0.95
        textFormat: Text.PlainText
        text: "z"
        color: art.panel ? art.panel.foreground : "white"
        font.family: art.panel && art.panel.displayFamily ? art.panel.displayFamily : Style.font.family
        font.pixelSize: 18 + zed.index * 4
        font.weight: Font.DemiBold
        SequentialAnimation on k {
          running: art.dozing && art.live
          loops: Animation.Infinite
          PauseAnimation { duration: zed.index * 1100 }
          NumberAnimation { from: 0; to: 1; duration: 3300; easing.type: Easing.OutSine }
          PauseAnimation { duration: (2 - zed.index) * 1100 }
        }
      }
    }
  }
}
