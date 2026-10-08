import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// A hue ring painted once, used for the "custom colour" chip.
Canvas {
  id: cring

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property bool rotating: false

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var r = Math.min(width, height) / 2
    var g = ctx.createConicalGradient(width / 2, height / 2, 0)
    var stops = ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
    for (var i = 0; i < stops.length; i++) g.addColorStop(i / (stops.length - 1), stops[i])
    ctx.fillStyle = g
    ctx.beginPath()
    ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
    ctx.fill()
  }

  RotationAnimation on rotation {
    running: cring.rotating && panel.opened
    loops: Animation.Infinite
    from: 0
    to: 360
    duration: 3000
  }
}
