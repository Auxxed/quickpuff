import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Colour cycle for the active profile: on/off, a live preview of the
// animation, the style, palettes, your own colours and the speed.
Section {
  id: cycleSection

  glyph: ""
  title: panel.activeProfile
    ? "COLOR CYCLE · " + String(panel.cleanName(panel.activeProfile.name) || ("Profile " + (panel.currentProfile + 1))).toUpperCase()
    : "COLOR CYCLE"
  trailing: panel.cycleOn ? "On the Peak" : ""

  SwitchRow {
    panel: cycleSection.panel
    width: parent.width
    label: "Cycle colors"
    checked: panel.cycleOn
    onToggled: panel.setCycleOn(!panel.cycleOn)
  }

  // A strip of LEDs acting out the chosen style at roughly its pace, frame
  // by frame: colours glide where the Peak glides them and jump where it
  // jumps them.
  Item {
    id: ledStrip
    width: parent.width
    height: Style.space(26)
    readonly property int leds: 14
    opacity: panel.cycleOn ? 1 : 0.55

    Behavior on opacity { NumberAnimation { duration: 250 } }

    // Repeatable noise in 0..1.
    function hash(x) {
      var v = Math.sin(x * 12.9898 + 78.233) * 43758.5453
      return v - Math.floor(v)
    }
    function dim(c, b) {
      var q = Qt.color(c)
      return Qt.rgba(q.r * b, q.g * b, q.b * b, 1)
    }

    function ledColor(i, phase) {
      var c = panel.cycleColors, n = c.length, L = leds
      if (!n) return Color.accent
      var whole = Math.floor(phase), frac = phase - whole
      switch (panel.cycleStyle) {
      // The palette laid round the ring, turning.
      case "spin": return panel.cycleColorAt(phase + i * n / L)
      // Each colour swells and sinks to dark before the next.
      case "breathe": return dim(c[whole % n], 0.1 + 0.9 * Math.pow(Math.sin(Math.PI * frac), 2))
      // Every LED its own colour, changing hard and fast.
      case "disco": {
        var step = Math.floor(phase * 2.5)
        return dim(c[Math.floor(hash(i * 7.31 + step * 1.17) * n) % n], 0.55 + 0.45 * hash(i * 3.1 + step))
      }
      // Two halves, each walking the palette half a turn apart.
      case "split": return panel.cycleColorAt(phase + (i < L / 2 ? 0 : Math.max(0.5, Math.floor(n / 2))))
      // The next colour wipes across the strip over the last.
      case "fill": {
        var front = frac * (L + 3) - 1.5
        var k = Math.max(0, Math.min(1, front - i + 0.5))
        return panel.mixColor(c[whole % n], c[(whole + 1) % n], k)
      }
      // Big slow blobs drifting and merging.
      case "lava": {
        var v = 0.6 * Math.sin(i * 0.45 + phase * 0.55) + 0.4 * Math.sin(i * 0.23 - phase * 0.31 + 1.3)
        return panel.cycleColorAt((v + 1) / 2 * n + phase * 0.12)
      }
      // A dim bed of colour with sparks popping up and fading out.
      case "confetti": {
        var bed = dim(panel.cycleColorAt(phase * 0.25), 0.16)
        var lane = phase * 3 + hash(i) * 3
        var slot = Math.floor(lane), age = lane - slot
        if (hash(i * 3.7 + slot * 9.1) > 0.36) return bed
        var spark = c[Math.floor(hash(i + slot * 5.3) * n) % n]
        return panel.mixColor(bed, spark, Math.pow(1 - age, 1.6))
      }
      // The whole ring fading from colour to colour.
      default: return panel.cycleColorAt(phase)
      }
    }

    Row {
      id: ledRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Repeater {
        model: ledStrip.leds

        Rectangle {
          required property int index
          readonly property color led: ledStrip.ledColor(index, panel.cyclePhase)
          width: (ledStrip.width - ledRow.spacing * (ledStrip.leds - 1)) / ledStrip.leds
          height: Style.space(14)
          radius: height / 2
          color: led

          Rectangle {
            z: -1
            anchors.centerIn: parent
            width: parent.width + Style.space(6)
            height: parent.height + Style.space(6)
            radius: height / 2
            color: Util.alpha(parent.led, 0.32)
          }
          // A wider haze, so the strip glows like real LEDs behind glass.
          Rectangle {
            z: -2
            anchors.centerIn: parent
            width: parent.width + Style.space(14)
            height: parent.height + Style.space(16)
            radius: height / 2
            color: Util.alpha(parent.led, 0.12)
          }
        }
      }
    }
  }

  // The app's animations, two rows of four.
  Grid {
    id: styleGrid
    width: parent.width
    columns: 4
    rowSpacing: Style.space(4)
    columnSpacing: Style.space(4)
    readonly property real cell: (width - columnSpacing * 3) / 4

    Repeater {
      model: panel.cycleStyles

      Rectangle {
        id: styleChip
        required property var modelData
        readonly property bool picked: panel.cycleStyle === modelData.value
        width: styleGrid.cell
        height: Style.space(40)
        radius: Style.cornerRadius
        color: picked ? Util.alpha(Color.accent, 0.2)
          : styleMouse.containsMouse ? Style.hoverFillFor(panel.foreground, Color.accent)
          : Style.normalFillFor(panel.foreground, Color.accent)
        border.width: 1
        border.color: picked ? Color.accent : Util.alpha(panel.foreground, 0.12)
        scale: styleMouse.pressed ? 0.93 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(2)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: styleChip.modelData.glyph
            color: styleChip.picked ? Color.accent : panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: styleChip.modelData.label
            color: styleChip.picked ? panel.foreground : panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: styleChip.picked
          }
        }

        MouseArea {
          id: styleMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.pickCycleStyle(styleChip.modelData.value)
        }
      }
    }
  }

  // Palette presets as gradient pills.
  Grid {
    id: paletteGrid
    width: parent.width
    columns: 3
    rowSpacing: Style.space(6)
    columnSpacing: Style.space(6)
    readonly property real cell: (width - columnSpacing * 2) / 3

    Repeater {
      model: panel.cyclePalettes

      Rectangle {
        id: paletteChip
        required property var modelData
        readonly property bool picked: {
          var a = panel.cycleColors, b = modelData.colors
          if (a.length !== b.length) return false
          for (var i = 0; i < a.length; i++) if (String(a[i]).toLowerCase() !== b[i]) return false
          return true
        }
        width: paletteGrid.cell
        height: Style.space(26)
        radius: height / 2
        border.width: picked ? 2 : 1
        border.color: picked ? panel.foreground : Util.alpha(panel.foreground, 0.25)
        scale: paletteMouse.pressed ? 0.94 : (paletteMouse.containsMouse ? 1.05 : 1)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: paletteChip.modelData.colors[0] }
          GradientStop { position: 0.5; color: paletteChip.modelData.colors[Math.floor(paletteChip.modelData.colors.length / 2)] }
          GradientStop { position: 1.0; color: paletteChip.modelData.colors[paletteChip.modelData.colors.length - 1] }
        }

        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        Rectangle {
          anchors.centerIn: parent
          width: paletteLabel.implicitWidth + Style.space(12)
          height: paletteLabel.implicitHeight + Style.space(2)
          radius: height / 2
          color: Util.alpha("black", 0.45)

          Text {
            id: paletteLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: (paletteChip.picked ? " " : "") + paletteChip.modelData.name
            color: "white"
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        MouseArea {
          id: paletteMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.pickCyclePalette(paletteChip.modelData.colors)
        }
      }
    }
  }

  // Your colours: tap one to drop it, + adds the colour on the wheel.
  Item {
    width: parent.width
    implicitHeight: yourRow.height + yourHint.implicitHeight + Style.space(6)

    Row {
      id: yourRow
      spacing: Style.space(8)
      height: Style.space(28)

      Repeater {
        model: panel.cycleColors

        Rectangle {
          id: cycleDot
          required property var modelData
          required property int index
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(26)
          height: width
          radius: width / 2
          color: String(modelData)
          border.width: panel.cycleColors[panel.cycleTick % panel.cycleColors.length] === modelData && panel.cycleOn ? 2 : 1
          border.color: border.width > 1 ? panel.foreground : Util.alpha(panel.foreground, 0.3)
          scale: dotMouse.containsMouse ? 1.12 : 1

          Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

          Text {
            anchors.centerIn: parent
            visible: dotMouse.containsMouse && panel.cycleColors.length > 1
            textFormat: Text.PlainText
            text: ""
            color: panel.inkOn(cycleDot.modelData)
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: dotMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: panel.cycleColors.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.removeCycleColor(cycleDot.index)
          }
        }
      }

      Rectangle {
        visible: panel.cycleColors.length < panel.maxCycleColors
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(26)
        height: width
        radius: width / 2
        color: addMouse.containsMouse ? Util.alpha(panel.foreground, 0.12) : "transparent"
        border.width: 1
        border.color: Util.alpha(panel.foreground, 0.45)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "+"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        MouseArea {
          id: addMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (panel.pickerOpen) {
              panel.addCycleColor(panel.pickHex)
            } else {
              // Open the wheel so the next colour can be picked exactly.
              panel.togglePicker()
            }
          }
        }
      }
    }

    Text {
      id: yourHint
      anchors.top: yourRow.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: panel.pickerOpen
        ? "+ adds the colour on the wheel. Tap a colour to drop it."
        : "+ opens the colour wheel. Tap a colour to drop it."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: speedLabel.implicitHeight

      Text {
        id: speedLabel
        textFormat: Text.PlainText
        text: "Speed"
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: panel.cycleTempo < 0.35 ? "Chill" : panel.cycleTempo < 0.7 ? "Groovy" : "Rave"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      width: parent.width
      bar: panel.bar
      minimum: 10
      maximum: 100
      step: 5
      integer: true
      value: Math.round(panel.cycleTempo * 100)
      onReleased: function(v) { panel.setCycleTempo(v / 100) }
    }
  }

  SwitchRow {
    panel: cycleSection.panel
    width: parent.width
    label: "React to inhales"
    checked: panel.cycleInhale
    onToggled: panel.toggleCycleInhale()
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: panel.cycleOn
      ? "The Peak runs the animation itself, even when this computer is away. Turn the LED on above to see it."
      : "Pick a style and colours, then switch it on."
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  SwitchRow {
    panel: cycleSection.panel
    width: parent.width
    label: "Surprise me after each session"
    checked: panel.surpriseOn
    onToggled: panel.toggleSurprise()
  }

  Text {
    width: parent.width
    visible: panel.surpriseOn
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: "After each dab, the profile you used gets a new cycle or one of My lights for next time. A light you made yourself is saved to My lights before it's replaced."
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
