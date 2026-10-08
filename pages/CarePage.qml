import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../components"

Column {
  id: carePage

  // The QuickPuff panel: palette, state and actions.
  property var panel
  width: parent.width
  visible: panel.onCare && panel.connected
  spacing: Style.spacing.panelGap

  Section {
    panel: carePage.panel
    title: "BATTERY"
    glyph: "\uf240"
    trailing: panel.batteryHealthLabel !== "" ? panel.batteryHealthLabel + " health" : ""

    MeterBar {
      panel: carePage.panel
      width: parent.width
      visible: panel.batteryHealthLabel !== ""
      value: parseFloat(panel.batteryHealthLabel) / 100
      fill: parseFloat(panel.batteryHealthLabel) < 70 ? panel.urgent
        : parseFloat(panel.batteryHealthLabel) < 80 ? "#ffb347"
        : Color.accent
    }

    SwitchRow {
      panel: carePage.panel
      width: parent.width
      visible: panel.preserveSupported
      label: "Charge to 80% only"
      checked: panel.preserveOn
      onToggled: panel.togglePreserve()
    }

    SwitchRow {
      panel: carePage.panel
      width: parent.width
      label: "Rest after sessions and 10 min idle"
      checked: panel.saverOn
      onToggled: panel.toggleSaver()
    }

    Text {
      width: parent.width
      visible: panel.preserveSupported && panel.preserveOn
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Stopping at 80% helps the battery last longer."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Section {
    panel: carePage.panel
    title: "CLEANING"
    glyph: "\uf0c3"
    trailing: panel.cleanDue ? "Due" : panel.cleanRemaining + " left"

    // Fills up as dabs pile on; turns urgent once a clean is due.
    MeterBar {
      panel: carePage.panel
      width: parent.width
      value: panel.cleanDue ? 1 : 1 - panel.cleanRemaining / Math.max(1, panel.cleanEvery)
      fill: panel.cleanDue ? panel.urgent
        : (1 - panel.cleanRemaining / Math.max(1, panel.cleanEvery)) > 0.75 ? "#ffb347"
        : Color.accent
      throb: panel.cleanDue
    }

    SwitchRow {
      panel: carePage.panel
      width: parent.width
      label: "Q-tip reminder after each dab"
      checked: panel.qtipOn
      onToggled: panel.toggleQtip()
    }

    StepperRow {
      panel: carePage.panel
      width: parent.width
      label: "Remind every"
      valueText: panel.cleanEvery + " dabs"
      canLower: panel.canStepCleanEvery(-panel.cleanEveryStep)
      canRaise: panel.canStepCleanEvery(panel.cleanEveryStep)
      onLower: panel.stepCleanEvery(-panel.cleanEveryStep)
      onRaise: panel.stepCleanEvery(panel.cleanEveryStep)
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.cleanDue
        ? "Swab the chamber, then mark it cleaned."
        : panel.cleanRemaining + " dab" + (panel.cleanRemaining === 1 ? "" : "s") + " until the reminder."
      color: panel.cleanDue ? panel.urgent : panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      implicitHeight: cleanButton.implicitHeight

      ActionButton {
        panel: carePage.panel
        id: cleanButton
        width: parent.width
        label: "Mark cleaned"
        glyph: "\uf0d0"
        emphasized: panel.cleanDue
        tint: panel.cleanDue ? panel.urgent : panel.foreground
        onActivated: {
          panel.markCleaned()
          cleanBurst.fire()
        }
      }

      Burst {
        panel: carePage.panel
        id: cleanBurst
        anchors.centerIn: cleanButton
        width: cleanButton.height * 2
        height: width
      }
    }
  }

  Section {
    panel: carePage.panel
    title: "GOALS"
    glyph: "\uf140"
    trailing: panel.dailyLimit > 0
      ? Number(panel.telemetry.today || 0) + " of " + panel.dailyLimit + " today"
      : ""

    StepperRow {
      panel: carePage.panel
      width: parent.width
      label: "Daily limit"
      valueText: panel.dailyLimit > 0 ? panel.dailyLimit + " dabs" : "Off"
      canLower: panel.dailyLimit > 0
      canRaise: panel.dailyLimit < 50
      onLower: panel.stepDailyLimit(-1)
      onRaise: panel.stepDailyLimit(1)
    }

    MeterBar {
      panel: carePage.panel
      width: parent.width
      visible: panel.dailyLimit > 0
      value: Number(panel.telemetry.today || 0) / Math.max(1, panel.dailyLimit)
      fill: Number(panel.telemetry.today || 0) >= panel.dailyLimit ? panel.urgent : Color.accent
    }

    Text {
      width: parent.width
      visible: panel.dailyLimit > 0
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "You'll get one notification the day you reach it."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    SwitchRow {
      panel: carePage.panel
      width: parent.width
      label: "Weekly recap on Sunday evening"
      checked: panel.recapOn
      onToggled: panel.toggleRecap()
    }
  }
}
