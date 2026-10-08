import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../components"

Column {
  id: lightsPage

  // The QuickPuff panel: palette, state and actions.
  property var panel
  width: parent.width
  visible: panel.onLights && panel.connected
  spacing: Style.spacing.panelGap

  Section {
    panel: lightsPage.panel
    title: "LEDS"
    glyph: "\uf0eb"

    // Your Peak, showing what its lantern is doing: the profile's colour
    // (or the cycle as it plays) at the chosen brightness.
    Item {
      width: parent.width
      height: lanternArt.height + Style.space(10)

      PeakArt {
        id: lanternArt
        panel: lightsPage.panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Style.space(58)
        height: width * 1.6
        colorway: panel.statusData.product ? String(panel.statusData.product.marketing_name || "") : ""
        tint: panel.cycleOn ? panel.cycleNow : panel.profileTint
        glow: panel.lanternOn ? 0.3 + 0.7 * panel.brightnessLevel / 255 : 0.1
        Behavior on glow { NumberAnimation { duration: 300 } }
      }

      Text {
        anchors.left: lanternArt.right
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: lanternArt.verticalCenter
        textFormat: Text.PlainText
        text: panel.lanternOn ? "LANTERN ON" : "LANTERN OFF"
        color: panel.lanternOn ? panel.foreground : panel.dim
        font.family: panel.displayFamily
        font.pixelSize: Math.round(Style.font.caption * panel.displayScale)
        font.weight: Font.DemiBold
        font.letterSpacing: panel.hasDisplayFont ? 1.2 : 0
      }
    }

    SwitchRow {
      panel: lightsPage.panel
      width: parent.width
      label: "LED"
      checked: panel.lanternOn
      onToggled: panel.toggleLantern()
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: brightnessLabel.implicitHeight

        Text {
          id: brightnessLabel
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: "Brightness"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: Math.round(panel.brightnessLevel / 255 * 100) + "%"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        width: parent.width
        bar: panel.bar
        minimum: 0
        maximum: 255
        step: 5
        integer: true
        value: panel.brightnessLevel
        onMoved: function(v) { panel.setBrightness(v) }
        onReleased: function(v) { panel.setBrightness(v) }
      }
    }

    SwitchRow {
      panel: lightsPage.panel
      width: parent.width
      label: "Stealth mode"
      checked: panel.stealthOn
      onToggled: panel.toggleStealth()
    }

    StepperRow {
      panel: lightsPage.panel
      width: parent.width
      label: "Turn off after"
      valueText: panel.formatTimeout(panel.lanternTimeoutStops[panel.lanternTimeoutStop])
      canLower: panel.lanternTimeoutStop > 0
      canRaise: panel.lanternTimeoutStop < panel.lanternTimeoutStops.length - 1
      onLower: panel.stepLanternTimeout(-1)
      onRaise: panel.stepLanternTimeout(1)
    }
  }

  Section {
    panel: lightsPage.panel
    glyph: "\uf1fc"
    title: panel.activeProfile
      ? "PROFILE LIGHT · " + String(panel.cleanName(panel.activeProfile.name) || ("Profile " + (panel.currentProfile + 1))).toUpperCase()
      : "PROFILE LIGHT"

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "The color this profile glows with while it heats."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Grid {
      id: colorGrid
      width: parent.width
      columns: 9
      rowSpacing: Style.space(6)
      columnSpacing: Style.space(6)
      readonly property real cell: (width - columnSpacing * 8) / 9

      Repeater {
        model: panel.colorPalette

        Rectangle {
          id: swatchChip
          required property var modelData
          readonly property bool picked: panel.activeProfile
            && String(panel.profileColor(panel.currentProfile, panel.activeProfile.color)).toLowerCase() === String(modelData).toLowerCase()
          width: colorGrid.cell
          height: colorGrid.cell
          radius: width / 2
          color: String(modelData)
          border.width: picked ? 2 : 1
          border.color: picked ? panel.foreground : Util.alpha(panel.foreground, 0.35)
          scale: swatchMouse.pressed ? 0.9 : (swatchMouse.containsMouse ? 1.15 : (picked ? 1.06 : 1))

          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

          // Glow ring around the colour the profile wears.
          Rectangle {
            z: -1
            anchors.centerIn: parent
            width: parent.width + Style.space(8)
            height: width
            radius: width / 2
            color: Util.alpha(String(swatchChip.modelData), swatchChip.picked ? 0.3 : 0)

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Text {
            anchors.centerIn: parent
            visible: swatchChip.picked
            textFormat: Text.PlainText
            text: "\uf00c"
            color: panel.inkOn(swatchChip.modelData)
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: swatchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              panel.applyLightColor(String(swatchChip.modelData))
              if (panel.pickerOpen) panel.seedPicker(String(swatchChip.modelData))
            }
          }
        }
      }

      // Rainbow chip that opens the colour wheel. Wears the custom
      // colour (with a check) while the profile is on one.
      Item {
        width: colorGrid.cell
        height: colorGrid.cell
        scale: customMouse.pressed ? 0.9 : (customMouse.containsMouse ? 1.15 : (panel.pickerOpen || panel.customLight ? 1.06 : 1))

        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width + Style.space(8)
          height: width
          radius: width / 2
          color: Util.alpha(panel.customLight ? panel.activeLightHex : panel.foreground, panel.pickerOpen || panel.customLight ? 0.3 : 0)

          Behavior on color { ColorAnimation { duration: 200 } }
        }

        ConicalRing {
          panel: lightsPage.panel
          anchors.fill: parent
          rotating: customMouse.containsMouse || panel.pickerOpen
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.56
          height: width
          radius: width / 2
          color: panel.customLight ? panel.activeLightHex : Color.background
          border.width: 1
          border.color: Util.alpha(panel.foreground, 0.35)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: panel.customLight ? "\uf00c" : (panel.pickerOpen ? "\uf00d" : "+")
            color: panel.customLight ? panel.inkOn(panel.activeLightHex) : panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        MouseArea {
          id: customMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.togglePicker()
        }
      }
    }

    Loader {
      width: parent.width
      active: panel.pickerOpen && panel.onLights
      visible: active
      sourceComponent: ColorPicker { panel: lightsPage.panel }
      // Scroll just far enough to bring the whole picker into view.
      onLoaded: Qt.callLater(function() {
        var bottom = pickerLoader.mapToItem(panel.contentColumn, 0, pickerLoader.height).y
        panel.scrollView.contentY = Math.max(panel.scrollView.contentY,
          Math.min(bottom - panel.scrollView.height, panel.scrollView.contentHeight - panel.scrollView.height))
      })
      id: pickerLoader
    }

  }

  CycleSection { panel: lightsPage.panel }

  MyLightsSection { panel: lightsPage.panel }

}
