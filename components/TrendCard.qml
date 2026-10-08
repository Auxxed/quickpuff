import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// One wear trend (wear.py): the latest value, how it compares with the
// earliest sessions, and a bar per month. A rising trend turns the glyph
// and this month's bar warm.
StatCard {
  id: trendCard

  property var trend: ({})
  // Appended to every value: "s" for heat-up, "%" for battery.
  property string unit: ""

  readonly property string trendState: trend && trend.state ? String(trend.state) : "learning"
  readonly property bool rising: trendState === "up"
  readonly property var months: trend && trend.months ? trend.months : []
  readonly property real monthPeak: {
    var peak = 0
    for (var i = 0; i < months.length; i++) peak = Math.max(peak, Number(months[i].value) || 0)
    return peak
  }
  readonly property string sinceLabel: trend && trend.since
    ? Qt.formatDate(new Date(Number(trend.since) * 1000), "MMM")
    : ""

  function fmt(v) {
    var n = Number(v)
    if (!isFinite(n)) return "–"
    return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + unit
  }

  value: trend && trend.recent != null ? fmt(trend.recent) : "–"
  glyphColor: rising ? panel.urgent : Color.accent
  meta: {
    if (!trend || trend.recent == null) return "Not enough data yet"
    if (trendState === "learning")
      return "Learning · " + Number(trend.samples) + " of " + Number(trend.needed) + " dabs"
    var change = Number(trend.change_pct) || 0
    if (trendState === "steady") return "Steady since " + sinceLabel
    return (change > 0 ? "+" : "−") + Math.abs(change) + "% since " + sinceLabel
  }

  Item {
    width: parent.width
    height: Style.space(22)
    visible: trendCard.months.length > 1

    Row {
      id: monthChart
      anchors.fill: parent
      spacing: Style.space(3)

      Repeater {
        model: trendCard.months
        Item {
          required property var modelData
          required property int index
          width: (monthChart.width - monthChart.spacing * (trendCard.months.length - 1)) / trendCard.months.length
          height: monthChart.height

          Rectangle {
            width: parent.width
            // Bars start a third of the way up so a few percent of change
            // still reads, without pretending the low end is zero.
            height: trendCard.monthPeak > 0
              ? parent.height * (0.35 + 0.65 * (Number(parent.modelData.value) / trendCard.monthPeak))
              : Style.space(2)
            anchors.bottom: parent.bottom
            radius: 1
            color: parent.index === trendCard.months.length - 1
              ? (trendCard.rising ? panel.urgent : Color.accent)
              : Util.alpha(panel.foreground, 0.3)
          }
        }
      }
    }
  }
}
