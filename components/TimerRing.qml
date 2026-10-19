import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Circular progress track; children (the countdown) sit in the middle. The
// arc runs from `startColor` to `fillColor`, glows wider toward its head
// like a comet's tail, and carries a bright head that breathes. It sweeps
// round to its value when it first shows.
Item {
  id: ring

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real progress: 0
  property color fillColor: Color.accent
  property color startColor: fillColor
  property color trackColor: Util.alpha(panel.foreground, 0.12)
  property real thickness: Style.space(6)

  // 0 → 1 as it first shows (the arc sweeping out to its value), and the
  // head's slow breath.
  property real sweep: 1
  property real headGlow: 1
  readonly property real drawn: Math.max(0, Math.min(1, progress)) * sweep

  onDrawnChanged: canvas.requestPaint()
  onFillColorChanged: canvas.requestPaint()
  onStartColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()

  function intro() { if (panel && panel.calm) { sweepAnim.stop(); sweep = 1 } else sweepAnim.restart() }
  onVisibleChanged: if (visible && panel && panel.opened) intro()
  Connections {
    target: ring.panel
    function onOpenSerialChanged() { if (ring.visible) ring.intro() }
  }
  NumberAnimation { id: sweepAnim; target: ring; property: "sweep"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

  SequentialAnimation on headGlow {
    running: ring.visible && ring.panel && ring.panel.opened && !ring.panel.calm
    loops: Animation.Infinite
    NumberAnimation { to: 0.55; duration: ring.panel.heartbeatMs / 2; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: ring.panel.heartbeatMs / 2; easing.type: Easing.InOutSine }
  }

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
      if (ring.drawn <= 0) return
      var start = -Math.PI / 2
      var end = start + Math.PI * 2 * ring.drawn

      // The tail's glow: wider and fainter, building toward the head.
      var tail = Math.min(ring.drawn, 0.3) * Math.PI * 2
      var steps = 10
      for (var i = 0; i < steps; i++) {
        var a0 = end - tail * (1 - i / steps)
        var a1 = end - tail * (1 - (i + 1) / steps)
        ctx.strokeStyle = Util.alpha(ring.fillColor, 0.025 + 0.11 * (i + 1) / steps)
        ctx.lineWidth = ring.thickness * (1.4 + 1.1 * (i + 1) / steps)
        ctx.beginPath()
        ctx.arc(cx, cy, r, a0, a1)
        ctx.stroke()
      }

      var grad = ctx.createLinearGradient(0, 0, width, height)
      grad.addColorStop(0, ring.startColor)
      grad.addColorStop(1, ring.fillColor)
      ctx.lineWidth = ring.thickness
      ctx.strokeStyle = grad
      ctx.beginPath()
      ctx.arc(cx, cy, r, start, end)
      ctx.stroke()
    }
  }

  // The head, drawn over the canvas so its breath doesn't repaint the arc
  // every frame.
  readonly property real headAngle: -Math.PI / 2 + Math.PI * 2 * drawn
  readonly property real headR: Math.min(width, height) / 2 - thickness
  readonly property real headX: width / 2 + headR * Math.cos(headAngle)
  readonly property real headY: height / 2 + headR * Math.sin(headAngle)
  Rectangle {
    visible: ring.drawn > 0
    width: ring.thickness * 2 * (1.05 + 0.35 * ring.headGlow)
    height: width
    radius: width / 2
    x: ring.headX - width / 2
    y: ring.headY - height / 2
    color: Util.alpha(ring.fillColor, 0.18 + 0.2 * ring.headGlow)
  }
  Rectangle {
    visible: ring.drawn > 0
    width: ring.thickness * 1.1
    height: width
    radius: width / 2
    x: ring.headX - width / 2
    y: ring.headY - height / 2
    color: Qt.tint(ring.fillColor, Util.alpha("#ffffff", 0.45))
  }
}
