import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ================================================================= Storm
// A storm rolls in: dark clouds gather over the top of the screen and rain
// slants down. Lightning strikes, forked bolts lighting the clouds from
// inside and flashing the screen; the last strike lands in the middle and
// READY is left crackling there.
Item {
  id: storm
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.6
  readonly property real now: t * dur
  readonly property real s: storm.host.u * storm.host.stage
  readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
  // When each bolt strikes (s), and where along the screen it lands; the
  // last one is the big one, into the middle.
  readonly property var strikes: [
    { "at": 1.0, "x": 0.18 + Math.random() * 0.1 },
    { "at": 1.85, "x": 0.78 + Math.random() * 0.1 },
    { "at": 2.55, "x": 0.34 + Math.random() * 0.1 },
    { "at": 3.5, "x": 0.5, "big": true }
  ]
  property var bolts: []
  property int fired: 0
  readonly property real readyAt: strikes[3].at

  NumberAnimation on t { from: 0; to: 1; duration: 6600; running: true; onFinished: storm.host.finished() }
  Component.onCompleted: storm.host.cue("rain")
  onNowChanged: {
    while (fired < strikes.length && now >= strikes[fired].at) {
      var sp = strikes[fired]
      var made = bolts.slice()
      var main = bolt(sp.x, sp.big === true)
      made.push({ "at": sp.at, "x": sp.x, "big": sp.big === true, "main": main, "forks": forksFor(main, sp.big === true) })
      bolts = made
      fired++
      // The big one cracks overhead; the others roll in from further off.
      if (sp.big === true) storm.host.cue("thunder")
      else storm.host.cue("rumble")
    }
  }

  // A bolt from the clouds to its landing point, by midpoint displacement:
  // each segment's middle pushed sideways at random, smaller each round.
  function bolt(fx, big) {
    var x0 = width * (fx + (Math.random() - 0.5) * 0.08), y0 = height * 0.1
    var x1 = width * fx, y1 = big ? height * 0.52 : height * (0.75 + Math.random() * 0.2)
    var pts = [Qt.point(x0, y0), Qt.point(x1, y1)]
    var spread = (y1 - y0) * 0.22
    for (var round = 0; round < 6; round++) {
      var next = [pts[0]]
      for (var i = 0; i < pts.length - 1; i++) {
        var a = pts[i], b = pts[i + 1]
        next.push(Qt.point((a.x + b.x) / 2 + (Math.random() - 0.5) * spread, (a.y + b.y) / 2 + (Math.random() - 0.5) * spread * 0.25))
        next.push(b)
      }
      pts = next
      spread *= 0.55
    }
    return pts
  }
  // Forks off a main bolt's path, angling down and away.
  function forksFor(main, big) {
    var out = [], n = big ? 4 : 2
    for (var f = 0; f < n; f++) {
      var start = main[Math.floor(main.length * (0.2 + Math.random() * 0.5))]
      var side = Math.random() < 0.5 ? -1 : 1
      var len = height * (0.08 + Math.random() * 0.12)
      var end = Qt.point(start.x + side * len * (0.5 + Math.random() * 0.5), start.y + len)
      var pts = [start, end]
      var spread = len * 0.3
      for (var round = 0; round < 4; round++) {
        var next = [pts[0]]
        for (var i = 0; i < pts.length - 1; i++) {
          var a = pts[i], b = pts[i + 1]
          next.push(Qt.point((a.x + b.x) / 2 + (Math.random() - 0.5) * spread, (a.y + b.y) / 2 + (Math.random() - 0.5) * spread * 0.3))
          next.push(b)
        }
        pts = next
        spread *= 0.55
      }
      out.push(pts)
    }
    return out
  }
  // A bolt itself: a flicker, a second flash, then fading.
  function flashOf(age) {
    if (age < 0) return 0
    if (age < 0.06) return 1
    if (age < 0.12) return 0.3
    if (age < 0.2) return 0.85
    return Math.max(0, 1 - (age - 0.2) / 0.5)
  }
  // The light it throws on the sky and the screen: one soft flash per
  // strike (a quick rise, a slow fade), never a strobe.
  function glowOf(age) {
    if (age < 0) return 0
    if (age < 0.04) return age / 0.04
    return Math.max(0, 1 - (age - 0.04) / 0.45)
  }
  readonly property real lastAge: fired > 0 ? now - strikes[fired - 1].at : -1
  readonly property real flash: glowOf(lastAge)

  // The sky darkening.
  Rectangle {
    anchors.fill: parent
    opacity: storm.dark
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha("#0a0d16", 0.85) }
      GradientStop { position: 0.5; color: Util.alpha("#0a0d16", 0.6) }
      GradientStop { position: 1.0; color: Util.alpha("#05060a", 0.5) }
    }
  }
  // Clouds rolling in along the top, lit from inside by each strike.
  Repeater {
    model: 14
    SoftGlow {
      required property int index
      readonly property real a: storm.host.hash(index * 2.9)
      readonly property real b: storm.host.hash(index * 7.3)
      hue: Qt.tint("#1b2130", Util.alpha(Qt.lighter(storm.host.tint, 1.6), 0.55 * storm.flash * Math.max(0, 1 - Math.abs(a - (storm.fired > 0 ? storm.strikes[storm.fired - 1].x : 0.5)) * 2.5)))
      x: storm.width * (a * 1.2 - 0.1) + storm.now * (10 + 20 * b) * storm.s - 50
      y: storm.height * (0.02 + 0.12 * b) - 50
      opacity: storm.dark * 0.95
      transform: Scale { origin.x: 50; origin.y: 50; xScale: storm.width * (0.25 + 0.2 * b) / 100; yScale: storm.height * (0.16 + 0.1 * a) / 100 }
    }
  }
  // Rain, slanting.
  Repeater {
    model: 140
    Rectangle {
      required property int index
      readonly property real a: storm.host.hash(index * 1.7)
      readonly property real b: storm.host.hash(index * 5.1)
      readonly property real p: (storm.now * (1.1 + 0.6 * b) + a) % 1
      width: Math.max(1, 1.2 * storm.s)
      height: (14 + 16 * b) * storm.s
      x: storm.width * ((index / 140 + p * 0.12) % 1)
      y: storm.height * (p * 1.2 - 0.1)
      rotation: 14
      color: Util.alpha("#c8d6ff", 0.25 + 0.2 * b)
      opacity: storm.dark * Math.min(1, storm.now / 1.2)
    }
  }
  // The screen flashing with each strike.
  Rectangle {
    anchors.fill: parent
    color: Qt.tint("#dfe8ff", Util.alpha(storm.host.tint, 0.2))
    opacity: 0.08 * storm.flash * storm.dark
  }

  // The bolts, drawn through a bloom.
  Item {
    id: sky
    anchors.fill: parent
    opacity: 0
    layer.enabled: true

    Repeater {
      model: storm.bolts.length
      Shape {
        required property int index
        readonly property var b: storm.bolts[index]
        readonly property real age: storm.now - b.at
        anchors.fill: parent
        opacity: storm.flashOf(age) * (b.big ? 1 : 0.9)
        visible: opacity > 0.01
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Util.alpha(Qt.lighter(storm.host.tint, 1.5), 0.45)
          strokeWidth: (b.big ? 12 : 8) * storm.s
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: b.main }
        }
        ShapePath {
          strokeColor: Qt.tint("#ffffff", Util.alpha(storm.host.tint, 0.15))
          strokeWidth: (b.big ? 3 : 2) * storm.s
          fillColor: "transparent"
          joinStyle: ShapePath.MiterJoin
          capStyle: ShapePath.RoundCap
          PathPolyline { path: b.main }
        }
        ShapePath {
          strokeColor: Util.alpha(Qt.tint("#ffffff", Util.alpha(storm.host.tint, 0.3)), 0.8)
          strokeWidth: 1.4 * storm.s
          fillColor: "transparent"
          joinStyle: ShapePath.MiterJoin
          capStyle: ShapePath.RoundCap
          PathMultiline { paths: b.forks }
        }
      }
    }

    // READY, crackling where the last bolt landed.
    Text {
      id: stormWord
      readonly property real e: Math.max(0, Math.min(1, (storm.now - storm.readyAt) / 0.3))
      anchors.horizontalCenter: parent.horizontalCenter
      y: storm.height * 0.52
      opacity: storm.now > storm.readyAt ? e : 0
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha(storm.host.tint, 0.35))
      font.family: storm.host.displayFamily
      font.pixelSize: 84 * storm.s
      font.weight: Font.DemiBold
      font.letterSpacing: 12 * storm.s
    }
  }
  MultiEffect {
    anchors.fill: sky
    source: sky
    blurEnabled: true
    blurMax: 40
    blur: 0.85
    brightness: 0.4
    opacity: storm.dark
  }
  MultiEffect {
    anchors.fill: sky
    source: sky
    opacity: storm.dark
  }

  // Little arcs jumping between READY's letters while it crackles.
  property var wordArcs: []
  Timer {
    interval: 300
    repeat: true
    running: storm.now > storm.readyAt + 0.2 && storm.now < storm.dur - 1.0
    onTriggered: {
      var out = []
      var x0 = stormWord.x, w = stormWord.width, y0 = stormWord.y + stormWord.height * 0.35, h = stormWord.height * 0.45
      for (var n = 0; n < 2; n++) {
        var ax = x0 + Math.random() * w, ay = y0 + Math.random() * h
        var pts = [Qt.point(ax, ay)]
        for (var k = 1; k <= 4; k++) pts.push(Qt.point(ax + k * (10 + Math.random() * 8) * storm.s * (n ? -1 : 1), ay + (Math.random() - 0.5) * 18 * storm.s))
        out.push(pts)
      }
      storm.wordArcs = out
    }
  }
  Shape {
    anchors.fill: parent
    visible: storm.now > storm.readyAt + 0.2 && storm.now < storm.dur - 1.0 && storm.wordArcs.length > 0
    opacity: storm.dark
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.tint("#ffffff", Util.alpha(storm.host.tint, 0.4))
      strokeWidth: 1.4 * storm.s
      fillColor: "transparent"
      joinStyle: ShapePath.MiterJoin
      PathMultiline { paths: storm.wordArcs }
    }
  }
}
