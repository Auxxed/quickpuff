import QtQuick
import Quickshell
import qs.Commons

// How a block arrives. Give the target a `transform: Translate { id: x }`
// and pass it here as `shift`; Reveal moves that and the target's opacity.
//
// - cascade: when the panel opens, the block rises into place a beat after
//   the ones above it (blocks below the fold just appear).
// - slide: when a tab switch brings the block into view, it slides in from
//   the side of the tab it came from (or `fromSide`, for a two-tab pair).
// - appear: when the block itself turns up on a page that's already showing
//   (the heat timer when heating starts), it rises in.
Item {
  id: reveal

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property Item target: null
  property Translate shift: null
  property bool cascade: true
  property bool slide: false
  property bool appear: false
  // A fixed side to slide in from (1 from the right, -1 from the left);
  // 0 follows the tab switch.
  property int fromSide: 0
  // One of a two-tab pair inside a page: slides only for its own switch,
  // not when the whole page arrives.
  property bool subTab: false

  visible: false
  width: 0
  height: 0

  function settle() {
    anim.stop()
    if (target) target.opacity = 1
    if (shift) { shift.x = 0; shift.y = 0 }
  }

  function play(dx, dy, delay, fadeMs, moveMs) {
    if (!target || !shift) return
    anim.stop()
    target.opacity = 0
    shift.x = dx
    shift.y = dy
    anim.delay = delay
    anim.fadeMs = fadeMs
    anim.moveMs = moveMs
    anim.start()
  }

  // Where the block sits in the visible part of the panel: <0 above it,
  // >height below it.
  function viewTop() {
    var view = panel ? panel.scrollView : null
    if (!view || !target) return 0
    return target.mapToItem(view, 0, 0).y
  }

  function runCascade() {
    if (!cascade || !target || !target.visible) return
    if (panel.calm) { settle(); return }
    var view = panel.scrollView
    var top = viewTop()
    if (view && (top > view.height || top + target.height < 0)) { settle(); return }
    play(0, Style.space(14), 20 + Math.min(220, Math.max(0, top) * 0.3), 240, 440)
  }

  function runShow() {
    if (!target || !target.visible || !panel || !panel.opened) return
    if (panel.calm) { settle(); return }
    // The panel's own opening plays the cascade instead.
    if (Date.now() - panel.openedAt < 250) return
    var now = Date.now()
    var switched = now - panel.pageChangedAt < 200
    var mine = subTab ? now - panel.subTabChangedAt < 200 : switched
    if (switched && slide && mine) {
      var side = fromSide !== 0 ? fromSide : panel.pageDir
      play(side * Style.space(30), side === 0 ? Style.space(10) : 0, 0, 200, 340)
    } else if (!switched && appear) {
      play(0, Style.space(12), 0, 240, 420)
    }
  }

  Connections {
    target: reveal.panel
    function onOpenSerialChanged() { reveal.runCascade() }
  }

  Connections {
    target: reveal.target
    function onVisibleChanged() { if (reveal.target.visible) reveal.runShow(); else reveal.settle() }
  }

  SequentialAnimation {
    id: anim
    property int delay: 0
    property int fadeMs: 240
    property int moveMs: 400
    PauseAnimation { duration: anim.delay }
    ParallelAnimation {
      NumberAnimation { target: reveal.target; property: "opacity"; to: 1; duration: anim.fadeMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: reveal.shift; property: "x"; to: 0; duration: anim.moveMs; easing.type: Easing.OutCubic }
      NumberAnimation { target: reveal.shift; property: "y"; to: 0; duration: anim.moveMs; easing.type: Easing.OutCubic }
    }
  }
}
