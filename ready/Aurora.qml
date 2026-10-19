import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Aurora
// Northern lights: curtains of green, teal and the profile's colour ripple
// across the top of the screen and fade.
Item {
  id: aurora
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real s: aurora.host.u
  readonly property real envelope: Math.min(1, t / 0.18, (1 - t) / 0.3)
  readonly property var curtains: [
    { "hue": "#3dff9e", "base": 0.16, "amp": 0.05, "k": 2.2, "speed": 1.0, "height": 0.22 },
    { "hue": "#2de2e6", "base": 0.24, "amp": 0.06, "k": 1.6, "speed": -0.7, "height": 0.18 },
    { "hue": String(aurora.host.tint), "base": 0.31, "amp": 0.04, "k": 2.8, "speed": 1.3, "height": 0.16 }
  ]

  Component.onCompleted: aurora.host.cue("shimmer")
  NumberAnimation on t { from: 0; to: 1; duration: 6500; running: true; onFinished: aurora.host.finished() }

  Item {
    id: sky
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: aurora.curtains.length * 64
      Rectangle {
        required property int index
        readonly property var c: aurora.curtains[Math.floor(index / 64)]
        readonly property int col: index % 64
        readonly property real fx: col / 63
        readonly property real wave: Math.sin(fx * Math.PI * 2 * c.k + aurora.t * Math.PI * 4 * c.speed)
        readonly property real tall: aurora.height * c.height * (0.6 + 0.4 * Math.sin(fx * 9 + aurora.t * 8 * c.speed))
        width: aurora.width / 64 + 3
        height: tall
        x: fx * aurora.width - width / 2
        y: aurora.height * (c.base + c.amp * wave) - tall * 0.8
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(c.hue, 0) }
          GradientStop { position: 0.75; color: Util.alpha(c.hue, 0.55) }
          GradientStop { position: 1.0; color: Util.alpha(c.hue, 0) }
        }
      }
    }
  }

  MultiEffect {
    anchors.fill: sky
    source: sky
    blurEnabled: true
    blurMax: 56
    blur: 0.9
    opacity: aurora.envelope
  }

  ReadyWord { host: aurora.host; now: aurora.t * 6.5; at: 1.2; until: 5.6; y: aurora.height * 0.36 }
}
