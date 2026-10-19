import QtQuick
import QtQuick.Shapes
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

  // Slides in from the side of the tab it was switched to from.
  transform: Translate { id: pageShift }
  Reveal { panel: usagePages.panel; target: usagePages; shift: pageShift; cascade: false; slide: true }

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

    transform: Translate { id: historyShift }
    Reveal { panel: usagePages.panel; target: historyPage; shift: historyShift; cascade: false; slide: true; subTab: true; fromSide: 1 }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.sessionList === null
        ? (panel.sessionsLoading ? "Loading your dabs\u2026" : "")
        : panel.sessionList.length === 0
          ? (Number(panel.statusData.total_dabs) > 0
            ? "No sessions recorded on this computer yet. Dabs you take while QuickPuff runs show up here, ready for a note."
            : "No dabs yet. Each one shows up here, ready for a note.")
          : "Tap a dab to add or edit its note."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: panel.sessionList || []

      Column {
        id: sessionRow
        required property var modelData
        required property int index
        width: parent ? parent.width : 0
        spacing: Style.space(6)
        transform: Translate { id: sessionShift }
        ListEnter { target: sessionRow; shift: sessionShift; index: sessionRow.index; fresh: Date.now() - panel.sessionsShownAt < 1500 }

        // A heading where a new day starts (Today, Yesterday, Friday, ...).
        Text {
          readonly property var prev: sessionRow.index > 0 && panel.sessionList ? panel.sessionList[sessionRow.index - 1] : null
          visible: !prev || panel.sessionDayKey(prev.ts) !== panel.sessionDayKey(sessionRow.modelData.ts)
          topPadding: sessionRow.index > 0 ? Style.space(6) : 0
          textFormat: Text.PlainText
          text: panel.sessionDayHeading(sessionRow.modelData.ts).toUpperCase()
          color: panel.dim
          font.family: panel.displayFamily
          font.pixelSize: Math.round(Style.font.caption * panel.displayScale)
          font.weight: Font.DemiBold
          font.letterSpacing: panel.hasDisplayFont ? 1.2 : 0
        }

        SessionCard {
          panel: usagePages.panel
          width: parent.width
          session: sessionRow.modelData
        }
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

    transform: Translate { id: statsShift }
    Reveal { panel: usagePages.panel; target: usagePage; shift: statsShift; cascade: false; slide: true; subTab: true; fromSide: -1 }

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

      SummaryCell { panel: usagePages.panel; width: summaryRow.cellWidth; title: "Today"; glyph: "\uf185"; tint: panel.urgent; highlight: panel.dailyLimit > 0 && (Number(panel.telemetry.today) || 0) >= panel.dailyLimit; value: panel.countLabel(panel.telemetry.today) }
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
                // Today in the profile's colour; earlier days quiet, unless
                // they went over your daily limit.
                readonly property bool over: panel.dailyLimit > 0 && parent.count > panel.dailyLimit
                readonly property color todayTone: over ? panel.urgent : Color.accent
                readonly property color barTop: parent.hovered
                    ? (parent.isToday ? Qt.lighter(todayTone, 1.2) : over ? Util.alpha(panel.urgent, 0.8) : Util.alpha(panel.foreground, 0.5))
                  : parent.isToday ? todayTone
                  : over ? Util.alpha(panel.urgent, 0.55)
                  : parent.count > 0 ? Util.alpha(panel.foreground, 0.28)
                  : Util.alpha(panel.foreground, 0.1)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: dayBar.barTop }
                  GradientStop { position: 1.0; color: Util.alpha(dayBar.barTop, dayBar.barTop.a * 0.45) }
                }

                // Bars rise in a left-to-right ripple.
                Behavior on height {
                  enabled: !panel.calm
                  SequentialAnimation {
                    PauseAnimation { duration: Math.min(dayBar.parent.index, 40) * 14 }
                    NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
                  }
                }

                // A bright cap on today (and the day under the pointer).
                Rectangle {
                  visible: dayBar.parent.count > 0 && (dayBar.parent.isToday || dayBar.parent.hovered)
                  width: parent.width
                  height: Math.max(2, Style.space(2))
                  radius: height / 2
                  color: Qt.lighter(dayBar.barTop, 1.35)
                }
              }
              Glow {
                visible: parent.isToday && parent.count > 0
                hue: Util.alpha(dayBar.over ? panel.urgent : Color.accent, 0.5)
                x: dayBar.width / 2 - 50
                y: dayBar.y - 50
                scale: Math.max(dayBar.width * 3, Style.space(20)) / 100
                z: -1
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

        // Your daily limit (Care → Goals), as a dashed line across the days.
        Item {
          id: limitLine
          readonly property bool shown: panel.dailyLimit > 0 && panel.dailyLimit <= panel.chartPeak && panel.onUsageStats
          visible: shown
          width: parent.width
          height: 1
          y: parent.height * (1 - panel.dailyLimit / Math.max(1, panel.chartPeak))
          Shape {
            anchors.fill: parent
            ShapePath {
              strokeColor: Util.alpha(panel.foreground, 0.45)
              strokeWidth: 1
              strokeStyle: ShapePath.DashLine
              dashPattern: [3, 3]
              fillColor: "transparent"
              startX: 0; startY: 0
              PathLine { x: limitLine.width; y: 0 }
            }
          }
          Text {
            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: Style.space(1)
            textFormat: Text.PlainText
            text: panel.dailyLimit + "/day"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
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
          // The first day as a date ("Oct 5"); the last is always today.
          text: {
            if (!panel.dailySeries.length) return ""
            var d = new Date(String(panel.dailySeries[0].date || "") + "T12:00:00")
            return isNaN(d.getTime()) ? String(panel.dailySeries[0].day || "") : Qt.formatDate(d, "MMM d")
          }
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: panel.dailySeries.length ? "Today" : ""
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
                required property int index
                width: Style.space(8)
                height: Style.space(8)
                radius: width / 2
                color: Number(modelData.count) > 0 ? panel.profileTint : "transparent"
                // Pops in, a beat after the dot before it, as the page shows.
                scale: (panel.onUsageStats ? 1 : 0) * (modelData.today ? 1.2 : 1)
                border.width: modelData.today ? 1 : (Number(modelData.count) > 0 ? 0 : 1)
                border.color: modelData.today ? panel.profileTint : Util.alpha(panel.foreground, 0.3)
                Behavior on scale {
                  SequentialAnimation {
                    PauseAnimation { duration: 180 + index * 45 }
                    NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                  }
                }
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
                      return panel.onUsageStats ? Math.max(Style.space(2), parent.height * (c / panel.hourPeak)) : Style.space(2)
                    }
                    // Rises in a sweep from midnight to midnight.
                    Behavior on height {
                      SequentialAnimation {
                        PauseAnimation { duration: 150 + index * 16 }
                        NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                      }
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

              Behavior on width {
                SequentialAnimation {
                  PauseAnimation { duration: 120 }
                  NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                }
              }
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
            required property int index
            height: Style.space(12)
            width: Math.max(Style.space(16), (parent.width - parent.spacing * Math.max(0, panel.colorSeries.length - 1)) / Math.max(1, panel.colorSeries.length))
            radius: height / 2
            color: String(modelData)
            border.width: 1
            border.color: Util.alpha(panel.foreground, 0.2)
            scale: panel.onUsageStats ? 1 : 0.2
            opacity: panel.onUsageStats ? 1 : 0
            Behavior on scale {
              SequentialAnimation {
                PauseAnimation { duration: 260 + index * 40 }
                NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
              }
            }
            Behavior on opacity {
              SequentialAnimation {
                PauseAnimation { duration: 260 + index * 40 }
                NumberAnimation { duration: 200 }
              }
            }
          }
        }
      }
    }
  }
}
