import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================== Deep sea
// The desktop sinks underwater: light ripples down from the surface,
// plankton glitters, bubbles wobble up, whale sharks cruise past (one huge
// and close, one far off in the blue), and bioluminescent jellyfish rise
// out of the deep, their bells pulsing (each beat a push upward) and their
// tentacles trailing, in the profile's colour, cyan and violet.
Item {
  id: sea
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.8
  readonly property real now: t * dur
  readonly property real s: sea.host.u * sea.host.stage
  readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
  readonly property var hues: [sea.host.tint, "#58f0ff", "#b38cff", Qt.lighter(sea.host.tint, 1.4), "#7affd2", "#ff8ad8"]

  NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: sea.host.finished() }
  Component.onCompleted: sea.host.cue("deep")

  // The water, darker the deeper it goes.
  Rectangle {
    anchors.fill: parent
    opacity: sea.dark
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha("#003048", 0.6) }
      GradientStop { position: 0.5; color: Util.alpha("#00182c", 0.74) }
      GradientStop { position: 1.0; color: Util.alpha("#000710", 0.88) }
    }
  }

  // Whale sharks: one far off in the blue, small and hazy, cruising the
  // other way; one close by, gliding slowly across the whole scene behind
  // the jellyfish, the light shafts falling across its back.
  WhaleShark {
    host: sea.host
    len: sea.width * 0.27
    haze: 0.68
    facing: -1
    swim: sea.now * 1.15
    pitch: 1.5 * Math.sin(sea.now * 0.5)
    x: sea.width * (1.12 - 0.62 * sea.now / sea.dur)
    y: sea.height * 0.27 + Math.sin(sea.now * 0.7) * 6 * sea.s
    opacity: 0.8 * sea.dark
  }
  WhaleShark {
    host: sea.host
    readonly property real p: Math.max(0, (sea.now - 0.15) / (sea.dur - 0.15))
    len: sea.width * 0.6
    haze: 0.12
    facing: 1
    swim: sea.now
    pitch: 2.5 + 1.2 * Math.sin(sea.now * 0.6)
    x: -len * 0.45 + (sea.width + len * 0.2) * p
    y: sea.height * (0.6 - 0.08 * p) + Math.sin(sea.now * 0.55) * 10 * sea.s
    opacity: Math.min(1, sea.now / 0.6) * sea.dark
  }

  // Light from the surface, in slow swaying shafts.
  Repeater {
    model: 8
    Rectangle {
      required property int index
      readonly property real a: sea.host.hash(index * 3.17)
      readonly property real b: sea.host.hash(index * 7.71)
      width: (50 + 130 * a) * sea.s
      height: sea.height * 0.95
      x: sea.width * (0.06 + 0.88 * b) - width / 2 + Math.sin(sea.now * 0.5 + index) * 30 * sea.s
      y: -sea.height * 0.04
      rotation: (b - 0.5) * 26 + Math.sin(sea.now * 0.45 + index * 1.3) * 3
      transformOrigin: Item.Top
      opacity: sea.dark * (0.55 + 0.45 * Math.sin(sea.now * 0.9 + index * 1.7))
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#a6ecff", 0.17) }
        GradientStop { position: 0.55; color: Util.alpha("#a6ecff", 0.05) }
        GradientStop { position: 1.0; color: Util.alpha("#a6ecff", 0) }
      }
    }
  }

  // Plankton glittering as it drifts.
  Item {
    anchors.fill: parent
    opacity: sea.dark
    ParticleSystem { id: seaSys; anchors.fill: parent }
    ImageParticle {
      system: seaSys
      source: Qt.resolvedUrl("../particles/glow.png")
      color: "#8af4ff"
      colorVariation: 0.25
      alpha: 0.85
      alphaVariation: 0.4
    }
    Emitter {
      system: seaSys
      anchors.fill: parent
      emitRate: sea.now < sea.dur - 1.4 ? 55 : 0
      lifeSpan: 2600; lifeSpanVariation: 1000
      size: 7 * sea.s; sizeVariation: 5 * sea.s; endSize: 1 * sea.s
      velocity: PointDirection { y: -14 * sea.s; xVariation: 10 * sea.s; yVariation: 10 * sea.s }
    }
    Wander { system: seaSys; xVariance: 40 * sea.s; pace: 60 * sea.s }
  }

  // Bubbles wobbling up to the surface.
  Repeater {
    model: 16
    Rectangle {
      required property int index
      readonly property real a: sea.host.hash(index * 5.9)
      readonly property real b: sea.host.hash(index * 2.3)
      readonly property real p: ((sea.now * (0.16 + 0.12 * a)) + b) % 1
      width: (5 + 12 * a) * sea.s
      height: width
      radius: width / 2
      x: sea.width * (0.05 + 0.9 * sea.host.hash(index * 9.7)) + Math.sin(p * 18 + index) * 8 * sea.s
      y: sea.height * (1.05 - 1.15 * p)
      color: Util.alpha("#c8f6ff", 0.06)
      border.width: Math.max(1, 1.2 * sea.s)
      border.color: Util.alpha("#c8f6ff", 0.5)
      opacity: sea.dark * Math.min(1, p / 0.1)
    }
  }

  // The jellyfish, drawn through a bloom.
  Item {
    id: deep
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    Repeater {
      model: 11
      Item {
        id: jelly
        required property int index
        // The first few are far off: small, faint and slow, behind the rest.
        readonly property bool far: index < 5
        readonly property real a: sea.host.hash(index * 2.31)
        readonly property real b: sea.host.hash(index * 6.07)
        readonly property color hue: sea.hues[index % sea.hues.length]
        readonly property real size: (78 + 86 * a) * sea.s * (far ? 0.42 : 1)
        readonly property real period: 1.25 + 0.55 * b
        readonly property real start: (far ? index * 0.2 : (index - 5) * 0.3) + a * 0.25
        readonly property real life: Math.max(0, sea.now - start)
        readonly property real beat: life / period
        readonly property real phase: beat - Math.floor(beat)
        // A beat: a quick squeeze, then a long relax.
        readonly property real squeeze: phase < 0.28 ? Math.sin(phase / 0.28 * Math.PI / 2) : Math.cos((phase - 0.28) / 0.72 * Math.PI / 2)
        // Each squeeze is a push upward, on top of a slow drift.
        readonly property real push: Math.floor(beat) + (1 - Math.pow(1 - Math.min(1, phase / 0.4), 2))
        readonly property real climb: (48 * life + (115 + 60 * b) * push) * sea.s * (far ? 0.5 : 1)
        readonly property real w: size / 2 * (1 - 0.2 * squeeze)
        readonly property real h: size * 0.5 * (1 + 0.24 * squeeze)
        x: sea.width * (0.08 + 0.84 * ((index * 0.37 + a * 0.31) % 1)) + Math.sin(life * 0.6 + index) * 46 * sea.s
        y: sea.height + size * 0.6 - climb
        rotation: Math.sin(life * 0.8 + index * 2) * 8
        opacity: (life > 0 ? Math.min(1, life / 0.5) : 0) * (far ? 0.45 : 1)

        // Tentacles: trailing, bunching on each squeeze, a wave running
        // down them; brighter near the bell.
        Repeater {
          model: 6
          Shape {
            id: tentacle
            required property int index
            readonly property real rootX: -jelly.w * 0.78 + index * (jelly.w * 1.56 / 5)
            readonly property real len: jelly.size * (1.3 + 0.8 * sea.host.hash(jelly.index * 3.1 + index))
            preferredRendererType: Shape.CurveRenderer
            function wave(lo, hi) {
              var out = []
              for (var k = lo; k <= hi; k++) {
                var f = k / 10
                out.push(Qt.point(rootX * (1 + 0.3 * f * jelly.squeeze) + Math.sin(k * 0.8 - jelly.life * 4 + index * 1.4) * 11 * sea.s * f,
                                  jelly.h * 0.08 + len * f * (1 - 0.16 * jelly.squeeze)))
              }
              return out
            }
            ShapePath {
              strokeColor: Util.alpha(Qt.lighter(jelly.hue, 1.2), 0.75)
              strokeWidth: 1.6 * sea.s
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              PathPolyline { path: tentacle.wave(0, 5) }
            }
            ShapePath {
              strokeColor: Util.alpha(jelly.hue, 0.32)
              strokeWidth: 1.2 * sea.s
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              PathPolyline { path: tentacle.wave(5, 10) }
            }
          }
        }

        // The bell: a dome over a scalloped rim, glowing from inside.
        Shape {
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Util.alpha(Qt.lighter(jelly.hue, 1.35), 0.9)
            strokeWidth: 1.7 * sea.s
            joinStyle: ShapePath.RoundJoin
            fillGradient: RadialGradient {
              centerX: 0; centerY: -jelly.h * 0.45; centerRadius: jelly.w * 1.15
              focalX: 0; focalY: -jelly.h * 0.6
              GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(jelly.hue, 1.5), 0.6) }
              GradientStop { position: 0.6; color: Util.alpha(jelly.hue, 0.28) }
              GradientStop { position: 1.0; color: Util.alpha(jelly.hue, 0.1) }
            }
            PathSvg {
              path: {
                var w = jelly.w, h = jelly.h
                return "M " + (-w) + " 0 C " + (-w) + " " + (-h * 1.3) + " " + w + " " + (-h * 1.3) + " " + w + " 0"
                  + " Q " + (w * 0.75) + " " + (h * 0.2) + " " + (w * 0.5) + " " + (h * 0.06)
                  + " Q " + (w * 0.25) + " " + (h * 0.22) + " 0 " + (h * 0.08)
                  + " Q " + (-w * 0.25) + " " + (h * 0.22) + " " + (-w * 0.5) + " " + (h * 0.06)
                  + " Q " + (-w * 0.75) + " " + (h * 0.2) + " " + (-w) + " 0 Z"
              }
            }
          }
        }
        // Its glowing heart, brightest at the end of each squeeze.
        SoftGlow {
          hue: Qt.lighter(jelly.hue, 1.5)
          x: -50
          y: -jelly.h * 0.5 - 50
          scale: jelly.w * (0.9 + 0.3 * jelly.squeeze) / 100
          opacity: 0.55 + 0.35 * jelly.squeeze
        }
        // Lights along the rim.
        Repeater {
          model: 7
          Rectangle {
            required property int index
            width: 3.2 * sea.s
            height: width
            radius: width / 2
            x: -jelly.w + index * (2 * jelly.w / 6) - width / 2
            y: (index % 2 ? jelly.h * 0.1 : 0) - height / 2
            color: Qt.lighter(jelly.hue, 1.6)
            opacity: 0.6 + 0.4 * Math.sin(sea.now * 6 + index + jelly.index)
          }
        }
      }
    }
  }

  MultiEffect {
    anchors.fill: deep
    source: deep
    blurEnabled: true
    blurMax: 48
    blur: 0.85
    brightness: 0.3
    opacity: sea.dark
  }
  MultiEffect {
    anchors.fill: deep
    source: deep
    opacity: sea.dark
  }

  // READY, in the shows' common lockup.
  Text {
    readonly property real e: Math.max(0, Math.min(1, (sea.now - 1.4) / 0.3)) * Math.max(0, Math.min(1, (sea.dur - 0.9 - sea.now) / 0.5))
    anchors.horizontalCenter: parent.horizontalCenter
    y: sea.height * 0.6 + (1 - Math.min(1, Math.max(0, (sea.now - 1.4) / 0.3))) * 12 * sea.s
    opacity: 0.92 * e
    visible: e > 0
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.tint("#ffffff", Util.alpha("#9ff4ff", 0.3))
    // A dark halo, so it reads over whatever swims or flies behind it.
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
      blurMax: 24
      shadowBlur: 0.5
      shadowColor: Util.alpha("#000000", 0.55)
    }
    font.family: sea.host.displayFamily
    font.pixelSize: 64 * sea.s
    font.weight: Font.DemiBold
    font.letterSpacing: 15 * sea.s
  }
}
