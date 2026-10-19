import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Thin rounded progress bar with a gradient fill that eases to its value.
// It grows out from empty whenever the panel opens on it or its page shows.
Rectangle {
  id: meter

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property real value: 0
  property color fill: Color.accent
  // Pulses for attention (a clean that's due).
  property bool throb: false
  // A light running along the fill (taking a charge).
  property bool sheen: false
  // A tick at this fraction (0-1), like the Puffco app's 80% charge-limit
  // mark; below 0 draws none.
  property real marker: -1
  readonly property real clamped: isFinite(value) ? Math.max(0, Math.min(1, value)) : 0

  implicitHeight: Style.space(6)
  height: implicitHeight
  radius: height / 2
  color: Util.alpha(panel.foreground, 0.1)

  // Emptied without animating, then let go so the fill grows back.
  property bool collapsed: false
  property bool glide: true
  function regrow() {
    if (panel.calm) return
    glide = false
    collapsed = true
    Qt.callLater(function() {
      meter.glide = true
      meter.collapsed = false
    })
  }
  onVisibleChanged: if (visible && panel.opened) regrow()
  Connections {
    target: meter.panel
    function onOpenSerialChanged() { if (meter.visible) meter.regrow() }
  }

  Rectangle {
    id: bar
    height: parent.height
    radius: parent.radius
    width: meter.collapsed || meter.clamped <= 0 ? 0 : Math.max(parent.height, parent.width * meter.clamped)
    clip: true
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Util.alpha(meter.fill, 0.45) }
      GradientStop { position: 1.0; color: meter.fill }
    }

    Behavior on width {
      enabled: meter.glide
      NumberAnimation { duration: 750; easing.type: Easing.OutCubic }
    }

    SequentialAnimation on opacity {
      running: meter.throb && meter.visible && panel.opened && !panel.calm
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    Rectangle {
      visible: meter.sheen
      property real k: 0
      width: Math.max(Style.space(24), bar.width * 0.35)
      height: parent.height
      x: -width + (bar.width + width) * k
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
        GradientStop { position: 0.5; color: Util.alpha("#ffffff", 0.5) }
        GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0) }
      }
      NumberAnimation on k {
        running: meter.sheen && meter.visible && panel.opened && !panel.calm
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 1700
        easing.type: Easing.InOutQuad
      }
    }
  }

  // Taking a charge, it crackles: sparks jump off the fill's leading edge.
  Repeater {
    model: meter.sheen && meter.clamped < 1 && !panel.calm ? 6 : 0
    Rectangle {
      id: crackle
      required property int index
      property real k: 0
      readonly property real side: index % 2 ? 1 : -1
      width: Style.space(index % 3 ? 2.5 : 3.5)
      height: width
      radius: width / 2
      x: bar.width - width / 2 + Style.space(6) * k * (0.5 + 0.5 * ((index * 37) % 10) / 10)
      y: meter.height / 2 - height / 2 + side * Style.space(9) * k * (0.4 + 0.6 * ((index * 53) % 10) / 10)
      color: index % 3 === 0 ? "#ffffff" : Qt.lighter(meter.fill, 1.4)
      opacity: (1 - k) * 0.9
      SequentialAnimation on k {
        running: meter.sheen && meter.visible && meter.panel.opened
        loops: Animation.Infinite
        PauseAnimation { duration: (crackle.index * 230) % 900 }
        NumberAnimation { from: 0; to: 1; duration: 420 + (crackle.index % 3) * 80; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 300 + (crackle.index * 170) % 500 }
      }
    }
  }

  Rectangle {
    visible: meter.marker >= 0 && meter.marker <= 1
    x: Math.round(parent.width * meter.marker) - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(2, Style.space(2))
    height: parent.height + Style.space(6)
    radius: width / 2
    color: panel.foreground
  }
}
