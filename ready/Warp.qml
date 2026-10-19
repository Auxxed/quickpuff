import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ================================================================== Warp
// The screen falls into space and the stars stretch into hyperspace,
// faster and faster, out of a point in the middle. Then it drops out of
// warp, and a spiral galaxy hangs there, tilted toward you: a blazing core,
// arms of stars and glowing dust in the profile's colour winding round it
// as it turns (the inner stars faster than the outer ones), with READY
// under it.
Item {
  id: warp
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.8
  readonly property real now: t * dur
  readonly property real s: warp.host.u * warp.host.stage
  readonly property real cx: width * 0.5
  readonly property real cy: height * 0.45
  readonly property real dark: Math.min(1, now / 0.5) * Math.max(0, Math.min(1, (dur - now) / 1.0))
  readonly property real dropAt: 1.8
  readonly property real since: now - dropAt
  // How far through the stars: the speed building as the square of time
  // until the drop, then braking hard.
  readonly property real travelled: {
    var a = 0.22, b = 2.4
    if (now < dropAt) return a * now + b * now * now * now / (3 * dropAt * dropAt)
    var atDrop = a * dropAt + b * dropAt / 3
    var brake = Math.min(since, 0.35)
    return atDrop + (a + b) * (brake - brake * brake / (2 * 0.35))
  }
  readonly property real speed: now < dropAt ? 0.22 + 2.4 * Math.pow(now / dropAt, 2) : Math.max(0, 2.62 * (1 - since / 0.35))
  readonly property real galaxyIn: Math.max(0, Math.min(1, since / 2.0))
  readonly property real grow: 0.35 + 0.65 * (1 - Math.pow(1 - galaxyIn, 3))
  // The disc's tilt: squashed to this fraction top to bottom, then turned.
  readonly property real tilt: 0.38
  readonly property real lean: -18 * Math.PI / 180
  readonly property real rMin: height * 0.03
  readonly property real rMax: height * 0.46

  // Where a point on the disc (polar, in the disc's own plane) lands on
  // screen, and how near the viewer it is (0 back, 1 front).
  function sx(a, r) { var x = Math.cos(a) * r * grow, y = Math.sin(a) * r * grow * tilt; return cx + x * Math.cos(lean) - y * Math.sin(lean) }
  function sy(a, r) { var x = Math.cos(a) * r * grow, y = Math.sin(a) * r * grow * tilt; return cy + x * Math.sin(lean) + y * Math.cos(lean) }
  // Turned by now: the inner disc faster than the outer.
  function spin(r) { return Math.max(0, since) * (0.18 + 0.75 * rMin * 3 / Math.max(r, rMin)) }

  NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: warp.host.finished() }
  // One cue for the whole trip: the drive spooling up, the drop, the galaxy.
  Component.onCompleted: warp.host.cue("warp")

  Rectangle { anchors.fill: parent; color: "#010208"; opacity: 0.8 * warp.dark }

  // Hyperspace: streaks rushing out of the vanishing point.
  Repeater {
    model: 170
    Rectangle {
      required property int index
      readonly property real ang: warp.host.hash(index * 1.91) * 6.283
      readonly property real rate: 0.6 + 0.8 * warp.host.hash(index * 4.37)
      readonly property real u: (warp.host.hash(index * 8.53) + warp.travelled * rate) % 1
      readonly property real reach: Math.max(warp.width, warp.height) * 0.75
      readonly property real r: (0.02 + 0.98 * u * u) * reach
      readonly property real streak: Math.max(2 * warp.s, warp.speed * r * 0.28)
      x: warp.cx + Math.cos(ang) * r
      y: warp.cy + Math.sin(ang) * r - height / 2
      width: streak
      height: (1 + 1.6 * u) * warp.s
      radius: height / 2
      rotation: ang * 180 / Math.PI
      transformOrigin: Item.Left
      opacity: warp.dark * Math.min(1, u * 3) * (warp.since < 0 ? 1 : Math.max(0, 1 - warp.since / 0.8))
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha("#cfe0ff", 0) }
        GradientStop { position: 1.0; color: index % 6 ? "#e8f0ff" : Qt.lighter(warp.host.tint, 1.5) }
      }
    }
  }

  // Dropping out of warp: a bloom of light from the middle.
  SoftGlow {
    hue: Qt.lighter(warp.host.tint, 1.8)
    x: warp.cx - 50
    y: warp.cy - 50
    readonly property real f: Math.max(0, Math.min(1, warp.since / 0.7))
    scale: warp.height * (0.3 + 1.2 * f) / 100
    opacity: warp.since >= 0 ? 0.55 * Math.pow(1 - f, 2) : 0
  }

  // The galaxy, drawn through a bloom.
  Item {
    id: space
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    Item {
      anchors.fill: parent
      opacity: warp.galaxyIn > 0 ? Math.min(1, warp.since / 0.7) : 0

      // A faint halo, and the dust of the arms: soft clouds laid along
      // the spirals, squashed and turned with the disc.
      Item {
        x: warp.cx
        y: warp.cy
        transform: [
          Scale { xScale: warp.grow; yScale: warp.grow * warp.tilt },
          Rotation { angle: warp.lean * 180 / Math.PI }
        ]
        SoftGlow { hue: Util.alpha("#8ea6ff", 0.09); x: -50; y: -50; scale: warp.rMax * 2.4 / 100 }
        Repeater {
          model: 52
          SoftGlow {
            required property int index
            readonly property real rr: warp.rMin * 2 + (warp.rMax - warp.rMin * 2) * Math.pow(warp.host.hash(index * 3.3), 0.8)
            readonly property real a: (index % 2) * Math.PI + Math.log(rr / warp.rMin) * 2.1 + warp.spin(rr)
              + (warp.host.hash(index * 6.7) - 0.5) * 0.45
            // Blue-white starlight, with knots of the profile's colour
            // where new stars are being born.
            hue: index % 4 === 0 ? Util.alpha(Qt.lighter(warp.host.tint, 1.25), 0.32)
              : Util.alpha(index % 2 ? "#a9bdff" : "#d4dcff", 0.2)
            x: Math.cos(a) * rr - 50
            y: Math.sin(a) * rr - 50
            transform: [
              Scale { origin.x: 50; origin.y: 50; xScale: (26 + rr * 0.3) / 100; yScale: (12 + rr * 0.1) / 100 },
              Rotation { origin.x: 50; origin.y: 50; angle: a * 180 / Math.PI + 70 }
            ]
          }
        }
      }

      // The stars, each placed on the disc and projected, so they stay
      // round however the disc leans; nearer ones a touch bigger.
      Repeater {
        model: 520
        Rectangle {
          required property int index
          readonly property real q: warp.host.hash(index * 1.37)
          readonly property real rr: warp.rMin + (warp.rMax - warp.rMin) * Math.sqrt(q)
          readonly property int arm: index % 2
          readonly property bool scattered: index % 4 === 3
          readonly property real th: (scattered ? warp.host.hash(index * 5.9) * 6.283
            : arm * Math.PI + Math.log(rr / warp.rMin) * 2.1 + (warp.host.hash(index * 2.9) - 0.5) * (0.25 + 0.6 * q))
            + warp.spin(rr)
          readonly property real near: 0.5 + 0.5 * Math.sin(th)
          width: (1.2 + 2.6 * warp.host.hash(index * 7.7)) * warp.s * (0.8 + 0.4 * near) * (0.6 + 0.4 * warp.grow)
          height: width
          radius: width / 2
          x: warp.sx(th, rr) - width / 2
          y: warp.sy(th, rr) - height / 2
          color: q < 0.12 ? "#fff1d2" : (index % 5 === 0 ? Qt.lighter(warp.host.tint, 1.5) : "#dbe7ff")
          opacity: (scattered ? 0.5 : 0.8) * (0.6 + 0.4 * Math.abs(Math.sin(warp.now * 2 + index)))
        }
      }

      // The core: blazing white at the heart of a warm glow.
      SoftGlow {
        hue: Util.alpha(Qt.tint("#ffe6c4", Util.alpha(warp.host.tint, 0.25)), 0.5)
        x: warp.cx - 50
        y: warp.cy - 50
        transform: Scale { origin.x: 50; origin.y: 50; xScale: warp.rMax * 0.6 * warp.grow / 100; yScale: warp.rMax * 0.34 * warp.grow / 100 }
      }
      SoftGlow {
        hue: "#fff6e4"
        x: warp.cx - 50
        y: warp.cy - 50
        scale: warp.rMax * 0.24 * warp.grow / 100
      }
    }
  }

  MultiEffect {
    anchors.fill: space
    source: space
    blurEnabled: true
    blurMax: 40
    blur: 0.75
    brightness: 0.25
    opacity: warp.dark
  }
  MultiEffect {
    anchors.fill: space
    source: space
    opacity: warp.dark
  }

  Text {
    readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (warp.since - 1.1) / 1.2)), 3)
    anchors.horizontalCenter: parent.horizontalCenter
    y: warp.cy + warp.height * 0.29
    opacity: warp.since > 1.1 ? e * warp.dark : 0
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.tint("#ffffff", Util.alpha(warp.host.tint, 0.25))
    font.family: warp.host.displayFamily
    font.pixelSize: 60 * warp.s
    font.weight: Font.DemiBold
    font.letterSpacing: (15 + 40 * (1 - e)) * warp.s
  }
}
