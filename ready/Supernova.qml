import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Supernova
// Deep space falls over the desktop. A star gathers light in a slow
// spiral and feeds with a heartbeat, collapses to a pinprick, then
// detonates: a flash, a shockwave, a lens flare across the screen, rays
// wheeling out of the core, debris and embers flung wide, and a nebula
// blooming (a glowing shell of gas in the profile's colour and its
// neighbours, veined with dark dust, star dust glittering in it) while
// READY condenses out of the light.
Item {
  id: nova
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.4
  readonly property real now: t * dur
  readonly property real s: nova.host.u * nova.host.stage
  readonly property real cx: width * 0.5
  readonly property real cy: height * 0.45
  readonly property real blastAt: 1.9
  // Seconds since the blast; negative before it.
  readonly property real since: now - blastAt
  readonly property real dark: Math.min(1, now / 0.7) * Math.max(0, Math.min(1, (dur - now) / 1.0))
  // How far the remnant has spread: fast at first, then drifting.
  readonly property real spread: since <= 0 ? 0 : 1 - Math.exp(-since / 1.1)
  // The remnant's gas: the profile's colour and its neighbours, with the
  // pale blue-white of the hottest filaments (like the Crab's), not a
  // rainbow.
  readonly property var cloud: [nova.host.tint, nova.host.hueTurn(0.06, 0.85, 0.6), nova.host.hueTurn(-0.07, 0.8, 0.55),
    "#c4d8ff", nova.host.hueTurn(0.1, 0.55, 0.72), "#9fb8ff"]
  property bool blown: false

  NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: nova.host.finished() }
  onSinceChanged: if (since >= 0 && !blown) {
    blown = true
    debris.burst(360)
    embers.burst(70)
    nova.host.cue("firework")
  }

  // Deep space, and its far stars.
  Rectangle { anchors.fill: parent; color: "#03020a"; opacity: 0.76 * nova.dark }
  Repeater {
    model: 130
    Rectangle {
      required property int index
      readonly property real a: nova.host.hash(index * 1.31)
      readonly property real b: nova.host.hash(index * 7.17)
      readonly property real c: nova.host.hash(index * 3.3)
      width: (0.8 + 2 * c * c) * nova.s
      height: width
      radius: width / 2
      x: a * nova.width
      y: b * nova.height
      color: index % 5 ? "#dfe6ff" : Qt.lighter(nova.host.tint, 1.6)
      opacity: nova.dark * (0.3 + 0.7 * Math.abs(Math.sin(nova.now * (0.7 + 2 * a) + index)))
    }
  }

  // Gathering: motes of light spiralling in to feed the star.
  Repeater {
    model: 80
    Rectangle {
      required property int index
      readonly property real seedA: nova.host.hash(index * 2.71)
      readonly property real seedB: nova.host.hash(index * 9.13)
      readonly property real start: 0.1 + seedA * 0.9
      readonly property real g: Math.max(0, Math.min(1, (nova.now - start) / (nova.blastAt - 0.2 - start)))
      readonly property real r: (0.14 + 0.36 * seedB) * nova.height * Math.pow(1 - g, 1.5)
      readonly property real a: seedB * 6.283 + (1 - Math.pow(1 - g, 2)) * 5.5
      width: (1.6 + 3 * seedA) * nova.s
      height: width
      radius: width / 2
      x: nova.cx + Math.cos(a) * r - width / 2
      y: nova.cy + Math.sin(a) * r * 0.8 - height / 2
      color: index % 3 ? Qt.lighter(nova.host.tint, 1.5) : "#ffffff"
      opacity: g > 0 && g < 1 ? Math.min(1, g * 5) * nova.dark : 0
    }
  }

  // The star: swelling as it feeds, a heartbeat in its light, a pinprick
  // for an instant before the blast.
  readonly property real coreSize: {
    if (since >= 0) return 0
    if (now > blastAt - 0.18) return 3 * s
    var feed = Math.min(1, now / (blastAt - 0.2))
    return (5 + 24 * feed) * s * (1 + 0.2 * Math.sin(now * 13) * feed)
  }
  SoftGlow {
    hue: Qt.lighter(nova.host.tint, 1.35)
    x: nova.cx - 50
    y: nova.cy - 50
    scale: nova.coreSize * 5 / 100
    opacity: nova.since < 0 ? nova.dark : 0
  }
  Rectangle {
    width: nova.coreSize
    height: width
    radius: width / 2
    x: nova.cx - width / 2
    y: nova.cy - height / 2
    color: "#ffffff"
    visible: nova.since < 0
  }

  // The nebula, turning slowly, blurred into gas.
  Item {
    anchors.fill: parent
    opacity: nova.since >= 0 ? Math.min(1, nova.since / 0.3) * nova.dark : 0
    transform: Rotation { origin.x: nova.cx; origin.y: nova.cy; angle: 7 * Math.max(0, nova.since) }
    layer.enabled: nova.since >= 0
    layer.effect: MultiEffect {
      blurEnabled: true
      blurMax: 40
      blur: 0.7
      saturation: 0.15
    }

    // A faint glow of hot gas inside, in the profile's colour, darker
    // toward the middle the way a shell nebula is hollow.
    SoftGlow {
      hue: Util.alpha(nova.host.tint, 0.3)
      x: nova.cx - 50
      y: nova.cy - 50
      opacity: 0.6
      transform: Scale { origin.x: 50; origin.y: 50; xScale: nova.height * (0.12 + 0.6 * nova.spread) / 100; yScale: nova.height * (0.1 + 0.5 * nova.spread) / 100 }
    }
    // The shell: clumps of glowing gas strung unevenly round the blast
    // front, stretched along it and overlapping, with a second, fainter
    // layer just inside in other colours.
    Repeater {
      model: 60
      SoftGlow {
        required property int index
        readonly property bool inner: index % 3 === 2
        readonly property real a: nova.host.hash(index * 2.9) * 6.283
        readonly property real r: nova.height * (0.07 + 0.3 * nova.spread) * (inner ? 0.72 : 1) * (0.78 + 0.44 * nova.host.hash(index * 5.3))
        readonly property real len: nova.height * (0.1 + 0.18 * nova.host.hash(index * 1.7)) * (0.3 + 0.7 * nova.spread)
        hue: Util.alpha(nova.cloud[(index * 5 + (inner ? 3 : 0)) % nova.cloud.length], inner ? 0.3 : 0.5)
        x: nova.cx + Math.cos(a) * r - 50
        y: nova.cy + Math.sin(a) * r * 0.84 - 50
        opacity: 0.6
        transform: [
          Scale { origin.x: 50; origin.y: 50; xScale: len / 100; yScale: len * (0.1 + 0.1 * nova.host.hash(index * 8.1)) / 100 },
          Rotation { origin.x: 50; origin.y: 50; angle: a * 180 / Math.PI + 90 + (nova.host.hash(index * 4.4) - 0.5) * 30 }
        ]
      }
    }
    // Dark dust lanes crossing it, for depth.
    Repeater {
      model: 4
      SoftGlow {
        required property int index
        readonly property real a: nova.host.hash(index * 7.7) * 6.283
        readonly property real len: nova.height * (0.22 + 0.2 * nova.host.hash(index * 3.9)) * nova.spread
        hue: Util.alpha("#020106", 0.7)
        x: nova.cx + Math.cos(a) * nova.height * 0.12 * nova.spread - 50
        y: nova.cy + Math.sin(a) * nova.height * 0.1 * nova.spread - 50
        opacity: 0.6
        transform: [
          Scale { origin.x: 50; origin.y: 50; xScale: len / 100; yScale: len * 0.18 / 100 },
          Rotation { origin.x: 50; origin.y: 50; angle: nova.host.hash(index * 9.1) * 180 }
        ]
      }
    }
  }

  // Rays wheeling out of the core.
  Repeater {
    model: 16
    Rectangle {
      required property int index
      readonly property real len: nova.height * (0.22 + 0.32 * nova.host.hash(index * 3.7)) * (0.4 + 0.6 * nova.spread)
      x: nova.cx
      y: nova.cy - height / 2
      width: len
      height: (2 + 4 * nova.host.hash(index * 1.1)) * nova.s
      radius: height / 2
      rotation: index / 16 * 360 + nova.host.hash(index) * 14 + 6 * Math.max(0, nova.since)
      transformOrigin: Item.Left
      opacity: nova.since >= 0 ? 0.5 * Math.min(1, nova.since / 0.15) * Math.max(0, 1 - nova.since / 3.2) * nova.dark : 0
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#ffffff" }
        GradientStop { position: 0.3; color: Util.alpha(Qt.lighter(nova.host.tint, 1.6), 0.6) }
        GradientStop { position: 1.0; color: Util.alpha(nova.host.tint, 0) }
      }
    }
  }

  // The blast's white heart, and the core left behind, still burning.
  SoftGlow {
    hue: "#ffffff"
    x: nova.cx - 50
    y: nova.cy - 50
    readonly property real f: Math.max(0, Math.min(1, nova.since / 1.6))
    scale: nova.height * (0.12 + 0.3 * Math.sqrt(f)) / 100
    opacity: nova.since >= 0 ? Math.pow(1 - f, 1.6) : 0
  }
  SoftGlow {
    hue: Qt.tint("#ffffff", Util.alpha(nova.host.tint, 0.3))
    x: nova.cx - 50
    y: nova.cy - 50
    scale: (22 + 4 * Math.sin(nova.now * 9)) * nova.s / 100
    opacity: nova.since >= 0 ? nova.dark : 0
  }

  // The shockwave: one ring, a bright thin line in a soft wide glow.
  Repeater {
    model: [{ "w": 0.008, "a": 0.6, "sp": 1.0 }, { "w": 0.03, "a": 0.14, "sp": 1.0 }]
    Rectangle {
      required property var modelData
      readonly property real p: Math.max(0, Math.min(1, nova.since / 1.5))
      readonly property real e: 1 - Math.pow(1 - p, 3)
      width: nova.height * (0.06 + 2.1 * e) * modelData.sp
      height: width
      radius: width / 2
      x: nova.cx - width / 2
      y: nova.cy - height / 2
      color: "transparent"
      border.width: Math.max(1, nova.height * modelData.w * (1 - 0.6 * e))
      border.color: Util.alpha(Qt.lighter(nova.host.tint, 1.5), modelData.a)
      opacity: nova.since >= 0 && p < 1 ? Math.pow(1 - p, 1.4) : 0
    }
  }

  // Lens flare: a streak of light across the whole screen through the core.
  Repeater {
    model: [{ "h": 3, "a": 1.0 }, { "h": 40, "a": 0.2 }]
    Rectangle {
      required property var modelData
      readonly property real p: Math.max(0, Math.min(1, nova.since / 1.6))
      width: nova.width * (0.25 + 0.9 * Math.sqrt(p))
      height: modelData.h * nova.s * (1 - 0.5 * p)
      radius: height / 2
      x: nova.cx - width / 2
      y: nova.cy - height / 2
      opacity: nova.since >= 0 ? modelData.a * Math.pow(1 - p, 1.5) : 0
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(nova.host.tint, 1.6), 0) }
        GradientStop { position: 0.5; color: "#ffffff" }
        GradientStop { position: 1.0; color: Util.alpha(Qt.lighter(nova.host.tint, 1.6), 0) }
      }
    }
  }

  // Debris, embers and star dust.
  Item {
    anchors.fill: parent
    opacity: nova.dark

    ParticleSystem { id: novaSys; anchors.fill: parent }
    ImageParticle {
      system: novaSys
      groups: ["debris"]
      source: Qt.resolvedUrl("../particles/glow.png")
      color: Qt.lighter(nova.host.tint, 1.45)
      colorVariation: 0.3
      alpha: 0.95
    }
    ImageParticle {
      system: novaSys
      groups: ["embers", "dust"]
      source: Qt.resolvedUrl("../particles/spark.png")
      color: Qt.tint("#fff6e8", Util.alpha(nova.host.tint, 0.25))
      colorVariation: 0.15
      rotationVariation: 30
      alpha: 1
    }
    Emitter {
      id: debris
      system: novaSys
      group: "debris"
      x: nova.cx - 2; y: nova.cy - 2; width: 4; height: 4
      emitRate: 0
      lifeSpan: 2600; lifeSpanVariation: 900
      size: 9 * nova.s; sizeVariation: 6 * nova.s; endSize: 2 * nova.s
      velocity: AngleDirection { angleVariation: 180; magnitude: 640 * nova.s; magnitudeVariation: 480 * nova.s }
    }
    Emitter {
      id: embers
      system: novaSys
      group: "embers"
      x: nova.cx - 2; y: nova.cy - 2; width: 4; height: 4
      emitRate: 0
      lifeSpan: 3000; lifeSpanVariation: 800
      size: 16 * nova.s; sizeVariation: 8 * nova.s; endSize: 3 * nova.s
      velocity: AngleDirection { angleVariation: 180; magnitude: 360 * nova.s; magnitudeVariation: 260 * nova.s }
    }
    Emitter {
      system: novaSys
      group: "dust"
      x: nova.cx - width / 2; y: nova.cy - height / 2
      width: nova.height * 0.85; height: nova.height * 0.6
      shape: EllipseShape { fill: true }
      emitRate: nova.since >= 0.4 && nova.now < nova.dur - 1.2 ? 42 : 0
      lifeSpan: 1500; lifeSpanVariation: 600
      size: 10 * nova.s; sizeVariation: 7 * nova.s; endSize: 0
      velocity: PointDirection { xVariation: 16 * nova.s; yVariation: 16 * nova.s }
    }
    Friction { system: novaSys; groups: ["debris", "embers"]; factor: 1.8 }
  }

  // READY, condensing out of the light: wide tracking pulling in.
  Item {
    readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (nova.since - 0.6) / 1.3)), 3)
    anchors.horizontalCenter: parent.horizontalCenter
    y: nova.cy + nova.height * 0.27
    width: readyWord.implicitWidth
    height: readyWord.implicitHeight
    opacity: nova.since > 0.6 ? e * nova.dark : 0

    Text {
      id: readyWord
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha(nova.host.tint, 0.2))
      // Glowing in the profile's colour (a blob behind it read as a smear).
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        blurMax: 24
        shadowBlur: 0.6
        shadowColor: Util.alpha(Qt.lighter(nova.host.tint, 1.2), 0.7)
      }
      font.family: nova.host.displayFamily
      font.pixelSize: 60 * nova.s
      font.weight: Font.DemiBold
      font.letterSpacing: (14 + 50 * (1 - parent.e)) * nova.s
    }
  }
}
