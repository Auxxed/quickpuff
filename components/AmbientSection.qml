import QtQuick
import qs.Commons

// The lantern's own colours from the desktop: your Omarchy theme, or the
// album art of what's playing (the music wins while something plays).
Section {
  id: ambientSection

  glyph: ""
  title: "LANTERN COLORS"
  trailing: panel.ambientNow
    ? (panel.ambientNow.source === "music" ? "Following the music" : "Following your theme")
    : ""

  SwitchRow {
    panel: ambientSection.panel
    width: parent.width
    label: "Match my Omarchy theme"
    checked: panel.themeLightOn
    onToggled: panel.toggleThemeLight()
  }

  SwitchRow {
    panel: ambientSection.panel
    width: parent.width
    label: "Match the album art playing"
    checked: panel.musicLightOn
    onToggled: panel.toggleMusicLight()
  }

  // The colours on the lantern now, and what they came from.
  Row {
    width: parent.width
    visible: panel.ambientNow !== null
    spacing: Style.space(8)

    Repeater {
      model: panel.ambientNow ? panel.ambientNow.colors : []

      Rectangle {
        required property var modelData
        width: Style.space(18)
        height: width
        radius: width / 2
        color: modelData
        border.width: 1
        border.color: Qt.lighter(modelData, 1.4)
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(30) * 3
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: !panel.ambientNow ? ""
        : panel.ambientNow.source === "music"
          ? (panel.ambientNow.track || "Now playing")
          : "Your theme's colors"
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: panel.themeLightOn || panel.musicLightOn
      ? "The lantern takes these colours whenever it's on (your heat profiles keep theirs). Switch both off and it gets its own light back."
      : "Let the lantern glow in your theme's colours, following you when you switch themes, or in the colours of the album you're playing."
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
