import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The session's temperature curve: a gradient area under the climb, the
// target as a dashed line, Ready and Cooling marked, and a live dot on the
// newest reading while the Peak heats.
Section {
  id: graph

  glyph: ""
  title: panel.heatTraceLive ? "HEAT CURVE" : "LAST SESSION"
  trailing: {
    var pts = panel.heatPoints
    if (!pts.length) return ""
    return (panel.heatTraceLive ? "Live · " : "") + panel.formatDuration(pts[pts.length - 1][0])
  }

  readonly property var pts: panel.heatPoints
  readonly property real targetF: panel.heatTrace && isFinite(Number(panel.heatTrace.target_f)) ? Number(panel.heatTrace.target_f) : NaN
  readonly property real readyAt: panel.heatTrace && panel.heatTrace.ready_at !== null && panel.heatTrace.ready_at !== undefined ? Number(panel.heatTrace.ready_at) : NaN
  readonly property real fadeAt: panel.heatTrace && panel.heatTrace.fade_at !== null && panel.heatTrace.fade_at !== undefined ? Number(panel.heatTrace.fade_at) : NaN
  readonly property real spanS: pts.length ? Math.max(10, Number(pts[pts.length - 1][0])) : 10
  readonly property real lowF: {
    var lo = Infinity
    for (var i = 0; i < pts.length; i++) lo = Math.min(lo, Number(pts[i][1]))
    return isFinite(lo) ? Math.max(0, lo - 20) : 0
  }
  readonly property real highF: {
    var hi = isFinite(targetF) ? targetF : 0
    if (isFinite(panel.heatPeakF)) hi = Math.max(hi, panel.heatPeakF)
    return hi + 25
  }

  Item {
    id: plot
    width: parent.width
    height: Style.space(96)

    readonly property real padTop: Style.space(6)
    readonly property real padBottom: Style.space(4)
    function xAt(t) { return Math.max(0, Math.min(1, t / graph.spanS)) * width }
    function yAt(f) {
      var frac = (f - graph.lowF) / Math.max(1, graph.highF - graph.lowF)
      return padTop + (1 - Math.max(0, Math.min(1, frac))) * (height - padTop - padBottom)
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.normalFillFor(panel.foreground, Color.accent)
      border.width: 1
      border.color: Util.alpha(panel.foreground, 0.1)
    }

    Canvas {
      id: curve
      anchors.fill: parent

      Connections {
        target: graph
        function onPtsChanged() { curve.requestPaint() }
        function onTargetFChanged() { curve.requestPaint() }
      }
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var pts = graph.pts
        if (pts.length < 2) return
        var bottom = height - plot.padBottom

        // Area under the curve, hot at the top fading to nothing.
        var fill = ctx.createLinearGradient(0, plot.padTop, 0, bottom)
        fill.addColorStop(0, Util.alpha(panel.urgent, 0.45))
        fill.addColorStop(1, Util.alpha(Color.accent, 0.02))
        ctx.fillStyle = fill
        ctx.beginPath()
        ctx.moveTo(plot.xAt(pts[0][0]), bottom)
        for (var i = 0; i < pts.length; i++) ctx.lineTo(plot.xAt(pts[i][0]), plot.yAt(pts[i][1]))
        ctx.lineTo(plot.xAt(pts[pts.length - 1][0]), bottom)
        ctx.closePath()
        ctx.fill()

        // The curve itself, cool accent climbing into the urgent heat colour.
        var stroke = ctx.createLinearGradient(0, bottom, 0, plot.padTop)
        stroke.addColorStop(0, Color.accent)
        stroke.addColorStop(1, panel.urgent)
        ctx.strokeStyle = stroke
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        for (var j = 0; j < pts.length; j++) {
          var x = plot.xAt(pts[j][0]), y = plot.yAt(pts[j][1])
          if (j === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()

        // Target temperature, dashed.
        if (isFinite(graph.targetF)) {
          var ty = plot.yAt(graph.targetF)
          ctx.strokeStyle = Util.alpha(panel.foreground, 0.45)
          ctx.lineWidth = 1
          ctx.beginPath()
          for (var dx = 0; dx < width; dx += 8) {
            ctx.moveTo(dx, ty)
            ctx.lineTo(Math.min(width, dx + 4), ty)
          }
          ctx.stroke()
        }

        // Phase markers.
        function marker(t, color) {
          if (!isFinite(t)) return
          var mx = plot.xAt(t)
          ctx.strokeStyle = color
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(mx, plot.padTop)
          ctx.lineTo(mx, bottom)
          ctx.stroke()
        }
        marker(graph.readyAt, Util.alpha(Color.accent, 0.8))
        marker(graph.fadeAt, Util.alpha(panel.foreground, 0.35))
      }
    }

    Text {
      visible: isFinite(graph.targetF)
      x: Style.space(6)
      y: plot.yAt(graph.targetF) - implicitHeight - 1
      textFormat: Text.PlainText
      text: panel.formatTemp(graph.targetF, undefined)
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: isFinite(graph.readyAt) && plot.xAt(graph.readyAt) < plot.width - implicitWidth - Style.space(4)
      x: plot.xAt(graph.readyAt) + Style.space(3)
      y: plot.height - implicitHeight - Style.space(3)
      textFormat: Text.PlainText
      text: "Ready"
      color: Color.accent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      visible: isFinite(graph.fadeAt) && plot.xAt(graph.fadeAt) < plot.width - implicitWidth - Style.space(4)
      x: plot.xAt(graph.fadeAt) + Style.space(3)
      y: plot.height - implicitHeight - Style.space(3)
      textFormat: Text.PlainText
      text: "Cooling"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Newest reading, pulsing while live.
    Rectangle {
      id: headDot
      visible: graph.pts.length > 0
      readonly property var last: graph.pts.length ? graph.pts[graph.pts.length - 1] : [0, 0]
      width: Style.space(7)
      height: width
      radius: width / 2
      x: plot.xAt(last[0]) - width / 2
      y: plot.yAt(last[1]) - height / 2
      color: panel.heatTraceLive ? Qt.lighter(panel.urgent, 1.2) : panel.dim

      Rectangle {
        z: -1
        anchors.centerIn: parent
        width: parent.width * 2.6
        height: width
        radius: width / 2
        color: Util.alpha(panel.urgent, 0.35)
        visible: panel.heatTraceLive

        SequentialAnimation on scale {
          running: panel.heatTraceLive && panel.opened
          loops: Animation.Infinite
          NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.OutSine }
          NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InSine }
        }
      }
    }
  }

  Row {
    id: graphStats
    width: parent.width
    spacing: Style.spacing.controlGap
    readonly property real cell: (width - spacing * 2) / 3

    SummaryCell {
      panel: graph.panel
      width: graphStats.cell
      title: "Heat-up"
      value: isFinite(graph.readyAt) ? panel.formatDuration(graph.readyAt) : "…"
    }
    SummaryCell {
      panel: graph.panel
      width: graphStats.cell
      title: "Peak"
      value: isFinite(panel.heatPeakF) ? panel.formatTemp(panel.heatPeakF, undefined) : "—"
    }
    SummaryCell {
      panel: graph.panel
      width: graphStats.cell
      title: "At temp"
      value: {
        if (!isFinite(graph.readyAt)) return "—"
        var end = isFinite(graph.fadeAt) ? graph.fadeAt : Number(graph.pts[graph.pts.length - 1][0])
        return panel.formatDuration(Math.max(0, end - graph.readyAt))
      }
    }
  }
}
