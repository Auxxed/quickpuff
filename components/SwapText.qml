import QtQuick
import Quickshell
import qs.Commons

// A line of text that changes by handing over: the old line lifts away and
// fades as the new one rises into place, instead of the words snapping. For
// state lines ("Preheating", "Ready") whose change is the news.
Item {
  id: swap

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string text: ""
  property color color: "white"
  property font font
  property int elide: Text.ElideRight
  property int horizontalAlignment: Text.AlignLeft
  property int duration: 320
  // How far the lines travel, as a share of the line height.
  property real travel: 0.55

  property string _front: ""
  property string _back: ""
  property real _t: 1

  implicitWidth: Math.max(frontText.implicitWidth, _t < 1 ? backText.implicitWidth : 0)
  implicitHeight: frontText.implicitHeight

  Component.onCompleted: _front = text
  onTextChanged: {
    if (text === _front) return
    if (!(panel && panel.opened) || _front === "") {
      _front = text
      return
    }
    _back = _t < 1 ? _back : _front
    _front = text
    handover.restart()
  }

  NumberAnimation {
    id: handover
    target: swap
    property: "_t"
    from: 0
    to: 1
    duration: swap.duration
    easing.type: Easing.OutCubic
  }

  Text {
    id: backText
    width: swap.width
    visible: swap._t < 1
    y: -swap._t * height * swap.travel
    opacity: 1 - Math.min(1, swap._t * 1.6)
    textFormat: Text.PlainText
    text: swap._back
    color: swap.color
    font: swap.font
    elide: swap.elide
    horizontalAlignment: swap.horizontalAlignment
  }

  Text {
    id: frontText
    width: swap.width
    y: (1 - swap._t) * height * swap.travel
    opacity: Math.min(1, swap._t * 1.4)
    textFormat: Text.PlainText
    text: swap._front
    color: swap.color
    font: swap.font
    elide: swap.elide
    horizontalAlignment: swap.horizontalAlignment
  }
}
