import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components/plain.js" as Plain

// QuickPuff Wrapped: your month (or year, or all time) in sessions, played
// over the desktop slide by slide, Spotify Wrapped style, ending on a card
// that's saved to ~/Pictures. Click to skip to the card, click again to close.
//
// Everything shown comes from `quickpuff wrapped`, checked in play(): known
// ranges for numbers, #rrggbb for the colour, plain short text for names.
PanelWindow {
  id: wrap

  signal finished()

  property bool soundsOn: true
  property real soundVolume: 0.7
  property var w: ({})
  property var slides: []
  property int slide: -1
  property string savedTo: ""
  property bool closing: false

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickpuff-wrapped"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/Rajdhani-SemiBold.ttf") }
  FontLoader { id: textFont; source: Qt.resolvedUrl("fonts/Rajdhani-Medium.ttf") }
  readonly property string display: displayFont.status === FontLoader.Ready ? displayFont.name : Style.font.family
  readonly property string body: textFont.status === FontLoader.Ready ? textFont.name : Style.font.family
  readonly property real u: Math.max(1, Math.min(width, height * 16 / 9) / 1536)
  readonly property color tint: w.color || "#ff4fa3"
  readonly property bool onCard: slide >= 0 && slide === slides.length - 1

  // ------------------------------------------------------------ the data

  function num(v, lo, hi) {
    var n = Number(v)
    return v !== null && v !== undefined && isFinite(n) && n >= lo && n <= hi ? n : null
  }

  function hourText(h) {
    return h === null ? "" : (h < 10 ? "0" : "") + h + ":00"
  }

  function play(d) {
    var top = d.top_profile && typeof d.top_profile === "object" ? d.top_profile : null
    var you = d.personality && typeof d.personality === "object" ? d.personality : ({})
    var busiest = d.busiest_day && typeof d.busiest_day === "object" ? d.busiest_day : ({})
    var hot = d.hottest && typeof d.hottest === "object" ? d.hottest : ({})
    var period = ["month", "year", "all"].indexOf(d.period) >= 0 ? d.period : "month"
    w = {
      "period": period,
      "label": Plain.plain(d.label, 24),
      "peak": Plain.plain(d.peak_name, 40),
      "sessions": num(d.sessions, 0, 1000000) || 0,
      "previous": num(d.previous, 0, 1000000),
      "days": num(d.days_active, 0, 100000),
      "streak": num(d.best_streak, 0, 100000),
      "busiest": num(busiest.count, 0, 10000),
      "busiestDate": Plain.plain(busiest.date, 10),
      "topName": top ? Plain.plain(top.name, 40) : "",
      "topShare": top ? num(top.share, 0, 1) : null,
      "color": top && typeof top.color === "string" && /^#[0-9a-fA-F]{6}$/.test(top.color) ? top.color : "",
      "hour": num(d.top_hour, 0, 23),
      "weekday": Plain.plain(d.top_weekday, 10),
      "hottest": num(hot.temp_f, 0, 1200),
      "heatup": num(d.avg_heatup_s, 0, 900),
      "title": Plain.plain(you.title, 30),
      "line": Plain.plain(you.line, 90)
    }
    var s = []
    var periodWord = period === "month" ? "month" : period === "year" ? "year" : "time"
    s.push({ "kicker": "QUICKPUFF WRAPPED", "big": w.label.toUpperCase(), "small": w.peak ? "Your " + w.peak + ", in sessions" : "Your sessions, wrapped" })
    if (w.sessions === 0) {
      s.push({ "kicker": "SESSIONS", "big": "0", "small": "Nothing yet this " + periodWord + ". Go make some memories." })
    } else {
      var change = ""
      if (w.previous) {
        var pct = Math.round((w.sessions - w.previous) / w.previous * 100)
        change = (pct >= 0 ? "+" : "") + pct + "% on the same days last " + periodWord
      }
      s.push({ "kicker": "SESSIONS", "count": w.sessions, "small": (w.days ? "over " + w.days + " days" : "") + (change ? "  ·  " + change : "") })
      if (w.streak) s.push({ "kicker": "LONGEST STREAK", "count": w.streak, "unit": w.streak === 1 ? " DAY" : " DAYS",
        "small": w.busiest ? "Busiest day: " + w.busiestDate + ", " + w.busiest + " sessions" : "" })
      if (w.topName) s.push({ "kicker": "YOUR FAVOURITE PROFILE", "big": w.topName.toUpperCase(),
        "small": w.topShare !== null ? Math.round(w.topShare * 100) + "% of your sessions" : "" })
      if (w.hottest) s.push({ "kicker": "HOTTEST SESSION", "count": w.hottest, "unit": "°F",
        "small": w.heatup ? "Average heat-up: " + w.heatup + " s" : "" })
      if (w.weekday) s.push({ "kicker": "PRIME TIME", "big": w.weekday.toUpperCase() + "S",
        "small": w.hour !== null ? "around " + hourText(w.hour) : "" })
      if (w.title) s.push({ "kicker": "YOU'RE A", "big": w.title.toUpperCase(), "small": w.line })
    }
    s.push({ "card": true })
    slides = s
    slide = 0
    cue("ready")
    advance.restart()
  }

  // ------------------------------------------------------------ the flow

  Timer {
    id: advance
    interval: 3300
    repeat: true
    onTriggered: wrap.next()
  }

  function next() {
    if (slide < slides.length - 1) {
      slide++
      if (onCard) {
        advance.stop()
        cue("complete")
        saveSoon.restart()
        closeSoon.restart()
      }
    } else {
      close()
    }
  }

  function close() {
    if (closing) return
    closing = true
    advance.stop()
    fadeOut.start()
  }

  Timer { id: saveSoon; interval: 900; onTriggered: wrap.save() }
  Timer { id: closeSoon; interval: 9000; onTriggered: wrap.close() }

  // The card, at 1600 x 900, into ~/Pictures under a name that's new each time.
  function save() {
    var home = String(Quickshell.env("HOME") || "")
    if (home.charAt(0) !== "/") return
    var stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14)
    var path = home + "/Pictures/QuickPuff-Wrapped-" + w.period + "-" + stamp + ".png"
    card.grabToImage(function(result) {
      if (result.saveToFile(path)) wrap.savedTo = "~/Pictures/QuickPuff-Wrapped-" + w.period + "-" + stamp + ".png"
    }, Qt.size(1600, 900))
  }

  function cue(name) {
    if (!soundsOn || !/^[a-z]+$/.test(name)) return
    var volume = Math.max(0, Math.min(1, Number(soundVolume) || 0))
    if (volume <= 0) return
    var url = String(Qt.resolvedUrl("sounds/" + name + ".ogg"))
    if (url.indexOf("file://") !== 0) return
    Quickshell.execDetached(["/usr/bin/timeout", "-k", "1", "10", "/usr/bin/pw-play",
      "--volume", volume.toFixed(2), "--", decodeURIComponent(url.slice(7))])
  }

  // ------------------------------------------------------------ the picture

  Item {
    id: scene
    anchors.fill: parent
    opacity: 0
    Component.onCompleted: fadeIn.start()
    NumberAnimation { id: fadeIn; target: scene; property: "opacity"; to: 1; duration: 600; easing.type: Easing.OutCubic }
    NumberAnimation {
      id: fadeOut; target: scene; property: "opacity"; to: 0; duration: 700; easing.type: Easing.InCubic
      onFinished: wrap.finished()
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#f20b0710" }
        GradientStop { position: 1.0; color: Qt.rgba(wrap.tint.r * 0.25, wrap.tint.g * 0.12, wrap.tint.b * 0.2, 0.96) }
      }
    }

    // Two slow glows drifting behind everything, in your profile's colour.
    Glow {
      hue: Util.alpha(wrap.tint, 0.55)
      width: wrap.width * 0.7; height: width
      x: wrap.width * (0.05 + 0.08 * Math.sin(drift.t * 2 * Math.PI)) - width * 0.2
      y: wrap.height * 0.15 - height * 0.3
    }
    Glow {
      hue: Util.alpha(Qt.lighter(wrap.tint, 1.4), 0.35)
      width: wrap.width * 0.55; height: width
      x: wrap.width * (0.62 - 0.06 * Math.cos(drift.t * 2 * Math.PI))
      y: wrap.height * 0.55 - height * 0.25
    }
    QtObject {
      id: drift
      property real t: 0
      NumberAnimation on t { from: 0; to: 1; duration: 16000; loops: Animation.Infinite }
    }

    // One slide at a time: the kicker, the big line (counting up when it's a
    // number), and the line under it.
    Repeater {
      model: wrap.slides.length

      Item {
        id: page
        required property int index
        readonly property var spec: wrap.slides[index]
        readonly property bool current: wrap.slide === index
        anchors.fill: parent
        visible: opacity > 0 && !spec.card
        opacity: current ? 1 : 0
        property real rise: current ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        Behavior on rise { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        property real shown: 0
        onCurrentChanged: if (current && spec.count !== undefined) { shown = 0; countUp.restart() }
        NumberAnimation { id: countUp; target: page; property: "shown"; to: page.spec.count || 0; duration: 1400; easing.type: Easing.OutCubic }

        Column {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: page.rise * 40 * wrap.u
          spacing: 18 * wrap.u
          width: wrap.width * 0.8

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: page.spec.kicker || ""
            color: Qt.lighter(wrap.tint, 1.35)
            font.family: wrap.display
            font.pixelSize: 30 * wrap.u
            font.letterSpacing: 10 * wrap.u
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: page.spec.count !== undefined ? Math.round(page.shown) + (page.spec.unit || "") : (page.spec.big || "")
            color: "white"
            font.family: wrap.display
            font.pixelSize: (page.spec.count !== undefined ? 220 : 120) * wrap.u
            font.letterSpacing: 6 * wrap.u
            style: Text.Outline
            styleColor: Util.alpha(wrap.tint, 0.35)
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: page.spec.small || ""
            color: "#e8d8e4"
            font.family: wrap.body
            font.pixelSize: 40 * wrap.u
            font.letterSpacing: 2 * wrap.u
          }
        }
      }
    }

    // The card: everything at once, and what gets saved.
    Rectangle {
      id: card
      width: Math.min(wrap.width * 0.78, 1400 * wrap.u)
      height: width * 9 / 16
      anchors.centerIn: parent
      radius: 28 * wrap.u
      opacity: wrap.onCard ? 1 : 0
      scale: wrap.onCard ? 1 : 0.94
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 700; easing.type: Easing.OutBack } }
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#1a0f18" }
        GradientStop { position: 1.0; color: Qt.rgba(wrap.tint.r * 0.35, wrap.tint.g * 0.18, wrap.tint.b * 0.3, 1) }
      }
      border.width: 2 * wrap.u
      border.color: Util.alpha(wrap.tint, 0.6)

      readonly property real k: width / 1400

      Glow { hue: Util.alpha(wrap.tint, 0.35); width: card.width * 0.6; height: width; x: card.width * 0.55; y: -height * 0.35 }

      Column {
        x: 70 * card.k
        y: 60 * card.k
        spacing: 10 * card.k

        Text {
          textFormat: Text.PlainText
          text: "QUICKPUFF WRAPPED  ·  " + String(wrap.w.label || "").toUpperCase()
          color: Qt.lighter(wrap.tint, 1.35)
          font.family: wrap.display
          font.pixelSize: 30 * card.k
          font.letterSpacing: 8 * card.k
        }
        Text {
          textFormat: Text.PlainText
          text: wrap.w.title ? "YOU'RE A " + String(wrap.w.title).toUpperCase() : ""
          color: "white"
          font.family: wrap.display
          font.pixelSize: 84 * card.k
          font.letterSpacing: 4 * card.k
        }
        Text {
          textFormat: Text.PlainText
          text: wrap.w.line || ""
          color: "#e8d8e4"
          font.family: wrap.body
          font.pixelSize: 30 * card.k
        }
      }

      Grid {
        x: 70 * card.k
        y: card.height * 0.46
        columns: 3
        columnSpacing: 70 * card.k
        rowSpacing: 34 * card.k

        Repeater {
          model: [
            { "label": "SESSIONS", "value": String(wrap.w.sessions || 0) },
            { "label": "LONGEST STREAK", "value": wrap.w.streak ? wrap.w.streak + " days" : "–" },
            { "label": "FAVOURITE", "value": wrap.w.topName || "–" },
            { "label": "HOTTEST", "value": wrap.w.hottest ? wrap.w.hottest + "°F" : "–" },
            { "label": "PRIME TIME", "value": wrap.w.weekday ? wrap.w.weekday + " " + wrap.hourText(wrap.w.hour) : "–" },
            { "label": "AVG HEAT-UP", "value": wrap.w.heatup ? wrap.w.heatup + " s" : "–" }
          ]

          Column {
            required property var modelData
            width: 360 * card.k
            spacing: 4 * card.k
            Text {
              textFormat: Text.PlainText
              text: modelData.label
              color: Qt.lighter(wrap.tint, 1.3)
              font.family: wrap.display
              font.pixelSize: 22 * card.k
              font.letterSpacing: 5 * card.k
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: modelData.value
              color: "white"
              font.family: wrap.display
              font.pixelSize: 52 * card.k
            }
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 40 * card.k
        textFormat: Text.PlainText
        text: "github.com/Auxxed/quickpuff"
        color: Util.alpha("#e8d8e4", 0.6)
        font.family: wrap.body
        font.pixelSize: 22 * card.k
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: card.bottom
      anchors.topMargin: 26 * wrap.u
      visible: wrap.onCard
      textFormat: Text.PlainText
      text: wrap.savedTo ? "Saved to " + wrap.savedTo : ""
      color: "#cdbccb"
      font.family: wrap.body
      font.pixelSize: 26 * wrap.u
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        if (wrap.onCard) {
          wrap.close()
        } else {
          wrap.slide = wrap.slides.length - 2
          wrap.next()
        }
      }
    }
  }

  component Glow: Shape {
    id: glow
    property color hue: "white"
    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: glow.width / 2; centerY: glow.height / 2; centerRadius: glow.width / 2
        focalX: glow.width / 2; focalY: glow.height / 2
        GradientStop { position: 0.0; color: glow.hue }
        GradientStop { position: 1.0; color: "transparent" }
      }
      PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height }
    }
  }
}
