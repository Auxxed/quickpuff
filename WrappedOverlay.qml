import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components"
import "components/plain.js" as Plain

// QuickPuff Wrapped: your month (or year, or all time) in sessions, played
// over the desktop slide by slide, Spotify Wrapped style, ending on a card
// that's saved to ~/Pictures/Puffco Wrapped. Click to skip to the card, click
// again to close.
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

  // 0 → 1 through the slide on screen, for its story bar; full on the card.
  property real slideT: 0
  onSlideChanged: {
    slideTAnim.stop()
    slideT = 0
    if (onCard) slideT = 1
    else slideTAnim.start()
  }
  NumberAnimation { id: slideTAnim; target: wrap; property: "slideT"; from: 0; to: 1; duration: 3300 }

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

  // Once the card has finished building, so the saved picture is whole.
  Timer { id: saveSoon; interval: 2000; onTriggered: wrap.save() }
  Timer { id: closeSoon; interval: 9000; onTriggered: wrap.close() }

  // The card, at 1600 x 900, into ~/Pictures/Puffco Wrapped (the daemon makes
  // the folder, see paths.wrapped_dir) under a name that's new each time.
  function save() {
    var home = String(Quickshell.env("HOME") || "")
    if (home.charAt(0) !== "/") return
    var stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14)
    var name = "Pictures/Puffco Wrapped/QuickPuff-Wrapped-" + w.period + "-" + stamp + ".png"
    card.grabToImage(function(result) {
      if (result.saveToFile(home + "/" + name)) wrap.savedTo = "~/" + name
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

    // Bokeh: soft discs of the profile's light floating slowly upward.
    Repeater {
      model: 18
      Glow {
        id: mote
        required property int index
        // Each starts partway through its climb, so the screen opens full.
        property real base: 0
        readonly property real seedA: ((index * 37) % 100) / 100
        readonly property real seedB: ((index * 71) % 100) / 100
        readonly property real k: (base + seedB) % 1
        width: (40 + 120 * seedA) * wrap.u
        height: width
        hue: Util.alpha(index % 3 ? wrap.tint : Qt.lighter(wrap.tint, 1.5), 0.18 + 0.2 * seedB)
        x: wrap.width * (0.04 + 0.92 * seedB) + Math.sin(k * Math.PI * 2 + index) * 40 * wrap.u - width / 2
        y: wrap.height * (1.1 - 1.3 * k) - height / 2
        opacity: Math.min(1, k / 0.15, (1 - k) / 0.25)
        NumberAnimation on base {
          from: 0
          to: 1
          duration: 14000 + mote.seedA * 9000
          loops: Animation.Infinite
        }
      }
    }

    // Story bars along the top: one per slide, filling while it plays.
    Row {
      id: storyBars
      anchors.horizontalCenter: parent.horizontalCenter
      y: 28 * wrap.u
      spacing: 8 * wrap.u
      readonly property int count: Math.max(1, wrap.slides.length)
      readonly property real barW: Math.min(140 * wrap.u, (wrap.width * 0.6 - spacing * (count - 1)) / count)
      Repeater {
        model: wrap.slides.length
        Rectangle {
          required property int index
          width: storyBars.barW
          height: 4 * wrap.u
          radius: height / 2
          color: Util.alpha("#ffffff", 0.18)
          readonly property real fill: index < wrap.slide ? 1 : index > wrap.slide ? 0 : wrap.slideT
          // A tinted glow under the filled part, so the bars read as lit.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * parent.fill + height / 2
            x: -height / 4
            height: parent.height * 3.5
            radius: height / 2
            color: Util.alpha(wrap.tint, 0.28)
            visible: parent.fill > 0
          }
          Rectangle {
            height: parent.height
            radius: parent.radius
            color: Qt.tint("#ffffff", Util.alpha(wrap.tint, 0.18))
            opacity: 0.9
            width: parent.width * parent.fill
          }
          // The playing bar's head: a spark riding the edge of the fill.
          Glow {
            visible: index === wrap.slide && !wrap.onCard
            hue: Util.alpha(Qt.lighter(wrap.tint, 1.4), 0.9)
            width: parent.height * 6
            height: width
            x: parent.width * parent.fill - width / 2
            anchors.verticalCenter: parent.verticalCenter
          }
          Rectangle {
            visible: index === wrap.slide && !wrap.onCard
            width: parent.height * 1.6
            height: width
            radius: width / 2
            x: parent.width * parent.fill - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
          }
        }
      }
    }

    // One slide at a time: the kicker tracking in, the big line springing
    // up (counting when it's a number), and the line under it after a beat.
    // The slide before lifts away as this one rises, and while it holds the
    // whole slide pushes in a touch.
    Repeater {
      model: wrap.slides.length

      Item {
        id: page
        required property int index
        readonly property var spec: wrap.slides[index]
        readonly property bool current: wrap.slide === index
        anchors.fill: parent
        visible: opacity > 0.001 && !spec.card
        // Before: below, waiting. Current: in place. After: lifted away.
        property real place: index < wrap.slide ? -1 : (current ? 0 : 1)
        Behavior on place { NumberAnimation { duration: 760; easing.type: Easing.OutCubic } }
        // Fades are started by hand: a Behavior would pick its timings
        // before `current` had flipped. The slide before clears quickly;
        // this one waits for it.
        opacity: 0
        SequentialAnimation {
          id: slideIn
          PauseAnimation { duration: 240 }
          NumberAnimation { target: page; property: "opacity"; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
        NumberAnimation { id: slideOut; target: page; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InQuad }
        property real shown: 0
        // 0 → 1 as the slide arrives: drives the type's entrance.
        property real arrive: 0
        property real push: 0
        onCurrentChanged: {
          if (!current) {
            slideIn.stop()
            slideOut.restart()
            return
          }
          shown = 0
          arrive = 0
          slideOut.stop()
          slideIn.restart()
          arriveStart.restart()
          pushAnim.restart()
        }
        // The type starts once the slide before has cleared.
        Timer {
          id: arriveStart
          interval: 200
          onTriggered: {
            if (page.spec.count !== undefined) countUp.restart()
            arriveAnim.restart()
            strikeSoon.restart()
          }
        }
        // As the big line lands: a word as it settles, a count as it arrives.
        Timer { id: strikeSoon; interval: page.spec.count !== undefined ? 1250 : 640; onTriggered: bigLine.strike() }
        NumberAnimation { id: countUp; target: page; property: "shown"; to: page.spec.count || 0; duration: 1500; easing.type: Easing.OutCubic }
        NumberAnimation { id: arriveAnim; target: page; property: "arrive"; from: 0; to: 1; duration: 1100; easing.type: Easing.Linear }
        NumberAnimation { id: pushAnim; target: page; property: "push"; from: 0; to: 1; duration: 3600; easing.type: Easing.OutSine }
        function beat(i) {
          var k = Math.max(0, Math.min(1, (arrive - i * 0.16) / 0.55))
          return 1 - Math.pow(1 - k, 3)
        }

        Column {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: page.place * 60 * wrap.u
          spacing: 18 * wrap.u
          width: wrap.width * 0.8
          scale: 1 + 0.035 * page.push

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: page.spec.kicker || ""
            color: Qt.lighter(wrap.tint, 1.35)
            opacity: page.beat(0)
            font.family: wrap.display
            font.pixelSize: 30 * wrap.u
            font.letterSpacing: (10 + 22 * (1 - page.beat(0))) * wrap.u
          }
          Text {
            id: bigLine
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: page.spec.count !== undefined ? Math.round(page.shown) + (page.spec.unit || "") : (page.spec.big || "")
            color: Qt.tint("white", Util.alpha(Qt.lighter(wrap.tint, 1.5), 0.6 * bigLine.zap))
            opacity: page.beat(1)

            // 1 → 0 through a strike, flickering on the way out.
            property real zap: 0
            property var forks: []
            function bolt(x0, y0, dir, len, segs, jag) {
              var pts = [Qt.point(x0, y0)]
              for (var i = 1; i <= segs; i++) {
                var f = i / segs
                pts.push(Qt.point(x0 + dir * len * f, y0 + (i === segs ? 0.4 : 1) * (Math.random() - 0.5) * 2 * jag * (0.4 + f)))
              }
              return pts
            }
            function strike() {
              var u = wrap.u
              var cx = width / 2, cy = height / 2
              var half = Math.min(width / 2, contentWidth / 2) + 26 * u
              var f = []
              for (var side = -1; side <= 1; side += 2) {
                var main = bolt(cx + side * half, cy + (Math.random() - 0.5) * contentHeight * 0.3, side, (200 + Math.random() * 120) * u, 9, 22 * u)
                f.push(main)
                // A branch off the main bolt's middle, angling away.
                var at = main[3 + Math.floor(Math.random() * 3)]
                var b = bolt(at.x, at.y, side, (70 + Math.random() * 60) * u, 4, 16 * u)
                var tilt = (Math.random() < 0.5 ? -1 : 1) * (40 + Math.random() * 40) * u
                for (var k = 1; k < b.length; k++) b[k] = Qt.point(b[k].x, b[k].y + tilt * k / (b.length - 1))
                f.push(b)
              }
              forks = f
              zapAnim.restart()
              shockAnim.restart()
            }
            SequentialAnimation {
              id: zapAnim
              NumberAnimation { target: bigLine; property: "zap"; from: 0; to: 1; duration: 50 }
              NumberAnimation { target: bigLine; property: "zap"; to: 0.25; duration: 70 }
              NumberAnimation { target: bigLine; property: "zap"; to: 0.9; duration: 50 }
              NumberAnimation { target: bigLine; property: "zap"; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }

            // The shockwave: a ring the shape of the line, spreading out.
            Rectangle {
              id: shock
              z: -1
              property real k: 1
              anchors.centerIn: parent
              width: Math.min(bigLine.width, bigLine.contentWidth) + (24 + 220 * k) * wrap.u
              height: bigLine.contentHeight * 0.8 + (12 + 140 * k) * wrap.u
              radius: height / 2
              color: "transparent"
              border.width: Math.max(1, (5 - 4 * k) * wrap.u)
              border.color: Qt.lighter(wrap.tint, 1.4)
              opacity: (1 - k) * 0.8
              visible: k < 1
              NumberAnimation { id: shockAnim; target: shock; property: "k"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
            }
            Shape {
              anchors.fill: parent
              visible: bigLine.zap > 0.01
              opacity: bigLine.zap
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeColor: Util.alpha(wrap.tint, 0.35)
                strokeWidth: 12 * wrap.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathMultiline { paths: bigLine.forks }
              }
              ShapePath {
                strokeColor: Qt.tint(wrap.tint, Util.alpha("#ffffff", 0.7))
                strokeWidth: 3 * wrap.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathMultiline { paths: bigLine.forks }
              }
            }
            scale: 0.86 + 0.14 * page.beat(1) + 0.04 * Math.sin(Math.PI * page.beat(1))
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
            opacity: page.beat(2.2)
            transform: Translate { y: (1 - page.beat(2.2)) * 24 * wrap.u }
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
      // 0 → 1 once the card is up: the headline, then each stat in turn.
      property real build: 0
      Connections {
        target: wrap
        function onOnCardChanged() { if (wrap.onCard) cardBuild.restart() }
      }
      NumberAnimation { id: cardBuild; target: card; property: "build"; from: 0; to: 1; duration: 1600; easing.type: Easing.Linear }
      function beat(i) {
        var t = Math.max(0, Math.min(1, (build - 0.12 - i * 0.08) / 0.35))
        return 1 - Math.pow(1 - t, 3)
      }

      Glow { hue: Util.alpha(wrap.tint, 0.35); width: card.width * 0.6; height: width; x: card.width * 0.55; y: -height * 0.35 }

      Item {
        anchors.fill: parent
        anchors.margins: card.radius * 0.3
        clip: true
        visible: card.build > 0.05 && card.build < 0.9
        Rectangle {
          readonly property real k: Math.max(0, Math.min(1, (card.build - 0.05) / 0.8))
          width: card.width * 0.22
          height: card.height * 2
          x: -width + (card.width + 2 * width) * k - width / 2
          y: -card.height * 0.5
          rotation: 18
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
            GradientStop { position: 0.5; color: Util.alpha(Qt.lighter(wrap.tint, 1.6), 0.16) }
            GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0) }
          }
        }
      }

      Column {
        x: 70 * card.k
        y: 60 * card.k
        spacing: 10 * card.k
        opacity: card.beat(0)
        transform: Translate { x: (1 - card.beat(0)) * -40 * card.k }

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
            required property int index
            width: 360 * card.k
            spacing: 4 * card.k
            opacity: card.beat(1 + index)
            transform: Translate { y: (1 - card.beat(1 + index)) * 30 * card.k }
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

    Item {
      id: cardEdge
      anchors.centerIn: card
      width: card.width
      height: card.height
      scale: card.scale
      opacity: card.opacity
      visible: card.visible

      property real flash: 0
      Connections {
        target: wrap
        function onOnCardChanged() { if (wrap.onCard) edgeFlash.restart() }
      }
      SequentialAnimation {
        id: edgeFlash
        PauseAnimation { duration: 180 }
        NumberAnimation { target: cardEdge; property: "flash"; from: 0; to: 1; duration: 90 }
        NumberAnimation { target: cardEdge; property: "flash"; to: 0; duration: 900; easing.type: Easing.OutCubic }
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -6 * wrap.u * (1 - cardEdge.flash)
        radius: card.radius + 6 * wrap.u * (1 - cardEdge.flash)
        color: "transparent"
        border.width: 3 * wrap.u
        border.color: Qt.tint(wrap.tint, Util.alpha("#ffffff", 0.6))
        opacity: cardEdge.flash
        visible: cardEdge.flash > 0.01
      }
      EdgeRunner {
        anchors.fill: parent
        radius: card.radius
        hue: Qt.lighter(wrap.tint, 1.2)
        count: 2
        duration: 5200
        length: 160 * wrap.u
        thickness: 2.5 * wrap.u
        running: wrap.onCard && !wrap.closing
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
