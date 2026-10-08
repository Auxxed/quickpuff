import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// A glowing orb previewing the lantern: the profile's colour at the chosen
// brightness, with ripples spreading out while the LEDs are on.
Item {
  id: lantern

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property color glow: Color.accent
  property real level: 1
  property bool lit: true
  readonly property real strength: lit ? 0.3 + 0.7 * level : 0.12

  implicitHeight: Style.space(78)

  Repeater {
    model: 2

    Rectangle {
      id: ripple
      required property int index
      anchors.centerIn: parent
      width: lantern.height * 0.5
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: Util.alpha(lantern.glow, 0.6 * lantern.strength)
      opacity: 0
      visible: lantern.lit

      SequentialAnimation {
        running: lantern.lit && panel.opened && panel.onLights
        loops: Animation.Infinite
        PauseAnimation { duration: ripple.index * 1100 }
        ParallelAnimation {
          NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.9; duration: 2200; easing.type: Easing.OutSine }
          NumberAnimation { target: ripple; property: "opacity"; from: 1; to: 0; duration: 2200; easing.type: Easing.InQuad }
        }
      }
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: lantern.height * 0.78
    height: width
    radius: width / 2
    color: Util.alpha(lantern.glow, 0.14 * lantern.strength)

    Behavior on color { ColorAnimation { duration: 300 } }

    // A lit lantern breathes; an off one holds still.
    SequentialAnimation on scale {
      running: lantern.lit && panel.opened && panel.onLights
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 1.1; duration: 1800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    id: lanternCore
    anchors.centerIn: parent
    width: lantern.height * 0.46
    height: width
    radius: width / 2
    color: Util.alpha(lantern.glow, lantern.strength)
    border.width: 1
    border.color: Util.alpha(panel.foreground, 0.25)

    Behavior on color { ColorAnimation { duration: 300 } }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: lantern.lit ? Math.round(lantern.level * 100) + "%" : "off"
      color: lantern.lit ? panel.inkOn(lantern.glow) : panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
