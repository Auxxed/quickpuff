import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Smoke rings
// Big soft rings puff out from the widget one after another, widening,
// rocking and drifting apart as they thin out.
Item {
  id: smoke
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real s: smoke.host.u * smoke.host.stage
  readonly property real dir: smoke.host.barAtTop ? 1 : -1
  readonly property color hue: Qt.tint("#f2f2f6", Util.alpha(smoke.host.tint, 0.3))

  Component.onCompleted: smoke.host.cue("smoke")
  NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: smoke.host.finished() }

  Repeater {
    model: 7

    // A circle filled with a soft donut of smoke, in place of a blur (a
    // radial gradient: a faint haze inside, densest round the ring's line,
    // gone at the edge), stretched into a rocking ellipse. Drawn at
    // 100 x 100 and sized by its transform, so it never re-tessellates.
    Shape {
      id: ring
      required property int index
      readonly property real p: Math.max(0, Math.min(1, (smoke.t - index * 0.075) / 0.5))
      readonly property real e: 1 - Math.pow(1 - p, 1.6)
      // How wide it is, how flat (breathing a little as it rolls), and
      // which way this one drifts, so the rings fan out.
      readonly property real across: (120 + 520 * e) * smoke.s
      readonly property real flat: 0.36 + 0.04 * Math.sin(p * Math.PI * 3 + index)
      readonly property real drift: ((index * 5) % 7 - 3) * 34 * smoke.s
      visible: p > 0 && p < 1
      width: 100
      height: 100
      x: Math.max(across / 2, Math.min(smoke.width - across / 2, smoke.host.originX + drift * e + Math.sin(p * Math.PI * 2 + index) * 60 * smoke.s)) - 50
      y: smoke.host.barEdge + smoke.dir * (60 * smoke.s + smoke.height * 0.6 * e) - 50
      opacity: Math.min(1, p / 0.08) * Math.pow(1 - p, 1.3)
      transform: [
        Scale { origin.x: 50; origin.y: 50; xScale: ring.across / 100; yScale: ring.across * ring.flat / 100 },
        Rotation { origin.x: 50; origin.y: 50; angle: 7 * Math.sin(ring.p * Math.PI * 2 + ring.index * 1.3) }
      ]

      ShapePath {
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: 50; centerY: 50; centerRadius: 50
          focalX: 50; focalY: 50
          GradientStop { position: 0.0; color: Util.alpha(smoke.hue, 0.05) }
          GradientStop { position: 0.42; color: Util.alpha(smoke.hue, 0.05) }
          GradientStop { position: 0.6; color: Util.alpha(smoke.hue, 0.2) }
          GradientStop { position: 0.72; color: Util.alpha(smoke.hue, 0.44) }
          GradientStop { position: 0.84; color: Util.alpha(smoke.hue, 0.44) }
          GradientStop { position: 0.94; color: Util.alpha(smoke.hue, 0.14) }
          GradientStop { position: 1.0; color: Util.alpha(smoke.hue, 0) }
        }
        PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
      }
    }
  }

  ReadyWord { host: smoke.host; now: smoke.t * 6.4; at: 0.8; until: 5.6; y: smoke.height * 0.42 }
}
