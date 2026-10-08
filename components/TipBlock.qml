import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: tip

  // The QuickPuff panel: palette, state and actions.
  property var panel

  property string title: ""
  property string body: ""

  spacing: Style.space(2)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: tip.title
    color: panel.foreground
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: tip.body
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
