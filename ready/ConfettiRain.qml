import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================== Confetti
// Puffco confetti: a burst from the widget, then two cannons firing up from
// the bottom corners toward the middle, so the whole screen fills. Logo-
// shaped chips, streamers and a few tiny Peaks in shades of the profile's
// colour, gold and white. Each piece flips like paper, slows in the air and
// sways as it settles.
Item {
  id: rain
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 5.2
  readonly property real now: t * dur
  readonly property real s: rain.host.u * rain.host.stage * 1.3
  readonly property real dir: rain.host.barAtTop ? 1 : -1
  // Pieces from the widget, then from each cannon (under 200 in all), and
  // when the cannons go off (s).
  readonly property int burstCount: 76
  readonly property int cannonCount: 58
  readonly property real cannonAt: 0.3
  readonly property bool cannonsOut: now >= cannonAt
  readonly property var hues: [rain.host.tint, Qt.lighter(rain.host.tint, 1.5), Qt.darker(rain.host.tint, 1.3), "#ffd76a", "#ffffff", Qt.lighter(rain.host.tint, 1.2)]

  Component.onCompleted: rain.host.cue("pop")
  onCannonsOutChanged: if (cannonsOut) rain.host.cue("pop")

  NumberAnimation on t { from: 0; to: 1; duration: 5200; running: true; onFinished: rain.host.finished() }

  // A soft flash in each corner as the cannons fire.
  Repeater {
    model: 2

    SoftGlow {
      required property int index
      readonly property real f: Math.max(0, Math.min(1, (rain.now - rain.cannonAt) / 0.5))
      visible: f > 0 && f < 1
      hue: Qt.lighter(rain.host.tint, 1.6)
      x: (index ? rain.width : 0) - 50
      y: rain.height - 50
      scale: rain.height * (0.3 + 0.4 * f) / 100
      opacity: 0.6 * (1 - f)
    }
  }

  Repeater {
    model: rain.burstCount + 2 * rain.cannonCount

    Item {
      id: bit
      required property int index
      // Fired by the widget (0), the left cannon (1) or the right one (2).
      readonly property int firedBy: index < rain.burstCount ? 0 : (index < rain.burstCount + rain.cannonCount ? 1 : 2)
      // Every 12th piece is a tiny Peak, every 3rd a streamer, the rest
      // logo chips. Deterministic spread so each burst looks full.
      readonly property int kind: index % 12 === 0 ? 2 : (index % 3 === 0 ? 1 : 0)
      readonly property real spread: ((index * 61) % 100) / 100 - 0.5
      readonly property real power: ((index * 47) % 100) / 100
      readonly property real drag: 2.2 + (index % 5) * 0.25
      // Where it starts, and where a cannon aims: just short of the middle,
      // a quarter of the way down. Drag stops each piece at speed / drag,
      // so the cannon pieces land from halfway there to a little past it.
      readonly property real ox: firedBy === 0 ? rain.host.originX : (firedBy === 1 ? 0 : rain.width)
      readonly property real oy: firedBy === 0 ? rain.host.barEdge : rain.height
      readonly property real aimX: rain.width * (firedBy === 1 ? 0.46 : 0.54) - ox
      readonly property real aimY: rain.height * 0.25 - oy
      readonly property real angle: firedBy === 0 ? spread * 2.6 : Math.atan2(aimY, aimX) + spread * 0.6
      readonly property real speed: firedBy === 0
        ? rain.height * (0.5 + 0.75 * power)
        : Math.sqrt(aimX * aimX + aimY * aimY) * drag * (0.5 + 0.8 * power)
      readonly property real vx: firedBy === 0 ? Math.sin(angle) * speed : Math.cos(angle) * speed
      readonly property real vy: firedBy === 0 ? Math.cos(angle) * speed * rain.dir : Math.sin(angle) * speed
      readonly property real fall: rain.height * (0.1 + ((index * 29) % 80) / 900)
      readonly property real sway: (14 + (index * 17) % 26) * rain.s
      readonly property real phase: index * 1.7
      readonly property real flipRate: 5 + (index * 13) % 9
      // Seconds since this piece was fired.
      readonly property real tau: Math.max(0, rain.now - (firedBy === 0 ? 0 : rain.cannonAt))
      readonly property real slow: (1 - Math.exp(-drag * tau)) / drag
      readonly property color hue: rain.hues[index % rain.hues.length]

      visible: firedBy === 0 || rain.cannonsOut
      x: ox + vx * slow + Math.sin(tau * 3 + phase) * sway * Math.min(1, tau)
      y: oy + vy * slow + fall * tau
      rotation: (index % 2 ? 1 : -1) * (120 + (index * 37) % 240) * tau
      opacity: rain.t < 0.78 ? 1 : (1 - rain.t) / 0.22
      // Paper flip: the piece turns edge-on and back.
      transform: Scale { xScale: Math.cos(bit.tau * bit.flipRate + bit.phase) }

      // Logo chip.
      Shape {
        visible: bit.kind === 0
        width: 6
        height: 14
        x: -width * rain.s / 2
        scale: rain.s * (0.9 + (bit.index % 3) * 0.25)
        transformOrigin: Item.TopLeft
        ShapePath {
          strokeColor: "transparent"
          fillColor: bit.hue
          PathSvg { path: "M0,3 L6,0 L6,11 L0,14 Z" }
        }
      }

      // Streamer.
      Rectangle {
        visible: bit.kind === 1
        width: 3 * rain.s
        height: (16 + (bit.index * 7) % 14) * rain.s
        radius: width / 2
        gradient: Gradient {
          GradientStop { position: 0.0; color: bit.hue }
          GradientStop { position: 1.0; color: Qt.darker(bit.hue, 1.3) }
        }
      }

      // A tiny Peak Pro, tumbling (only built for the pieces that are one).
      Loader {
        active: bit.kind === 2
        sourceComponent: Component {
          Shape {
            width: 80
            height: 160
            scale: rain.s * 0.24
            transformOrigin: Item.TopLeft
            ShapePath {
              strokeColor: Util.alpha("white", 0.6)
              strokeWidth: 3
              fillColor: Util.alpha(bit.hue, 0.35)
              PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z" }
            }
            ShapePath {
              strokeColor: "transparent"
              fillColor: "#2a2a2d"
              PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
            }
            ShapePath {
              strokeColor: "transparent"
              fillColor: "#55555a"
              PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C52,116 24,136 6.5,151 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
            }
            ShapePath {
              strokeColor: bit.hue
              strokeWidth: 4
              fillColor: "transparent"
              PathSvg { path: "M8.5,157 L61,157" }
            }
          }
        }
      }
    }
  }

  ReadyWord { host: rain.host; now: rain.now; at: 0.5; until: rain.dur - 0.7; y: rain.height * 0.42 }
}
