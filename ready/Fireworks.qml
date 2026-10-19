import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ============================================================ Fireworks
// Ten shells whistle up across the whole width of the screen and burst in
// the profile's colour, gold and white: big peonies with a white heart,
// and two gold willows whose sparks droop and linger. Every spark drags a
// streak along its flight; each burst flashes and lights up the sky, with
// a bloom over it all.
Item {
  id: fw
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property real t: 0
  readonly property real dur: 6.2
  readonly property real now: t * dur
  readonly property real s: fw.host.u * fw.host.stage
  readonly property var hues: [fw.host.tint, "#ffd76a", "#ffffff", Qt.lighter(fw.host.tint, 1.5), Color.accent, "#ff6ad5", "#7fe3ff"]
  // The show, in launch order: where each shell bursts (fractions of the
  // screen), when it leaves the ground (s), how far its sparks fly (a
  // fraction of the screen height), its colour (into `hues`), and whether
  // it is a gold willow. Everything is out by about 5.9 s.
  readonly property var basePlan: [
    { "x": 0.50, "y": 0.30, "at": 0.05, "size": 0.26, "hue": 0, "willow": false },
    { "x": 0.18, "y": 0.36, "at": 0.45, "size": 0.21, "hue": 5, "willow": false },
    { "x": 0.80, "y": 0.26, "at": 0.85, "size": 0.24, "hue": 1, "willow": true },
    { "x": 0.34, "y": 0.22, "at": 1.25, "size": 0.19, "hue": 6, "willow": false },
    { "x": 0.64, "y": 0.38, "at": 1.55, "size": 0.23, "hue": 3, "willow": false },
    { "x": 0.10, "y": 0.28, "at": 1.90, "size": 0.18, "hue": 2, "willow": false },
    { "x": 0.42, "y": 0.24, "at": 2.25, "size": 0.27, "hue": 1, "willow": true },
    { "x": 0.90, "y": 0.34, "at": 2.45, "size": 0.22, "hue": 4, "willow": false },
    { "x": 0.26, "y": 0.42, "at": 2.85, "size": 0.20, "hue": 5, "willow": false },
    { "x": 0.70, "y": 0.20, "at": 3.15, "size": 0.28, "hue": 0, "willow": false }
  ]
  // No two shows alike: every shell bursts a little to one side, higher or
  // lower, early or late, bigger or smaller, in another of the colours, and
  // now and then as a willow. Worked out once, when the show starts.
  readonly property var plan: basePlan.map(function(p) {
    return {
      "x": Math.max(0.06, Math.min(0.94, p.x + (Math.random() - 0.5) * 0.12)),
      "y": Math.max(0.16, Math.min(0.46, p.y + (Math.random() - 0.5) * 0.08)),
      "at": Math.max(0, p.at + (Math.random() - 0.5) * 0.16),
      "size": p.size * (0.9 + Math.random() * 0.2),
      "hue": Math.floor(Math.random() * 7),
      "willow": Math.random() < 0.2
    }
  })

  // Seconds a shell takes to climb (higher bursts take longer), and its
  // colour.
  function climbTime(spec) { return 0.55 + 0.55 * (1 - spec.y) }
  function hueOf(spec) { return spec.willow ? "#ffc861" : fw.hues[spec.hue] }

  NumberAnimation on t { from: 0; to: 1; duration: 6200; running: true; onFinished: fw.host.finished() }

  // Each burst lights up the sky round it. Drawn straight rather than
  // through the bloom, which would band the wide, faint edge.
  Repeater {
    model: fw.plan.length

    SoftGlow {
      required property int index
      readonly property var spec: fw.plan[index]
      readonly property real f: Math.max(0, Math.min(1, (fw.now - spec.at - fw.climbTime(spec)) / 0.9))
      visible: f > 0 && f < 1
      hue: fw.hueOf(spec)
      x: fw.width * spec.x - 50
      y: fw.height * spec.y - 50
      scale: fw.height * spec.size * 4 / 100
      opacity: 0.2 * (1 - f) * (1 - f)
    }
  }

  // Drawn only through the effects below. Everything in here hides with
  // opacity, never `visible`: a child that starts hidden inside a hidden
  // layer source never shows up in the layer, even once it is visible.
  Item {
    id: night
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: fw.plan.length

      Item {
        id: shell
        required property int index
        readonly property var spec: fw.plan[index]
        readonly property bool willow: spec.willow
        readonly property int count: willow ? 32 : 40
        // Seconds to climb, and for the sparks to burn out.
        readonly property real climb: fw.climbTime(spec)
        readonly property real life: willow ? 2.7 : 1.8
        readonly property real bx: fw.width * spec.x
        readonly property real by: fw.height * spec.y
        // Launched a little to one side, so the climb leans.
        readonly property real lx: bx + (index % 2 ? 1 : -1) * fw.width * 0.035
        readonly property real radius: fw.height * spec.size
        readonly property color hue: fw.hueOf(spec)
        readonly property bool launched: fw.now >= spec.at
        // 0..1 through the climb, then seconds since the burst. Both hold
        // still outside their stretch, so idle sparks cost nothing.
        readonly property real rise: Math.max(0, Math.min(1, (fw.now - spec.at) / climb))
        readonly property real age: Math.max(0, Math.min(life, fw.now - spec.at - climb))
        readonly property real burst: age / life
        // Flight, shared by every spark of the shell: air drag slows the
        // spread (the share of its reach covered, and how fast, per second)
        // and gravity pulls toward a terminal fall speed.
        readonly property real drag: willow ? 2.4 : 3.6
        readonly property real spread: 1 - Math.exp(-drag * age)
        readonly property real speed: drag * Math.exp(-drag * age)
        readonly property real fallMax: fw.height * (willow ? 0.17 : 0.09)
        readonly property real drop: fallMax * (age - (1 - Math.exp(-1.5 * age)) / 1.5)
        readonly property real dropRate: fallMax * (1 - Math.exp(-1.5 * age))
        // Each spark's streak: seconds of its flight, and the longest.
        readonly property real trail: willow ? 0.28 : 0.1
        readonly property real maxTrail: fw.height * (willow ? 0.14 : 0.1)
        // Willows linger; late in the burst a third of the sparks glitter.
        readonly property real fade: willow
          ? 1 - Math.pow(Math.max(0, burst - 0.35) / 0.65, 1.6)
          : 1 - Math.pow(Math.max(0, burst - 0.5) / 0.5, 1.3)
        readonly property real glitter: Math.max(0, Math.min(1, (burst - 0.4) / 0.2))

        onLaunchedChanged: if (launched) fw.host.cue("firework")

        // The climbing shell: a hot head and its trail, leaning with it.
        Rectangle {
          readonly property real e: 1 - Math.pow(1 - shell.rise, 2)
          opacity: shell.rise > 0 && shell.rise < 1 ? 1 : 0
          width: 4 * fw.s
          height: (40 + 70 * (1 - shell.rise)) * fw.s
          radius: width / 2
          transformOrigin: Item.Top
          rotation: Math.atan2(shell.bx - shell.lx, fw.height - shell.by) * 180 / Math.PI
          x: shell.lx + (shell.bx - shell.lx) * e - width / 2
          y: fw.height - (fw.height - shell.by) * e
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 0.12; color: Qt.lighter(shell.hue, 1.4) }
            GradientStop { position: 1.0; color: Util.alpha(shell.hue, 0) }
          }
        }

        // The bang: a white-hot core.
        SoftGlow {
          readonly property real f: Math.min(1, shell.age / 0.3)
          hue: "#ffffff"
          x: shell.bx - 50
          y: shell.by - 50
          scale: shell.radius * (0.4 + 0.6 * f) / 100
          opacity: shell.age > 0 ? 1 - f : 0
        }

        // The sparks.
        Item {
          opacity: shell.age > 0 && shell.age < shell.life ? 1 : 0

          Repeater {
            model: shell.count

            Rectangle {
              id: spark
              required property int index
              readonly property real angle: index / shell.count * Math.PI * 2 + shell.index * 0.7 + ((index * 53) % 10) / 40
              // A ball of sparks seen from the side: most fly out near the
              // rim, the rest toward or away from us and look shorter.
              readonly property real depth: Math.sin((((index * 7) % shell.count) + 0.5) / shell.count * Math.PI)
              // Every 5th spark of a peony is its heart: a tight inner ring.
              readonly property bool heart: !shell.willow && index % 5 === 0
              readonly property real reach: shell.radius * (heart ? 0.4 : depth * (0.88 + ((index * 37) % 25) / 100))
              readonly property real dx: Math.cos(angle) * reach
              readonly property real dy: Math.sin(angle) * reach
              readonly property real vx: dx * shell.speed
              readonly property real vy: dy * shell.speed + shell.dropRate
              readonly property color hue: shell.willow
                ? (index % 3 ? "#ffc861" : "#ff9f43")
                : (heart ? (shell.spec.hue === 2 ? "#ffd76a" : "#ffffff") : (index % 6 === 0 ? Qt.lighter(shell.hue, 1.35) : shell.hue))

              // A streak behind the spark, its head at the spark and turned
              // along its flight: long while fast, a dot once it hangs.
              height: (heart ? 2.8 : 3.6) * fw.s
              width: Math.min(shell.maxTrail, Math.max(height, Math.sqrt(vx * vx + vy * vy) * shell.trail))
              radius: height / 2
              transformOrigin: Item.Right
              rotation: Math.atan2(vy, vx) * 180 / Math.PI
              x: shell.bx + dx * shell.spread - width
              y: shell.by + dy * shell.spread + shell.drop - height / 2
              opacity: shell.fade * (index % 3 ? 1 : 1 - shell.glitter * (Math.sin(shell.age * 41 + index * 1.7) > 0 ? 0.85 : 0))
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Util.alpha(spark.hue, 0) }
                GradientStop { position: 0.65; color: spark.hue }
                GradientStop { position: 1.0; color: shell.willow ? "#fff4d6" : "#ffffff" }
              }
            }
          }
        }
      }
    }
  }

  // The bloom, then the sparks themselves, crisp, on top of it.
  MultiEffect {
    anchors.fill: night
    source: night
    blurEnabled: true
    blurMax: 48
    blur: 0.9
    brightness: 0.3
    opacity: 0.9
  }
  MultiEffect {
    anchors.fill: night
    source: night
    blurEnabled: true
    blurMax: 4
    blur: 0.25
  }

  ReadyWord { host: fw.host; now: fw.now; at: 1.0; until: fw.dur - 0.8; y: fw.height * 0.45 }
}
