import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "plain.js" as Plain

// Titled block: every group of controls gets the same small-caps header
// and spacing, which is most of what makes the pages read as one system.
Column {
  id: section

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string title: ""
  property string trailing: ""
  property string glyph: ""
  default property alias body: sectionBody.data

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  // Cascades in as the panel opens; rises in when it turns up later.
  transform: Translate { id: sectionShift }
  Reveal { panel: section.panel; target: section; shift: sectionShift; appear: true }

  // The header's trace drawing out and its glyph flashing, as the section
  // comes into view.
  property real trace: 1
  property real spark: 0
  function lightUp() {
    if (panel && panel.calm) { traceAnim.stop(); trace = 1; spark = 0; return }
    traceAnim.restart()
  }
  onVisibleChanged: if (visible && panel && panel.opened) lightUp()
  Connections {
    target: section.panel
    function onOpenSerialChanged() { if (section.visible) section.lightUp() }
  }
  SequentialAnimation {
    id: traceAnim
    ScriptAction { script: { section.trace = 0; section.spark = 0 } }
    PauseAnimation { duration: 160 }
    ParallelAnimation {
      NumberAnimation { target: section; property: "trace"; to: 1; duration: 700; easing.type: Easing.OutCubic }
      SequentialAnimation {
        NumberAnimation { target: section; property: "spark"; to: 1; duration: 120 }
        NumberAnimation { target: section; property: "spark"; to: 0; duration: 600; easing.type: Easing.OutCubic }
      }
    }
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(sectionHeader.implicitHeight, sectionGlyph.implicitHeight)

    // The glyph glows, brighter for a moment as the section arrives.
    Glow {
      visible: sectionGlyph.visible
      hue: Util.alpha(Color.accent, 0.4)
      x: sectionGlyph.x + sectionGlyph.width / 2 - 50
      y: sectionGlyph.y + sectionGlyph.height / 2 - 50
      scale: sectionGlyph.height * 2.4 / 100
      opacity: 0.55 + 0.45 * section.spark
    }

    Text {
      id: sectionGlyph
      visible: section.glyph !== ""
      width: visible ? implicitWidth : 0
      anchors.left: parent.left
      anchors.verticalCenter: sectionHeader.verticalCenter
      textFormat: Text.PlainText
      text: section.glyph
      color: Color.accent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    PanelSectionHeader {
      id: sectionHeader
      anchors.left: sectionGlyph.right
      anchors.leftMargin: sectionGlyph.visible ? Style.space(6) : 0
      // Drawn by the shell (AutoText), so plain()ed here.
      text: Plain.plain(section.title, 60)
      foreground: panel.foreground
      fontFamily: panel.displayFamily
      fontSize: Math.round(Style.font.caption * panel.displayScale)
      font.letterSpacing: panel.hasDisplayFont ? 0.8 : 0
    }

    // A fine trace of light runs out from the title toward the right, like
    // a line on a circuit board, drawing itself as the section arrives.
    Item {
      readonly property real from: sectionHeader.x + sectionHeader.implicitWidth + Style.space(8)
      readonly property real to: trailingText.visible ? trailingText.x - Style.space(8) : parent.width
      x: from
      anchors.verticalCenter: sectionHeader.verticalCenter
      anchors.verticalCenterOffset: Style.space(1)
      width: Math.max(0, to - from)
      height: Math.max(1, Style.space(1))

      Rectangle {
        width: parent.width * section.trace
        height: parent.height
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.42) }
          GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.04) }
        }
      }
      // The spark at the trace's head while it draws.
      Rectangle {
        visible: section.trace > 0.01 && section.trace < 0.99
        x: parent.width * section.trace - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(5)
        height: width
        radius: width / 2
        color: Qt.tint(Color.accent, Util.alpha("#ffffff", 0.5))
        opacity: 1 - section.trace
      }
    }

    Text {
      id: trailingText
      visible: section.trailing !== ""
      anchors.right: parent.right
      anchors.bottom: sectionHeader.bottom
      textFormat: Text.PlainText
      text: section.trailing
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Column {
    id: sectionBody
    width: parent.width
    spacing: Style.space(8)
  }
}
