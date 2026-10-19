import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Celebration pop. `fire()` sends a soft shockwave out from the centre and
// throws a spray of confetti (dots, Puffco logo chips, streaks and a few
// twinkling sparks) that flies out, slows in the air and falls away.
Item {
  id: burst

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property color tint: panel.profileTint
  property real t: 0
  readonly property real dur: 1.15
  readonly property real now: t * dur
  readonly property var colors: [tint, Qt.lighter(tint, 1.45), "#ffffff", "#ffd76a", Color.accent, Qt.lighter(tint, 1.15)]
  // Different every time: which way the spray leans and how hard.
  property real lean: 0
  property real seed: 0

  function fire() {
    lean = (Math.random() - 0.5) * 0.5
    seed = Math.random() * 10
    burstAnim.restart()
  }

  visible: burstAnim.running

  NumberAnimation {
    id: burstAnim
    target: burst
    property: "t"
    from: 0
    to: 1
    duration: burst.dur * 1000
    easing.type: Easing.Linear
  }

  // The shockwave: a thin bright ring and a soft wide one behind it.
  Repeater {
    model: [{ "w": 0.16, "a": 0.25 }, { "w": 0.035, "a": 0.85 }]
    Rectangle {
      required property var modelData
      readonly property real k: Math.min(1, burst.now / 0.6)
      readonly property real e: 1 - Math.pow(1 - k, 3)
      width: burst.width * (0.25 + 0.95 * e)
      height: width
      radius: width / 2
      anchors.centerIn: parent
      color: "transparent"
      border.width: Math.max(1, burst.width * modelData.w * (1 - 0.7 * e))
      border.color: Util.alpha(Qt.lighter(burst.tint, 1.35), modelData.a)
      opacity: Math.pow(1 - k, 1.5)
    }
  }

  Repeater {
    model: 24

    Rectangle {
      id: bit
      required property int index
      // Every 6th a streak, every 4th a logo chip, every 5th a spark.
      readonly property int kind: index % 6 === 0 ? 1 : (index % 4 === 0 ? 2 : (index % 5 === 0 ? 3 : 0))
      readonly property real jitter: (((index * 37 + burst.seed * 13) % 100) / 100) - 0.5
      readonly property real angle: index / 24 * Math.PI * 2 + jitter * 0.5 + burst.lean
      readonly property real speed: burst.width * (1.15 + ((index * 53) % 40) / 50)
      readonly property real drag: 3.4 + (index % 3) * 0.6
      readonly property real gravity: burst.width * 0.62
      readonly property real flight: (1 - Math.exp(-drag * burst.now)) / drag
      readonly property real vx: Math.cos(angle) * speed * Math.exp(-drag * burst.now)
      readonly property real vy: Math.sin(angle) * speed * Math.exp(-drag * burst.now) + gravity * burst.now
      readonly property real px: Math.cos(angle) * speed * flight
      readonly property real py: Math.sin(angle) * speed * flight + 0.5 * gravity * burst.now * burst.now
      readonly property real fade: Math.max(0, 1 - Math.pow(Math.max(0, burst.now - 0.35) / (burst.dur - 0.35), 1.4))

      width: kind === 1 ? Math.max(Style.space(4), Math.min(Style.space(14), Math.sqrt(vx * vx + vy * vy) * 0.045))
        : kind === 2 ? Style.space(4) : Style.space(kind === 3 ? 6 : (index % 3 === 0 ? 6 : 5))
      height: kind === 1 ? Style.space(2) : kind === 2 ? Style.space(8) : width
      radius: kind === 0 ? width / 2 : (kind === 1 ? height / 2 : 1)
      x: burst.width / 2 + px - width / 2
      y: burst.height / 2 + py - height / 2
      color: kind === 3 ? "#ffffff" : burst.colors[index % burst.colors.length]
      rotation: kind === 1 ? Math.atan2(vy, vx) * 180 / Math.PI
        : kind === 3 ? 45 : (index % 2 ? 1 : -1) * 420 * burst.now
      // Sparks twinkle; chips flip like paper.
      scale: kind === 3 ? 0.6 + 0.6 * Math.abs(Math.sin(burst.now * 18 + index)) : 1
      transform: Scale {
        origin.x: bit.width / 2
        xScale: bit.kind === 2 ? Math.cos(burst.now * (9 + bit.index % 5) + bit.index) : 1
      }
      opacity: fade
    }
  }
}
