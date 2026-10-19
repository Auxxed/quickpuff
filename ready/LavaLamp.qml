import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Lava lamp
// Molten blobs in the profile's colour rise up the screen, wobbling and
// melting into one another (blurred together, like wax in a lamp).
Item {
  id: lava
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real s: lava.host.u
  readonly property var hues: [lava.host.tint, Qt.lighter(lava.host.tint, 1.45), Qt.darker(lava.host.tint, 1.35)]

  Component.onCompleted: lava.host.cue("bubbles")
  NumberAnimation on t { from: 0; to: 1; duration: 6000; running: true; onFinished: lava.host.finished() }

  // Hidden by opacity, not `visible`: a hidden layer source whose blobs
  // all start transparent never renders into its layer on Qt 6.12, and
  // the lamp stayed blank.
  Item {
    id: wax
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    Repeater {
      model: 11
      Rectangle {
        id: blob
        required property int index
        readonly property real size: (170 + (index * 53) % 170) * lava.s
        readonly property real delay: (index % 6) * 0.07
        readonly property real p: Math.max(0, Math.min(1, (lava.t - delay) / 0.8))
        readonly property real eased: p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2
        width: size * (1 + 0.16 * Math.sin(p * Math.PI * 5 + index))
        height: size * (1 - 0.12 * Math.sin(p * Math.PI * 5 + index))
        radius: Math.min(width, height) / 2
        x: lava.width * (0.04 + ((index * 37) % 92) / 100) + Math.sin(p * Math.PI * 2 + index) * 40 * lava.s - width / 2
        y: lava.height + size * 0.35 - eased * (lava.height + 1.75 * size)
        color: lava.hues[index % lava.hues.length]
        opacity: p <= 0 || p >= 1 ? 0 : Math.min(1, p / 0.1, (1 - p) / 0.15)
      }
    }
  }

  // Wax: the blobs blurred together, then cut at a threshold so they
  // merge and pull apart with clean, rounded edges, like the real thing.
  // A soft halo of the same wax glows behind it.
  MultiEffect {
    id: waxBlur
    anchors.fill: wax
    source: wax
    visible: false
    layer.enabled: true
    blurEnabled: true
    blurMax: 64
    blur: 1
  }
  MultiEffect {
    anchors.fill: wax
    source: wax
    blurEnabled: true
    blurMax: 64
    blur: 1
    brightness: 0.15
    opacity: 0.35
  }
  MultiEffect {
    anchors.fill: wax
    source: waxBlur
    maskEnabled: true
    maskSource: waxBlur
    maskThresholdMin: 0.42
    maskSpreadAtMin: 0.08
    saturation: 0.15
    opacity: 0.92
  }

  ReadyWord { host: lava.host; now: lava.t * 6.0; at: 0.8; until: 5.3; y: lava.height * 0.42 }
}
