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

  // Down while the card is out of sight, so its bars rise each time its
  // page shows (not on every open of the panel).
  readonly property bool grown: visible
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
  glyphColor: rising ? panel.urgent : tint
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
            id: monthBar
            width: parent.width
            // Bars start a third of the way up so a few percent of change
            // still reads, without pretending the low end is zero. They rise
            // left to right as the card shows.
            height: trendCard.monthPeak > 0 && trendCard.grown
              ? parent.height * (0.35 + 0.65 * (Number(parent.modelData.value) / trendCard.monthPeak))
              : Style.space(2)
            Behavior on height {
              enabled: !trendCard.panel.calm
              SequentialAnimation {
                PauseAnimation { duration: 150 + index * 50 }
                NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
              }
            }
            anchors.bottom: parent.bottom
            radius: Math.min(width / 2, Style.space(3))
            readonly property bool latest: index === trendCard.months.length - 1
            readonly property color tone: trendCard.rising ? panel.urgent : trendCard.tint
            // This month lit from the top down; earlier months quiet.
            gradient: Gradient {
              GradientStop { position: 0.0; color: monthBar.latest ? monthBar.tone : Util.alpha(trendCard.panel.foreground, 0.32) }
              GradientStop { position: 1.0; color: monthBar.latest ? Util.alpha(monthBar.tone, 0.45) : Util.alpha(trendCard.panel.foreground, 0.18) }
            }
          }
        }
      }
    }
  }
}
