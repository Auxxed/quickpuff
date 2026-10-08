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

    // Charge as a big readout in the Peak's battery colour, the way the
    // Puffco app leads its battery card.
    Item {
      width: parent.width
      visible: panel.batteryLabel !== ""
      implicitHeight: batteryBig.implicitHeight

      Text {
        id: batteryBig
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: Math.round(Number(panel.statusData.battery)) + "%"
        color: panel.batteryColor(Number(panel.statusData.battery) / 100)
        font.family: panel.displayFamily
        font.pixelSize: Math.round(Style.font.subtitle * panel.displayScale)
        font.weight: Font.DemiBold
      }
      Text {
        anchors.right: parent.right
        anchors.baseline: batteryBig.baseline
        textFormat: Text.PlainText
        text: panel.pluggedIn ? "\uf0e7  " + String(panel.statusData.charge_state || "Plugged in") : "On battery"
        color: panel.pluggedIn ? Color.accent : panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Charge, in the Peak's own battery colours, with the 80% mark while
    // Battery Preservation holds it there (as the Puffco app draws it).
    MeterBar {
      panel: carePage.panel
      width: parent.width
      visible: panel.batteryLabel !== ""
      value: Number(panel.statusData.battery) / 100
      fill: panel.pluggedIn ? Color.accent : panel.batteryColor(Number(panel.statusData.battery) / 100)
      marker: panel.preserveSupported && panel.preserveOn ? 0.8 : -1
      throb: panel.pluggedIn && Number(panel.statusData.battery) < 100
    }

    Item {
      width: parent.width
      height: Math.max(healthLabel.implicitHeight, healthValue.implicitHeight)
      visible: panel.batteryHealthLabel !== ""

      Text {
        id: healthLabel
        anchors.baseline: healthValue.baseline
        textFormat: Text.PlainText
        text: "Health"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        id: healthValue
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: panel.batteryHealthLabel
        color: panel.foreground
        font.family: panel.displayFamily
        font.pixelSize: Math.round(Style.font.bodySmall * panel.displayScale)
        font.weight: Font.DemiBold
      }
    }

    MeterBar {
      panel: carePage.panel
      width: parent.width
      visible: panel.batteryHealthLabel !== ""
      value: parseFloat(panel.batteryHealthLabel) / 100
      fill: parseFloat(panel.batteryHealthLabel) < 70 ? panel.urgent
        : parseFloat(panel.batteryHealthLabel) < 80 ? "#ffb347"
        : panel.profileTint
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
        : panel.profileTint
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
    title: "WEAR"
    glyph: "\uf0ad"

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.spacing.controlGap

      readonly property real cellWidth: (width - columnSpacing) / 2

      TrendCard {
        panel: carePage.panel
        width: parent.cellWidth
        title: panel.wear.heatup && panel.wear.heatup.ref_temp_f
          ? "Heat-up · " + panel.formatTemp(panel.wear.heatup.ref_temp_f)
          : "Heat-up"
        glyph: "\uf2c9"
        unit: "s"
        trend: panel.wear.heatup || ({})
      }

      TrendCard {
        panel: carePage.panel
        width: parent.cellWidth
        title: "Battery per dab"
        glyph: "\uf240"
        unit: "%"
        trend: panel.wear.battery || ({})
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: {
        var hints = []
        if (panel.wear.heatup && panel.wear.heatup.state === "up")
          hints.push("Heating up slower than it used to. A deep clean of the chamber often fixes it; if not, the atomizer may be wearing out.")
        if (panel.wear.battery && panel.wear.battery.state === "up")
          hints.push("Each dab takes more of the battery than it used to, a sign the pack is ageing. Charge to 80% only helps it last.")
        if (hints.length === 0)
          return "Heat-up counts cold starts only, scaled to the heat you use now. Both compare your first sessions with your latest."
        return hints.join(" ")
      }
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
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
      fill: Number(panel.telemetry.today || 0) >= panel.dailyLimit ? panel.urgent : panel.profileTint
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
