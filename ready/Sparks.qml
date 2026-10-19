import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// A ring of sparks thrown from a point; `fire()` plays it once.
Item {
  id: sparks
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  property int count: 10
  property real reach: 30
  property real dot: 4 * sparks.host.u
  property var hues: ["#ffffff"]
  property real t: 0

  function fire() { sparkAnim.restart() }

  visible: sparkAnim.running

  NumberAnimation {
    id: sparkAnim
    target: sparks
    property: "t"
    from: 0
    to: 1
    duration: 520
    easing.type: Easing.OutCubic
  }

  Repeater {
    model: sparks.count

    Rectangle {
      required property int index
      readonly property real angle: index / sparks.count * Math.PI * 2
      width: sparks.dot
      height: width
      radius: width / 2
      x: Math.cos(angle) * sparks.reach * sparks.t - width / 2
      y: Math.sin(angle) * sparks.reach * sparks.t * 0.6 - height / 2
      color: sparks.hues[index % sparks.hues.length]
      opacity: 1 - sparks.t
    }
  }
}
