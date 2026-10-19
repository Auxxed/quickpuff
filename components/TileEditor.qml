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
  maximumLength: maxChars > 0 ? maxChars : 64
  placeholderText: digitsOnly ? "" : "Name"

  Component.onCompleted: {
    panel.openEditor = editor
    text = seed
    Qt.callLater(function() {
      editor.selectAll()
      editor.forceActiveFocus()
      editor.armed = true
    })
  }

  // Set once Enter or Esc has settled it, so losing focus as it closes
  // doesn't save (again).
  property bool settled: false
  Component.onDestruction: if (panel && panel.openEditor === editor) panel.openEditor = null
  // Keeps what was typed when the panel moves on without a blur (another
  // field picked, the panel closed).
  function flush() {
    if (settled) return
    settled = true
    var typed = String(text).trim()
    if (typed !== "" && typed !== String(seed).trim()) committed(typed)
  }
  onAccepted: {
    settled = true
    editor.committed(editor.text)
  }
  Keys.onEscapePressed: function(event) {
    settled = true
    panel.cancelEditFor(editor.owningIndex, editor.owningField)
    event.accepted = true
  }
  // Clicking away keeps what was typed (as notes do); Esc is the way out
  // without saving. An unchanged or empty field just closes.
  onActiveFocusChanged: {
    if (!armed || activeFocus || settled) return
    settled = true
    var index = editor.owningIndex
    var field = editor.owningField
    var typed = String(editor.text).trim()
    if (typed !== "" && typed !== String(editor.seed).trim()) {
      Qt.callLater(function() { editor.committed(typed) })
      return
    }
    Qt.callLater(function() { panel.cancelEditFor(index, field) })
  }
}
