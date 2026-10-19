import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================= Fireflies
// A swarm of fireflies pours out of the bar and wheels across the screen
// like a murmuration. They gather into the shape of your Peak Pro and
// flash together, its ring in the profile's colour, then scatter into the
// dark and wink out.
Item {
  id: ff
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.8
  readonly property real now: t * dur
  readonly property real s: ff.host.u * ff.host.stage
  readonly property int count: 150
  readonly property real dark: Math.min(1, now / 0.6) * Math.max(0, Math.min(1, (dur - now) / 0.8))
  readonly property real k: height * 0.58 / 160
  readonly property real ox: width * 0.5 - 40 * k
  readonly property real oy: height * 0.49 - 80 * k
  readonly property real formAt: 2.6
  readonly property real holdAt: 3.8
  readonly property real scatterAt: 5.2
  // Where each firefly lands: points spread evenly round the Peak's
  // outline (and the glass's chrome seat), the light ring's flagged.
  readonly property var targets: {
    var P = [[12.5, 1.5], [21.5, 0.8], [46, 93], [49.5, 80.5], [71, 80.5], [72.5, 104],
             [56, 113.5], [64.5, 152], [60, 158], [9.5, 158], [6.5, 111.5], [9.5, 108]]
    var segs = []
    for (var i = 0; i < P.length; i++) segs.push([P[i], P[(i + 1) % P.length], i === 8])
    segs.push([[9.5, 108], [46, 93], false])
    var total = 0
    for (i = 0; i < segs.length; i++) {
      var dx = segs[i][1][0] - segs[i][0][0], dy = segs[i][1][1] - segs[i][0][1]
      segs[i].push(Math.sqrt(dx * dx + dy * dy))
      total += segs[i][3]
    }
    var out = []
    for (var n = 0; n < count; n++) {
      var d = n / count * total, g = 0
      while (g < segs.length - 1 && d > segs[g][3]) { d -= segs[g][3]; g++ }
      var f = segs[g][3] > 0 ? d / segs[g][3] : 0
      out.push([segs[g][0][0] + (segs[g][1][0] - segs[g][0][0]) * f, segs[g][0][1] + (segs[g][1][1] - segs[g][0][1]) * f, segs[g][2]])
    }
    return out
  }
  // The swarm's heart wanders the middle of the screen.
  readonly property real flockX: width * (0.5 + 0.17 * Math.sin(now * 0.8 + 0.4))
  readonly property real flockY: height * (0.45 + 0.12 * Math.sin(now * 1.25))
  readonly property real turn: now * 0.55
  readonly property real aspect: 0.42 + 0.22 * Math.sin(now * 0.9)
  // Once they're in shape, light chases round the outline; then, just
  // before they scatter, they all flash together.
  readonly property real flashAt: scatterAt - 0.55
  function glow(index) {
    if (now > flashAt) return 0.6 + 0.4 * Math.sin(Math.min(1, (now - flashAt) / 0.5) * Math.PI)
    return 0.4 + 0.6 * Math.pow(0.5 + 0.5 * Math.sin(now * 5.5 - index * 0.22), 3)
  }

  NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: ff.host.finished() }
  Component.onCompleted: ff.host.cue("night")

  Rectangle { anchors.fill: parent; color: "#02060a"; opacity: 0.7 * ff.dark }

  // Drawn once through a bloom, once crisp: the glow is the point.
  Item {
    id: swarm
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    Repeater {
      model: ff.count
      Item {
        id: fly
        required property int index
        readonly property real a: ff.host.hash(index * 1.37)
        readonly property real b: ff.host.hash(index * 4.91)
        readonly property real c: ff.host.hash(index * 8.29)
        readonly property var target: ff.targets[index]
        readonly property real tx: ff.ox + target[0] * ff.k
        readonly property real ty: ff.oy + target[1] * ff.k
        // Out of the bar, into the swarm.
        readonly property real pe: 1 - Math.pow(1 - Math.max(0, Math.min(1, (ff.now - a * 0.9) / 1.0)), 3)
        readonly property real ang: c * 6.283 + ff.now * (0.9 + 0.9 * a) * (index % 3 ? 1 : -1)
        // The flock ripples (lobes running round it), breathes and turns.
        readonly property real rad: (50 + 240 * b) * ff.s * (0.72 + 0.3 * Math.sin(ang * 3 + ff.now * 2.2) + 0.15 * Math.sin(ff.now * 1.3 + index * 0.1))
        readonly property real lx: Math.cos(ang) * rad
        readonly property real ly: Math.sin(ang) * rad * ff.aspect
        readonly property real fx: ff.flockX + lx * Math.cos(ff.turn) - ly * Math.sin(ff.turn)
        readonly property real fy: ff.flockY + lx * Math.sin(ff.turn) + ly * Math.cos(ff.turn)
        readonly property real sx: ff.host.originX + (fx - ff.host.originX) * pe
        readonly property real sy: ff.host.barEdge + (fy - ff.host.barEdge) * pe
        // Into the Peak's shape.
        readonly property real pfRaw: Math.max(0, Math.min(1, (ff.now - ff.formAt - c * 0.45) / 1.0))
        readonly property real pf: pfRaw < 0.5 ? 2 * pfRaw * pfRaw : 1 - Math.pow(-2 * pfRaw + 2, 2) / 2
        readonly property real hx: sx + (tx - sx) * pf + Math.sin(ff.now * 3 + index) * 3 * ff.s * pf
        readonly property real hy: sy + (ty - sy) * pf + Math.cos(ff.now * 2.6 + index) * 3 * ff.s * pf
        // Away into the dark.
        readonly property real ps: Math.max(0, Math.min(1, (ff.now - ff.scatterAt - b * 0.3) / 1.3))
        readonly property real ex: (tx - ff.width * 0.5) * 0.004 + (a - 0.5)
        readonly property real ey: -0.6 - b
        readonly property real blink: ff.now > ff.holdAt - 0.2 && ps === 0
          ? ff.glow(index)
          : 0.35 + 0.65 * Math.pow(0.5 + 0.5 * Math.sin(ff.now * (2.5 + 3 * a) + index * 2.1), 3)
        readonly property color hue: target[2] && pf > 0 ? Qt.tint("#efff8a", Util.alpha(ff.host.tint, pf))
          : (index % 4 === 0 ? "#fff1a8" : "#e2ff76")
        x: hx + ex * 420 * ff.s * Math.pow(ps, 1.4)
        y: hy + ey * 260 * ff.s * Math.pow(ps, 1.4)
        opacity: (ff.now > a * 0.9 ? 1 : 0) * blink * (1 - ps)

        // A point of light; the bloom below gives it its glow (a flat
        // halo disc here drew a hard ring in the crisp pass).
        Rectangle {
          width: (3.5 + 2.5 * fly.c) * ff.s
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: Qt.tint(fly.hue, Util.alpha("#ffffff", 0.25))
        }
      }
    }
  }

  MultiEffect {
    anchors.fill: swarm
    source: swarm
    blurEnabled: true
    blurMax: 48
    blur: 1.0
    brightness: 0.6
    opacity: ff.dark
  }
  MultiEffect {
    anchors.fill: swarm
    source: swarm
    blurEnabled: true
    blurMax: 16
    blur: 0.8
    brightness: 0.3
    opacity: ff.dark
  }
  MultiEffect {
    anchors.fill: swarm
    source: swarm
    opacity: ff.dark
  }

  // READY, in the shows' common lockup.
  Text {
    readonly property real e: Math.max(0, Math.min(1, (ff.now - ff.holdAt) / 0.3)) * Math.max(0, Math.min(1, (ff.scatterAt + 0.6 - ff.now) / 0.5))
    anchors.horizontalCenter: parent.horizontalCenter
    y: ff.oy + 160 * ff.k + 22 * ff.s + (1 - Math.min(1, Math.max(0, (ff.now - ff.holdAt) / 0.3))) * 12 * ff.s
    opacity: 0.92 * e
    visible: e > 0
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.tint("#ffffff", Util.alpha("#ffe9a0", 0.35))
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
    font.family: ff.host.displayFamily
    font.pixelSize: 64 * ff.s
    font.weight: Font.DemiBold
    font.letterSpacing: 15 * ff.s
  }
}
