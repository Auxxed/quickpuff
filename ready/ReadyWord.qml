import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// A soft round glow: `hue` in the middle, fading out to the edge. Drawn at
// 100 x 100 and sized with `scale`, so it never has to re-tessellate.
// READY in the shows' common lockup (64 px display face, wide tracking,
// white at 92% with a soft dark halo): it rises in at `at` seconds into
// the show and fades out by `until`, on the show's own clock `now`.
Text {
  id: readyWord
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null
  property real now: 0
  property real at: 0
  property real until: 5
  property real s: readyWord.host.u * readyWord.host.stage
  property color tone: Qt.tint("#ffffff", Util.alpha(readyWord.host.tint, 0.25))
  readonly property real rise: Math.max(0, Math.min(1, (now - at) / 0.3))
  readonly property real e: rise * Math.max(0, Math.min(1, (until - now) / 0.5))
  anchors.horizontalCenter: parent.horizontalCenter
  opacity: 0.92 * e
  visible: e > 0
  transform: Translate { y: (1 - rideRise(rise)) * 12 * s }
  function rideRise(k) { return 1 - Math.pow(1 - k, 3) }
  textFormat: Text.PlainText
  text: "READY"
  color: tone
  font.family: readyWord.host.displayFamily
  font.pixelSize: 64 * s
  font.weight: Font.DemiBold
  font.letterSpacing: 15 * s
  layer.enabled: visible
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
    blurMax: 24
    shadowBlur: 0.5
    shadowColor: Util.alpha("#000000", 0.55)
  }
}
