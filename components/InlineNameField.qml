import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// One-line name editor: Enter commits, Escape or clicking away cancels.
TextField {
  id: nameField

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string seed: ""
  property bool armed: false
  property bool done: false

  signal committed(string value)
  signal canceled()

  function finish(save) {
    if (done) return
    done = true
    if (save) nameField.committed(nameField.text)
    else nameField.canceled()
  }

  foreground: panel.foreground
  accent: Color.accent
  font.family: panel.fontFamily
  font.pixelSize: Style.font.bodySmall
  horizontalPadding: Style.spacing.xs
  maximumLength: 32

  Component.onCompleted: {
    text = seed
    Qt.callLater(function() {
      nameField.selectAll()
      nameField.forceActiveFocus()
      nameField.armed = true
    })
  }

  onAccepted: nameField.finish(true)
  Keys.onEscapePressed: function(event) {
    nameField.finish(false)
    event.accepted = true
  }
  onActiveFocusChanged: {
    if (!armed || activeFocus) return
    Qt.callLater(function() { nameField.finish(false) })
  }
}
