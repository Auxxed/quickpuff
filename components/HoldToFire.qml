import QtQuick

// A press that only counts once it has been held for `duration`. progress
// runs 0 to 1 while held; fired() comes when it fills, cancelled() when the
// press ends early. A tap or a slip off the target never fires, which is
// the point: what fires here may heat a chamber in another room.
Item {
  id: hold

  property int duration: 900
  property real progress: 0
  readonly property bool holding: grow.running

  signal fired()
  signal cancelled()

  function start() {
    fade.stop()
    grow.restart()
  }

  // Only a hold still running can be cancelled; after fired() it is over.
  function end() {
    if (!grow.running) return
    grow.stop()
    fade.restart()
    cancelled()
  }

  NumberAnimation {
    id: grow
    target: hold
    property: "progress"
    from: 0
    to: 1
    duration: hold.duration
    // Only a natural finish counts; stop() on release doesn't emit this.
    onFinished: if (hold.progress >= 1) {
      fade.restart()
      hold.fired()
    }
  }

  NumberAnimation { id: fade; target: hold; property: "progress"; to: 0; duration: 220; easing.type: Easing.OutCubic }
}
