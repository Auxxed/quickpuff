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
  // Rocket on the stage: the stage's own Peak grows fins, counts down in the
  // big numerals and lifts off, instead of a second rocket somewhere else.
  property bool launch: false
  // How long the stage holds after Ready, so the ready animation plays on it.
  property real holdAfterReady: 6.5
  property bool armed: false

  signal finished()
  // Ready, the instant the daemon says so: the bar starts the ready
  // animation off this, so it lands on the flash.
  signal readyMoment()

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

  DaemonFeed {
    id: feed
    connected: show.armed && socketPath !== ""
    onStatus: function(d) {
      // The lists drawn here, no longer than the daemon ever sends them.
      var trace = d.heat_trace && typeof d.heat_trace === "object" ? d.heat_trace.points : undefined
      if (trace !== undefined && trace !== null && (!Array.isArray(trace) || trace.length > 360)) return
      if (d.profiles !== undefined && d.profiles !== null && (!Array.isArray(d.profiles) || d.profiles.length > 8)) return
      show.ingest(d)
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
    readyMoment()
    if (mode === "stage" && launch) {
      launchSeq.start()
    } else if (mode === "stage") {
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

  // Plays sounds/<name>.ogg (one of the bundled cues) through pw-play,
  // fire-and-forget, stopped after ten seconds at most.
  function cue(name) {
    if (!soundsOn || !/^[a-z]+$/.test(name)) return
    var volume = Math.max(0, Math.min(1, Number(soundVolume) || 0))
    if (volume <= 0) return
    var url = String(Qt.resolvedUrl("sounds/" + name + ".ogg"))
    if (url.indexOf("file://") !== 0) return
    Quickshell.execDetached(["/usr/bin/timeout", "-k", "1", "10", "/usr/bin/pw-play",
      "--volume", volume.toFixed(2), "--", decodeURIComponent(url.slice(7))])
  }

  // ------------------------------------------------------------ launch
  // Ready → fins out → 3, 2, 1 in the big numerals (a beep each) while the
  // Peak rumbles and the flame builds → liftoff (with its roar) → the stage
  // steps back into the card. One timeline, so sound and picture agree.
  property string countText: ""
  property real finT: 0
  property real flame: 0
  property real flameStretch: 1
  property real shake: 0
  property real shakeX: 0
  property real flicker: 1
  property real liftY: 0
  property bool smoking: false
  property bool flying: false

  Timer {
    interval: 32
    repeat: true
    running: show.shake > 0 || show.flame > 0
    onTriggered: {
      show.shakeX = (Math.random() * 2 - 1) * show.shake * show.u
      show.flicker = 0.82 + Math.random() * 0.36
    }
  }

  SequentialAnimation {
    id: launchSeq
    PauseAnimation { duration: 350 }
    NumberAnimation { target: show; property: "finT"; to: 1; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    PauseAnimation { duration: 120 }
    ScriptAction { script: { show.countText = "3"; show.cue("count"); readyPop.restart(); show.smoking = true } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "shake"; to: 1.2; duration: 600 }
      NumberAnimation { target: show; property: "flame"; to: 0.3; duration: 600 }
    }
    ScriptAction { script: { show.countText = "2"; show.cue("count"); readyPop.restart() } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "shake"; to: 2.4; duration: 600 }
      NumberAnimation { target: show; property: "flame"; to: 0.65; duration: 600 }
    }
    ScriptAction { script: { show.countText = "1"; show.cue("count"); readyPop.restart() } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "shake"; to: 4; duration: 600 }
      NumberAnimation { target: show; property: "flame"; to: 1; duration: 600 }
    }
    ScriptAction { script: { show.countText = "READY"; show.cue("liftoff"); show.flying = true; readyPop.restart() } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "liftY"; to: -show.height * 1.25; duration: 1500; easing.type: Easing.InCubic }
      NumberAnimation { target: show; property: "flameStretch"; to: 2.6; duration: 700; easing.type: Easing.OutCubic }
      NumberAnimation { target: show; property: "shake"; to: 0; duration: 600 }
      SequentialAnimation {
        PauseAnimation { duration: 900 }
        ScriptAction { script: show.smoking = false }
      }
    }
    PauseAnimation { duration: 700 }
    ScriptAction { script: { show.flame = 0; stageOut.start(); cardIn.start() } }
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
      x: stage.restX + peak.width * 0.44 - r
      y: stage.restY + peak.height * 0.98 - r
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

    // Where the Peak stands; the floor, its glow and the smoke stay here
    // when it lifts off.
    readonly property real restX: show.width * 0.3 - peak.width / 2
    readonly property real restY: show.height * 0.5 - peak.height * 0.52 + (1 - show.stageT) * show.height * 0.06

    // Fins and flames, in the Peak's own 80 x 160 drawing, moving with it.
    Item {
      id: rig
      x: peak.x
      y: peak.y
      width: 80
      height: 160
      transform: Scale { xScale: peak.width / 80; yScale: peak.width / 80 }
      visible: show.finT > 0 || show.flame > 0

      Repeater {
        model: [
          { "w": 40, "h": 74, "top": "#ff9a3c", "bottom": "#ff2a00" },
          { "w": 28, "h": 54, "top": "#ffe27a", "bottom": "#ff7a1a" },
          { "w": 14, "h": 32, "top": "#ffffff", "bottom": "#ffd84a" }
        ]
        Shape {
          required property var modelData
          x: 35 - modelData.w / 2
          y: 155
          width: modelData.w
          height: modelData.h
          visible: show.flame > 0
          preferredRendererType: Shape.CurveRenderer
          transform: Scale {
            origin.x: modelData.w / 2
            origin.y: 0
            xScale: show.flame * (0.9 + 0.1 * show.flicker)
            yScale: show.flame * show.flicker * show.flameStretch
          }
          ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
              x1: 0; y1: 0; x2: 0; y2: modelData.h
              GradientStop { position: 0.0; color: modelData.top }
              GradientStop { position: 0.6; color: modelData.bottom }
              GradientStop { position: 1.0; color: Util.alpha(modelData.bottom, 0) }
            }
            PathSvg {
              path: {
                var w = modelData.w, h = modelData.h
                return "M " + w / 2 + " 0 Q " + w + " " + h * 0.15 + " " + w * 0.86 + " " + h * 0.45
                  + " Q " + w * 0.7 + " " + h * 0.8 + " " + w / 2 + " " + h
                  + " Q " + w * 0.3 + " " + h * 0.8 + " " + w * 0.14 + " " + h * 0.45
                  + " Q 0 " + h * 0.15 + " " + w / 2 + " 0 Z"
              }
            }
          }
        }
      }

      Repeater {
        model: [-1, 1]
        Shape {
          required property var modelData
          width: 80
          height: 160
          x: -modelData * (1 - show.finT) * 12
          opacity: Math.min(1, show.finT * 1.5)
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Util.alpha("white", 0.35)
            strokeWidth: 0.8
            fillGradient: LinearGradient {
              x1: 0; y1: 126; x2: 0; y2: 162
              GradientStop { position: 0.0; color: Qt.lighter(show.tint, 1.3) }
              GradientStop { position: 1.0; color: Qt.darker(show.tint, 1.6) }
            }
            PathSvg {
              path: modelData < 0
                ? "M 7 126 L 7 156 L -12 162 Q -15 146 -4 134 Z"
                : "M 62 128 L 64 156 L 82 162 Q 85 146 74 136 Z"
            }
          }
        }
      }
    }

    // The Peak, big, rising into place.
    PeakArt {
      id: peak
      panel: palette
      height: show.height * 0.6
      width: height / 2
      x: stage.restX + show.shakeX
      y: stage.restY + show.liftY
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
      opacity: 0.22 * show.stageT * Math.max(0, 1 + show.liftY / (show.height * 0.35))
      transform: Scale { origin.y: mirror.height / 2; yScale: -1 }
    }
    Rectangle {
      x: stage.restX - peak.width
      y: stage.restY + peak.height * 0.985
      width: peak.width * 3
      height: peak.height * 0.6
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#050407", 0.15) }
        GradientStop { position: 0.45; color: Util.alpha("#050407", 0.92) }
        GradientStop { position: 1.0; color: "#050407" }
      }
      opacity: show.stageT
    }

    // The Ready moment, from the light ring: a bloom of the profile's light
    // bursting out across the floor, and a soft shockwave racing outward.
    Item {
      id: wave
      property real k: 0
      readonly property real cx: stage.restX + peak.width * (35 / 80)
      readonly property real cy: stage.restY + peak.height * (157 / 160)
      anchors.fill: parent
      visible: k > 0 && k < 1

      Shape {
        id: bloom
        readonly property real r: show.height * (0.25 + 0.95 * Math.sqrt(wave.k))
        x: wave.cx - r
        y: wave.cy - r
        width: r * 2
        height: r * 2
        opacity: Math.pow(1 - wave.k, 1.6) * show.stageT
        transform: Scale { origin.x: bloom.r; origin.y: bloom.r; yScale: 0.55 }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: bloom.r; centerY: bloom.r; centerRadius: bloom.r
            focalX: centerX; focalY: centerY
            GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(show.tint, 1.5), 0.9) }
            GradientStop { position: 0.25; color: Util.alpha(show.tint, 0.55) }
            GradientStop { position: 0.6; color: Util.alpha(show.tint, 0.16) }
            GradientStop { position: 1.0; color: Util.alpha(show.tint, 0) }
          }
          startX: 0; startY: 0
          PathLine { x: bloom.width; y: 0 }
          PathLine { x: bloom.width; y: bloom.height }
          PathLine { x: 0; y: bloom.height }
          PathLine { x: 0; y: 0 }
        }
      }

      Repeater {
        model: [{ "w": 34, "a": 0.12 }, { "w": 16, "a": 0.3 }, { "w": 5, "a": 0.95 }]
        Rectangle {
          required property var modelData
          width: peak.width * (0.9 + 3.6 * wave.k)
          height: width * 0.22
          radius: height / 2
          x: wave.cx - width / 2
          y: wave.cy - height / 2
          color: "transparent"
          border.width: Math.max(1, modelData.w * show.u * (1 - 0.6 * wave.k))
          border.color: Util.alpha(Qt.lighter(show.tint, 1.45), modelData.a)
          opacity: Math.pow(1 - wave.k, 1.8) * show.stageT
        }
      }
    }
    NumberAnimation { id: shock; target: wave; property: "k"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }

    // Exhaust smoke billowing along the floor: soft clouds, faintly lit
    // pink by the ring below them.
    Repeater {
      model: 18
      Shape {
        id: puff
        required property int index
        readonly property real side: index % 2 ? 1 : -1
        readonly property real fx: stage.restX + peak.width * (35 / 80)
        readonly property real fy: stage.restY + peak.height * 0.985
        readonly property real reach: (60 + (index * 37) % 110) * show.u
        readonly property real r: (26 + (index * 13) % 24) * show.u
        width: r * 2
        height: r * 2
        opacity: 0
        x: fx - r
        y: fy - r
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: puff.r; centerY: puff.r; centerRadius: puff.r
            focalX: puff.r * 0.8; focalY: puff.r * 0.75
            GradientStop { position: 0.0; color: Util.alpha(Qt.tint("#e9e6ee", Util.alpha(show.tint, 0.18)), 0.85) }
            GradientStop { position: 0.55; color: Util.alpha(Qt.tint("#cfcbd6", Util.alpha(show.tint, 0.12)), 0.45) }
            GradientStop { position: 1.0; color: Util.alpha("#cfcbd6", 0) }
          }
          startX: 0; startY: 0
          PathLine { x: puff.width; y: 0 }
          PathLine { x: puff.width; y: puff.height }
          PathLine { x: 0; y: puff.height }
          PathLine { x: 0; y: 0 }
        }
        SequentialAnimation {
          running: show.smoking
          loops: Animation.Infinite
          PauseAnimation { duration: (puff.index * 97) % 600 }
          ParallelAnimation {
            NumberAnimation { target: puff; property: "x"; from: puff.fx - puff.r; to: puff.fx - puff.r + puff.side * puff.reach * 2.2; duration: 1500; easing.type: Easing.OutCubic }
            NumberAnimation { target: puff; property: "y"; from: puff.fy - puff.r; to: puff.fy - puff.r - (puff.index % 4) * 14 * show.u; duration: 1500; easing.type: Easing.OutCubic }
            NumberAnimation { target: puff; property: "scale"; from: 0.5; to: 2.6; duration: 1500 }
            SequentialAnimation {
              NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.9; duration: 220 }
              NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 1280; easing.type: Easing.InQuad }
            }
          }
        }
      }
    }

    // Speed streaks round the Peak as it climbs.
    Repeater {
      model: 8
      Rectangle {
        id: streak
        required property int index
        visible: show.flying && show.liftY < -show.height * 0.05
        width: 2 * show.u
        height: (40 + (index * 23) % 60) * show.u
        radius: width / 2
        x: index % 2 ? peak.x - (30 + index * 14) * show.u : peak.x + peak.width + (20 + index * 14) * show.u
        color: Util.alpha("white", 0.45)
        NumberAnimation on y {
          running: streak.visible
          loops: Animation.Infinite
          from: show.height * 0.1 + streak.index * 30 * show.u
          to: show.height
          duration: 280 + streak.index * 40
        }
      }
    }

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
            textFormat: Text.PlainText
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
          text: show.countText !== "" ? show.countText
            : isFinite(show.shownF) && show.shownF > 0 ? String(Math.round(show.shownF)) : "—"
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
          visible: show.countText === ""
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
    color: Qt.lighter(show.tint, 1.9)
    opacity: 0
  }
  SequentialAnimation {
    id: flash
    NumberAnimation { target: flashRect; property: "opacity"; to: show.mode === "stage" ? 0.16 : 0.1; duration: 60 }
    NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 420; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------ the card
  Item {
    id: card
    readonly property real w: 470 * show.u
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
          return bits.join(" · ")
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
