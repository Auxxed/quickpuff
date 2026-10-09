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

  Item {
    width: parent.width
    implicitHeight: Math.max(sectionHeader.implicitHeight, sectionGlyph.implicitHeight)

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

    Text {
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
