import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ================================================================ Plasma
// A plasma globe materialises over the desktop on a dark base whose ring
// glows in the profile's colour. Its core ignites and tendrils of light
// reach out to the glass, forking and wandering, flickering, with bright
// points where they touch; READY sits under the base.
Item {
  id: globe
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.4
  readonly property real now: t * dur
  readonly property real s: globe.host.u * globe.host.stage
  readonly property real cx: width * 0.5
  readonly property real cy: height * 0.42
  readonly property real r: height * 0.27
  readonly property real dark: Math.min(1, now / 0.6) * Math.max(0, Math.min(1, (dur - now) / 0.9))
  // The core lighting, then the tendrils reaching out to the glass.
  readonly property real ignite: Math.max(0, Math.min(1, (now - 0.55) / 0.35))
  readonly property real reach: 1 - Math.pow(1 - Math.max(0, Math.min(1, (now - 0.7) / 0.8)), 3)
  readonly property color hot: Qt.lighter(globe.host.tint, 1.5)
  readonly property color cool: globe.host.hueTurn(0.75, 0.85, 0.65)
  readonly property int count: 9

  NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: globe.host.finished() }
  Component.onCompleted: globe.host.cue("plasma")

  // Where tendril `i` leaves the glass now, and its points out from the
  // core: a wandering angle, a fast jitter along its length.
  function angleOf(i) {
    // Spread round the core, each a little off its slot, so they never
    // bunch up on one side.
    var a = (i + 0.5 + 0.9 * (globe.host.hash(i * 3.7) - 0.5)) / count * 6.283
    return a + 0.7 * Math.sin(now * (0.5 + 0.4 * globe.host.hash(i * 1.3)) + i) + 0.25 * Math.sin(now * 1.7 + i * 2.3)
  }
  function tendril(i, from, to, n) {
    var a = angleOf(i), out = []
    var r0 = r * 0.1, r1 = r0 + (r * 0.93 - r0) * reach
    for (var k = from; k <= to; k++) {
      var f = k / n
      var jitter = (Math.sin(k * 1.7 + now * 11 + i * 3) * 0.07 + Math.sin(k * 3.3 - now * 17 + i) * 0.04) * f
      var rr = r0 + (r1 - r0) * f
      out.push(Qt.point(cx + Math.cos(a + jitter) * rr, cy + Math.sin(a + jitter) * rr))
    }
    return out
  }
  function forkOf(i) {
    var a = angleOf(i) + (i % 2 ? 0.32 : -0.32), out = []
    var base = tendril(i, 11, 11, 16)[0]
    var r0 = Math.sqrt((base.x - cx) * (base.x - cx) + (base.y - cy) * (base.y - cy))
    for (var k = 0; k <= 4; k++) {
      var rr = r0 + (r * 0.9 * reach - r0) * (k / 4) * 0.85
      out.push(k === 0 ? base : Qt.point(cx + Math.cos(a + Math.sin(k * 2 + now * 13) * 0.03) * rr, cy + Math.sin(a + Math.sin(k * 2 + now * 13) * 0.03) * rr))
    }
    return out
  }

  Rectangle { anchors.fill: parent; color: "#05020c"; opacity: 0.66 * globe.dark }

  // The base, with its ring of light.
  Shape {
    anchors.fill: parent
    opacity: globe.dark
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Util.alpha("#ffffff", 0.12)
      strokeWidth: 1
      fillGradient: LinearGradient {
        x1: 0; y1: globe.cy + globe.r * 0.9; x2: 0; y2: globe.cy + globe.r * 1.45
        GradientStop { position: 0.0; color: "#26232c" }
        GradientStop { position: 1.0; color: "#08070a" }
      }
      PathSvg {
        path: {
          var x0 = globe.cx, y0 = globe.cy + globe.r * 0.92, w = globe.r * 0.55, w2 = globe.r * 0.8, h = globe.r * 0.5
          return "M " + (x0 - w) + " " + y0 + " L " + (x0 + w) + " " + y0 + " L " + (x0 + w2) + " " + (y0 + h)
            + " L " + (x0 - w2) + " " + (y0 + h) + " Z"
        }
      }
    }
  }
  Rectangle {
    x: globe.cx - globe.r * 0.78
    y: globe.cy + globe.r * 1.38
    width: globe.r * 1.56
    height: Math.max(2, 3 * globe.s)
    radius: height / 2
    color: Qt.tint(globe.host.tint, Util.alpha("#ffffff", 0.25))
    opacity: globe.dark * globe.ignite
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 1.05
      height: parent.height * 6
      radius: height / 2
      color: Util.alpha(globe.host.tint, 0.25)
      z: -1
    }
  }

  // The glass: a faint violet body with a rim and a highlight.
  Rectangle {
    x: globe.cx - globe.r
    y: globe.cy - globe.r
    width: globe.r * 2
    height: width
    radius: width / 2
    opacity: globe.dark
    color: Util.alpha(Qt.tint("#140a24", Util.alpha(globe.host.tint, 0.15)), 0.55)
    border.width: Math.max(1, 1.5 * globe.s)
    border.color: Util.alpha("#e8deff", 0.3)
  }
  // The glass catching the light: a soft sweep along its upper left
  // rim, brightest in the middle.
  Shape {
    anchors.fill: parent
    opacity: globe.dark
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Util.alpha("#ffffff", 0.08)
      strokeWidth: 9 * globe.s
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: globe.cx; centerY: globe.cy; radiusX: globe.r * 0.86; radiusY: globe.r * 0.86; startAngle: 196; sweepAngle: 62 }
    }
    ShapePath {
      strokeColor: Util.alpha("#ffffff", 0.26)
      strokeWidth: 3 * globe.s
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: globe.cx; centerY: globe.cy; radiusX: globe.r * 0.86; radiusY: globe.r * 0.86; startAngle: 208; sweepAngle: 38 }
    }
  }

  // The tendrils and the core, drawn through a bloom.
  Item {
    id: plasma
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    SoftGlow {
      hue: Util.alpha(globe.cool, 0.35)
      x: globe.cx - 50
      y: globe.cy - 50
      scale: globe.r * 1.6 / 100
      opacity: globe.ignite * (0.6 + 0.2 * Math.sin(globe.now * 3))
    }
    Repeater {
      model: globe.count
      Shape {
        required property int index
        anchors.fill: parent
        visible: globe.reach > 0
        opacity: 0.55 + 0.45 * Math.pow(Math.sin(globe.now * (14 + index) + index * 5), 2)
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Util.alpha(index % 3 === 0 ? globe.cool : globe.host.tint, 0.4)
          strokeWidth: 9 * globe.s
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: globe.tendril(index, 0, 16, 16) }
        }
        ShapePath {
          strokeColor: Qt.tint(globe.hot, Util.alpha("#ffffff", 0.55))
          strokeWidth: 1.8 * globe.s
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: globe.tendril(index, 0, 16, 16) }
        }
        ShapePath {
          strokeColor: Util.alpha(Qt.tint(globe.hot, Util.alpha(globe.host.tint, 0.3)), 0.45)
          strokeWidth: 1.1 * globe.s
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: globe.reach > 0.6 ? globe.forkOf(index) : [Qt.point(0, 0), Qt.point(0, 0)] }
        }
      }
    }
    // Where each one touches the glass.
    Repeater {
      model: globe.count
      SoftGlow {
        required property int index
        readonly property real a: globe.angleOf(index)
        hue: Qt.tint(globe.hot, Util.alpha("#ffffff", 0.4))
        x: globe.cx + Math.cos(a) * globe.r * 0.93 - 50
        y: globe.cy + Math.sin(a) * globe.r * 0.93 - 50
        scale: (12 + 5 * Math.sin(globe.now * 9 + index)) * globe.s / 100
        opacity: globe.reach > 0.95 ? 0.9 : 0
      }
    }
    // The core.
    SoftGlow {
      hue: "#ffffff"
      x: globe.cx - 50
      y: globe.cy - 50
      scale: globe.r * (0.16 + 0.03 * Math.sin(globe.now * 7)) / 100
      opacity: globe.ignite
    }
    SoftGlow {
      hue: globe.hot
      x: globe.cx - 50
      y: globe.cy - 50
      scale: globe.r * 0.42 / 100
      opacity: 0.7 * globe.ignite
    }
  }
  MultiEffect {
    anchors.fill: plasma
    source: plasma
    blurEnabled: true
    blurMax: 40
    blur: 0.8
    brightness: 0.3
    opacity: globe.dark
  }
  MultiEffect {
    anchors.fill: plasma
    source: plasma
    opacity: globe.dark
  }

  Text {
    readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (globe.now - 1.6) / 1.2)), 3)
    anchors.horizontalCenter: parent.horizontalCenter
    y: globe.cy + globe.r * 1.62
    opacity: e * globe.dark
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.tint("#ffffff", Util.alpha(globe.host.tint, 0.3))
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
      blurMax: 24
      shadowBlur: 0.55
      shadowColor: Util.alpha(globe.hot, 0.6)
    }
    font.family: globe.host.displayFamily
    font.pixelSize: 60 * globe.s
    font.weight: Font.DemiBold
    font.letterSpacing: (15 + 36 * (1 - e)) * globe.s
  }
}
