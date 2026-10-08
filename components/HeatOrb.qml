import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The hero's centrepiece: a ring that fills as the chamber climbs toward
// the profile's target, a Peak whose light ring glows the profile's colour, wisps of vapour
// drifting up while heating, and sleepy z's while the Peak is away.
Item {
  id: orb

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real progress: 0
  property color tint: Color.accent
  property bool lit: false
  property bool climbing: false
  property bool sleeping: false
  readonly property bool live: panel.opened

  // Soft backlight that swells with the heat.
  Rectangle {
    anchors.centerIn: parent
    width: parent.width * 0.86
    height: width
    radius: width / 2
    color: Util.alpha(orb.tint, orb.lit ? 0.2 : 0.08)

    Behavior on color { ColorAnimation { duration: 400 } }

    SequentialAnimation on scale {
      running: orb.lit && orb.live
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 1.12; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.12; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
    }
  }

  TimerRing {
    panel: orb.panel
    anchors.fill: parent
    thickness: Style.space(4)
    progress: orb.progress
    fillColor: orb.tint
    startColor: Color.accent
    trackColor: Util.alpha(panel.foreground, 0.08)

    Behavior on progress { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
  }

  // Vapour wisps, only while heating.
  Repeater {
    model: 4

    Rectangle {
      id: wisp
      required property int index
      readonly property real drift: (index % 2 === 0 ? -1 : 1) * orb.width * (0.08 + 0.04 * index)
      x: orb.width / 2 - width / 2
      y: orb.height * 0.2
      width: orb.width * 0.13
      height: width
      radius: width / 2
      color: Util.alpha(panel.foreground, 0.5)
      opacity: 0
      visible: orb.lit

      SequentialAnimation {
        running: orb.lit && orb.live
        loops: Animation.Infinite
        PauseAnimation { duration: wisp.index * 420 }
        ParallelAnimation {
          NumberAnimation { target: wisp; property: "y"; from: orb.height * 0.2; to: -orb.height * 0.12; duration: 1600; easing.type: Easing.OutSine }
          NumberAnimation { target: wisp; property: "x"; from: orb.width / 2 - wisp.width / 2; to: orb.width / 2 - wisp.width / 2 + wisp.drift; duration: 1600; easing.type: Easing.InOutSine }
          NumberAnimation { target: wisp; property: "scale"; from: 0.5; to: 1.6; duration: 1600 }
          SequentialAnimation {
            NumberAnimation { target: wisp; property: "opacity"; from: 0; to: 0.55; duration: 300 }
            NumberAnimation { target: wisp; property: "opacity"; to: 0; duration: 1300; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }

  // A Peak Pro in silhouette, as the Puffco app shows it: the glass on top,
  // the base below, and the light ring round the foot glowing the active
  // profile's colour. It breathes while the chamber climbs, shines once at
  // temperature, and goes dark while the Peak is away.
  Item {
    id: peak
    anchors.horizontalCenter: parent.horizontalCenter
    y: orb.height * 0.2
    width: orb.width * 0.4
    height: orb.height * 0.6

    readonly property color glassLine: Util.alpha(panel.foreground, orb.sleeping ? 0.25 : 0.55)
    property real glow: orb.sleeping ? 0.15 : (orb.lit ? 1 : 0.6)
    Behavior on glow { NumberAnimation { duration: 400 } }

    // Mouthpiece.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 0
      width: parent.width * 0.26
      height: parent.height * 0.14
      radius: width * 0.3
      color: "transparent"
      border.color: peak.glassLine
      border.width: Math.max(1, Style.space(1.5))
    }
    // The glass bubble.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.1
      width: parent.width * 0.82
      height: parent.height * 0.42
      radius: width * 0.42
      color: Util.alpha(orb.tint, orb.lit ? 0.16 : 0.05)
      border.color: peak.glassLine
      border.width: Math.max(1, Style.space(1.5))
      Behavior on color { ColorAnimation { duration: 400 } }
    }
    // The base: a squat, slightly flared body.
    Rectangle {
      id: peakBase
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.48
      width: parent.width
      height: parent.height * 0.48
      radius: width * 0.14
      border.width: 1
      border.color: Util.alpha(panel.foreground, orb.sleeping ? 0.2 : 0.4)
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(panel.foreground, orb.sleeping ? 0.22 : 0.5) }
        GradientStop { position: 0.25; color: Util.alpha(panel.foreground, orb.sleeping ? 0.14 : 0.3) }
        GradientStop { position: 1.0; color: Util.alpha(panel.foreground, orb.sleeping ? 0.1 : 0.2) }
      }
    }
    // Light ring round the foot, with its glow spilling onto the desk.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: ring.verticalCenter
      width: parent.width * 1.5
      height: parent.height * 0.22
      radius: height / 2
      color: Util.alpha(orb.tint, 0.22 * peak.glow)
    }
    Rectangle {
      id: ring
      anchors.horizontalCenter: parent.horizontalCenter
      y: peakBase.y + peakBase.height - height * 1.4
      width: peakBase.width * 0.92
      height: Math.max(2, parent.height * 0.06)
      radius: height / 2
      color: orb.sleeping ? panel.dim : orb.tint
      opacity: 0.35 + 0.65 * peak.glow
      Behavior on color { ColorAnimation { duration: 300 } }
    }

    SequentialAnimation on glow {
      running: orb.climbing && orb.live
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }
  }

  // Sleepy z's drifting off to the upper right.
  Repeater {
    model: 3

    Text {
      id: zee
      required property int index
      textFormat: Text.PlainText
      text: "z"
      visible: orb.sleeping
      x: orb.width * 0.62
      y: orb.height * 0.3
      opacity: 0
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption + zee.index * 2
      font.bold: true

      SequentialAnimation {
        running: orb.sleeping && orb.live
        loops: Animation.Infinite
        PauseAnimation { duration: zee.index * 700 }
        ParallelAnimation {
          NumberAnimation { target: zee; property: "x"; from: orb.width * 0.6; to: orb.width * 0.95; duration: 2100; easing.type: Easing.OutSine }
          NumberAnimation { target: zee; property: "y"; from: orb.height * 0.3; to: -orb.height * 0.05; duration: 2100; easing.type: Easing.OutSine }
          SequentialAnimation {
            NumberAnimation { target: zee; property: "opacity"; from: 0; to: 0.9; duration: 400 }
            NumberAnimation { target: zee; property: "opacity"; to: 0; duration: 1700 }
          }
        }
      }
    }
  }
}
