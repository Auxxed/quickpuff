import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Circular progress track; children (the countdown) sit in the middle. The
// arc runs from `startColor` to `fillColor` and carries a glowing head.
Item {
  id: ring

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real progress: 0
  property color fillColor: Color.accent
  property color startColor: fillColor
  property color trackColor: Util.alpha(panel.foreground, 0.12)
  property real thickness: Style.space(6)

  onProgressChanged: canvas.requestPaint()
  onFillColorChanged: canvas.requestPaint()
  onStartColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.min(width, height) / 2 - ring.thickness
      ctx.lineWidth = ring.thickness
      ctx.lineCap = "round"
      ctx.strokeStyle = ring.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      if (ring.progress <= 0) return
      var end = -Math.PI / 2 + Math.PI * 2 * ring.progress
      var grad = ctx.createLinearGradient(0, 0, width, height)
      grad.addColorStop(0, ring.startColor)
      grad.addColorStop(1, ring.fillColor)
      ctx.strokeStyle = grad
      ctx.beginPath()
      ctx.arc(cx, cy, r, -Math.PI / 2, end)
      ctx.stroke()
      var hx = cx + r * Math.cos(end)
      var hy = cy + r * Math.sin(end)
      ctx.fillStyle = Util.alpha(ring.fillColor, 0.3)
      ctx.beginPath()
      ctx.arc(hx, hy, ring.thickness * 1.1, 0, Math.PI * 2)
      ctx.fill()
      ctx.fillStyle = ring.fillColor
      ctx.beginPath()
      ctx.arc(hx, hy, ring.thickness * 0.6, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
