import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// A whale shark in side view, gliding: the broad flat head and wide mouth,
// gill slits, ridges running down its flanks, the white checkerboard of
// spots, a tall dorsal fin, a pectoral that rows gently and a crescent tail
// sweeping as it swims, with a remora under its belly and pilot fish riding
// its bow wave. Drawn on a body 1000 units long (head to the right, centred
// on 500, 120) and scaled to `len` pixels; `haze` (0-1) sinks it into the
// blue with distance.
Item {
  id: shark
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real len: 600
  property real haze: 0
  // 1 swims right, -1 left.
  property int facing: 1
  // Seconds, driving the tail and fins.
  property real swim: 0
  // Degrees, nose up.
  property real pitch: 0

  readonly property color water: "#0b3550"
  function hazed(c, amount) { return Qt.tint(c, Util.alpha(water, Math.min(1, haze * amount))) }
  readonly property real stroke: Math.sin(swim * 2 * Math.PI / 2.6)
  readonly property color back: hazed("#4d6a7c", 1)
  readonly property color flank: hazed("#213646", 1)
  readonly property color belly: hazed("#93a8b4", 0.9)
  readonly property color mark: hazed("#e8f4ff", 0.85)

  // The outline, as its top and bottom edges from tail to snout.
  readonly property var topEdge: [[90, 114], [130, 108], [200, 92], [300, 70], [420, 47], [560, 33], [700, 35],
    [850, 48], [950, 70], [985, 88], [1000, 104]]
  readonly property var bottomEdge: [[90, 128], [160, 132], [260, 148], [380, 172], [500, 192], [640, 200],
    [780, 196], [900, 177], [960, 153], [990, 136], [1000, 124]]
  function edgeAt(edge, x) {
    for (var i = 0; i < edge.length - 1; i++) {
      if (x <= edge[i + 1][0]) {
        var f = (x - edge[i][0]) / (edge[i + 1][0] - edge[i][0])
        return edge[i][1] + (edge[i + 1][1] - edge[i][1]) * f
      }
    }
    return edge[edge.length - 1][1]
  }
  // A closed path through the outline's points, smoothed through their
  // midpoints.
  readonly property string bodyPath: {
    var pts = topEdge.slice().reverse().concat([[80, 121]]).concat(bottomEdge)
    pts.splice(0, 0, [1003, 114])
    var d = "M " + pts[0][0] + " " + pts[0][1]
    for (var i = 1; i < pts.length - 1; i++)
      d += " Q " + pts[i][0] + " " + pts[i][1] + " " + (pts[i][0] + pts[i + 1][0]) / 2 + " " + (pts[i][1] + pts[i + 1][1]) / 2
    return d + " L " + pts[pts.length - 1][0] + " " + pts[pts.length - 1][1] + " Z"
  }
  // The spots: loose columns over the back and upper flank, small and
  // close on the head, each nudged and sized a little differently (and a
  // few missing) so they read as a pattern, not a grid; pale stripes
  // between the columns, and the ridges running along the flank.
  readonly property string spotPath: {
    var d = ""
    function dot(x, y, r) { d += " M " + (x - r) + " " + y + " a " + r + " " + r + " 0 1 0 " + (2 * r) + " 0 a " + r + " " + r + " 0 1 0 " + (-2 * r) + " 0" }
    var c = 0, n = 0
    for (var x = 140; x < 960; c++) {
      var head = x > 820
      var t = edgeAt(topEdge, x), b = edgeAt(bottomEdge, x)
      var low = t + (b - t) * (head ? 0.75 : 0.62)
      var gap = head ? 13 : 18
      var r = (head ? 2.2 : 3.4) * (0.75 + 0.25 * Math.min(1, x / 400))
      for (var y = t + 9 + (c % 2) * gap / 2; y < low; y += gap) {
        n++
        if (shark.host.hash(n * 2.71) < 0.1) continue
        var jx = (shark.host.hash(n * 1.37) - 0.5) * (head ? 5 : 9)
        var jy = (shark.host.hash(n * 3.11) - 0.5) * (head ? 4 : 7)
        dot(x + jx, Math.min(low, y + jy), r * (0.7 + 0.6 * shark.host.hash(n * 0.83)))
      }
      x += (head ? 15 : 26) * (0.85 + 0.3 * shark.host.hash(c * 5.3))
    }
    return d
  }
  readonly property string barPath: {
    var d = ""
    for (var x = 262; x <= 820; x += 34 + 10 * shark.host.hash(x * 0.17)) {
      var t = edgeAt(topEdge, x), b = edgeAt(bottomEdge, x)
      var bow = (shark.host.hash(x * 0.29) - 0.5) * 6
      d += " M " + x + " " + (t + 5) + " Q " + (x + 2 + bow) + " " + (t + (b - t) * 0.3) + " " + (x + 4) + " " + (t + (b - t) * 0.58)
    }
    // The ridges along the flank.
    for (var k = 0; k < 2; k++) {
      var f = k ? 0.42 : 0.26
      d += " M 300 " + (edgeAt(topEdge, 300) + (edgeAt(bottomEdge, 300) - edgeAt(topEdge, 300)) * f)
      for (var rx = 360; rx <= 820; rx += 60) {
        var rt = edgeAt(topEdge, rx), rb = edgeAt(bottomEdge, rx)
        d += " L " + rx + " " + (rt + (rb - rt) * f)
      }
    }
    return d
  }

  Item {
    width: 1000
    height: 400
    transform: [
      Translate { x: -500; y: -120 },
      Scale { xScale: shark.len / 1000 * shark.facing; yScale: shark.len / 1000 },
      Rotation { angle: -shark.pitch * shark.facing }
    ]

    // The tail, sweeping from the root of the body.
    Shape {
      width: 1000
      height: 400
      preferredRendererType: Shape.CurveRenderer
      transform: Rotation { origin.x: 92; origin.y: 121; angle: shark.stroke * 8 }
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: -60; x2: 0; y2: 215
          GradientStop { position: 0.0; color: shark.back }
          GradientStop { position: 1.0; color: shark.flank }
        }
        PathSvg { path: "M 102 110 C 70 80 20 20 -78 -58 C -62 -10 -46 40 -14 104 L -10 121 C -30 155 -42 185 -52 214 C 10 186 58 156 102 132 Z" }
      }
    }

    // The fins along the back and belly, their roots under the body.
    Shape {
      width: 1000
      height: 400
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: -58; x2: 0; y2: 226
          GradientStop { position: 0.0; color: shark.back }
          GradientStop { position: 0.5; color: shark.flank }
          GradientStop { position: 1.0; color: Qt.darker(shark.belly, 1.4) }
        }
        PathSvg { path: "M 585 36 C 552 -6 512 -40 474 -58 C 466 -50 462 -32 460 -14 C 456 10 446 32 425 49 Z M 262 81 C 250 68 236 58 222 52 C 220 66 214 80 205 93 Z M 432 182 C 417 198 402 213 384 226 C 386 210 388 192 390 178 Z M 264 149 C 252 161 238 173 224 181 C 224 169 224 158 222 146 Z" }
      }
    }

    // The body: lit from above, dark down the flank, pale underneath.
    Shape {
      width: 1000
      height: 400
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: Util.alpha(shark.mark, 0.12)
        strokeWidth: 1.2
        fillGradient: LinearGradient {
          x1: 0; y1: 30; x2: 0; y2: 202
          GradientStop { position: 0.0; color: shark.back }
          GradientStop { position: 0.55; color: shark.flank }
          GradientStop { position: 1.0; color: shark.belly }
        }
        PathSvg { path: shark.bodyPath }
      }
      // Spots and pale bars.
      ShapePath {
        strokeColor: "transparent"
        fillColor: Util.alpha(shark.mark, 0.62 * (1 - 0.4 * shark.haze))
        PathSvg { path: shark.spotPath }
      }
      ShapePath {
        strokeColor: Util.alpha(shark.mark, 0.2 * (1 - 0.5 * shark.haze))
        strokeWidth: 2.4
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: shark.barPath }
      }
      // Ridges down the flank.
      ShapePath {
        strokeColor: Util.alpha(shark.mark, 0.22 * (1 - 0.5 * shark.haze))
        strokeWidth: 1.6
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: "M 905 72 Q 600 44 180 100 M 885 106 Q 600 110 165 117 M 860 150 Q 600 166 210 134" }
      }
      // Gill slits, the mouth and the eye.
      ShapePath {
        strokeColor: Util.alpha("#05121b", 0.55)
        strokeWidth: 2.2
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: "M 842 90 Q 832 132 842 172 M 855 88 Q 845 130 855 169 M 868 86 Q 858 128 868 166 M 881 84 Q 872 125 881 162 M 894 82 Q 886 122 894 158 M 1003 122 Q 980 134 952 138" }
      }
      ShapePath {
        strokeColor: "transparent"
        fillColor: Util.alpha("#05121b", 0.8)
        PathSvg { path: "M 928 102 a 4.5 4.5 0 1 0 9 0 a 4.5 4.5 0 1 0 -9 0" }
      }
    }

    // The near pectoral fin, rowing slowly.
    Shape {
      width: 1000
      height: 400
      preferredRendererType: Shape.CurveRenderer
      transform: Rotation { origin.x: 735; origin.y: 194; angle: Math.sin(shark.swim * 2 * Math.PI / 2.6 + 1) * 5 }
      ShapePath {
        strokeColor: Util.alpha(shark.mark, 0.1)
        strokeWidth: 1
        fillGradient: LinearGradient {
          x1: 0; y1: 190; x2: 0; y2: 312
          GradientStop { position: 0.0; color: shark.flank }
          GradientStop { position: 1.0; color: Qt.darker(shark.flank, 1.3) }
        }
        PathSvg { path: "M 778 190 C 748 240 702 284 605 312 C 612 302 640 278 668 244 C 682 226 690 210 695 198 Z" }
      }
    }

    // A remora riding under the belly, and pilot fish in the bow wave.
    Shape {
      width: 1000
      height: 400
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillColor: shark.hazed("#2c3c46", 1)
        PathSvg { path: "M 600 206 C 618 200 650 200 672 205 C 650 211 618 212 600 206 Z M 600 206 L 588 200 L 590 212 Z" }
      }
    }
    Repeater {
      model: 5
      Shape {
        required property int index
        width: 40
        height: 20
        x: 1030 + (index % 3) * 26 + Math.sin(shark.swim * 1.7 + index) * 5
        y: 110 + index * 14 + Math.cos(shark.swim * 1.3 + index * 2) * 4
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillColor: shark.hazed("#c9d6dd", 1)
          PathSvg { path: "M 4 10 C 12 4 26 4 34 10 C 26 16 12 16 4 10 Z M 4 10 L -4 5 L -4 15 Z" }
        }
        ShapePath {
          strokeColor: Util.alpha(shark.hazed("#1d2a33", 1), 0.8)
          strokeWidth: 2
          fillColor: "transparent"
          PathSvg { path: "M 12 6 L 12 14 M 20 5 L 20 15 M 28 6 L 28 14" }
        }
      }
    }
  }
}
