import QtQuick
import Quickshell
import qs.Commons

// A readout whose digits roll to each new value, odometer-style: up when the
// number grows, down when it shrinks, each digit a beat after the one to its
// right. Anything that isn't a digit (°F, a colon, a unit) slides over only
// when it changes. Characters are right-aligned in fixed slots, so 99 → 100
// grows a digit on the left instead of shifting the rest, and every digit
// gets the width of the widest one, so nothing beside the number jitters.
//
// `live` is for readings that change every moment (the temperature, a
// countdown, a stepper): each digit steps straight to its new value, quick
// and all at once, never wheeling through the numbers in between, so the
// readout never shows a value that wasn't read.
//
// Lays out like a Text of the same font: same height and baseline.
Item {
  id: roll

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string text: ""
  property color color: "white"
  property font font
  property int duration: 560
  property int stagger: 45
  property bool live: false
  // The longest text it holds; longer text loses its leftmost characters.
  readonly property int maxSlots: 8

  // Which way the digits turn on the next change: 1 up, -1 down.
  property int dir: 1
  property string shown: ""

  implicitWidth: slots.implicitWidth
  implicitHeight: line.height
  height: implicitHeight
  // So anchors.baseline lines other text up with the digits.
  baselineOffset: fontInfo.ascent

  // The line box, and the window the digits roll through: the digits'
  // height with a little air, so a rolling digit leaves the window as soon
  // as it leaves its place.
  TextMetrics {
    id: line
    font: roll.font
    text: "0"
  }
  FontMetrics {
    id: fontInfo
    font: roll.font
  }
  // The widest digit: every digit slot is this wide, its glyph centred.
  readonly property real digitW: {
    var w = 0, probe = fontInfo.height
    for (var d = 0; d < 10; d++) w = Math.max(w, fontInfo.advanceWidth(String(d)))
    return w
  }
  readonly property real capTop: fontInfo.ascent + line.tightBoundingRect.y
  readonly property real capH: line.tightBoundingRect.height
  readonly property real pad: capH * 0.16
  readonly property real windowY: Math.max(0, capTop - pad)
  readonly property real windowH: Math.min(height - windowY, capH + pad * 2)

  function numeric(s) {
    var d = String(s).replace(/[^0-9]/g, "")
    return d === "" ? NaN : Number(d)
  }

  Component.onCompleted: shown = text
  onTextChanged: {
    var a = numeric(shown), b = numeric(text)
    if (isFinite(a) && isFinite(b) && a !== b) dir = b > a ? 1 : -1
    shown = text
  }

  // Every character rises into place, right to left, as if the readout had
  // just been switched on (used when the panel opens). Nothing passes
  // through a value that wasn't read.
  function intro() {
    for (var i = 0; i < slotRepeater.count; i++) {
      var s = slotRepeater.itemAt(i)
      if (s) s.intro()
    }
  }

  Row {
    id: slots
    height: roll.height

    Repeater {
      id: slotRepeater
      model: roll.maxSlots

      Item {
        id: slot
        required property int index
        readonly property int fromRight: roll.maxSlots - 1 - index
        readonly property string ch: {
          var s = roll.shown, i = s.length - 1 - fromRight
          return i >= 0 ? s.charAt(i) : ""
        }
        property string lastCh: ""
        property bool wheel: false
        // The digit wheel: whole numbers sit on a digit; past 9 or below 0
        // while it wraps.
        property real pos: 0
        property real target: 0
        // A non-digit change: the old character slides out as the new one
        // slides in.
        property string fromCh: ""
        property string toCh: ""
        property real t: 1
        property int swapDir: 1
        readonly property real frac: pos - Math.floor(pos)

        function digitAt(k) { return String(((Math.floor(k) % 10) + 10) % 10) }
        function isDigit(c) { return c.length === 1 && c >= "0" && c <= "9" }

        function intro() {
          if (ch === "") return
          wheelAnim.stop()
          fromCh = ""
          toCh = ch
          wheel = false
          swapDir = 1
          swapAnim.restart()
        }

        Component.onCompleted: {
          lastCh = ch
          toCh = ch
          wheel = isDigit(ch)
          if (wheel) { pos = Number(ch); target = pos }
        }

        onChChanged: {
          var prev = lastCh
          lastCh = ch
          if (isDigit(prev) && isDigit(ch) && wheel && !roll.live) {
            var base = Math.round(target)
            var n = Number(ch)
            var cur = ((base % 10) + 10) % 10
            var steps = roll.dir > 0 ? (n - cur + 10) % 10 : -((cur - n + 10) % 10)
            if (steps === 0) return
            target = base + steps
            wheelAnim.restart()
            return
          }
          // Mid-roll digit about to be swapped away: settle it first.
          wheelAnim.stop()
          fromCh = wheel ? digitAt(Math.round(target)) : toCh
          toCh = ch
          swapDir = roll.dir
          wheel = false
          if (isDigit(ch)) { pos = Number(ch); target = pos }
          swapAnim.restart()
        }

        // A slot that empties narrows as its character leaves; one that
        // fills, or changes to a wider digit, eases to the new width.
        width: ch === "" ? (fromCh !== "" ? (isDigit(fromCh) ? roll.digitW : leaving.advanceWidth) * (1 - t) : 0)
          : isDigit(ch) ? roll.digitW : glyph.advanceWidth
        height: roll.height
        Behavior on width {
          enabled: slot.ch !== ""
          NumberAnimation { duration: roll.duration * 0.6; easing.type: Easing.OutCubic }
        }

        TextMetrics {
          id: glyph
          font: roll.font
          text: slot.ch
        }
        TextMetrics {
          id: leaving
          font: roll.font
          text: slot.fromCh
        }

        SequentialAnimation {
          id: wheelAnim
          onRunningChanged: if (!running) {
            slot.target = ((Math.round(slot.target) % 10) + 10) % 10
            slot.pos = slot.target
          }
          PauseAnimation { duration: slot.fromRight * roll.stagger }
          NumberAnimation {
            target: slot
            property: "pos"
            to: slot.target
            duration: roll.duration
            easing.type: Easing.OutQuart
          }
        }

        SequentialAnimation {
          id: swapAnim
          onRunningChanged: if (!running) {
            slot.fromCh = ""
            slot.wheel = slot.isDigit(slot.ch)
          }
          ScriptAction { script: slot.t = 0 }
          PauseAnimation { duration: roll.live ? 0 : slot.fromRight * roll.stagger * 0.5 }
          NumberAnimation {
            target: slot
            property: "t"
            to: 1
            duration: roll.live ? 140 : roll.duration * 0.75
            easing.type: roll.live ? Easing.OutCubic : Easing.OutQuart
          }
        }

        // The window: everything moves inside it, fading as it nears an edge.
        Item {
          y: roll.windowY
          width: parent.width
          height: roll.windowH
          clip: true

          // Wheel: the digit it's on and the next one up, by the fraction
          // between them.
          Text {
            visible: slot.wheel
            x: (parent.width - implicitWidth) / 2
            y: -roll.windowY - slot.frac * roll.windowH
            opacity: 1 - slot.frac
            textFormat: Text.PlainText
            text: slot.digitAt(slot.pos)
            color: roll.color
            font: roll.font
          }
          Text {
            visible: slot.wheel && slot.frac > 0
            x: (parent.width - implicitWidth) / 2
            y: -roll.windowY + (1 - slot.frac) * roll.windowH
            opacity: slot.frac
            textFormat: Text.PlainText
            text: slot.digitAt(slot.pos + 1)
            color: roll.color
            font: roll.font
          }

          // Swap: out one way, in from the other.
          Text {
            visible: !slot.wheel && slot.fromCh !== "" && slot.t < 1
            x: (parent.width - implicitWidth) / 2
            y: -roll.windowY - slot.swapDir * slot.t * roll.windowH
            opacity: roll.live ? 1 : 1 - slot.t
            textFormat: Text.PlainText
            text: slot.fromCh
            color: roll.color
            font: roll.font
          }
          Text {
            visible: !slot.wheel && slot.toCh !== ""
            x: (parent.width - implicitWidth) / 2
            y: -roll.windowY + slot.swapDir * (1 - slot.t) * roll.windowH
            opacity: roll.live ? 1 : slot.t
            textFormat: Text.PlainText
            text: slot.toCh
            color: roll.color
            font: roll.font
          }
        }
      }
    }
  }
}
