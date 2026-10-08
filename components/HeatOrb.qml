import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The hero's centrepiece: a ring that fills as the chamber climbs toward
// the profile's target, a flame that flickers while lit, wisps of vapour
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
      y: orb.height * 0.34
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
          NumberAnimation { target: wisp; property: "y"; from: orb.height * 0.34; to: -orb.height * 0.05; duration: 1600; easing.type: Easing.OutSine }
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

  Text {
    id: flame
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: orb.sleeping ? "" : ""
    color: orb.sleeping ? panel.dim : orb.tint
    font.family: panel.fontFamily
    font.pixelSize: Style.font.display
    transformOrigin: Item.Bottom

    Behavior on color { ColorAnimation { duration: 300 } }

    // A lively flicker while lit, a slow breath while climbing to temp.
    SequentialAnimation {
      running: orb.lit && orb.live
      loops: Animation.Infinite
      alwaysRunToEnd: true
      ParallelAnimation {
        NumberAnimation { target: flame; property: "scale"; to: 1.1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: flame; property: "rotation"; to: -5; duration: 180 }
      }
      ParallelAnimation {
        NumberAnimation { target: flame; property: "scale"; to: 0.95; duration: 240; easing.type: Easing.InOutQuad }
        NumberAnimation { target: flame; property: "rotation"; to: 4; duration: 240 }
      }
      ParallelAnimation {
        NumberAnimation { target: flame; property: "scale"; to: 1.05; duration: 200 }
        NumberAnimation { target: flame; property: "rotation"; to: -2; duration: 200 }
      }
      ParallelAnimation {
        NumberAnimation { target: flame; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutQuad }
        NumberAnimation { target: flame; property: "rotation"; to: 0; duration: 260 }
      }
    }

    SequentialAnimation on opacity {
      running: orb.climbing && orb.live
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
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
