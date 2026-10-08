import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Unlike TileEditor, losing focus saves: a half-written note shouldn't vanish.
TextField {
  id: noteEditor

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string noteKey: ""
  property string seed: ""
  property bool armed: false
  property bool done: false

  function finish(save) {
    if (done) return
    done = true
    if (save) panel.saveNote(noteKey, text)
    else panel.closeNote(noteKey)
  }

  foreground: panel.foreground
  accent: Color.accent
  font.family: panel.fontFamily
  font.pixelSize: Style.font.bodySmall
  horizontalPadding: Style.spacing.xs
  maximumLength: 500
  placeholderText: "How was it? Flavor, clouds, what you'd change"

  Component.onCompleted: {
    text = seed
    Qt.callLater(function() {
      if (noteEditor.cursorPosition !== undefined) noteEditor.cursorPosition = noteEditor.text.length
      noteEditor.forceActiveFocus()
      noteEditor.armed = true
    })
  }

  onAccepted: noteEditor.finish(true)
  Keys.onEscapePressed: function(event) {
    noteEditor.finish(false)
    event.accepted = true
  }
  onActiveFocusChanged: {
    if (!armed || activeFocus) return
    Qt.callLater(function() { noteEditor.finish(true) })
  }
}
