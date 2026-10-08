import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The custom colour picker: a hue/saturation wheel, a brightness slider,
// a live preview and a hex field. Releasing the wheel or the slider sends
// the colour to the Peak; so does Enter in the hex field.
BorderSurface {
  id: picker

  // The QuickPuff panel: palette, state and actions.
  property var panel

  radius: Style.cornerRadius
  color: Util.alpha(panel.pickColor, 0.06)
  borderSpec: Border.flat(Util.alpha(panel.pickColor, 0.45), Math.max(1, Style.normalBorderWidth))
  implicitHeight: pickerRow.implicitHeight + Style.spacing.controlPaddingY * 4

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: pickerRow
    anchors.centerIn: parent
    width: parent.width - Style.spacing.controlPaddingX * 2
    spacing: Style.space(14)

    // ----- Wheel -----
    Item {
      id: wheel
      width: Style.space(140)
      height: width
      anchors.verticalCenter: parent.verticalCenter
      readonly property real radius: width / 2

      // Glow in the picked colour behind the wheel.
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + Style.space(10)
        height: width
        radius: width / 2
        color: Util.alpha(panel.pickColor, 0.22)
      }

      // Hue runs round the wheel (red at 3 o'clock, counter-clockwise) and
      // saturation out from the white centre, at full value; the slider
      // darkens it. Linear RGB blends between pure hues, and from white to
      // a hue, are exactly HSV at full value, so the colour under the
      // cursor is the one the maths below picks.
      Canvas {
        id: wheelCanvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2, cy = height / 2, R = Math.min(width, height) / 2
          var hues = ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
          var cone = ctx.createConicalGradient(cx, cy, 0)
          for (var i = 0; i < hues.length; i++) cone.addColorStop(i / (hues.length - 1), hues[i])
          ctx.fillStyle = cone
          ctx.beginPath()
          ctx.arc(cx, cy, R, 0, Math.PI * 2)
          ctx.fill()
          var white = ctx.createRadialGradient(cx, cy, 0, cx, cy, R)
          white.addColorStop(0, "rgba(255,255,255,1)")
          white.addColorStop(1, "rgba(255,255,255,0)")
          ctx.fillStyle = white
          ctx.beginPath()
          ctx.arc(cx, cy, R, 0, Math.PI * 2)
          ctx.fill()
        }
      }

      // Darkens the whole wheel to match the brightness slider.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "black"
        opacity: 1 - panel.pickV
      }

      // Cursor.
      Rectangle {
        id: wheelKnob
        readonly property real angle: panel.pickH * Math.PI * 2
        readonly property real reach: panel.pickS * wheel.radius
        width: Style.space(wheelMouse.pressed ? 20 : 16)
        height: width
        radius: width / 2
        x: wheel.radius + Math.cos(angle) * reach - width / 2
        y: wheel.radius - Math.sin(angle) * reach - height / 2
        color: panel.pickColor
        border.width: 2
        border.color: "white"

        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

        Rectangle {
          anchors.fill: parent
          anchors.margins: -1
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Util.alpha("black", 0.5)
        }
      }

      MouseArea {
        id: wheelMouse
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        preventStealing: true

        function pick(mx, my) {
          var dx = mx - wheel.radius
          var dy = my - wheel.radius
          var hue = Math.atan2(-dy, dx) / (Math.PI * 2)
          if (hue < 0) hue += 1
          panel.pickH = hue
          panel.pickS = Math.min(1, Math.sqrt(dx * dx + dy * dy) / wheel.radius)
          // A dark colour picked off the wheel is almost never what's meant.
          if (panel.pickV < 0.15) panel.pickV = 1
        }

        onPressed: function(mouse) { pick(mouse.x, mouse.y) }
        onPositionChanged: function(mouse) { if (pressed) pick(mouse.x, mouse.y) }
        onReleased: panel.schedulePickApply()
      }
    }

    // ----- Preview, brightness, hex -----
    Column {
      width: pickerRow.width - wheel.width - pickerRow.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(38)
          height: width
          radius: width / 2
          color: panel.pickColor
          border.width: 1
          border.color: Util.alpha(panel.foreground, 0.35)

          Rectangle {
            z: -1
            anchors.centerIn: parent
            width: parent.width + Style.space(10)
            height: width
            radius: width / 2
            color: Util.alpha(panel.pickColor, 0.3)
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: panel.pickHex.toUpperCase()
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: {
              var c = panel.pickColor
              return Math.round(c.r * 255) + " · " + Math.round(c.g * 255) + " · " + Math.round(c.b * 255)
            }
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Brightness (HSV value) slider over a black-to-colour gradient.
      Column {
        width: parent.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: valueLabel.implicitHeight

          Text {
            id: valueLabel
            textFormat: Text.PlainText
            text: "Brightness"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: Math.round(panel.pickV * 100) + "%"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          id: valueTrack
          width: parent.width
          height: Style.space(16)

          Rectangle {
            anchors.fill: parent
            anchors.topMargin: Style.space(3)
            anchors.bottomMargin: Style.space(3)
            radius: height / 2
            border.width: 1
            border.color: Util.alpha(panel.foreground, 0.2)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "black" }
              GradientStop { position: 1.0; color: Qt.hsva(panel.pickH, panel.pickS, 1, 1) }
            }
          }

          Rectangle {
            width: Style.space(valueMouse.pressed ? 18 : 14)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: panel.pickV * (valueTrack.width - width)
            color: panel.pickColor
            border.width: 2
            border.color: "white"

            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
          }

          MouseArea {
            id: valueMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            function set(mx) { panel.pickV = Math.max(0, Math.min(1, mx / valueTrack.width)) }

            onPressed: function(mouse) { set(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) set(mouse.x) }
            onReleased: panel.schedulePickApply()
          }
        }
      }

      // Exact colour by hex; Enter applies it.
      TextField {
        id: hexField
        width: parent.width
        foreground: panel.foreground
        accent: Color.accent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.xs
        maximumLength: 7
        placeholderText: "#rrggbb"

        property bool bad: false

        // Follows the wheel until you start typing in it.
        Binding on text {
          when: !hexField.activeFocus
          value: panel.pickHex.toUpperCase()
        }

        onTextChanged: bad = false
        onAccepted: {
          if (panel.applyTypedHex(text)) {
            bad = false
            panel.refocusPanel()
          } else {
            bad = true
          }
        }
        Keys.onEscapePressed: function(event) {
          panel.refocusPanel()
          event.accepted = true
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: hexField.bad ? "That's not a colour. Try #ff6a1a."
          : panel.cycleOn ? "Cycling: choose a colour here, then + in Color cycle adds it."
          : "Let go of the wheel or press Enter to send it to the Peak."
        color: hexField.bad ? panel.urgent : panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
