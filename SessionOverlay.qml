import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"

// Showtime: a heat cycle, played out over the desktop. Opened by the bar
// widget when the Peak starts heating, fed live by the daemon's socket, and
// closed by itself once the session is over.
//
// - "stage": the desktop dims and the Peak takes the middle of the screen,
//   its light ring brightening as a giant temperature counts up and the heat
//   curve draws; Ready lands with a flash and a shockwave from the ring, the
//   ready animation plays over the stage, then it settles into the card.
// - "corner": the same story in a card under the widget.
//
// Click-through (empty mask) and keyboard-less, like the ready animation.
PanelWindow {
  id: show

  property string mode: "corner"
  // Where the widget sits, in this window's coordinates.
  property real originX: 0
  property real barEdge: 0
  property bool barAtTop: true
  property bool soundsOn: true
  property real soundVolume: 0.7
  // Play the ready chime here, when no ready animation will.
  property bool chimeOnReady: false
  // How long the stage holds after Ready, so the ready animation plays on it.
  property real holdAfterReady: 6.5
  property bool armed: false

  signal finished()

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickpuff-showtime"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  mask: Region {}

  FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/Rajdhani-SemiBold.ttf") }
  readonly property string display: displayFont.status === FontLoader.Ready ? displayFont.name : Style.font.family
  readonly property real u: Math.max(1, Math.min(width, height * 16 / 9) / 1536)

  // PeakArt reads its palette and liveness off a panel; this is all it needs.
  QtObject {
    id: palette
    property color foreground: "#f2eef4"
    property bool opened: true
  }

  // ------------------------------------------------------------ live feed
  // The daemon pushes a status event to every client on each poll (and the
  // demo several times a second), so nothing here polls.
  property var st: ({})
  property real sampledAt: 0
  property real nowMs: Date.now()
  property int prevState: -1

  Socket {
    id: feed
    path: (Quickshell.env("QUICKPUFF_SOCKET") || (Quickshell.env("XDG_RUNTIME_DIR") + "/quickpuff.sock"))
    connected: show.armed
    parser: SplitParser {
      onRead: function(line) {
        var msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg && msg.event === "status" && msg.data) show.ingest(msg.data)
      }
    }
  }

  Timer {
    interval: 33
    running: show.armed && show.phase !== "done"
    repeat: true
    onTriggered: show.nowMs = Date.now()
  }

  readonly property int stateId: {
    var n = Number(st.operating_state_id)
    return isFinite(n) ? n : -1
  }
  readonly property var profile: {
    var list = st.profiles || []
    for (var i = 0; i < list.length; i++)
      if (Number(list[i].index) === Number(st.current_profile)) return list[i]
    return null
  }
  readonly property color tint: {
    var c = profile && /^#[0-9a-fA-F]{6}$/.test(String(profile.color || "")) ? String(profile.color) : ""
    return c !== "" ? c : Color.accent
  }
  readonly property string profileName: profile && profile.name ? String(profile.name).toUpperCase() : "HEAT"
  readonly property real targetF: profile ? Number(profile.temp_f) : NaN
  readonly property real tempF: Number(st.heater_temp_f)
  readonly property bool demo: !!(st.demo && st.demo.badge)
  readonly property string colorway: st.product ? String(st.product.marketing_name || "") : ""
  readonly property real totalS: Number(st.state_total_s) > 0 ? Number(st.state_total_s) : NaN
  readonly property real elapsedS: isFinite(Number(st.state_elapsed_s))
    ? Number(st.state_elapsed_s) + Math.max(0, nowMs - sampledAt) / 1000 : NaN
  readonly property real progress: {
    if (phase === "preheat") {
      if (isFinite(totalS) && isFinite(elapsedS)) return Math.max(0, Math.min(1, elapsedS / totalS))
      if (isFinite(tempF) && isFinite(targetF) && targetF > 90) return Math.max(0, Math.min(1, (tempF - 80) / (targetF - 80)))
      return 0
    }
    if (phase === "session" || phase === "ready")
      return isFinite(totalS) && isFinite(elapsedS) ? Math.max(0, Math.min(1, 1 - elapsedS / totalS)) : 1
    return 0
  }
  readonly property int secondsLeft: isFinite(totalS) && isFinite(elapsedS) ? Math.max(0, Math.ceil(totalS - elapsedS)) : 0
  readonly property var tracePoints: st.heat_trace && st.heat_trace.points ? st.heat_trace.points : []

  // Counts toward each reading rather than snapping to it.
  property real shownF: 0
  Behavior on shownF { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

  // Phase: preheat → ready (the moment) → session → cooling → done.
  property string phase: "waiting"
  property real peakF: 0
  property real sessionStarted: 0
  property real readyAt: 0
  property real sessionEnded: 0
  property real batteryStart: NaN

  function fmtTime(s) {
    var m = Math.floor(s / 60), r = s % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }

  function ingest(d) {
    st = d
    sampledAt = Date.now()
    var t = Number(d.heater_temp_f)
    if (isFinite(t)) {
      shownF = t
      if (phase !== "waiting" && t > peakF) peakF = t
    }
    var s = Number(d.operating_state_id)
    if (d.connected === false) s = -1
    if (phase === "waiting") {
      if (s === 7) begin("preheat")
      else if (s === 8) begin("session")
      else if (prevState === -1 && s !== 9) closeSoon(0)
    } else if (prevState === 7 && s === 8) {
      readyHit()
    } else if ((phase === "session" || phase === "ready") && s === 9) {
      sessionEnded = Date.now()
      phase = "cooling"
    } else if (phase !== "done" && s !== 7 && s !== 8 && s !== 9) {
      complete()
    }
    prevState = s
  }

  function begin(p) {
    phase = p
    sessionStarted = Date.now()
    batteryStart = Number(st.battery)
    peakF = isFinite(tempF) ? tempF : 0
    if (p === "preheat") {
      cue("ignite")
      if (mode === "stage") stageIn.start()
      else cardIn.start()
    } else {
      cardIn.start()
    }
  }

  function readyHit() {
    readyAt = Date.now()
    phase = "ready"
    flash.start()
    shock.start()
    readyPop.start()
    if (chimeOnReady) cue("ready")
    if (mode === "stage") {
      stageHold.restart()
      // Leave the floor to the ready animation, if one is coming.
      if (holdAfterReady > 3) readoutDip.restart()
    } else {
      cardFlash.start()
    }
    afterReady.restart()
  }

  Timer {
    id: readoutDip
    interval: 700
    onTriggered: { show.readoutT = 0.12; readoutBack.restart() }
  }
  Timer {
    id: readoutBack
    interval: Math.max(500, show.holdAfterReady * 1000 - 1900)
    onTriggered: show.readoutT = 1
  }

  Timer {
    id: afterReady
    interval: 1600
    onTriggered: if (show.phase === "ready") show.phase = "session"
  }

  // After the ready animation has had the stage, step back into the card.
  Timer {
    id: stageHold
    interval: show.holdAfterReady * 1000
    onTriggered: { stageOut.start(); cardIn.start() }
  }

  property real summaryDur: 0
  property real summaryHeatup: NaN
  property real summaryBattery: NaN
  function complete() {
    if (phase === "done" || phase === "summary") return
    var wasStage = stageT > 0.01
    phase = "summary"
    // The session is the time at temperature; the climb before it is heat-up.
    var end = sessionEnded > 0 ? sessionEnded : Date.now()
    summaryDur = readyAt > 0 ? Math.max(0, Math.round((end - readyAt) / 1000)) : 0
    summaryHeatup = readyAt > 0 ? Math.round((readyAt - sessionStarted) / 1000) : NaN
    summaryBattery = isFinite(batteryStart) && isFinite(Number(st.battery)) ? batteryStart - Number(st.battery) : NaN
    if (wasStage) { stageHold.stop(); stageOut.start() }
    if (cardT < 0.99) cardIn.start()
    cue("complete")
    closeSoon(5200)
  }

  function closeSoon(ms) { closer.interval = Math.max(1, ms); closer.restart() }
  Timer {
    id: closer
    onTriggered: { show.phase = "done"; outAnim.start() }
  }

  function cue(name) {
    if (!soundsOn) return
    var path = String(Qt.resolvedUrl("sounds/" + name + ".ogg")).replace(/^file:\/\//, "")
    Quickshell.execDetached(["pw-play", "--volume", String(Math.max(0, Math.min(1, soundVolume))), path])
  }

  // ------------------------------------------------------------ stage
  property real stageT: 0     // 0 hidden, 1 on stage
  // The readout steps back while the ready animation has the stage.
  property real readoutT: 1
  Behavior on readoutT { NumberAnimation { duration: 500; easing.type: Easing.InOutCubic } }
  property real cardT: 0      // 0 hidden, 1 shown
  property real fadeAll: 1

  ParallelAnimation {
    id: stageIn
    NumberAnimation { target: show; property: "stageT"; to: 1; duration: 1100; easing.type: Easing.OutCubic }
  }
  ParallelAnimation {
    id: stageOut
    NumberAnimation { target: show; property: "stageT"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
  }
  NumberAnimation { id: cardIn; target: show; property: "cardT"; to: 1; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
  SequentialAnimation {
    id: outAnim
    NumberAnimation { target: show; property: "fadeAll"; to: 0; duration: 700; easing.type: Easing.InCubic }
    ScriptAction { script: show.finished() }
  }

  // The ring breathes while the chamber climbs and burns steady at temp.
  property real breath: 1
  SequentialAnimation on breath {
    running: show.phase === "preheat"
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
  }
  readonly property real glow: (phase === "preheat" ? 0.35 + 0.65 * progress : 1) * breath

  Item {
    id: stage
    anchors.fill: parent
    opacity: show.fadeAll
    visible: show.stageT > 0.001

    // The room goes dark.
    Rectangle {
      anchors.fill: parent
      color: "#050407"
      opacity: 0.9 * show.stageT
    }

    // A pool of the profile's light under the Peak, swelling with the heat.
    Shape {
      id: pool
      readonly property real r: show.height * 0.75
      x: peak.x + peak.width * 0.44 - r
      y: peak.y + peak.height * 0.98 - r
      width: r * 2
      height: r * 2
      opacity: show.stageT * (0.25 + 0.75 * show.glow)
      transform: Scale { origin.x: pool.r; origin.y: pool.r; yScale: 0.32 }
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: pool.r; centerY: pool.r; centerRadius: pool.r
          focalX: centerX; focalY: centerY
          GradientStop { position: 0.0; color: Util.alpha(show.tint, 0.55) }
          GradientStop { position: 0.35; color: Util.alpha(show.tint, 0.18) }
          GradientStop { position: 1.0; color: Util.alpha(show.tint, 0) }
        }
        startX: 0; startY: 0
        PathLine { x: pool.width; y: 0 }
        PathLine { x: pool.width; y: pool.height }
        PathLine { x: 0; y: pool.height }
        PathLine { x: 0; y: 0 }
      }
    }

    // The Peak, big, rising into place.
    PeakArt {
      id: peak
      panel: palette
      height: show.height * 0.6
      width: height / 2
      x: show.width * 0.3 - width / 2
      y: show.height * 0.5 - height * 0.52 + (1 - show.stageT) * show.height * 0.06
      colorway: show.colorway
      tint: show.tint
      glow: show.glow
      vapor: show.phase === "session" || show.phase === "ready"
      hero: true
      opacity: show.stageT
    }

    // Its reflection on the floor, fading into the dark.
    ShaderEffectSource {
      id: mirror
      sourceItem: peak
      live: true
      width: peak.width
      height: peak.height
      x: peak.x
      y: peak.y + peak.height
      opacity: 0.22 * show.stageT
      transform: Scale { origin.y: mirror.height / 2; yScale: -1 }
    }
    Rectangle {
      x: peak.x - peak.width
      y: peak.y + peak.height * 0.985
      width: peak.width * 3
      height: peak.height * 0.6
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#050407", 0.15) }
        GradientStop { position: 0.45; color: Util.alpha("#050407", 0.92) }
        GradientStop { position: 1.0; color: "#050407" }
      }
      opacity: show.stageT
    }

    // Shockwave from the light ring at the Ready moment.
    Rectangle {
      id: wave
      property real k: 0
      readonly property real cx: peak.x + peak.width * (35 / 80)
      readonly property real cy: peak.y + peak.height * (157 / 160)
      width: peak.width * (0.9 + 5 * k)
      height: width * 0.22
      radius: height / 2
      x: cx - width / 2
      y: cy - height / 2
      color: "transparent"
      border.width: Math.max(2, 10 * show.u * (1 - k))
      border.color: Qt.lighter(show.tint, 1.4)
      opacity: k > 0 && k < 1 ? (1 - k) * show.stageT : 0
    }
    NumberAnimation { id: shock; target: wave; property: "k"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }

    // ---- the readout
    Column {
      id: readout
      x: show.width * 0.47
      y: show.height * 0.5 - height / 2 + (1 - show.stageT) * show.height * 0.04
      spacing: 6 * show.u
      opacity: show.stageT * show.readoutT

      Row {
        spacing: 14 * show.u
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 12 * show.u
          height: width
          radius: width / 2
          color: show.phase === "preheat" ? show.tint : Qt.lighter(show.tint, 1.3)
          opacity: show.phase === "preheat" ? 0.5 + 0.5 * show.breath : 1
        }
        Text {
          textFormat: Text.PlainText
          text: (show.phase === "preheat" ? "PREHEATING" : show.phase === "cooling" ? "COOLING" : "READY") + "  ·  " + show.profileName
          color: Qt.lighter(show.tint, 1.25)
          font.family: show.display
          font.pixelSize: 30 * show.u
          font.weight: Font.DemiBold
          font.letterSpacing: 6 * show.u
        }
        Rectangle {
          visible: show.demo
          anchors.verticalCenter: parent.verticalCenter
          width: demoText.implicitWidth + 16 * show.u
          height: demoText.implicitHeight + 6 * show.u
          radius: 4 * show.u
          color: "transparent"
          border.width: 1
          border.color: Util.alpha("#ffffff", 0.35)
          Text {
            id: demoText
            anchors.centerIn: parent
            text: "DEMO"
            color: Util.alpha("#ffffff", 0.6)
            font.family: show.display
            font.pixelSize: 16 * show.u
            font.letterSpacing: 3 * show.u
          }
        }
      }

      Row {
        id: bigRow
        spacing: 6 * show.u
        transformOrigin: Item.Left
        Text {
          id: big
          textFormat: Text.PlainText
          text: isFinite(show.shownF) && show.shownF > 0 ? String(Math.round(show.shownF)) : "—"
          color: show.phase === "preheat"
            ? Qt.tint("#f4eef6", Util.alpha(show.tint, 0.25 + 0.5 * show.progress))
            : Qt.tint("#ffffff", Util.alpha(show.tint, 0.35))
          font.family: show.display
          font.pixelSize: 250 * show.u
          font.weight: Font.DemiBold
          style: Text.Normal
        }
        Text {
          y: big.height * 0.14
          textFormat: Text.PlainText
          text: "°F"
          color: Util.alpha("#f4eef6", 0.6)
          font.family: show.display
          font.pixelSize: 64 * show.u
          font.weight: Font.DemiBold
        }
      }
      SequentialAnimation {
        id: readyPop
        NumberAnimation { target: bigRow; property: "scale"; to: 1.07; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: bigRow; property: "scale"; to: 1.0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2 }
      }

      Text {
        textFormat: Text.PlainText
        text: show.phase === "preheat"
          ? "→  " + (isFinite(show.targetF) ? Math.round(show.targetF) + "°F" : "") + (show.secondsLeft > 0 ? "   ·   " + show.fmtTime(show.secondsLeft) : "")
          : show.phase === "cooling" ? "Session over" : "Slow pull. Big flavor."
        color: Util.alpha("#f4eef6", 0.62)
        font.family: show.display
        font.pixelSize: 34 * show.u
        font.weight: Font.DemiBold
        font.letterSpacing: 2 * show.u
      }

      Item { width: 1; height: 14 * show.u }

      // Progress: the climb to temperature.
      Rectangle {
        width: show.width * 0.36
        height: 6 * show.u
        radius: height / 2
        color: Util.alpha("#ffffff", 0.1)
        Rectangle {
          height: parent.height
          radius: parent.radius
          width: parent.width * (show.phase === "preheat" ? show.progress : 1)
          color: show.tint
          Behavior on width { NumberAnimation { duration: 300 } }
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 22 * show.u
            height: width
            radius: width / 2
            color: Util.alpha(show.tint, 0.45)
            visible: show.phase === "preheat"
          }
        }
      }

      Item { width: 1; height: 18 * show.u }

      // The heat curve, drawing as it happens.
      Shape {
        id: curve
        width: show.width * 0.36
        height: show.height * 0.12
        preferredRendererType: Shape.CurveRenderer
        readonly property var pts: show.tracePoints
        readonly property real tMax: pts.length ? Math.max(20, Number(pts[pts.length - 1][0])) : 20
        readonly property real fMin: 80
        readonly property real fMax: Math.max(560, isFinite(show.targetF) ? show.targetF + 20 : 560)
        function poly() {
          var out = []
          for (var i = 0; i < pts.length; i++) {
            var x = Number(pts[i][0]) / tMax * width
            var y = height - (Number(pts[i][1]) - fMin) / (fMax - fMin) * height
            out.push(Qt.point(x, Math.max(0, Math.min(height, y))))
          }
          if (out.length < 2) out = [Qt.point(0, height), Qt.point(0.01, height)]
          return out
        }
        ShapePath {
          strokeColor: Qt.lighter(show.tint, 1.2)
          strokeWidth: 3 * show.u
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          PathPolyline { path: curve.poly() }
        }
        // Target line.
        Rectangle {
          visible: isFinite(show.targetF)
          width: parent.width
          height: 1
          y: parent.height - (show.targetF - parent.fMin) / (parent.fMax - parent.fMin) * parent.height
          color: Util.alpha("#ffffff", 0.18)
        }
      }
    }
  }

  // Full-screen flash at the Ready moment.
  Rectangle {
    id: flashRect
    anchors.fill: parent
    color: Qt.lighter(show.tint, 1.6)
    opacity: 0
  }
  SequentialAnimation {
    id: flash
    NumberAnimation { target: flashRect; property: "opacity"; to: show.mode === "stage" ? 0.42 : 0.12; duration: 90 }
    NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 650; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------ the card
  Item {
    id: card
    readonly property real w: 420 * show.u
    readonly property real h: 150 * show.u
    width: w
    height: h
    x: Math.max(16 * show.u, Math.min(show.width - w - 16 * show.u, show.originX - w / 2))
    y: show.barAtTop ? show.barEdge + 14 * show.u : show.barEdge - h - 14 * show.u
    opacity: show.cardT * show.fadeAll
    scale: 0.92 + 0.08 * show.cardT
    transformOrigin: show.barAtTop ? Item.Top : Item.Bottom
    visible: show.cardT > 0.001

    Rectangle {
      id: cardBg
      anchors.fill: parent
      radius: 20 * show.u
      color: Util.alpha("#0c0a10", 0.9)
      border.width: 1
      border.color: Util.alpha(show.tint, 0.5)
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(Qt.tint("#0c0a10", Util.alpha(show.tint, 0.22)), 0.92) }
        GradientStop { position: 1.0; color: Util.alpha("#0c0a10", 0.9) }
      }
    }
    Rectangle {
      id: cardFlashRect
      anchors.fill: parent
      radius: cardBg.radius
      color: show.tint
      opacity: 0
    }
    SequentialAnimation {
      id: cardFlash
      NumberAnimation { target: cardFlashRect; property: "opacity"; to: 0.5; duration: 90 }
      NumberAnimation { target: cardFlashRect; property: "opacity"; to: 0; duration: 700 }
    }

    PeakArt {
      id: miniPeak
      panel: palette
      height: card.h - 24 * show.u
      width: height / 2
      x: 18 * show.u
      y: 12 * show.u
      colorway: show.colorway
      tint: show.tint
      glow: show.glow
      vapor: show.phase === "session" || show.phase === "ready"
    }

    Column {
      x: miniPeak.x + miniPeak.width + 18 * show.u
      anchors.verticalCenter: parent.verticalCenter
      width: card.w - x - 22 * show.u
      spacing: 2 * show.u

      Text {
        textFormat: Text.PlainText
        text: {
          var p = show.phase
          var head = p === "preheat" ? "PREHEATING" : p === "ready" ? "READY" : p === "session" ? "SESSION"
            : p === "cooling" ? "COOLING" : "SESSION COMPLETE"
          return head + (p === "summary" || p === "done" ? "" : "  ·  " + show.profileName) + (show.demo ? "  ·  DEMO" : "")
        }
        color: Qt.lighter(show.tint, 1.25)
        font.family: show.display
        font.pixelSize: 17 * show.u
        font.weight: Font.DemiBold
        font.letterSpacing: 3 * show.u
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        textFormat: Text.PlainText
        text: {
          var p = show.phase
          if (p === "session" || p === "ready") return show.fmtTime(show.secondsLeft)
          if (p === "summary" || p === "done") return show.fmtTime(show.summaryDur)
          return isFinite(show.shownF) && show.shownF > 0 ? Math.round(show.shownF) + "°" : "—"
        }
        color: "#f4eef6"
        font.family: show.display
        font.pixelSize: 64 * show.u
        font.weight: Font.DemiBold
      }
      Text {
        textFormat: Text.PlainText
        text: {
          var p = show.phase
          if (p === "preheat") return "to " + (isFinite(show.targetF) ? Math.round(show.targetF) + "°F" : "temperature")
          if (p === "session" || p === "ready") return Math.round(show.shownF) + "°F  ·  left in session"
          if (p === "cooling") return Math.round(show.shownF) + "°F  ·  cooling down"
          var bits = []
          if (isFinite(show.summaryHeatup)) bits.push("Heat-up " + show.fmtTime(show.summaryHeatup))
          bits.push("Peak " + Math.round(show.peakF) + "°F")
          if (isFinite(show.summaryBattery) && show.summaryBattery > 0) bits.push("−" + Math.round(show.summaryBattery) + "% battery")
          return bits.join("  ·  ")
        }
        color: Util.alpha("#f4eef6", 0.6)
        font.family: show.display
        font.pixelSize: 18 * show.u
        font.weight: Font.DemiBold
        font.letterSpacing: 1 * show.u
        elide: Text.ElideRight
        width: parent.width
      }
      Item { width: 1; height: 6 * show.u }
      Rectangle {
        width: parent.width
        height: 4 * show.u
        radius: height / 2
        color: Util.alpha("#ffffff", 0.1)
        visible: show.phase !== "summary" && show.phase !== "done"
        Rectangle {
          height: parent.height
          radius: parent.radius
          width: parent.width * show.progress
          color: show.tint
          Behavior on width { NumberAnimation { duration: 300 } }
        }
      }
    }
  }
}
