import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../components"

Column {
  id: controlPage

  // The QuickPuff panel: palette, state and actions.
  property var panel
  width: parent.width
  visible: panel.onControl && panel.connected
  spacing: Style.spacing.panelGap

  Row {
    id: actionRow
    width: parent.width
    spacing: Style.spacing.controlGap

    readonly property real cellWidth: (width - spacing * 2) / 3

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth
      label: "Heat"
      glyph: "\uf06d"
      tall: true
      tint: Color.accent
      emphasized: !panel.heating
      pulse: panel.preheating
      onActivated: panel.run("quickpuff heat start")
    }

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth
      label: "Boost"
      glyph: "\uf0e7"
      tall: true
      tint: Qt.tint(Color.accent, Util.alpha(panel.urgent, 0.5))
      onActivated: panel.run("quickpuff heat boost")
    }

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth
      label: "Stop"
      glyph: "\uf04d"
      tall: true
      tint: panel.urgent
      emphasized: panel.heating || panel.cooling
      onActivated: panel.run("quickpuff heat stop")
    }
  }

  Text {
    width: parent.width
    visible: panel.lowHeatBattery && !panel.heating
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    text: "\uf071  Battery " + Math.round(Number(panel.statusData.battery)) + "%: the Peak may refuse to heat. Plug it in first."
    color: panel.urgent
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Item {
    width: parent.width
    visible: panel.timerActive
    implicitHeight: timerRing.height

    TimerRing {
      panel: controlPage.panel
      id: timerRing
      anchors.left: parent.left
      width: Style.space(84)
      height: width
      progress: panel.timerProgress
      fillColor: panel.atTemp ? Color.accent : panel.urgent
      startColor: panel.atTemp ? Qt.lighter(Color.accent, 1.4) : Color.accent

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: panel.formatDuration(panel.timerSecondsLeft)
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    Column {
      anchors.left: timerRing.right
      anchors.leftMargin: Style.space(16)
      anchors.right: parent.right
      anchors.verticalCenter: timerRing.verticalCenter
      spacing: Style.space(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: panel.atTemp ? "\uf0c2  Session" : "\uf06d  Heating up"
        color: panel.atTemp ? Color.accent : panel.urgent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: panel.atTemp
          ? panel.formatDuration(panel.timerSecondsLeft) + " left before the Peak cools down"
          : "Ready in about " + panel.formatDuration(panel.timerSecondsLeft)
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  HeatGraph {
    panel: controlPage.panel
    visible: panel.heatPoints.length >= 2
  }

  Section {
    panel: controlPage.panel
    visible: panel.hasProfiles
    title: "HEAT PROFILES"
    glyph: "\uf06d"

    Grid {
      id: profileGrid
      width: parent.width
      columns: 2
      rowSpacing: Style.spacing.controlGap
      columnSpacing: Style.spacing.controlGap

      readonly property real cellWidth: (width - columnSpacing) / 2

      Repeater {
        model: panel.profiles

        BorderSurface {
          id: tile
          required property var modelData

          readonly property int profileIndex: {
            var n = Number(modelData.index)
            return isFinite(n) ? Math.round(n) : -1
          }
          readonly property bool active: profileIndex >= 0 && profileIndex === panel.currentProfile
          readonly property string swatch: panel.profileColor(profileIndex, modelData.color)
          // A cycling profile's dot runs through its colours.
          readonly property var cycleColors: profileIndex === panel.currentProfile
            ? (panel.cycleOn ? panel.cycleColors : [])
            : (modelData.cycle && modelData.cycle.colors ? modelData.cycle.colors : [])
          readonly property string dotColor: cycleColors.length
            ? cycleColors[panel.cycleTick % cycleColors.length] : swatch
          readonly property real tempF: panel.profileTempF(profileIndex, modelData.temp_f)
          readonly property real timeS: panel.profileTime(profileIndex, modelData.time)
          readonly property string name: {
            var n = panel.profileName(profileIndex, modelData.name)
            return n !== "" ? n : ("Profile " + (profileIndex + 1))
          }

          readonly property bool editingName: panel.editIndex === profileIndex && panel.editField === "name"
          readonly property bool editingTemp: panel.editIndex === profileIndex && panel.editField === "temp"
          readonly property bool editingTime: panel.editIndex === profileIndex && panel.editField === "time"
          readonly property bool editingThis: editingName || editingTemp || editingTime

          // Controls inside the tile sit above the tile's own mouse
          // area, so their hover has to count as the tile's too.
          readonly property bool hot: tileMouse.containsMouse
            || renameButton.hovered || lowerStep.hovered || raiseStep.hovered
            || lowerTime.hovered || raiseTime.hovered
            || tempTapMouse.containsMouse || timeTapMouse.containsMouse
            || nameTap.containsMouse

          width: profileGrid.cellWidth
          implicitHeight: tileBody.implicitHeight + Style.spacing.controlPaddingY * 2
          radius: Style.cornerRadius

          // Each tile wears the colour its lantern glows, so the grid
          // reads like the Peak's own light ring.
          readonly property color tint: swatch !== "" ? swatch : Color.accent

          // Pale swatches (white) wash out fast, so they tint lighter.
          readonly property real tintStrength: tint.hslLightness > 0.8 ? 0.55 : 1
          color: tileMouse.pressed ? Util.alpha(tint, 0.22 * tintStrength)
            : active ? Util.alpha(tint, 0.15 * tintStrength)
            : hot || editingThis ? Util.alpha(tint, 0.09 * tintStrength)
            : Util.alpha(tint, 0.045 * tintStrength)

          borderSpec: active
            ? Border.flat(tint, Math.max(1, Style.normalBorderWidth))
            : (hot || editingThis
               ? Border.flat(Util.alpha(tint, 0.6), Math.max(1, Style.normalBorderWidth))
               : Border.controlSpec("normal", panel.foreground, Color.accent))

          Behavior on color { ColorAnimation { duration: 160 } }

          // A little hop when this becomes the active profile.
          onActiveChanged: if (active && panel.opened) tileHop.restart()
          SequentialAnimation {
            id: tileHop
            NumberAnimation { target: tile; property: "scale"; to: 1.045; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: tile; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
          }

          // Colour stripe down the leading edge; it breathes while
          // this profile is the one heating.
          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Math.max(1, Style.normalBorderWidth)
            width: Style.space(3)
            color: tile.tint
            opacity: tile.active ? 1 : 0.35

            Behavior on opacity { NumberAnimation { duration: 200 } }

            SequentialAnimation on opacity {
              running: tile.active && panel.heating && panel.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
          }

          // Declared before the body so every control in it swallows
          // its own taps instead of also reselecting the profile.
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (tile.profileIndex < 0) return
              panel.runArgv(["quickpuff", "profile", String(tile.profileIndex)])
            }
          }

          Column {
            id: tileBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            spacing: Style.spacing.xxs

            // ----- Name -----
            Item {
              width: parent.width
              implicitHeight: Math.max(Style.space(19), nameRow.implicitHeight)

              Row {
                id: nameRow
                visible: !tile.editingName
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.md

                Rectangle {
                  id: swatchDot
                  width: tile.swatch !== "" ? Style.space(8) : 0
                  height: Style.space(8)
                  radius: width / 2
                  visible: tile.swatch !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  color: tile.dotColor !== "" ? tile.dotColor : "transparent"
                  border.width: 1
                  border.color: Util.alpha(panel.foreground, 0.25)

                  Behavior on color { ColorAnimation { duration: panel.cycleStepMs * 0.9 } }

                  Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width * 1.8
                    height: width
                    radius: width / 2
                    color: Util.alpha(tile.tint, tile.active ? 0.3 : 0)

                    Behavior on color { ColorAnimation { duration: 200 } }
                  }
                }

                Text {
                  id: nameLabel
                  textFormat: Text.PlainText
                  width: nameRow.width
                    - (swatchDot.visible ? swatchDot.width + nameRow.spacing : 0)
                    - (tile.hot ? renameButton.width + nameRow.spacing : 0)
                  text: tile.name
                  color: nameTap.containsMouse ? Color.accent : (tile.active ? tile.tint : panel.foreground)
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: tile.active
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter

                  Behavior on color { ColorAnimation { duration: 120 } }
                  Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                  MouseArea {
                    id: nameTap
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onClicked: panel.startEdit(tile.profileIndex, "name")
                  }
                }

                TileButton {
                  panel: controlPage.panel
                  id: renameButton
                  anchors.verticalCenter: parent.verticalCenter
                  glyph: "\uf040"
                  tooltipHot: tile.hot
                  canTap: tile.profileIndex >= 0
                  onActivated: panel.startEdit(tile.profileIndex, "name")
                }
              }

              Loader {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                active: tile.editingName

                sourceComponent: TileEditor {
                  panel: controlPage.panel
                  owningIndex: tile.profileIndex
                  owningField: "name"
                  seed: tile.name
                  maxChars: 20
                  onCommitted: function(value) { panel.commitName(tile.profileIndex, value) }
                }
              }
            }

            // ----- Temperature -----
            Item {
              width: parent.width
              implicitHeight: Math.max(lowerStep.implicitHeight, tempReadout.implicitHeight)

              TileButton {
                panel: controlPage.panel
                id: lowerStep
                visible: !tile.editingTemp
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "−"
                canTap: panel.canStepTemp(tile.profileIndex, tile.modelData.temp_f, -panel.tempStepF)
                onActivated: panel.stepTemp(tile.profileIndex, tile.modelData.temp_f, -panel.tempStepF)
              }

              Item {
                visible: !tile.editingTemp
                anchors.centerIn: parent
                width: Math.max(tempReadout.implicitWidth + Style.space(10), Style.space(34))
                height: parent.height

                Text {
                  id: tempReadout
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: {
                    var t = panel.formatTemp(tile.tempF, undefined)
                    return t !== "" ? t : "—"
                  }
                  color: tempTapMouse.containsMouse ? Color.accent
                    : (tile.active ? panel.heatRamp(tile.tempF)
                       : Qt.tint(panel.dim, Util.alpha(panel.heatRamp(tile.tempF), 0.45)))
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: tile.active

                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                  id: tempTapMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.IBeamCursor
                  onClicked: panel.startEdit(tile.profileIndex, "temp")
                }
              }

              TileButton {
                panel: controlPage.panel
                id: raiseStep
                visible: !tile.editingTemp
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "+"
                canTap: panel.canStepTemp(tile.profileIndex, tile.modelData.temp_f, panel.tempStepF)
                onActivated: panel.stepTemp(tile.profileIndex, tile.modelData.temp_f, panel.tempStepF)
              }

              Loader {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                active: tile.editingTemp

                sourceComponent: TileEditor {
                  panel: controlPage.panel
                  owningIndex: tile.profileIndex
                  owningField: "temp"
                  digitsOnly: true
                  horizontalAlignment: TextInput.AlignHCenter
                  seed: isFinite(tile.tempF)
                    ? String(Math.round(panel.celsius ? panel.fToC(tile.tempF) : tile.tempF))
                    : ""
                  onCommitted: function(value) { panel.commitTemp(tile.profileIndex, value) }
                }
              }
            }

            // ----- Heat time -----
            Item {
              width: parent.width
              implicitHeight: Math.max(lowerTime.implicitHeight, timeReadout.implicitHeight)

              TileButton {
                panel: controlPage.panel
                id: lowerTime
                visible: !tile.editingTime
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "−"
                canTap: panel.canStepTime(tile.profileIndex, tile.modelData.time, -panel.timeStepS)
                onActivated: panel.stepTime(tile.profileIndex, tile.modelData.time, -panel.timeStepS)
              }

              Item {
                visible: !tile.editingTime
                anchors.centerIn: parent
                width: Math.max(timeReadout.implicitWidth + Style.space(10), Style.space(34))
                height: parent.height

                Text {
                  id: timeReadout
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: isFinite(tile.timeS) ? Math.round(tile.timeS) + "s" : "—"
                  color: timeTapMouse.containsMouse ? Color.accent
                    : (tile.active ? panel.foreground : panel.dim)
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.bodySmall

                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                  id: timeTapMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.IBeamCursor
                  onClicked: panel.startEdit(tile.profileIndex, "time")
                }
              }

              TileButton {
                panel: controlPage.panel
                id: raiseTime
                visible: !tile.editingTime
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "+"
                canTap: panel.canStepTime(tile.profileIndex, tile.modelData.time, panel.timeStepS)
                onActivated: panel.stepTime(tile.profileIndex, tile.modelData.time, panel.timeStepS)
              }

              Loader {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                active: tile.editingTime

                sourceComponent: TileEditor {
                  panel: controlPage.panel
                  owningIndex: tile.profileIndex
                  owningField: "time"
                  digitsOnly: true
                  horizontalAlignment: TextInput.AlignHCenter
                  seed: isFinite(tile.timeS) ? String(Math.round(tile.timeS)) : ""
                  onCommitted: function(value) { panel.commitTime(tile.profileIndex, value) }
                }
              }
            }
            // ----- Where this temperature sits in the Peak's range -----
            Item {
              width: parent.width
              height: Style.space(7)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(3)
                radius: height / 2
                color: Util.alpha(panel.foreground, 0.1)

                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: isFinite(tile.tempF)
                    ? Math.max(parent.height, parent.width * (tile.tempF - panel.minTempF) / (panel.maxTempF - panel.minTempF))
                    : 0
                  opacity: tile.active ? 1 : 0.55
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Util.alpha(tile.tint, 0.35) }
                    GradientStop { position: 1.0; color: tile.tint }
                  }

                  Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                }
              }
            }
          }
        }
      }
    }
  }

  Section {
    panel: controlPage.panel
    visible: panel.hasProfiles && panel.currentProfile >= 0
    title: "VAPOR"
    glyph: "\uf0c2"

    Segmented {
      panel: controlPage.panel
      width: parent.width
      options: panel.vaporLevels
      value: panel.profileVapor(panel.currentProfile,
        (panel.activeProfile && panel.activeProfile.vapor) || "")
      onPicked: function(value) { panel.applyVapor(value) }
    }
  }

  Section {
    panel: controlPage.panel
    id: boostSection
    visible: panel.hasProfiles && panel.currentProfile >= 0
    title: "BOOST"
    glyph: "\uf0e7"

    readonly property var active: panel.activeProfile || ({})

    // Where a boost lands: the profile's temperature plus the extra.
    readonly property real boostedF: panel.profileTempF(panel.currentProfile, active.temp_f)
      + panel.profileBoostTempF(panel.currentProfile, active.boost_temp_f)
    trailing: isFinite(boostedF) ? "Boost peaks at " + panel.formatTemp(boostedF, undefined) : ""

    StepperRow {
      panel: controlPage.panel
      width: parent.width
      label: "Extra temperature"
      valueText: panel.formatBoostTemp(panel.profileBoostTempF(panel.currentProfile, boostSection.active.boost_temp_f))
      canLower: panel.canStepBoostTemp(panel.currentProfile, boostSection.active.boost_temp_f, -panel.boostTempStepF)
      canRaise: panel.canStepBoostTemp(panel.currentProfile, boostSection.active.boost_temp_f, panel.boostTempStepF)
      onLower: panel.stepBoostTemp(panel.currentProfile, boostSection.active.boost_temp_f, -panel.boostTempStepF)
      onRaise: panel.stepBoostTemp(panel.currentProfile, boostSection.active.boost_temp_f, panel.boostTempStepF)
    }

    StepperRow {
      panel: controlPage.panel
      width: parent.width
      label: "Extra time"
      valueText: "+" + Math.round(panel.profileBoostTime(panel.currentProfile, boostSection.active.boost_time)) + "s"
      canLower: panel.canStepBoostTime(panel.currentProfile, boostSection.active.boost_time, -panel.boostTimeStepS)
      canRaise: panel.canStepBoostTime(panel.currentProfile, boostSection.active.boost_time, panel.boostTimeStepS)
      onLower: panel.stepBoostTime(panel.currentProfile, boostSection.active.boost_time, -panel.boostTimeStepS)
      onRaise: panel.stepBoostTime(panel.currentProfile, boostSection.active.boost_time, panel.boostTimeStepS)
    }
  }

  // What plays over the desktop when the Peak is ready. A registry,
  // so another animation is one more entry here and in ReadyOverlay.
  Section {
    panel: controlPage.panel
    glyph: ""
    title: "READY ANIMATION"
    trailing: panel.readyAnimation === "off" ? "" : "Plays when it's ready"

    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Segmented {
        panel: controlPage.panel
        width: parent.width - previewButton.width - parent.spacing
        compact: true
        options: panel.readyAnimations
        value: panel.readyAnimation
        onPicked: function(value) { panel.setReadyAnimation(value) }
      }

      ActionButton {
        panel: controlPage.panel
        id: previewButton
        width: Style.space(80)
        implicitHeight: Style.space(24)
        label: "Preview"
        glyph: ""
        tint: Color.accent
        opacity: panel.readyAnimation === "off" ? 0.4 : 1
        onActivated: panel.previewReadyAnimation()
      }
    }
  }
}
