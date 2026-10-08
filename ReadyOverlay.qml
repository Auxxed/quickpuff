import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// A celebration when the Peak reaches temperature, played over the desktop
// from the bar widget. Full-screen, transparent and click-through (the empty
// mask), so it never gets in the way; it closes itself when done.
//
// Animations are a registry: add a component below and an entry in
// `animations`, then list it in READY_ANIMATIONS (constants.py) and the
// panel's `readyAnimations`.
PanelWindow {
  id: overlay

  property string animation: "rocket"
  // Launch point in this window's coordinates: under the widget, and the
  // bar's inner edge.
  property real originX: 0
  property real barEdge: 0
  property bool barAtTop: true
  property string fontFamily: Style.font.family
  // The active profile's LED colour, fetched as the show starts.
  property color tint: Color.accent
  // Set once the host has filled in the properties above, so the show starts
  // with the right animation and position.
  property bool armed: false

  signal finished()

  readonly property var animations: ({
    "rocket": rocketComponent,
    "confetti": confettiComponent,
    "lava": lavaComponent,
    "aurora": auroraComponent,
    "fireworks": fireworksComponent,
    "smoke": smokeComponent,
    "neon": neonComponent
  })
  // Puffco's display face, for the neon sign.
  FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/Rajdhani-SemiBold.ttf") }
  readonly property string displayFamily: displayFont.status === FontLoader.Ready ? displayFont.name : fontFamily
  readonly property real u: Style.spaceReal(1)

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickpuff-ready"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  // Nothing here takes a click.
  mask: Region {}

  Loader {
    anchors.fill: parent
    active: overlay.armed
    sourceComponent: overlay.animations[overlay.animation] || null
    onStatusChanged: if (status === Loader.Null || status === Loader.Error) overlay.finished()
  }

  Process {
    running: true
    command: ["bash", "-lc", "quickpuff --json status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          var list = d.profiles || []
          for (var i = 0; i < list.length; i++) {
            if (Number(list[i].index) !== Number(d.current_profile)) continue
            var hex = String(list[i].color || "")
            if (/^#[0-9a-fA-F]{6}$/.test(hex)) overlay.tint = hex
          }
        } catch (e) {}
      }
    }
  }

  Component { id: rocketComponent; RocketLaunch {} }
  Component { id: confettiComponent; ConfettiRain {} }
  Component { id: lavaComponent; LavaLamp {} }
  Component { id: auroraComponent; Aurora {} }
  Component { id: fireworksComponent; Fireworks {} }
  Component { id: smokeComponent; SmokeRings {} }
  Component { id: neonComponent; NeonSign {} }

  // ================================================================ Rocket
  // The Peak Pro assembles on a launch pad (body, glass into its chrome
  // seat, chamber cap onto the shelf), lights its ring and logo in the
  // profile's colour, grows fins, counts down and blasts off through the bar.
  component RocketLaunch: Item {
    id: show

    readonly property real s: overlay.u * 1.25
    readonly property real padX: Math.max(90 * s, Math.min(width - 90 * s, overlay.originX))
    readonly property real padY: overlay.barAtTop ? overlay.barEdge + 250 * s : overlay.barEdge - 40 * s

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
      ScriptAction { script: { show.count = "3"; show.smoking = true } }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 0.35; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 0.8; duration: 560 }
      }
      ScriptAction { script: show.count = "2" }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 0.65; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 1.6; duration: 560 }
      }
      ScriptAction { script: show.count = "1" }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 1; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 2.6; duration: 560 }
      }
      // Liftoff.
      ScriptAction { script: { show.count = ""; readyText.pop() } }
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
      ScriptAction { script: overlay.finished() }
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
        color: Util.alpha(overlay.tint, 0.12 + 0.2 * show.ledOn)
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

    // ---- Smoke
    Repeater {
      model: 18

      Rectangle {
        id: puff
        required property int index
        readonly property real side: index % 2 ? 1 : -1
        readonly property real reach: (40 + (index * 37) % 70) * show.s
        width: (18 + (index * 13) % 16) * show.s
        height: width
        radius: width / 2
        color: index % 3 ? "#d9dce3" : "#b7bcc6"
        opacity: 0
        x: show.padX - width / 2
        y: show.padY - height / 2

        SequentialAnimation {
          running: show.smoking
          loops: Animation.Infinite
          PauseAnimation { duration: (puff.index * 97) % 600 }
          ParallelAnimation {
            NumberAnimation { target: puff; property: "x"; from: show.padX - puff.width / 2; to: show.padX - puff.width / 2 + puff.side * puff.reach; duration: 1100; easing.type: Easing.OutCubic }
            NumberAnimation { target: puff; property: "y"; from: show.padY - puff.height / 2; to: show.padY - puff.height / 2 - (puff.index % 4) * 9 * show.s; duration: 1100; easing.type: Easing.OutCubic }
            NumberAnimation { target: puff; property: "scale"; from: 0.4; to: 1.8; duration: 1100 }
            SequentialAnimation {
              NumberAnimation { target: puff; property: "opacity"; from: 0; to: 0.75 * show.fadeAll; duration: 180 }
              NumberAnimation { target: puff; property: "opacity"; to: 0; duration: 920; easing.type: Easing.InQuad }
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
        color: Util.alpha(overlay.tint, 0.08 + 0.16 * show.ledOn)
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
              GradientStop { position: 0.0; color: Qt.lighter(overlay.tint, 1.3) }
              GradientStop { position: 1.0; color: Qt.darker(overlay.tint, 1.6) }
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
          fillColor: Util.alpha(overlay.tint, show.ledOn)
          PathSvg { path: "M12,123 L14.6,121.6 L14.6,128.6 L12,130 Z" }
        }
        ShapePath {
          strokeColor: Util.alpha(overlay.tint, show.ledOn)
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
            GradientStop { position: 0.55; color: Util.alpha(overlay.tint, 0.06 * show.ledOn) }
            GradientStop { position: 1.0; color: Util.alpha(Qt.tint("#cfe8ff", Util.alpha(overlay.tint, show.ledOn)), 0.25 + 0.3 * show.ledOn) }
          }
          PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z" }
        }
        ShapePath {
          strokeColor: "transparent"
          fillGradient: LinearGradient {
            x1: 0; y1: 36; x2: 0; y2: 105
            GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.2) }
            GradientStop { position: 1.0; color: Util.alpha(overlay.tint, 0.1 + 0.3 * show.ledOn) }
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
      id: clink
      x: show.padX - 8 * show.s * 1.25
      y: show.padY - 60 * show.s * 1.25
      count: 12
      reach: 34 * show.s
      hues: ["#ffffff", "#cfe8ff", overlay.tint]
    }
    Sparks {
      id: pop
      x: show.padX + 25 * show.s * 1.25
      y: show.padY - 74 * show.s * 1.25
      count: 9
      reach: 24 * show.s
      hues: ["#ffffff", "#f6d32d", overlay.tint]
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
      font.family: overlay.displayFamily
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
      color: Qt.lighter(overlay.tint, 1.4)
      style: Text.Outline
      styleColor: Util.alpha("black", 0.55)
      font.family: overlay.displayFamily
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

  // ============================================================== Confetti
  // Puffco confetti burst from the widget: logo-shaped chips, streamers and
  // a few tiny Peaks in shades of the profile's colour, gold and white. Each
  // piece flips like paper, slows in the air and sways as it settles.
  component ConfettiRain: Item {
    id: rain

    property real t: 0
    readonly property real s: overlay.u
    readonly property real dur: 4.2
    readonly property real dir: overlay.barAtTop ? 1 : -1
    readonly property var hues: [overlay.tint, Qt.lighter(overlay.tint, 1.5), Qt.darker(overlay.tint, 1.3), "#ffd76a", "#ffffff", Qt.lighter(overlay.tint, 1.2)]

    NumberAnimation on t { from: 0; to: 1; duration: 4200; running: true; onFinished: overlay.finished() }

    Repeater {
      model: 84

      Item {
        id: bit
        required property int index
        // Every 12th piece is a tiny Peak, every 3rd a streamer, the rest
        // logo chips. Deterministic spread so each burst looks full.
        readonly property int kind: index % 12 === 0 ? 2 : (index % 3 === 0 ? 1 : 0)
        readonly property real angle: (((index * 61) % 100) / 100 - 0.5) * 2.6
        readonly property real speed: (380 + (index * 47) % 520) * rain.s
        readonly property real vx: Math.sin(angle) * speed
        readonly property real vy: Math.cos(angle) * speed * rain.dir
        readonly property real drag: 2.2 + (index % 5) * 0.25
        readonly property real fall: (90 + (index * 29) % 80) * rain.s
        readonly property real sway: (14 + (index * 17) % 26) * rain.s
        readonly property real phase: index * 1.7
        readonly property real flipRate: 5 + (index * 13) % 9
        readonly property real tau: rain.t * rain.dur
        readonly property real slow: (1 - Math.exp(-drag * tau)) / drag
        readonly property color hue: rain.hues[index % rain.hues.length]

        x: overlay.originX + vx * slow + Math.sin(tau * 3 + phase) * sway * Math.min(1, tau)
        y: overlay.barEdge + vy * slow + fall * tau
        rotation: (index % 2 ? 1 : -1) * (120 + (index * 37) % 240) * tau
        opacity: rain.t < 0.75 ? 1 : (1 - rain.t) / 0.25
        // Paper flip: the piece turns edge-on and back.
        transform: Scale { xScale: Math.cos(bit.tau * bit.flipRate + bit.phase) }

        // Logo chip.
        Shape {
          visible: bit.kind === 0
          width: 6
          height: 14
          x: -width * rain.s / 2
          scale: rain.s * (0.9 + (bit.index % 3) * 0.25)
          transformOrigin: Item.TopLeft
          ShapePath {
            strokeColor: "transparent"
            fillColor: bit.hue
            PathSvg { path: "M0,3 L6,0 L6,11 L0,14 Z" }
          }
        }

        // Streamer.
        Rectangle {
          visible: bit.kind === 1
          width: 3 * rain.s
          height: (16 + (bit.index * 7) % 14) * rain.s
          radius: width / 2
          gradient: Gradient {
            GradientStop { position: 0.0; color: bit.hue }
            GradientStop { position: 1.0; color: Qt.darker(bit.hue, 1.3) }
          }
        }

        // A tiny Peak Pro, tumbling.
        Shape {
          visible: bit.kind === 2
          width: 80
          height: 160
          scale: rain.s * 0.24
          transformOrigin: Item.TopLeft
          ShapePath {
            strokeColor: Util.alpha("white", 0.6)
            strokeWidth: 3
            fillColor: Util.alpha(bit.hue, 0.35)
            PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z" }
          }
          ShapePath {
            strokeColor: "transparent"
            fillColor: "#2a2a2d"
            PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
          }
          ShapePath {
            strokeColor: "transparent"
            fillColor: "#55555a"
            PathSvg { path: "M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C52,116 24,136 6.5,151 L6.5,111.5 Q6.5,109.8 8.5,109 Z" }
          }
          ShapePath {
            strokeColor: bit.hue
            strokeWidth: 4
            fillColor: "transparent"
            PathSvg { path: "M8.5,157 L61,157" }
          }
        }
      }
    }
  }

  // ============================================================ Lava lamp
  // Molten blobs in the profile's colour rise up the screen, wobbling and
  // melting into one another (blurred together, like wax in a lamp).
  component LavaLamp: Item {
    id: lava

    property real t: 0
    readonly property real s: overlay.u
    readonly property var hues: [overlay.tint, Qt.lighter(overlay.tint, 1.45), Qt.darker(overlay.tint, 1.35)]

    NumberAnimation on t { from: 0; to: 1; duration: 6000; running: true; onFinished: overlay.finished() }

    Item {
      id: wax
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Repeater {
        model: 11
        Rectangle {
          id: blob
          required property int index
          readonly property real size: (170 + (index * 53) % 170) * lava.s
          readonly property real delay: (index % 6) * 0.07
          readonly property real p: Math.max(0, Math.min(1, (lava.t - delay) / 0.8))
          readonly property real eased: p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2
          width: size * (1 + 0.16 * Math.sin(p * Math.PI * 5 + index))
          height: size * (1 - 0.12 * Math.sin(p * Math.PI * 5 + index))
          radius: Math.min(width, height) / 2
          x: lava.width * (0.04 + ((index * 37) % 92) / 100) + Math.sin(p * Math.PI * 2 + index) * 40 * lava.s - width / 2
          y: lava.height + size - eased * (lava.height + 2.4 * size)
          color: lava.hues[index % lava.hues.length]
          opacity: p <= 0 || p >= 1 ? 0 : Math.min(1, p / 0.1, (1 - p) / 0.15)
        }
      }
    }

    MultiEffect {
      anchors.fill: wax
      source: wax
      blurEnabled: true
      blurMax: 64
      blur: 0.8
      opacity: 0.85
    }
  }

  // ============================================================ Aurora
  // Northern lights: curtains of green, teal and the profile's colour ripple
  // across the top of the screen and fade.
  component Aurora: Item {
    id: aurora

    property real t: 0
    readonly property real s: overlay.u
    readonly property real envelope: Math.min(1, t / 0.18, (1 - t) / 0.3)
    readonly property var curtains: [
      { "hue": "#3dff9e", "base": 0.16, "amp": 0.05, "k": 2.2, "speed": 1.0, "height": 0.22 },
      { "hue": "#2de2e6", "base": 0.24, "amp": 0.06, "k": 1.6, "speed": -0.7, "height": 0.18 },
      { "hue": String(overlay.tint), "base": 0.31, "amp": 0.04, "k": 2.8, "speed": 1.3, "height": 0.16 }
    ]

    NumberAnimation on t { from: 0; to: 1; duration: 6500; running: true; onFinished: overlay.finished() }

    Item {
      id: sky
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Repeater {
        model: aurora.curtains.length * 64
        Rectangle {
          required property int index
          readonly property var c: aurora.curtains[Math.floor(index / 64)]
          readonly property int col: index % 64
          readonly property real fx: col / 63
          readonly property real wave: Math.sin(fx * Math.PI * 2 * c.k + aurora.t * Math.PI * 4 * c.speed)
          readonly property real tall: aurora.height * c.height * (0.6 + 0.4 * Math.sin(fx * 9 + aurora.t * 8 * c.speed))
          width: aurora.width / 64 + 3
          height: tall
          x: fx * aurora.width - width / 2
          y: aurora.height * (c.base + c.amp * wave) - tall * 0.8
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(c.hue, 0) }
            GradientStop { position: 0.75; color: Util.alpha(c.hue, 0.55) }
            GradientStop { position: 1.0; color: Util.alpha(c.hue, 0) }
          }
        }
      }
    }

    MultiEffect {
      anchors.fill: sky
      source: sky
      blurEnabled: true
      blurMax: 56
      blur: 0.9
      opacity: aurora.envelope
    }
  }

  // ============================================================ Fireworks
  // Shells whistle up from the bottom of the screen and burst in the
  // profile's colour, gold and white, sparks falling as they fade.
  component Fireworks: Item {
    id: fw

    property real t: 0
    readonly property real s: overlay.u
    readonly property int shells: 6
    readonly property int sparks: 36
    readonly property var hues: [overlay.tint, "#ffd76a", "#ffffff", Qt.lighter(overlay.tint, 1.5), Color.accent, "#ff6ad5"]

    NumberAnimation on t { from: 0; to: 1; duration: 5200; running: true; onFinished: overlay.finished() }

    // Bloom behind the sparks.
    MultiEffect {
      anchors.fill: night
      source: night
      blurEnabled: true
      blurMax: 40
      blur: 0.8
      brightness: 0.25
    }

    Item {
      id: night
      anchors.fill: parent
      layer.enabled: true

    Repeater {
      model: fw.shells
      Item {
        id: shell
        required property int index
        readonly property real start: index * 0.12
        readonly property real rise: Math.max(0, Math.min(1, (fw.t - start) / 0.14))
        readonly property real burst: Math.max(0, Math.min(1, (fw.t - start - 0.14) / 0.4))
        readonly property real bx: fw.width * (0.15 + ((index * 41) % 70) / 100)
        readonly property real by: fw.height * (0.22 + ((index * 29) % 30) / 100)
        readonly property color hue: fw.hues[index % fw.hues.length]

        // The rising shell and its trail.
        Rectangle {
          visible: shell.rise > 0 && shell.rise < 1
          width: 4 * fw.s
          height: 22 * fw.s
          radius: width / 2
          x: shell.bx - width / 2
          y: fw.height - (fw.height - shell.by) * (1 - Math.pow(1 - shell.rise, 2))
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: Util.alpha(shell.hue, 0) }
          }
        }

        // The flash at the burst.
        Rectangle {
          visible: shell.burst > 0 && shell.burst < 0.3
          width: 120 * fw.s * shell.burst / 0.3
          height: width
          radius: width / 2
          x: shell.bx - width / 2
          y: shell.by - height / 2
          color: Util.alpha(shell.hue, 0.35 * (1 - shell.burst / 0.3))
        }

        Repeater {
          model: fw.sparks
          Rectangle {
            required property int index
            readonly property real angle: index / fw.sparks * Math.PI * 2 + shell.index
            readonly property real reach: (230 + (index * 37) % 110) * fw.s
            readonly property real e: 1 - Math.pow(1 - shell.burst, 3)
            visible: shell.burst > 0 && shell.burst < 1
            // A short streak pointing along its flight.
            width: (index % 3 ? 7 : 10) * fw.s * (1 + 2.2 * (1 - shell.burst))
            height: (index % 3 ? 4 : 6) * fw.s
            radius: height / 2
            rotation: angle * 180 / Math.PI
            x: shell.bx + Math.cos(angle) * reach * e - width / 2
            y: shell.by + Math.sin(angle) * reach * e + 120 * fw.s * shell.burst * shell.burst - height / 2
            color: index % 5 === 0 ? "#ffffff" : shell.hue
            opacity: 1 - shell.burst
          }
        }
      }
    }
    }
  }

  // ============================================================ Smoke rings
  // Soft rings puff out from the widget one after another, widening and
  // drifting off as they thin out.
  component SmokeRings: Item {
    id: smoke

    property real t: 0
    readonly property real s: overlay.u
    readonly property real dir: overlay.barAtTop ? 1 : -1

    NumberAnimation on t { from: 0; to: 1; duration: 5600; running: true; onFinished: overlay.finished() }

    Repeater {
      model: 5
      Item {
        id: ring
        required property int index
        readonly property real p: Math.max(0, Math.min(1, (smoke.t - index * 0.13) / 0.55))
        readonly property real e: 1 - Math.pow(1 - p, 2)
        visible: p > 0 && p < 1
        width: (70 + 300 * e) * smoke.s
        height: width * 0.36
        x: Math.max(0, Math.min(smoke.width - width, overlay.originX - width / 2 + Math.sin(p * Math.PI * 2 + index) * 50 * smoke.s))
        y: overlay.barEdge + smoke.dir * (50 + 520 * e) * smoke.s - height / 2
        opacity: 1 - p * p

        // A few soft layers in place of a blur: a dense core band with
        // fainter, wider halos either side, so it reads as smoke.
        Repeater {
          model: 4
          Rectangle {
            required property int index
            readonly property real spread: index * 5 * smoke.s
            x: -spread
            y: -spread * 0.6
            width: ring.width + spread * 2
            height: ring.height + spread * 1.2
            radius: height / 2
            color: "transparent"
            border.width: Math.max(2, ring.height * (0.22 - index * 0.03))
            border.color: Util.alpha(Qt.tint("#f2f2f6", Util.alpha(overlay.tint, 0.3)), [0.55, 0.3, 0.16, 0.08][index])
          }
        }
      }
    }
  }

  // ============================================================ Neon sign
  // A neon Peak and READY buzz on in the middle of the screen, flicker,
  // glow for a moment, then switch off.
  component NeonSign: Item {
    id: neon

    property real t: 0
    readonly property real s: overlay.u * 1.6
    readonly property color glow: Qt.lighter(overlay.tint, 1.25)
    // On, off, on, stutter, steady... then a fade.
    readonly property real power: {
      var k = t * 50
      if (k < 1) return 0
      if (k < 2) return 1
      if (k < 3) return 0.15
      if (k < 4.5) return 1
      if (k < 5) return 0.4
      if (t > 0.8) return Math.max(0, (1 - t) / 0.2)
      return 0.92 + 0.08 * Math.sin(t * 90)
    }

    NumberAnimation on t { from: 0; to: 1; duration: 4500; running: true; onFinished: overlay.finished() }

    Item {
      id: sign
      readonly property real k: height / 166
      width: 80 * k + 30 * neon.s + readyWord.implicitWidth + 20 * neon.s
      height: 230 * neon.s
      anchors.centerIn: parent
      visible: false
      layer.enabled: true

      // The Peak, in tube outline (the same paths as the panel's drawing).
      Shape {
        x: 3 * sign.k
        y: 3 * sign.k
        width: 80
        height: 160
        transform: Scale { xScale: sign.k; yScale: sign.k }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: neon.glow
          strokeWidth: 1.8
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z M72.3,104.4 C52,116 24,136 6.8,150.6 M51.5,80.5 H69 Q71,80.5 71,82.5 V89 Q71,91 69,91 H51.5 Q49.5,91 49.5,89 V82.5 Q49.5,80.5 51.5,80.5 Z" }
        }
      }

      Text {
        id: readyWord
        x: 80 * sign.k + 30 * neon.s
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 30 * neon.s
        textFormat: Text.PlainText
        text: "READY"
        color: "transparent"
        style: Text.Outline
        styleColor: neon.glow
        font.family: overlay.displayFamily
        font.pixelSize: 110 * neon.s
        font.weight: Font.DemiBold
        font.letterSpacing: 6 * neon.s
      }
    }

    // The glow, then the tubes on top of it.
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 64
      blur: 1
      brightness: 0.3
      opacity: neon.power * 0.9
    }
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 8
      blur: 0.3
      opacity: neon.power
    }
  }

  // A ring of sparks thrown from a point; `fire()` plays it once.
  component Sparks: Item {
    id: sparks

    property int count: 10
    property real reach: 30
    property var hues: ["#ffffff"]
    property real t: 0

    function fire() { sparkAnim.restart() }

    visible: sparkAnim.running

    NumberAnimation {
      id: sparkAnim
      target: sparks
      property: "t"
      from: 0
      to: 1
      duration: 520
      easing.type: Easing.OutCubic
    }

    Repeater {
      model: sparks.count

      Rectangle {
        required property int index
        readonly property real angle: index / sparks.count * Math.PI * 2
        width: 4 * overlay.u
        height: width
        radius: width / 2
        x: Math.cos(angle) * sparks.reach * sparks.t - width / 2
        y: Math.sin(angle) * sparks.reach * sparks.t * 0.6 - height / 2
        color: sparks.hues[index % sparks.hues.length]
        opacity: 1 - sparks.t
      }
    }
  }
}
