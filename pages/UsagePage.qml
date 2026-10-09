import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../components"

Column {
  id: usagePages

  // The QuickPuff panel: palette, state and actions.
  property var panel
  width: parent.width
  visible: panel.onUsage && panel.connected
  spacing: Style.spacing.panelGap

  Segmented {
    panel: usagePages.panel
    width: parent.width
    visible: panel.onUsage && panel.connected
    compact: true
    options: panel.usageTabOptions
    value: panel.usageTab
    onPicked: function(value) {
      panel.usageTab = value
      panel.scrollView.contentY = 0
    }
  }

  // Wrapped: the month or the year played over the desktop as a recap.
  Row {
    width: parent.width
    spacing: Style.space(8)

    ActionButton {
      panel: usagePages.panel
      width: (parent.width - parent.spacing) / 2
      label: "My month, wrapped"
      onActivated: panel.runArgv(["quickpuff", "wrapped", "month", "--show"])
    }

    ActionButton {
      panel: usagePages.panel
      width: (parent.width - parent.spacing) / 2
      label: "My year, wrapped"
      onActivated: panel.runArgv(["quickpuff", "wrapped", "year", "--show"])
    }
  }

  Column {
    id: historyPage
    width: parent.width
    visible: panel.onUsageHistory && panel.connected
    spacing: Style.spacing.controlGap

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.sessionList === null
        ? (panel.sessionsLoading ? "Loading your dabs\u2026" : "")
        : panel.sessionList.length === 0
          ? "No dabs yet. Each one shows up here, ready for a note."
          : "Tap a dab to add or edit its note."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: panel.sessionList || []

      SessionCard {
        panel: usagePages.panel
        required property var modelData
        width: parent ? parent.width : 0
        session: modelData
      }
    }

    ActionButton {
      panel: usagePages.panel
      width: parent.width
      visible: panel.sessionList !== null && panel.sessionTotal > panel.sessionList.length
        && panel.sessionList.length < panel.maxSessions
      label: panel.sessionsLoading ? "Loading\u2026" : "Show more"
      onActivated: {
        panel.sessionLimit = Math.min(panel.maxSessions, panel.sessionLimit + 30)
        panel.loadSessions()
      }
    }
  }

  Column {
    id: usagePage
    width: parent.width
    visible: panel.onUsageStats && panel.connected
    spacing: Style.spacing.panelGap

    Text {
      width: parent.width
      visible: panel.statusData.usage_syncing === true
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Reading usage history from this Peak. The first read on a new computer takes a minute or two."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: summaryRow
      width: parent.width
      spacing: Style.spacing.controlGap
      readonly property real cellWidth: (width - spacing * 3) / 4

      SummaryCell { panel: usagePages.panel; width: summaryRow.cellWidth; title: "Today"; glyph: "\uf185"; highlight: true; value: panel.countLabel(panel.telemetry.today) }
      SummaryCell { panel: usagePages.panel; width: summaryRow.cellWidth; title: "Week"; glyph: "\uf073"; value: panel.countLabel(panel.telemetry.this_week) }
      SummaryCell { panel: usagePages.panel; width: summaryRow.cellWidth; title: "Month"; glyph: "\uf274"; value: panel.countLabel(panel.telemetry.this_month) }
      SummaryCell { panel: usagePages.panel; width: summaryRow.cellWidth; title: "Lifetime"; glyph: "\uf091"; value: panel.countLabel(panel.statusData.total_dabs) }
    }

    Section {
      panel: usagePages.panel
      id: dailySection
      title: "DAILY"
      glyph: "\uf073"
      // Hovering a bar swaps the average for that day's count.
      property int hoverIndex: -1
      trailing: hoverIndex >= 0 && hoverIndex < panel.dailySeries.length
        ? String(panel.dailySeries[hoverIndex].day || "") + " \u00b7 " + (Number(panel.dailySeries[hoverIndex].count) || 0)
          + ((Number(panel.dailySeries[hoverIndex].count) || 0) === 1 ? " dab" : " dabs")
        : "Avg " + (Number(panel.telemetry.avg_per_day) || 0) + "/day"

      Item {
        width: parent.width
        height: Style.space(68)

        Row {
          id: chartRow
          anchors.fill: parent
          spacing: Math.max(1, Style.space(2))

          Repeater {
            model: panel.dailySeries

            Item {
              required property var modelData
              required property int index
              width: {
                var n = Math.max(1, panel.dailySeries.length)
                return (chartRow.width - chartRow.spacing * (n - 1)) / n
              }
              height: chartRow.height

              readonly property int count: Number(modelData.count) || 0
              readonly property bool isToday: index === panel.dailySeries.length - 1
              readonly property bool hovered: dailySection.hoverIndex === index

              Rectangle {
                id: dayBar
                width: parent.width
                // Grows up from the baseline when the page opens.
                height: panel.onUsageStats
                  ? Math.max(Style.space(2), parent.height * (parent.count / panel.chartPeak))
                  : Style.space(2)
                anchors.bottom: parent.bottom
                radius: Math.min(2, Style.cornerRadius)
                // Bars wear the active profile's colour, today's fullest.
                readonly property color barTop: parent.hovered ? Qt.lighter(panel.profileTint, 1.35)
                  : parent.isToday ? panel.profileTint
                  : parent.count > 0 ? Util.alpha(panel.profileTint, 0.7)
                  : Util.alpha(panel.foreground, 0.12)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: dayBar.barTop }
                  GradientStop { position: 1.0; color: Util.alpha(dayBar.barTop, dayBar.barTop.a * 0.45) }
                }

                // Bars rise in a left-to-right ripple.
                Behavior on height {
                  SequentialAnimation {
                    PauseAnimation { duration: Math.min(dayBar.parent.index, 40) * 14 }
                    NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: {
                  if (containsMouse) dailySection.hoverIndex = parent.index
                  else if (dailySection.hoverIndex === parent.index) dailySection.hoverIndex = -1
                }
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        implicitHeight: firstDay.implicitHeight

        Text {
          id: firstDay
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: panel.dailySeries.length ? String(panel.dailySeries[0].day || "") : ""
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: panel.dailySeries.length ? String(panel.dailySeries[panel.dailySeries.length - 1].day || "") : ""
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Section {
      panel: usagePages.panel
      title: "HABITS"
      glyph: "\uf005"

      Grid {
        width: parent.width
        columns: 2
        rowSpacing: Style.spacing.controlGap
        columnSpacing: Style.spacing.controlGap

        readonly property real cellWidth: (width - columnSpacing) / 2

        StatCard {
          panel: usagePages.panel
          width: parent.cellWidth
          title: "Streak"
          glyph: "\uf06d"
          glyphColor: (Number(panel.telemetry.streak) || 0) > 0 ? panel.urgent : panel.dim
          // A live streak is worth showing off.
          highlight: (Number(panel.telemetry.streak) || 0) > 0
          value: (Number(panel.telemetry.streak) || 0) + "d"
          meta: (Number(panel.telemetry.streak_best) || 0) > 0
            ? "Best " + Math.round(Number(panel.telemetry.streak_best)) + "d"
            : "No streak yet"

          Row {
            spacing: Style.space(4)
            Repeater {
              model: panel.weekdaySeries
              Rectangle {
                required property var modelData
                width: Style.space(8)
                height: Style.space(8)
                radius: width / 2
                color: Number(modelData.count) > 0 ? panel.profileTint : "transparent"
                scale: modelData.today ? 1.2 : 1
                border.width: modelData.today ? 1 : (Number(modelData.count) > 0 ? 0 : 1)
                border.color: modelData.today ? panel.profileTint : Util.alpha(panel.foreground, 0.3)
              }
            }
          }
        }

        StatCard {
          panel: usagePages.panel
          width: parent.cellWidth
          title: "Peak hour"
          glyph: "\uf017"
          value: panel.formatHour(panel.telemetry.top_hour)
          meta: Number(panel.telemetry.top_hour_share) > 0
            ? Math.round(Number(panel.telemetry.top_hour_share) * 100) + "% of sessions"
            : "Not enough data"

          Item {
            width: parent.width
            height: Style.space(22)

            Row {
              id: hourChart
              anchors.fill: parent
              spacing: 1

              Repeater {
                model: 24
                Item {
                  required property int index
                  width: (hourChart.width - 23) / 24
                  height: hourChart.height

                  Rectangle {
                    width: parent.width
                    height: {
                      var c = Number(panel.hourSeries[parent.index]) || 0
                      return Math.max(Style.space(2), parent.height * (c / panel.hourPeak))
                    }
                    anchors.bottom: parent.bottom
                    radius: 1
                    color: parent.index === Number(panel.telemetry.top_hour)
                      ? panel.profileTint
                      : Util.alpha(panel.foreground, (Number(panel.hourSeries[parent.index]) || 0) > 0 ? 0.45 : 0.12)
                  }
                }
              }
            }
          }
        }

        StatCard {
          panel: usagePages.panel
          width: parent.cellWidth
          title: "Avg duration"
          glyph: "\uf252"
          value: panel.formatDuration(panel.telemetry.avg_time_s)
          meta: panel.telemetry.avg_time_s == null ? "Not enough data" : "Per session"
        }

        StatCard {
          panel: usagePages.panel
          width: parent.cellWidth
          title: "Avg temperature"
          glyph: "\uf2c9"
          value: panel.formatAvgTemp(panel.telemetry.avg_temp_f)
          meta: panel.telemetry.avg_temp_f == null ? "Not enough data" : "Per session"
        }
      }
    }

    Section {
      panel: usagePages.panel
      visible: panel.profileUsage.length > 0
      title: "PROFILES"
      glyph: "\uf0ca"
      trailing: "Last " + (Number(panel.telemetry.profile_days) || 30) + " days"

      Repeater {
        model: panel.profileUsage

        Column {
          id: usageRow
          required property var modelData
          width: parent ? parent.width : 0
          spacing: Style.space(4)

          Item {
            width: parent.width
            implicitHeight: Math.max(usageName.implicitHeight, usageCount.implicitHeight)

            Text {
              id: usageName
              anchors.left: parent.left
              anchors.right: usageCount.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: panel.profileUsageName(usageRow.modelData.index)
              color: panel.foreground
              font.family: panel.displayFamily
              font.pixelSize: Math.round(Style.font.bodySmall * panel.displayScale)
              font.weight: Font.DemiBold
              font.capitalization: panel.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
              font.letterSpacing: panel.hasDisplayFont ? 0.6 : 0
            }

            Text {
              id: usageCount
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var d = usageRow.modelData
                var n = Number(d.count)
                var s = n + (n === 1 ? " session" : " sessions") + " \u00b7 " + Math.round(Number(d.share) * 100) + "%"
                if (d.temp_f !== null && d.temp_f !== undefined) s += " \u00b7 " + panel.formatTemp(d.temp_f, d.temp_c)
                return s
              }
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Style.normalFillFor(panel.foreground, Color.accent)

            Rectangle {
              id: shareBar
              readonly property color tint: panel.profileUsageColor(usageRow.modelData.index)
              width: panel.onUsageStats
                ? Math.max(parent.height, parent.width * Math.min(1, Number(usageRow.modelData.share) || 0))
                : parent.height
              height: parent.height
              radius: height / 2
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Util.alpha(shareBar.tint, 0.45) }
                GradientStop { position: 1.0; color: shareBar.tint }
              }

              Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
          }
        }
      }
    }

    Section {
      panel: usagePages.panel
      visible: panel.colorSeries.length > 0
      title: "TOP COLORS"
      glyph: "\uf1fb"

      Row {
        width: parent.width
        spacing: Style.space(3)
        Repeater {
          model: panel.colorSeries
          Rectangle {
            required property var modelData
            height: Style.space(12)
            width: Math.max(Style.space(16), (parent.width - parent.spacing * Math.max(0, panel.colorSeries.length - 1)) / Math.max(1, panel.colorSeries.length))
            radius: height / 2
            color: String(modelData)
            border.width: 1
            border.color: Util.alpha(panel.foreground, 0.2)
          }
        }
      }
    }
  }
}
