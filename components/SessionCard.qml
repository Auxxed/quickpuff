import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// One dab in History: what it was, when, and its note (tap to edit).
BorderSurface {
  id: sessionCard

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property var session: ({})
  readonly property string key: String(session.key || "")
  readonly property bool editingNote: panel.noteKey === key
  readonly property string note: panel.noteFor(session)

  radius: Style.cornerRadius
  color: Style.normalFillFor(panel.foreground, Color.accent)
  borderSpec: Border.controlSpec(sessionMouse.containsMouse || editingNote ? "hover-cursor" : "normal", panel.foreground, Color.accent)
  implicitHeight: sessionCol.implicitHeight + Style.spacing.controlPaddingY * 2

  // The profile's colour down the leading edge, like the heat tiles.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: Math.max(1, Style.normalBorderWidth)
    width: Style.space(3)
    color: sessionCard.session.profile !== null && sessionCard.session.profile !== undefined
      ? panel.profileUsageColor(sessionCard.session.profile)
      : panel.profileTint
    opacity: sessionMouse.containsMouse || sessionCard.editingNote ? 1 : 0.6
  }

  MouseArea {
    id: sessionMouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: !sessionCard.editingNote
    cursorShape: Qt.PointingHandCursor
    onClicked: panel.editNote(sessionCard.key)
  }

  Column {
    id: sessionCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.topMargin: Style.spacing.controlPaddingY
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(sessionTitle.implicitHeight, sessionTime.implicitHeight)

      Text {
        id: sessionTitle
        anchors.left: parent.left
        anchors.right: sessionTime.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        // Profile and temperature read like the Control tab's cards.
        text: panel.sessionTitle(sessionCard.session)
        color: panel.foreground
        font.family: panel.displayFamily
        font.pixelSize: Math.round(Style.font.bodySmall * panel.displayScale)
        font.weight: Font.DemiBold
        font.capitalization: panel.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: panel.hasDisplayFont ? 0.6 : 0
      }

      Text {
        id: sessionTime
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: panel.formatSessionTime(sessionCard.session.ts)
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      text: panel.sessionDetail(sessionCard.session)
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      visible: !sessionCard.editingNote
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: sessionCard.note !== "" ? sessionCard.note : "Add a note"
      color: sessionCard.note !== "" ? panel.foreground : panel.dim
      font.family: panel.fontFamily
      font.pixelSize: sessionCard.note !== "" ? Style.font.bodySmall : Style.font.caption
      font.italic: sessionCard.note === ""
    }

    Loader {
      width: parent.width
      active: sessionCard.editingNote

      sourceComponent: NoteEditor {
        panel: sessionCard.panel
        noteKey: sessionCard.key
        seed: sessionCard.note
      }
    }

    Text {
      width: parent.width
      visible: sessionCard.editingNote
      textFormat: Text.PlainText
      text: "Enter or click away to save \u00b7 Esc to cancel"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
