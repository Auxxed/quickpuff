import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Lights saved off the Peak. Exclusive moods (Puffcon, Plasma, ...) only
// come from Puffco's servers to a signed-in app, so the way to keep one is
// to put it on a profile in the app once and save it here.
Section {
  id: lightsSection

  glyph: ""
  title: "MY LIGHTS"
  trailing: panel.savedLights.length ? panel.savedLights.length + " saved" : ""

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: panel.savedLights.length
      ? "Tap one to put it on " + (panel.activeProfile ? panel.cleanName(panel.activeProfile.name) || "this profile" : "this profile") + "."
      : "Exclusive moods like Puffcon only come from the Puffco app. To keep one: Disconnect here (Device tab), set the mood on a profile in the app, reconnect, then save it below."
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: panel.savedLights

    BorderSurface {
      id: lightRow
      required property var modelData
      readonly property bool worn: panel.wornLightId === modelData.id
      readonly property bool renaming: panel.renamingLight === modelData.id
      readonly property bool confirming: panel.confirmDeleteLight === modelData.id
      readonly property var colors: modelData.colors || []

      width: parent ? parent.width : 0
      implicitHeight: Style.space(44)
      radius: Style.cornerRadius
      color: rowMouse.pressed ? Util.alpha(Color.accent, 0.22)
        : worn ? Util.alpha(Color.accent, 0.14)
        : rowMouse.containsMouse ? Style.hoverFillFor(panel.foreground, Color.accent)
        : Style.normalFillFor(panel.foreground, Color.accent)
      borderSpec: worn
        ? Border.flat(Color.accent, Math.max(1, Style.normalBorderWidth))
        : Border.controlSpec(rowMouse.containsMouse ? "hover-cursor" : "normal", panel.foreground, Color.accent)

      Behavior on color { ColorAnimation { duration: 140 } }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !lightRow.renaming
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.applySavedLight(lightRow.modelData.id)
      }

      // The light's colours as a pill, or a rainbow when it keeps them to itself.
      Item {
        id: lightSwatch
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: Style.space(18)

        Rectangle {
          anchors.fill: parent
          visible: lightRow.colors.length > 0
          radius: height / 2
          border.width: 1
          border.color: Util.alpha(panel.foreground, 0.25)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: lightRow.colors.length ? lightRow.colors[0] : "black" }
            GradientStop { position: 0.5; color: lightRow.colors.length ? lightRow.colors[Math.floor(lightRow.colors.length / 2)] : "black" }
            GradientStop { position: 1.0; color: lightRow.colors.length ? lightRow.colors[lightRow.colors.length - 1] : "black" }
          }
        }

        ConicalRing {
          panel: lightsSection.panel
          anchors.centerIn: parent
          visible: lightRow.colors.length === 0
          width: parent.height
          height: width
          rotating: lightRow.worn
        }
      }

      Column {
        anchors.left: lightSwatch.right
        anchors.leftMargin: Style.space(10)
        anchors.right: lightButtons.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        visible: !lightRow.renaming

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: lightRow.modelData.name
          color: lightRow.worn ? Color.accent : panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var style = String(lightRow.modelData.style || "")
            var label = style === "custom" ? "Exclusive" : style === "solid" ? "Solid" : style.charAt(0).toUpperCase() + style.slice(1)
            return lightRow.worn ? " On this profile · " + label : label
          }
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Loader {
        anchors.left: lightSwatch.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        active: lightRow.renaming

        sourceComponent: InlineNameField {
          panel: lightsSection.panel
          seed: lightRow.modelData.name
          onCommitted: function(value) { panel.renameSavedLight(lightRow.modelData.id, value) }
          onCanceled: {
            panel.renamingLight = ""
            panel.refocusPanel()
          }
        }
      }

      Row {
        id: lightButtons
        visible: !lightRow.renaming
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        TileButton {
          panel: lightsSection.panel
          anchors.verticalCenter: parent.verticalCenter
          glyph: ""
          onActivated: {
            panel.namingLight = false
            panel.renamingLight = lightRow.modelData.id
          }
        }

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: lightRow.confirming ? sureLabel.implicitWidth + Style.space(12) : Style.space(18)
          height: Style.space(18)

          Behavior on width { NumberAnimation { duration: 140 } }

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: lightRow.confirming ? Util.alpha(panel.urgent, 0.25)
              : trashMouse.containsMouse ? Style.hoverFillFor(panel.foreground, Color.accent) : "transparent"
          }

          Text {
            id: sureLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: lightRow.confirming ? "Delete?" : ""
            color: lightRow.confirming || trashMouse.containsMouse ? panel.urgent : panel.dim
            font.family: panel.fontFamily
            font.pixelSize: lightRow.confirming ? Style.font.caption : Style.font.bodySmall
            font.bold: lightRow.confirming
          }

          MouseArea {
            id: trashMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.deleteSavedLight(lightRow.modelData.id)
          }
        }
      }
    }
  }

  // Save whatever this profile wears right now.
  Item {
    width: parent.width
    implicitHeight: panel.namingLight ? nameLoader.implicitHeight : saveButton.implicitHeight

    ActionButton {
      panel: lightsSection.panel
      id: saveButton
      visible: !panel.namingLight
      width: parent.width
      label: panel.wearingSaved ? "Already saved" : "Save this profile's light"
      glyph: panel.wearingSaved ? "" : ""
      tint: Color.accent
      emphasized: !panel.wearingSaved
      onActivated: {
        if (panel.wearingSaved || panel.currentProfile < 0) return
        panel.renamingLight = ""
        panel.namingLight = true
      }
    }

    Loader {
      id: nameLoader
      width: parent.width
      active: panel.namingLight

      sourceComponent: InlineNameField {
        panel: lightsSection.panel
        seed: panel.activeCycle && panel.activeCycle.style === "custom"
          ? "Exclusive " + (panel.savedLights.length + 1)
          : (panel.activeProfile ? panel.cleanName(panel.activeProfile.name) || "My light" : "My light") + " light"
        placeholderText: "Name it, e.g. Puffcon 2026"
        onCommitted: function(value) { panel.saveCurrentLight(value) }
        onCanceled: {
          panel.namingLight = false
          panel.refocusPanel()
        }
      }
    }
  }
}
