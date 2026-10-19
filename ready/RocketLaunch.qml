import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

// ================================================================ Rocket
// The Peak Pro assembles on a launch pad (body, glass into its chrome
// seat, chamber cap onto the shelf), lights its ring and logo in the
// profile's colour, grows fins, counts down and blasts off through the bar.
Item {
  id: show
  // The ReadyOverlay window: size, tint, sound cues, timing helpers.
  property var host: null

  // About 1.3x the old size on a 1536 x 864 screen, growing with bigger ones.
  readonly property real s: show.host.u * 1.5 * show.host.stage
  // Kept clear of the screen edges, the countdown on the right included.
  readonly property real padX: Math.max(90 * s, Math.min(width - 115 * s, show.host.originX))
  readonly property real padY: show.host.barAtTop ? show.host.barEdge + 250 * s : show.host.barEdge - 40 * s

  // Timeline state, driven by `script` below.
  property real padOn: 0
  property real baseIn: 0
  property real glassOn: 0
  property real glassDrop: -320
  property real capOn: 0
  property real capDrop: -140
  property real capSpin: 540
  property real ledOn: 0
  property real finOut: 0
  property real flame: 0
  property real flameStretch: 1
  property real shake: 0
  property bool smoking: false
  property string count: ""
  property real liftY: 0
  property real trailOn: 0
  property real fadeAll: 1
  property real shakeX: 0
  property real flicker: 1

  Component.onCompleted: script.start()

  Timer {
    interval: 32
    repeat: true
    running: show.shake > 0 || show.flame > 0
    onTriggered: {
      show.shakeX = (Math.random() * 2 - 1) * show.shake * show.s
      show.flicker = 0.82 + Math.random() * 0.36
    }
  }

  SequentialAnimation {
    id: script
    NumberAnimation { target: show; property: "padOn"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    // Assembly.
    NumberAnimation { target: show; property: "baseIn"; to: 1; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    ParallelAnimation {
      NumberAnimation { target: show; property: "glassOn"; to: 1; duration: 140 }
      NumberAnimation { target: show; property: "glassDrop"; to: 0; duration: 560; easing.type: Easing.OutBounce }
    }
    ScriptAction { script: clink.fire() }
    ParallelAnimation {
      NumberAnimation { target: show; property: "capOn"; to: 1; duration: 120 }
      NumberAnimation { target: show; property: "capDrop"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 }
      NumberAnimation { target: show; property: "capSpin"; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }
    ScriptAction { script: pop.fire() }
    // Power on, grow fins.
    ParallelAnimation {
      NumberAnimation { target: show; property: "ledOn"; to: 1; duration: 380 }
      NumberAnimation { target: show; property: "finOut"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    PauseAnimation { duration: 160 }
    // Countdown.
    ScriptAction { script: { show.count = "3"; show.smoking = true; show.host.cue("count") } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "flame"; to: 0.35; duration: 560 }
      NumberAnimation { target: show; property: "shake"; to: 0.8; duration: 560 }
    }
    ScriptAction { script: { show.count = "2"; show.host.cue("count") } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "flame"; to: 0.65; duration: 560 }
      NumberAnimation { target: show; property: "shake"; to: 1.6; duration: 560 }
    }
    ScriptAction { script: { show.count = "1"; show.host.cue("count") } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "flame"; to: 1; duration: 560 }
      NumberAnimation { target: show; property: "shake"; to: 2.6; duration: 560 }
    }
    // Liftoff.
    ScriptAction { script: { show.count = ""; readyText.pop(); show.host.cue("liftoff"); blastAnim.restart() } }
    ParallelAnimation {
      NumberAnimation { target: show; property: "liftY"; to: -(show.padY + 420 * show.s); duration: 1450; easing.type: Easing.InCubic }
      NumberAnimation { target: show; property: "flameStretch"; to: 2.4; duration: 800; easing.type: Easing.OutCubic }
      NumberAnimation { target: show; property: "shake"; to: 0; duration: 700 }
      NumberAnimation { target: show; property: "trailOn"; to: 1; duration: 260 }
      SequentialAnimation {
        PauseAnimation { duration: 800 }
        ScriptAction { script: show.smoking = false }
      }
    }
    NumberAnimation { target: show; property: "fadeAll"; to: 0; duration: 800; easing.type: Easing.InQuad }
    ScriptAction { script: show.host.finished() }
  }

  // ---- Launch pad
  Item {
    opacity: show.padOn * show.fadeAll
    x: show.padX - width / 2
    y: show.padY
    width: 128 * show.s
    height: 10 * show.s

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 1.3
      height: 26 * show.s
      radius: height / 2
      color: Util.alpha(show.host.tint, 0.12 + 0.2 * show.ledOn)
    }
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#2b2d33" }
        GradientStop { position: 0.5; color: "#5a5e68" }
        GradientStop { position: 1.0; color: "#2b2d33" }
      }
      border.width: 1
      border.color: Util.alpha("white", 0.25)
    }
    // Hazard ticks.
    Row {
      anchors.centerIn: parent
      spacing: 9 * show.s
      Repeater {
        model: 7
        Rectangle {
          width: 4 * show.s
          height: 3 * show.s
          radius: 1
          color: index % 2 ? "#f6d32d" : "#1d1f24"
        }
      }
    }
  }

  // ---- Liftoff: a ring of light and dust racing out across the ground.
  property real blast: 0
  NumberAnimation { id: blastAnim; target: show; property: "blast"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
  Repeater {
    model: [{ "w": 18, "a": 0.18 }, { "w": 4, "a": 0.85 }]
    Rectangle {
      required property var modelData
      visible: show.blast > 0 && show.blast < 1
      width: (60 + 520 * show.blast) * show.s
      height: width * 0.2
      radius: height / 2
      x: show.padX - width / 2
      y: show.padY - height / 2
      color: "transparent"
      border.width: Math.max(1, modelData.w * show.s * (1 - 0.6 * show.blast))
      border.color: Util.alpha(Qt.tint("#ffd9a8", Util.alpha(show.host.tint, 0.4)), modelData.a)
      opacity: Math.pow(1 - show.blast, 1.5) * show.fadeAll
    }
  }

  // ---- Sparks spraying off the flame while it burns.
  Repeater {
    model: 16
    Rectangle {
      id: spark
      required property int index
      property real k: 0
      readonly property real side: index % 2 ? 1 : -1
      readonly property real spread: (0.25 + ((index * 41) % 60) / 100) * side
      readonly property real fly: (60 + (index * 29) % 90) * show.s
      width: 3 * show.s
      height: (8 + 10 * (1 - k)) * show.s
      radius: width / 2
      rotation: drop > show.padY ? 90 * side : spread * 60
      // Down out of the flame, then skidding along the pad once they hit it.
      readonly property real drop: rocket.y + rocket.height + 6 * show.s + fly * 1.1 * k
      x: show.padX + show.shakeX + spread * fly * k * (drop > show.padY ? 1.8 : 1) - width / 2
      y: Math.min(show.padY + 2 * show.s, drop) - height / 2
      color: index % 3 ? "#ffd27a" : "#ffffff"
      opacity: show.flame > 0.3 ? (1 - k) * show.fadeAll : 0
      SequentialAnimation on k {
        running: show.flame > 0.3
        loops: Animation.Infinite
        PauseAnimation { duration: (spark.index * 53) % 300 }
        NumberAnimation { from: 0; to: 1; duration: 420 + (spark.index % 4) * 70; easing.type: Easing.OutQuad }
      }
    }
  }

  // ---- Contrail from the pad up to the rocket
  Rectangle {
    opacity: show.trailOn * show.fadeAll * 0.8
    width: 14 * show.s
    x: show.padX - width / 2
    y: rocket.y + rocket.height
    height: Math.max(0, show.padY - y)
    radius: width / 2
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#ffd27a" }
      GradientStop { position: 0.25; color: Util.alpha("#ff7a1a", 0.7) }
      GradientStop { position: 1.0; color: Util.alpha("white", 0.0) }
    }
  }

  // ---- Smoke: soft clouds rolling out along the ground, lit warm from
  // the flame on their near side.
  Repeater {
    model: 22

    Shape {
      id: puff
      required property int index
      readonly property real side: index % 2 ? 1 : -1
      readonly property real reach: (40 + (index * 37) % 80) * show.s
      readonly property color body: index % 3 ? "#e3e5ea" : "#c3c7cf"
      width: (22 + (index * 13) % 18) * show.s
      height: width
      opacity: 0
      x: show.padX - width / 2
      y: show.padY - height / 2
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: puff.width / 2; centerY: puff.height / 2; centerRadius: puff.width / 2
          focalX: puff.width * 0.42; focalY: puff.height * 0.62
          GradientStop { position: 0.0; color: Qt.tint(puff.body, Util.alpha("#ffb36b", 0.22)) }
          GradientStop { position: 0.55; color: Util.alpha(puff.body, 0.55) }
          GradientStop { position: 1.0; color: Util.alpha(puff.body, 0) }
        }
        PathSvg { path: "M0," + puff.height / 2 + " A" + puff.width / 2 + "," + puff.height / 2 + " 0 1,0 " + puff.width + "," + puff.height / 2 + " A" + puff.width / 2 + "," + puff.height / 2 + " 0 1,0 0," + puff.height / 2 + " Z" }
      }

      SequentialAnimation {
        running: show.smoking
        loops: Animation.Infinite
        PauseAnimation { duration: (puff.index * 97) % 600 }
        ParallelAnimation {
          NumberAnimation { target: puff; property: "x"; from: show.padX - puff.width / 2; to: show.padX - puff.width / 2 + puff.side * puff.reach; duration: 1100; easing.type: Easing.OutCubic }
          NumberAnimation { target: puff; property: "y"; from: show.padY - puff.height / 2; to: show.padY - puff.height / 2 - (puff.index % 4) * 9 * show.s; duration: 1100; easing.type: Easing.OutCubic }
          NumberAnimation { target: puff; property: "scale"; from: 0.4; to: 2.2; duration: 1100; easing.type: Easing.OutCubic }
          SequentialAnimation {
            NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.95 * show.fadeAll; duration: 160 }
            NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 940; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }

  // ---- The Peak Pro, assembled for real (the panel's 80 x 160 drawing,
  // scaled; the foot sits on the pad)
  Item {
    id: rocket
    readonly property real k: show.s * 1.25
    width: 80
    height: 160
    x: show.padX - 35 + show.shakeX
    y: show.padY - height + show.liftY
    transform: Scale { origin.x: 35; origin.y: 160; xScale: rocket.k; yScale: rocket.k }
    opacity: show.fadeAll > 0 ? 1 : 0

    // Soft halo so the dark body reads on any wallpaper.
    Rectangle {
      x: -20
      y: 80
      width: 110
      height: 90
      radius: 45
      color: Util.alpha(show.host.tint, 0.08 + 0.16 * show.ledOn)
      opacity: show.baseIn
    }

    // Flames from the foot, stacked outer to inner.
    Repeater {
      model: [
        { "w": 40, "h": 74, "top": "#ff9a3c", "bottom": "#ff2a00" },
        { "w": 28, "h": 54, "top": "#ffe27a", "bottom": "#ff7a1a" },
        { "w": 14, "h": 32, "top": "#ffffff", "bottom": "#ffd84a" }
      ]

      Shape {
        required property var modelData
        x: 35 - modelData.w / 2
        y: 156
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

    // Fins in the profile's colour, sliding out from behind the pedestal.
    Repeater {
      model: [-1, 1]

      Shape {
        required property var modelData
        width: 80
        height: 160
        x: -modelData * (1 - show.finOut) * 12
        opacity: show.finOut
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Util.alpha("white", 0.35)
          strokeWidth: 0.8
          fillGradient: LinearGradient {
            x1: 0; y1: 126; x2: 0; y2: 162
            GradientStop { position: 0.0; color: Qt.lighter(show.host.tint, 1.3) }
            GradientStop { position: 1.0; color: Qt.darker(show.host.tint, 1.6) }
          }
          PathSvg {
            path: modelData < 0
              ? "M 7 126 L 7 156 L -12 162 Q -15 146 -4 134 Z"
              : "M 62 128 L 64 156 L 82 162 Q 85 146 74 136 Z"
          }
        }
      }
    }

    // Pedestal and hood, springing up from the pad as one body.
    Shape {
      width: 80
      height: 160
      opacity: Math.min(1, show.baseIn * 2)
      transform: Scale { origin.x: 35; origin.y: 160; xScale: show.baseIn; yScale: show.baseIn }
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 6; y1: 0; x2: 73; y2: 0
          GradientStop { position: 0.0; color: "#1a1a1c" }
          GradientStop { position: 1.0; color: "#08080a" }
        }
        PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
      }
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 6; y1: 93; x2: 73; y2: 130
          GradientStop { position: 0.0; color: "#4c4c51" }
          GradientStop { position: 1.0; color: "#18181b" }
        }
        PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C52,116 24,136 6.5,151 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
      }
      ShapePath {
        strokeColor: Util.alpha("white", 0.16)
        strokeWidth: 0.7
        fillColor: "transparent"
        PathSvg { path: "M72.3,104.4 C52,116 24,136 6.8,150.6" }
      }
      ShapePath {
        strokeColor: Util.alpha("white", 0.4)
        strokeWidth: 0.8
        fillColor: "transparent"
        PathSvg { path: "M46.5,93.2 L70,93.2 Q72.2,93.2 72.4,95.4" }
      }
      ShapePath {
        strokeColor: "#d8d8dc"
        strokeWidth: 1.3
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: "M8.8,108.6 L45.8,93.1" }
      }
      // Logo and the light ring round the foot, once it powers on.
      ShapePath {
        strokeColor: "transparent"
        fillColor: Util.alpha(show.host.tint, show.ledOn)
        PathSvg { path: "M12,123 L14.6,121.6 L14.6,128.6 L12,130 Z" }
      }
      ShapePath {
        strokeColor: Util.alpha(show.host.tint, show.ledOn)
        strokeWidth: 1.8
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: "M8.5,157 L61,157" }
      }
    }

    // Glass, dropping into its chrome seat, lit from below once on.
    Shape {
      width: 80
      height: 160
      y: show.glassDrop
      opacity: show.glassOn
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: Util.alpha("white", 0.6)
        strokeWidth: 1
        joinStyle: ShapePath.RoundJoin
        fillGradient: LinearGradient {
          x1: 0; y1: 1; x2: 0; y2: 108
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.06) }
          GradientStop { position: 0.55; color: Util.alpha(show.host.tint, 0.06 * show.ledOn) }
          GradientStop { position: 1.0; color: Util.alpha(Qt.tint("#cfe8ff", Util.alpha(show.host.tint, show.ledOn)), 0.25 + 0.3 * show.ledOn) }
        }
        PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z" }
      }
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: 36; x2: 0; y2: 105
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.2) }
          GradientStop { position: 1.0; color: Util.alpha(show.host.tint, 0.1 + 0.3 * show.ledOn) }
        }
        PathSvg { path: "M17.5,37 Q20,35.8 22.5,36.5 L35,97 L13,105 Z" }
      }
      ShapePath {
        strokeColor: Util.alpha("white", 0.4)
        strokeWidth: 1.3
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        PathSvg { path: "M14.5,6 L11,100" }
      }
    }

    // The chamber's chrome collar and knurled cap, dropping onto the shelf
    // with a twist.
    Shape {
      width: 80
      height: 160
      y: show.capDrop
      opacity: show.capOn
      transform: Rotation { origin.x: 60; origin.y: 86; angle: show.capSpin / 30 }
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: "transparent"
        fillColor: "#c9c9ce"
        PathSvg { path: "M50.5,90.5 H69.5 V93.5 H50.5 Z" }
      }
      ShapePath {
        strokeColor: Util.alpha("white", 0.18)
        strokeWidth: 0.5
        fillColor: "#232326"
        PathSvg { path: "M51.5,80.5 H69 Q71,80.5 71,82.5 V89 Q71,91 69,91 H51.5 Q49.5,91 49.5,89 V82.5 Q49.5,80.5 51.5,80.5 Z" }
      }
      ShapePath {
        strokeColor: Util.alpha("white", 0.12)
        strokeWidth: 0.6
        fillColor: "transparent"
        PathSvg { path: "M52,82 L54,90 M55,82 L57,90 M58,82 L60,90 M61,82 L63,90 M64,82 L66,90 M67,82 L69,90" }
      }
    }

    // Speed streaks while flying.
    Repeater {
      model: 6

      Rectangle {
        id: streak
        required property int index
        visible: show.trailOn > 0 && show.liftY < -20
        width: 1.6
        height: 22 + (index * 17) % 26
        radius: 1
        x: index % 2 ? -16 - index * 4 : 90 + index * 4
        color: Util.alpha("white", 0.5)

        NumberAnimation on y {
          running: streak.visible
          loops: Animation.Infinite
          from: 30 + streak.index * 10
          to: 220
          duration: 260 + streak.index * 35
        }
      }
    }
  }

  // Sparks where glass meets base, and a pop as the cap lands.
  Sparks {
    host: show.host
    id: clink
    x: show.padX - 8 * show.s * 1.25
    y: show.padY - 60 * show.s * 1.25
    count: 12
    reach: 34 * show.s
    dot: 3.2 * show.s
    hues: ["#ffffff", "#cfe8ff", show.host.tint]
  }
  Sparks {
    host: show.host
    id: pop
    x: show.padX + 25 * show.s * 1.25
    y: show.padY - 74 * show.s * 1.25
    count: 9
    reach: 24 * show.s
    dot: 3.2 * show.s
    hues: ["#ffffff", "#f6d32d", show.host.tint]
  }

  // Countdown.
  Text {
    id: countText
    visible: show.count !== ""
    x: show.padX + 70 * show.s
    y: show.padY - 150 * show.s
    textFormat: Text.PlainText
    text: show.count
    color: "white"
    style: Text.Outline
    styleColor: Util.alpha("black", 0.6)
    font.family: show.host.displayFamily
    font.pixelSize: 64 * show.s
    font.weight: Font.DemiBold

    onTextChanged: if (countText.text !== "") countPop.restart()
    ParallelAnimation {
      id: countPop
      NumberAnimation { target: countText; property: "scale"; from: 1.8; to: 1; duration: 380; easing.type: Easing.OutBack }
      NumberAnimation { target: countText; property: "opacity"; from: 0.2; to: 1; duration: 200 }
    }
  }

  // READY!
  Text {
    id: readyText
    function pop() { readyAnim.restart() }
    width: 320 * show.s
    x: show.padX - width / 2
    y: show.padY - 60 * show.s
    horizontalAlignment: Text.AlignHCenter
    opacity: 0
    textFormat: Text.PlainText
    text: "READY"
    color: Qt.lighter(show.host.tint, 1.4)
    style: Text.Outline
    styleColor: Util.alpha("black", 0.55)
    font.family: show.host.displayFamily
    font.pixelSize: 44 * show.s
    font.weight: Font.DemiBold
    font.letterSpacing: 6

    SequentialAnimation {
      id: readyAnim
      ParallelAnimation {
        NumberAnimation { target: readyText; property: "opacity"; to: 1; duration: 160 }
        NumberAnimation { target: readyText; property: "scale"; from: 0.3; to: 1; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
      }
      PauseAnimation { duration: 1300 }
      NumberAnimation { target: readyText; property: "opacity"; to: 0; duration: 600 }
    }
  }
}
