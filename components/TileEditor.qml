import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Inline field for a profile tile. Commits on Enter, abandons on Escape or
// on losing focus — the identity guard means a blur fired while this field
// is torn down can't cancel whichever edit replaced it.
TextField {
  id: editor

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property int owningIndex: -1
  property string owningField: ""
  property string seed: ""
  property bool digitsOnly: false
  property int maxChars: 0
  // Ignore the blur that fires while the field is still taking focus, or
  // the editor vanishes the instant it appears.
  property bool armed: false

  signal committed(string value)

  foreground: panel.foreground
  accent: Color.accent
  font.family: panel.fontFamily
  font.pixelSize: Style.font.bodySmall
  horizontalPadding: Style.spacing.xs
  verticalPadding: 0
  inputMethodHints: digitsOnly ? Qt.ImhDigitsOnly : Qt.ImhNone
  maximumLength: maxChars > 0 ? maxChars : 32767
  placeholderText: digitsOnly ? "" : "Name"

  Component.onCompleted: {
    text = seed
    Qt.callLater(function() {
      editor.selectAll()
      editor.forceActiveFocus()
      editor.armed = true
    })
  }

  onAccepted: editor.committed(editor.text)
  Keys.onEscapePressed: function(event) {
    panel.cancelEditFor(editor.owningIndex, editor.owningField)
    event.accepted = true
  }
  onActiveFocusChanged: {
    if (!armed || activeFocus) return
    var index = editor.owningIndex
    var field = editor.owningField
    Qt.callLater(function() { panel.cancelEditFor(index, field) })
  }
}
