import QtQuick
import Quickshell
import qs.Commons

// One row of a list that just arrived (dabs read from the daemon, the fault
// log, Peaks found nearby): it fades and rises in a beat after the row
// above. A list rebuilt later (a note saved, Show more) isn't fresh, so its
// rows simply stay put. Give the row `transform: Translate { id: x }` and
// pass it as `shift`.
Item {
  id: enter

  property Item target: null
  property Translate shift: null
  property int index: 0
  property bool fresh: false

  visible: false
  width: 0
  height: 0

  Component.onCompleted: {
    if (!fresh || !target || !shift) return
    target.opacity = 0
    shift.y = Style.space(10)
    anim.start()
  }

  SequentialAnimation {
    id: anim
    PauseAnimation { duration: Math.min(enter.index, 12) * 40 }
    ParallelAnimation {
      NumberAnimation { target: enter.target; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
      NumberAnimation { target: enter.shift; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
    }
  }
}
