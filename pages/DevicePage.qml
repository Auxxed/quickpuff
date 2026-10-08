import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../components"

Column {
  id: devicePage

  // The QuickPuff panel: palette, state and actions.
  property var panel
  width: parent.width
  visible: panel.onDevice && panel.connected
  spacing: Style.spacing.panelGap

  Segmented {
    panel: devicePage.panel
    width: parent.width
    compact: true
    options: panel.deviceTabOptions
    value: panel.deviceTab
    onPicked: function(value) {
      panel.deviceTab = value
      panel.scrollView.contentY = 0
    }
  }

  Column {
    width: parent.width
    visible: panel.onDeviceInfo
    spacing: Style.spacing.panelGap

  Section {
    panel: devicePage.panel
    title: "NAME"
    glyph: "\uf02b"

    Item {
      width: parent.width
      implicitHeight: Math.max(Style.space(28), deviceNameRow.implicitHeight)

      Row {
        id: deviceNameRow
        visible: !(panel.editIndex === -1 && panel.editField === "device")
        width: parent.width
        spacing: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter

        // The Peak's name, big and uppercase in the display face, with
        // its model underneath, like the header of the Puffco app.
        Column {
          width: parent.width - deviceRename.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: panel.shownDeviceName
            color: deviceNameTap.containsMouse ? panel.profileTint : panel.foreground
            font.family: panel.displayFamily
            font.pixelSize: Math.round(Style.font.title * panel.displayScale)
            font.weight: Font.DemiBold
            font.capitalization: panel.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: panel.hasDisplayFont ? 1.2 : 0
            elide: Text.ElideRight

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
              id: deviceNameTap
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              onClicked: panel.startEdit(-1, "device")
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            text: (panel.statusData.product && panel.statusData.product.label) || ""
            color: Qt.tint(panel.dim, Util.alpha(panel.profileTint, 0.35))
            font.family: panel.displayFamily
            font.pixelSize: Math.round(Style.font.caption * panel.displayScale)
            font.capitalization: panel.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: panel.hasDisplayFont ? 1 : 0
            elide: Text.ElideRight
          }
        }

        TileButton {
          panel: devicePage.panel
          id: deviceRename
          anchors.verticalCenter: parent.verticalCenter
          glyph: "\uf040"
          canTap: true
          onActivated: panel.startEdit(-1, "device")
        }
      }

      Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        active: panel.editIndex === -1 && panel.editField === "device"

        sourceComponent: TileEditor {
          panel: devicePage.panel
          owningIndex: -1
          owningField: "device"
          seed: panel.shownDeviceName
          maxChars: 32
          onCommitted: function(value) { panel.commitDeviceName(value) }
        }
      }
    }
  }

  Section {
    panel: devicePage.panel
    title: "DETAILS"
    glyph: "\uf05a"

    InfoRow { panel: devicePage.panel; width: parent.width; label: "Model"; value: (panel.statusData.product && panel.statusData.product.label) || "" }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Chamber"; value: panel.chamberLabel }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Battery"; value: panel.batteryDetail }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Battery capacity"; value: panel.batteryCapacityLabel }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Battery health"; value: panel.batteryHealthLabel }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Dabs left on charge"; value: panel.remainingLabel }
    InfoRow {
      panel: devicePage.panel
      width: parent.width
      label: "Firmware"
      value: {
        var fw = String(panel.statusData.firmware || "")
        var boot = String(panel.statusData.bootloader || "")
        return fw !== "" && boot !== "" ? fw + " (bootloader " + boot + ")" : fw
      }
    }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Serial"; value: String(panel.statusData.serial || "") }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "First used"; value: String(panel.statusData.birthday_label || "") }
    InfoRow { panel: devicePage.panel; width: parent.width; label: "Uptime"; value: String(panel.statusData.uptime || "") }
  }

  Section {
    panel: devicePage.panel
    title: "FAULT LOG"
    glyph: "\uf071"
    trailing: panel.faultLog !== null && !panel.faultsLoading
      ? panel.faultLog.length + (panel.faultLog.length === 1 ? " fault" : " faults")
      : ""

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.faultsLoading ? "Reading the Peak's fault log. The first read takes a minute or two."
        : panel.faultError ? "Couldn't read the fault log. Check the Peak is connected, then try again."
        : panel.faultLog === null ? "Heater, battery and pairing problems the Peak has recorded."
        : panel.faultLog.length === 0 ? "No faults recorded."
        : ""
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: panel.faultLog && !panel.faultsLoading ? panel.faultLog.slice(0, panel.faultShown) : []

      FaultCard {
        panel: devicePage.panel
        required property var modelData
        width: parent ? parent.width : 0
        fault: modelData
      }
    }

    ActionButton {
      panel: devicePage.panel
      width: parent.width
      visible: !panel.faultsLoading && panel.faultLog !== null && panel.faultLog.length > panel.faultShown
      label: "Show " + (panel.faultLog ? panel.faultLog.length - panel.faultShown : 0) + " more"
      onActivated: panel.faultShown = panel.faultLog.length
    }

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap
      readonly property bool opened: panel.faultLog !== null && !panel.faultsLoading

      ActionButton {
        panel: devicePage.panel
        width: parent.opened ? (parent.width - parent.spacing) / 2 : parent.width
        label: panel.faultsLoading ? "Reading…" : (panel.faultLog === null ? "Read fault log" : "Refresh")
        onActivated: panel.readFaults()
      }

      ActionButton {
        panel: devicePage.panel
        visible: parent.opened
        width: (parent.width - parent.spacing) / 2
        label: "Close"
        onActivated: panel.closeFaults()
      }
    }
  }

  Section {
    panel: devicePage.panel
    title: "SHOW ON DEVICE"
    glyph: "\uf10b"

    ActionButton {
      panel: devicePage.panel
      width: parent.width
      label: "Battery level"
      glyph: "\uf240"
      onActivated: panel.run("quickpuff battery")
    }
  }

  Section {
    panel: devicePage.panel
    title: "CONNECTION"
    glyph: "\uf293"

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "The Peak accepts one connection at a time. Disconnect to use it from your phone or another computer."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    ActionButton {
      panel: devicePage.panel
      width: parent.width
      label: "Disconnect"
      glyph: "\uf127"
      onActivated: panel.disconnectDevice()
    }
  }

  Section {
    panel: devicePage.panel
    title: "POWER"
    glyph: "\uf011"

    ActionButton {
      panel: devicePage.panel
      width: parent.width
      label: "Power off"
      glyph: "\uf011"
      tint: panel.urgent
      onActivated: panel.confirmPowerOff = true
    }
  }
  }

  Column {
    width: parent.width
    visible: panel.onDeviceTips
    spacing: Style.spacing.panelGap

    Section {
      panel: devicePage.panel
      title: "STOCK HEAT"
      glyph: "\uf2c9"
      trailing: "Factory"

      Grid {
        width: parent.width
        columns: 2
        rowSpacing: Style.spacing.controlGap
        columnSpacing: Style.spacing.controlGap

        readonly property real cellWidth: (width - columnSpacing) / 2

        Repeater {
          model: panel.stockHeats

          SummaryCell {
            panel: devicePage.panel
            required property var modelData
            width: parent.cellWidth
            value: panel.formatTemp(modelData.temp_f, undefined)
            title: modelData.color + " · " + modelData.name
            stripe: panel.stockSwatches[modelData.color] || ""
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Green is the everyday setting. Blue keeps flavor; White is clouds."
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Section {
      panel: devicePage.panel
      title: "CARE"
      glyph: "\uf004"

      Repeater {
        model: panel.peakTips

        TipBlock {
          panel: devicePage.panel
          required property var modelData
          width: parent ? parent.width : 0
          title: String(modelData.title)
          body: String(modelData.body)
        }
      }
    }

    Section {
      panel: devicePage.panel
      title: "LIGHTS"
      glyph: "\uf0eb"

      Repeater {
        model: panel.peakLights

        TipBlock {
          panel: devicePage.panel
          required property var modelData
          width: parent ? parent.width : 0
          title: String(modelData.title)
          body: String(modelData.body)
        }
      }
    }
  }
}
