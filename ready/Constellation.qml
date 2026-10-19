import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ========================================================= Constellation
// Night falls over the desktop: the Milky Way spills across it and its
// stars come out. Then stars ignite one after another, each with a ripple
// of light, and draw your Peak Pro between them in fine glowing lines. A
// shooting star dives in and lights its ring in the profile's colour; the
// figure fills softly with light, as if it had come alive, and READY
// appears beside it like a name on a star chart.
Item {
  id: sky
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.6
  readonly property real now: t * dur
  readonly property real s: sky.host.u * sky.host.stage
  readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
  // The Peak's outline as stars, on the panel drawing's 80 x 160 grid,
  // going round from the top of the glass. Edge 8 → 9 is the light ring;
  // edge 12 is the glass's chrome seat, drawn last.
  readonly property var pts: [[12.5, 1.5], [21.5, 0.8], [46, 93], [49.5, 80.5], [71, 80.5], [72.5, 104],
    [56, 113.5], [64.5, 152], [60, 158], [9.5, 158], [6.5, 111.5], [9.5, 108]]
  readonly property var edges: [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 0], [11, 2]]
  readonly property real k: height * 0.6 / 160
  readonly property real ox: width * 0.46 - 40 * k
  readonly property real oy: height * 0.48 - 80 * k
  function px(i) { return ox + pts[i][0] * k }
  function py(i) { return oy + pts[i][1] * k }
  function litAt(i) { return 0.8 + i * 0.16 }
  function edgeAt(e) { return e < 12 ? litAt(e) + 0.08 : litAt(11) + 0.35 }
  readonly property real shootAt: litAt(11) + 0.6
  readonly property real shotP: Math.max(0, Math.min(1, (now - shootAt) / 0.5))
  // The ring lighting up once the shooting star lands, and the figure
  // filling with light after it.
  readonly property real ringK: Math.max(0, Math.min(1, (now - shootAt - 0.5) / 0.35))
  readonly property real alive: Math.max(0, Math.min(1, (now - shootAt - 0.7) / 0.9))
  property bool shot: false

  NumberAnimation on t { from: 0; to: 1; duration: 6600; running: true; onFinished: sky.host.finished() }
  onRingKChanged: if (ringK > 0 && !shot) { shot = true; sky.host.cue("shimmer"); ringSparks.fire() }

  // Night.
  Rectangle {
    anchors.fill: parent
    opacity: sky.dark
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha("#02030f", 0.9) }
      GradientStop { position: 0.6; color: Util.alpha("#040920", 0.8) }
      GradientStop { position: 1.0; color: Util.alpha("#060c26", 0.62) }
    }
  }

  // The Milky Way: a faint, misty river of light across the sky, veined
  // with dark dust and thick with stars.
  Item {
    anchors.fill: parent
    opacity: sky.dark * Math.min(1, sky.now / 1.4)
    Item {
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect { blurEnabled: true; blurMax: 48; blur: 0.8 }
      Repeater {
        model: 16
        SoftGlow {
          required property int index
          readonly property real f: sky.host.hash(index * 3.7)
          hue: Util.alpha(index % 4 === 1 ? "#a99cff" : "#b8c8ff", 0.09 + 0.07 * sky.host.hash(index * 1.3))
          x: sky.width * (-0.05 + 1.1 * f) + (sky.host.hash(index * 6.1) - 0.5) * sky.height * 0.05 - 50
          y: sky.height * (0.85 - 0.75 * f) + (sky.host.hash(index * 5.3) - 0.5) * sky.height * 0.1 - 50
          transform: [
            Scale { origin.x: 50; origin.y: 50; xScale: sky.width * (0.16 + 0.18 * sky.host.hash(index * 2.9)) / 100; yScale: sky.height * (0.1 + 0.14 * sky.host.hash(index * 7.3)) / 100 },
            Rotation { origin.x: 50; origin.y: 50; angle: -34 + (sky.host.hash(index * 8.8) - 0.5) * 16 }
          ]
        }
      }
      Repeater {
        model: 5
        SoftGlow {
          required property int index
          readonly property real f: 0.12 + index * 0.19 + (sky.host.hash(index * 4.1) - 0.5) * 0.08
          hue: Util.alpha("#010208", 0.45)
          x: sky.width * (-0.05 + 1.1 * f) - 50
          y: sky.height * (0.85 - 0.75 * f) - 50
          transform: [
            Scale { origin.x: 50; origin.y: 50; xScale: sky.width * 0.14 / 100; yScale: sky.height * 0.025 / 100 },
            Rotation { origin.x: 50; origin.y: 50; angle: -30 }
          ]
        }
      }
    }
    Repeater {
      model: 260
      Rectangle {
        required property int index
        readonly property real f: sky.host.hash(index * 2.17)
        // Gathered close about the river's middle, thinning out from it.
        readonly property real off: (sky.host.hash(index * 6.61) + sky.host.hash(index * 9.03) - 1) * sky.height * 0.16
        width: (0.7 + 1.3 * sky.host.hash(index * 4.4)) * sky.s
        height: width
        radius: width / 2
        x: sky.width * (-0.05 + 1.1 * f) + off * 0.56
        y: sky.height * (0.85 - 0.75 * f) + off * 0.83
        color: "#e0e7ff"
        opacity: 0.25 + 0.6 * Math.abs(Math.sin(sky.now * (1 + sky.host.hash(index)) + index))
      }
    }
  }

  // Far stars, coming out one by one and twinkling, a few of them big.
  Repeater {
    model: 120
    Item {
      required property int index
      readonly property real a: sky.host.hash(index * 1.77)
      readonly property real b: sky.host.hash(index * 5.03)
      readonly property real c: sky.host.hash(index * 9.41)
      readonly property bool big: index % 12 === 0
      readonly property real twinkle: 0.3 + 0.7 * Math.abs(Math.sin(sky.now * (0.8 + 2.2 * a) + index * 1.3))
      x: a * sky.width
      y: b * sky.height * 0.92
      opacity: sky.dark * Math.min(1, Math.max(0, (sky.now - c * 1.2) / 0.6)) * twinkle

      Rectangle {
        width: (1 + 2 * c * c) * sky.s
        height: width
        radius: width / 2
        x: -width / 2
        y: -height / 2
        color: c > 0.85 ? "#fff1d6" : "#dbe5ff"
      }
      Image {
        visible: parent.big
        source: Qt.resolvedUrl("../particles/spark.png")
        width: (16 + 10 * parent.twinkle) * sky.s
        height: width
        x: -width / 2
        y: -height / 2
        smooth: true
      }
    }
  }

  // The figure filling with light, once it's alive.
  Shape {
    anchors.fill: parent
    opacity: 0.22 * sky.alive * sky.dark
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillGradient: LinearGradient {
        x1: 0; y1: sky.py(0); x2: 0; y2: sky.py(8)
        GradientStop { position: 0.0; color: Util.alpha("#bcd0ff", 0.4) }
        GradientStop { position: 1.0; color: sky.host.tint }
      }
      PathPolyline {
        path: {
          var out = []
          for (var i = 0; i <= sky.pts.length; i++) out.push(Qt.point(sky.px(i % sky.pts.length), sky.py(i % sky.pts.length)))
          return out
        }
      }
    }
  }

  // The lines between the stars, drawing themselves once both ends burn.
  Repeater {
    model: sky.edges.length
    Item {
      required property int index
      readonly property int i0: sky.edges[index][0]
      readonly property int i1: sky.edges[index][1]
      readonly property real x0: sky.px(i0)
      readonly property real y0: sky.py(i0)
      readonly property real x1: sky.px(i1)
      readonly property real y1: sky.py(i1)
      readonly property real len: Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
      readonly property real p: Math.max(0, Math.min(1, (sky.now - sky.edgeAt(index)) / 0.32))
      readonly property bool ring: index === 8
      readonly property color ink: ring ? Qt.tint("#cfdcff", Util.alpha(sky.host.tint, sky.ringK))
        : Qt.tint("#cfdcff", Util.alpha(sky.host.tint, 0.35 * sky.alive))
      x: x0
      y: y0
      rotation: Math.atan2(y1 - y0, x1 - x0) * 180 / Math.PI
      transformOrigin: Item.TopLeft
      opacity: sky.dark * (index === 12 ? 0.7 : 1)

      Rectangle {
        y: -height / 2
        width: parent.len * parent.p
        height: (parent.ring ? 10 + 16 * sky.ringK : 9) * sky.s
        radius: height / 2
        color: Util.alpha(parent.ink, parent.ring ? 0.2 + 0.25 * sky.ringK : 0.17 + 0.08 * sky.alive)
      }
      Rectangle {
        y: -height / 2
        width: parent.len * parent.p
        height: (parent.ring ? 2 + 2.4 * sky.ringK : 1.7) * sky.s
        radius: height / 2
        color: parent.ink
      }
    }
  }

  // Light pooling under the ring once it's lit.
  SoftGlow {
    hue: sky.host.tint
    x: (sky.px(8) + sky.px(9)) / 2 - 50
    y: sky.py(8) - 50
    opacity: 0.5 * sky.ringK * sky.dark
    transform: Scale { origin.x: 50; origin.y: 50; xScale: (sky.px(8) - sky.px(9)) * 1.9 / 100; yScale: 70 * sky.s / 100 }
  }

  // The stars themselves: a ripple and a flare as each ignites, then a
  // steady twinkle.
  Repeater {
    model: 12
    Item {
      required property int index
      readonly property real f: Math.max(0, Math.min(1, (sky.now - sky.litAt(index)) / 0.6))
      readonly property real flare: f <= 0 ? 0 : (f < 0.2 ? f / 0.2 : 1 - 0.72 * (f - 0.2) / 0.8)
      x: sky.px(index)
      y: sky.py(index)
      opacity: f > 0 ? sky.dark : 0

      Rectangle {
        readonly property real rp: Math.min(1, parent.f * 1.4)
        width: (10 + 90 * rp) * sky.s
        height: width
        radius: width / 2
        x: -width / 2
        y: -height / 2
        color: "transparent"
        border.width: Math.max(1, 1.4 * sky.s)
        border.color: Util.alpha("#cfdcff", 0.7)
        opacity: rp < 1 ? Math.pow(1 - rp, 1.5) : 0
      }
      SoftGlow {
        hue: Util.alpha(Qt.tint("#bcd0ff", Util.alpha(sky.host.tint, 0.5 * sky.alive)), 0.75)
        x: -50
        y: -50
        scale: (18 + 44 * parent.flare + 8 * sky.alive) * sky.s / 100
      }
      Image {
        source: Qt.resolvedUrl("../particles/spark.png")
        width: (16 + 56 * parent.flare + 6 * Math.sin(sky.now * 5 + parent.index)) * sky.s
        height: width
        x: -width / 2
        y: -height / 2
        rotation: 40 * (1 - parent.f)
        smooth: true
      }
      Rectangle {
        width: 4.5 * sky.s
        height: width
        radius: width / 2
        x: -width / 2
        y: -height / 2
        color: "#ffffff"
      }
    }
  }

  // The shooting star, diving in from the top right to the end of the ring.
  Item {
    id: comet
    readonly property real sx: sky.width * 0.97
    readonly property real sy: sky.height * 0.02
    readonly property real ex: sky.px(8)
    readonly property real ey: sky.py(8)
    readonly property real e: sky.shotP * sky.shotP
    x: sx + (ex - sx) * e
    y: sy + (ey - sy) * e
    visible: sky.shotP > 0 && sky.shotP < 1
    rotation: Math.atan2(ey - sy, ex - sx) * 180 / Math.PI

    Rectangle {
      x: -width
      y: -height / 2
      width: 420 * sky.s
      height: 14 * sky.s
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha(sky.host.tint, 0) }
        GradientStop { position: 1.0; color: Util.alpha(Qt.lighter(sky.host.tint, 1.5), 0.35) }
      }
    }
    Rectangle {
      x: -width
      y: -height / 2
      width: 380 * sky.s
      height: 3.5 * sky.s
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
        GradientStop { position: 1.0; color: "#ffffff" }
      }
    }
    SoftGlow { hue: "#ffffff"; x: -50; y: -50; scale: 40 * sky.s / 100 }
  }
  Sparks {
    host: sky.host
    id: ringSparks
    x: sky.px(8)
    y: sky.py(8)
    count: 16
    reach: 90 * sky.s
    dot: 4.5 * sky.s
    hues: ["#ffffff", Qt.lighter(sky.host.tint, 1.5), sky.host.tint]
  }

  // READY, like a name on a star chart.
  Text {
    readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (sky.now - sky.shootAt - 0.8) / 1.0)), 3)
    x: sky.px(5) + 54 * sky.s
    y: sky.py(5) - height / 2
    opacity: e * sky.dark
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.tint("#f2f5ff", Util.alpha(sky.host.tint, 0.25))
    // Starlight round the letters.
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
      blurMax: 20
      shadowBlur: 0.5
      shadowColor: Util.alpha("#cfdcff", 0.6)
    }
    font.family: sky.host.displayFamily
    font.pixelSize: 58 * sky.s
    font.weight: Font.DemiBold
    font.letterSpacing: (14 + 26 * (1 - e)) * sky.s
  }
}
