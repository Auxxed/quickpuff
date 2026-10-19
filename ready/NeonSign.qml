import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Neon sign
// A neon Peak and READY buzz on in the middle of a dimmed screen, flicker,
// hum for a moment over their reflection on the floor, then switch off.
Item {
  id: neon
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 5.0
  readonly property real s: neon.host.u * 1.45 * neon.host.stage
  // Coloured glass round a white-hot core.
  readonly property color glass: Qt.lighter(neon.host.tint, 1.3)
  readonly property color core: Qt.tint("#ffffff", Util.alpha(neon.host.tint, 0.25))
  // On, off, on, stutter, steady... then a fade. Timed in milliseconds, so
  // the flicker-on keeps its rhythm (and stays with its sound).
  readonly property real power: {
    var ms = t * dur * 1000
    if (ms < 90) return 0
    if (ms < 180) return 1
    if (ms < 270) return 0.15
    if (ms < 405) return 1
    if (ms < 450) return 0.4
    if (t > 0.82) return Math.max(0, (1 - t) / 0.18)
    return 0.92 + 0.08 * Math.sin(t * dur * 20)
  }
  // The room going dark behind it as the sign catches, and back as it
  // switches off.
  readonly property real dark: Math.max(0, Math.min(1, t * dur / 0.45, (1 - t) / 0.18))
  // The panel's Peak drawing, in tube.
  readonly property string peakPath: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z M72.3,104.4 C52,116 24,136 6.8,150.6 M51.5,80.5 H69 Q71,80.5 71,82.5 V89 Q71,91 69,91 H51.5 Q49.5,91 49.5,89 V82.5 Q49.5,80.5 51.5,80.5 Z"

  Component.onCompleted: neon.host.cue("neon")
  NumberAnimation on t { from: 0; to: 1; duration: 5000; running: true; onFinished: neon.host.finished() }

  TextMetrics {
    id: word
    font.family: neon.host.displayFamily
    font.pixelSize: 110 * neon.s
    font.weight: Font.DemiBold
    font.letterSpacing: 6 * neon.s
    text: "READY"
  }

  // Dim the desktop while the sign is lit, so it pops on any wallpaper.
  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: 0.32 * neon.dark
  }

  Item {
    id: sign
    // Room round the tubes for the glow and the reflection's blur.
    readonly property real pad: 28 * neon.s
    // The Peak drawing's scale, the tube and its core, and the floor line
    // the Peak stands on.
    readonly property real k: 230 * neon.s / 166
    readonly property real tube: 2.6 * k
    readonly property real wire: 0.9 * k
    readonly property real floor: pad + 161 * k
    width: 2 * pad + 80 * k + 30 * neon.s + word.advanceWidth + 10 * neon.s
    height: 2 * pad + 230 * neon.s
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -neon.height * 0.06
    visible: false
    layer.enabled: true

    // The Peak, in tube outline (the same paths as the panel's drawing).
    Shape {
      x: sign.pad + 3 * sign.k
      y: sign.pad + 3 * sign.k
      width: 80
      height: 160
      transform: Scale { xScale: sign.k; yScale: sign.k }
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: neon.glass
        strokeWidth: 2.6
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: neon.peakPath }
      }
      ShapePath {
        strokeColor: neon.core
        strokeWidth: 0.9
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: neon.peakPath }
      }
    }

    // READY, its letters outlined in the same tube, their middle 60% of
    // the way down the sign (PathText puts the top of the letters at y).
    Shape {
      x: sign.pad + 80 * sign.k + 30 * neon.s
      y: sign.pad + 138 * neon.s - word.tightBoundingRect.height / 2
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: neon.glass
        strokeWidth: sign.tube
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathText { text: word.text; font: word.font }
      }
      ShapePath {
        strokeColor: neon.core
        strokeWidth: sign.wire
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathText { text: word.text; font: word.font }
      }
    }
  }

  // Its light pooling on the floor...
  SoftGlow {
    hue: neon.glass
    x: sign.x + sign.width / 2 - 50
    y: sign.y + sign.floor - 50
    transform: Scale { origin.x: 50; origin.y: 50; xScale: sign.width * 1.2 / 100; yScale: sign.height * 0.3 / 100 }
    opacity: 0.16 * neon.power
  }

  // ...and its reflection: flipped about the floor, squashed, blurred and
  // fading out away from the sign. The fade is drawn unflipped: clear at
  // the top, solid at the floor, nothing below it.
  Item {
    id: floorFade
    width: sign.width
    height: sign.height
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: sign.floor / sign.height * 0.55; color: Util.alpha("white", 0.2) }
        GradientStop { position: sign.floor / sign.height; color: "white" }
        GradientStop { position: Math.min(1, sign.floor / sign.height + 0.01); color: "transparent" }
      }
    }
  }
  MultiEffect {
    anchors.fill: sign
    source: sign
    transform: Scale { origin.y: sign.floor; yScale: -0.5 }
    autoPaddingEnabled: false
    blurEnabled: true
    blurMax: 24
    blur: 0.6
    maskEnabled: true
    maskSource: floorFade
    opacity: 0.3 * neon.power
  }

  // The glow, wide to tight, and the tubes, crisp, on top of it.
  MultiEffect {
    anchors.fill: sign
    source: sign
    blurEnabled: true
    blurMax: 64
    blur: 1
    brightness: 0.5
    opacity: neon.power
  }
  MultiEffect {
    anchors.fill: sign
    source: sign
    blurEnabled: true
    blurMax: 32
    blur: 0.8
    brightness: 0.35
    opacity: neon.power
  }
  MultiEffect {
    anchors.fill: sign
    source: sign
    blurEnabled: true
    blurMax: 12
    blur: 0.6
    brightness: 0.2
    opacity: neon.power
  }
  MultiEffect {
    anchors.fill: sign
    source: sign
    blurEnabled: true
    blurMax: 4
    blur: 0.2
    opacity: neon.power
  }
}
