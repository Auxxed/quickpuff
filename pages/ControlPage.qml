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

  // Slides in from the side of the tab it was switched to from.
  transform: Translate { id: pageShift }
  Reveal { panel: controlPage.panel; target: controlPage; shift: pageShift; cascade: false; slide: true }

  Row {
    id: actionRow
    width: parent.width
    spacing: Style.spacing.controlGap

    // Heat leads, twice as wide, in the colour the Peak will glow.
    readonly property real cellWidth: (width - spacing * 2) / 4

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth * 2
      label: panel.preheating ? "Heating" : panel.atTemp ? "Ready" : "Heat"
      glyph: "\uf06d"
      tall: true
      tint: panel.profileTint
      solid: !panel.heating
      emphasized: !panel.heating
      // Full once it's there. While it climbs the hero's bar and the timer
      // ring show how far, and Stop is the action, so Heat keeps still.
      progress: panel.atTemp ? 1 : -1
      onActivated: panel.runArgv(["quickpuff", "heat", "start"])
    }

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth
      label: "Boost"
      glyph: "\uf0e7"
      tall: true
      zaps: true
      tint: Qt.tint(Color.accent, Util.alpha(panel.urgent, 0.5))
      onActivated: panel.runArgv(["quickpuff", "heat", "boost"])
    }

    ActionButton {
      panel: controlPage.panel
      width: actionRow.cellWidth
      label: "Stop"
      glyph: "\uf04d"
      tall: true
      tint: panel.urgent
      // The live action once a heat starts: solid, like Heat at rest.
      solid: panel.heating
      emphasized: panel.heating || panel.cooling
      onActivated: panel.runArgv(["quickpuff", "heat", "stop"])
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
    id: timerRow
    width: parent.width
    visible: panel.timerActive
    implicitHeight: timerRing.height

    // Rises in when heating starts.
    transform: Translate { id: timerShift }
    Reveal { panel: controlPage.panel; target: timerRow; shift: timerShift; appear: true }

    TimerRing {
      panel: controlPage.panel
      id: timerRing
      anchors.left: parent.left
      width: Style.space(84)
      height: width
      progress: panel.timerProgress
      fillColor: panel.atTemp ? Color.accent : panel.urgent
      startColor: panel.atTemp ? Qt.lighter(Color.accent, 1.4) : Color.accent

      RollingNumber {
        live: true
        panel: controlPage.panel
        anchors.centerIn: parent
        text: panel.formatDuration(panel.timerSecondsLeft)
        color: panel.foreground
        duration: 420
        stagger: 35
        font.family: panel.displayFamily
        font.pixelSize: Math.round(Style.font.title * panel.displayScale)
        font.weight: Font.DemiBold
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
        // What the ring's number is, without saying it twice.
        text: panel.atTemp ? "Left before the Peak cools down" : "Until it's ready, roughly"
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
          // Stepping through its colours, or holding the first in Calm motion.
          readonly property string dotColor: cycleColors.length
            ? cycleColors[panel.calm ? 0 : panel.cycleTick % cycleColors.length] : swatch
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

          // A little hop when this becomes the active profile, and a band of
          // its light sweeping across it.
          onActiveChanged: if (active && panel.opened && !panel.calm) { tileHop.restart(); tileSweep.restart() }
          SequentialAnimation {
            id: tileHop
            NumberAnimation { target: tile; property: "scale"; to: 1.045; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: tile; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
          }
          clip: true

          Rectangle {
            id: sweepBand
            property real k: -1
            visible: k > -1 && k < 1
            width: tile.width * 0.55
            height: tile.height * 2.2
            y: -tile.height * 0.6
            x: -width + (tile.width + width) * k
            rotation: 18
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Util.alpha(tile.tint, 0) }
              GradientStop { position: 0.5; color: Util.alpha(Qt.lighter(tile.tint, 1.25), 0.28 * tile.tintStrength) }
              GradientStop { position: 1.0; color: Util.alpha(tile.tint, 0) }
            }
          }
          NumberAnimation {
            id: tileSweep
            target: sweepBand
            property: "k"
            from: 0
            to: 1
            duration: 720
            easing.type: Easing.InOutCubic
            onStopped: sweepBand.k = -1
          }

          // Puffco's heat-profile cards: the profile's colour, shaded
          // darker toward the foot.
          Rectangle {
            anchors.fill: parent
            anchors.margins: Math.max(1, Style.normalBorderWidth)
            radius: Math.max(0, tile.radius - anchors.margins)
            opacity: tile.active ? 1 : 0.5
            gradient: Gradient {
              GradientStop { position: 0.0; color: Util.alpha(tile.tint, 0.2 * tile.tintStrength) }
              GradientStop { position: 1.0; color: Util.alpha(Qt.darker(tile.tint, 1.6), 0) }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
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
            opacity: !tile.active ? 0.35 : panel.heating ? 1 - 0.65 * panel.wave : 1

            Behavior on opacity {
              enabled: !panel.heating
              NumberAnimation { duration: 200 }
            }
          }

          // Declared before the body so every control in it swallows
          // its own taps instead of also reselecting the profile.
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.selectProfile(tile.profileIndex)
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

                  // A quick hop to each colour, like the Peak's LEDs: a glide
                  // across the whole step kept the panel redrawing nonstop.
                  Behavior on color { ColorAnimation { duration: Math.min(220, panel.cycleStepMs * 0.4) } }

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
                    cursorShape: tile.active ? Qt.IBeamCursor : Qt.PointingHandCursor
                    // On another profile the first tap picks it; on the
                    // active one it edits.
                    onClicked: tile.active ? panel.startEdit(tile.profileIndex, "name") : panel.selectProfile(tile.profileIndex)
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
                // Out of the way until the card is pointed at, as on Puffco's cards.
                tooltipHot: tile.hot || tile.editingThis
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

                RollingNumber {
                  id: tempReadout
                  live: true
                  panel: controlPage.panel
                  anchors.centerIn: parent
                  duration: 380
                  stagger: 30
                  text: {
                    var t = panel.formatTemp(tile.tempF, undefined)
                    return t !== "" ? t : "—"
                  }
                  color: tempTapMouse.containsMouse ? Color.accent
                    : (tile.active ? panel.heatRamp(tile.tempF)
                       : Qt.tint(panel.dim, Util.alpha(panel.heatRamp(tile.tempF), 0.45)))
                  font.family: panel.displayFamily
                  font.pixelSize: Math.round(Style.font.subtitle * panel.displayScale)
                  font.weight: Font.DemiBold

                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                  id: tempTapMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: tile.active ? Qt.IBeamCursor : Qt.PointingHandCursor
                  onClicked: tile.active ? panel.startEdit(tile.profileIndex, "temp") : panel.selectProfile(tile.profileIndex)
                }
              }

              TileButton {
                panel: controlPage.panel
                id: raiseStep
                // Out of the way until the card is pointed at, as on Puffco's cards.
                tooltipHot: tile.hot || tile.editingThis
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
                // Out of the way until the card is pointed at, as on Puffco's cards.
                tooltipHot: tile.hot || tile.editingThis
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

                RollingNumber {
                  id: timeReadout
                  live: true
                  panel: controlPage.panel
                  anchors.centerIn: parent
                  duration: 380
                  stagger: 30
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
                  cursorShape: tile.active ? Qt.IBeamCursor : Qt.PointingHandCursor
                  onClicked: tile.active ? panel.startEdit(tile.profileIndex, "time") : panel.selectProfile(tile.profileIndex)
                }
              }

              TileButton {
                panel: controlPage.panel
                id: raiseTime
                // Out of the way until the card is pointed at, as on Puffco's cards.
                tooltipHot: tile.hot || tile.editingThis
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
    visible: panel.hasProfiles && panel.currentProfile >= 0
    title: "FLAVOUR FIRST"
    glyph: "\uf2c9"
    trailing: isNaN(panel.rampTarget) ? "" : "Now " + panel.formatTemp(panel.rampTarget, (panel.rampTarget - 32) * 5 / 9)

    SwitchRow {
      panel: controlPage.panel
      width: parent.width
      label: "Start low, finish hot"
      checked: panel.flavorFirst
      onToggled: panel.toggleFlavorFirst()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.rampMethod === "live"
        ? "This profile's first pull runs 40° under its temperature for flavour, the last 20° over it so nothing's left in the chamber."
        : "The last pull runs 20° hot so nothing's left in the chamber. (The low start needs a one-time check: quickpuff ramp probe --yes, next to the Peak.)"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
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

    Grid {
      id: animGrid
      width: parent.width
      // Three across, so the longer names (Smoke Rings, Supernova) fit.
      columns: 3
      rowSpacing: Style.spacing.controlGap
      columnSpacing: Style.spacing.controlGap

      readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

      Repeater {
        model: panel.readyAnimations
        ActionButton {
          panel: controlPage.panel
          required property var modelData
          width: animGrid.cellWidth
          label: modelData.label
          glyph: modelData.glyph
          // Picked in the accent, like every other choice in the panel.
          tint: modelData.value === "off" ? panel.foreground : Color.accent
          emphasized: panel.readyAnimation === modelData.value
          onActivated: panel.setReadyAnimation(modelData.value)
        }
      }
    }

    ActionButton {
      panel: controlPage.panel
      id: previewButton
      width: parent.width
      label: panel.readyAnimation === "off" ? "Pick one to preview" : "Preview it on screen"
      glyph: "\uf04b"
      tint: Color.accent
      opacity: panel.readyAnimation === "off" ? 0.4 : 1
      onActivated: panel.previewReadyAnimation()
    }
  }

  // The heat cycle, played out over the desktop, and its sounds.
  Section {
    panel: controlPage.panel
    glyph: "\uf008"
    title: "SHOWTIME"
    trailing: panel.showtimeMode === "stage" ? "Takes the whole screen" : panel.showtimeMode === "corner" ? "A card under the bar" : ""

    Segmented {
      panel: controlPage.panel
      width: parent.width
      compact: true
      options: panel.showtimeOptions
      value: panel.showtimeMode
      onPicked: function(value) { panel.setShowtime(value) }
    }

    SwitchRow {
      panel: controlPage.panel
      width: parent.width
      label: "Sounds"
      checked: panel.soundsOn
      onToggled: panel.toggleSounds()
    }

    ActionButton {
      panel: controlPage.panel
      width: parent.width
      label: "Watch a demo cycle"
      glyph: "\uf04b"
      tint: panel.profileTint
      onActivated: panel.runDemo()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "The demo plays a whole heat cycle on screen, from preheat to the ready show to the session, without heating your Peak."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Everyday comfort: the flourishes off, the information kept.
  Section {
    panel: controlPage.panel
    glyph: "\uf0e4"
    title: "MOTION"

    SwitchRow {
      panel: controlPage.panel
      width: parent.width
      label: "Calm motion"
      checked: panel.calm
      onToggled: panel.toggleCalm()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.calm
        ? "Progress, readings and state changes still move; the sparks, breathing, slides and celebrations are off, here and in the bar. The ready show still plays."
        : "Calm motion keeps the panel and bar to what tells you something, without the sparks, breathing, slides and celebrations."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
