import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Confetti pop. `fire()` flings a ring of dots outward from the centre.
Item {
  id: burst

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real t: 0
  readonly property var colors: [Color.accent, panel.urgent, panel.foreground, panel.profileTint]

  function fire() { burstAnim.restart() }

  visible: burstAnim.running

  NumberAnimation {
    id: burstAnim
    target: burst
    property: "t"
    from: 0
    to: 1
    duration: 750
    easing.type: Easing.OutCubic
  }

  Repeater {
    model: 14

    Rectangle {
      required property int index
      readonly property real angle: index / 14 * Math.PI * 2 + (index % 2) * 0.2
      readonly property real reach: burst.width * (0.55 + (index % 3) * 0.12) * burst.t
      width: Style.space(index % 3 === 0 ? 5 : 4)
      height: width
      radius: index % 2 === 0 ? width / 2 : 1
      rotation: burst.t * 180
      x: burst.width / 2 + Math.cos(angle) * reach - width / 2
      y: burst.height / 2 + Math.sin(angle) * reach - height / 2
      color: burst.colors[index % burst.colors.length]
      opacity: 1 - burst.t * burst.t
    }
  }
}
