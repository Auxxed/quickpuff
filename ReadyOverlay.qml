import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"

// A celebration when the Peak reaches temperature, played over the desktop
// from the bar widget. Full-screen, transparent and click-through (the empty
// mask), so it never gets in the way; it closes itself when done.
//
// Animations are a registry: add a component below and an entry in
// `animations`, then list it in READY_ANIMATIONS (constants.py) and the
// panel's `readyAnimations`.
//
// Shows play sound cues with `cue(name)` (sounds/<name>.ogg). The `ready`
// chime opens every show; the rest are fired by each animation.
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
  // Sound cues, and how loud they play (0..1).
  property bool soundsOn: true
  property real soundVolume: 0.7
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
  // Screen-relative scale for the big shows: 1 up to a 1400 px wide 16:9
  // stage, more past that (about 1.1 at 1536 x 864, 1.46 at 2048 x 1152).
  readonly property real stage: Math.max(1, Math.min(scene.width, scene.height * 16 / 9) / 1400)

  // Plays sounds/<name>.ogg (one of the bundled cues) through pw-play,
  // fire-and-forget, stopped after ten seconds at most. Nothing when sounds
  // are off.
  // How many versions each cue has in sounds/: firework, firework-2, ...
  readonly property var cueVersions: ({ "firework": 3, "pop": 2, "smoke": 2, "liftoff": 2 })

  function cue(name) {
    if (!overlay.soundsOn || !/^[a-z]+$/.test(name)) return
    var volume = Math.max(0, Math.min(1, Number(overlay.soundVolume) || 0))
    if (volume <= 0) return
    // A cue with versions plays one of them, so repeats don't sound identical.
    var versions = cueVersions[name] || 1
    var pick = Math.floor(Math.random() * versions)
    var url = String(Qt.resolvedUrl("sounds/" + (pick > 0 ? name + "-" + (pick + 1) : name) + ".ogg"))
    if (url.indexOf("file://") !== 0) return
    Quickshell.execDetached(["/usr/bin/timeout", "-k", "1", "10", "/usr/bin/pw-play",
      "--volume", volume.toFixed(2), "--", decodeURIComponent(url.slice(7))])
  }

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
    id: scene
    anchors.fill: parent
    active: overlay.armed
    // Only a name in the registry; anything else plays nothing.
    sourceComponent: Object.prototype.hasOwnProperty.call(overlay.animations, overlay.animation) ? overlay.animations[overlay.animation] : null
    // The signature chime, as every show starts.
    onLoaded: overlay.cue("ready")
    onStatusChanged: if (status === Loader.Null || status === Loader.Error) overlay.finished()
  }

  QuickpuffCli { id: cli }

  BoundedProcess {
    id: statusProc
    maxBytes: 262144
    timeoutMs: 8000
    Component.onCompleted: launch(cli.argv(["--json", "status"]))
    onDone: function(ok, code, out) {
      if (!ok) return
      try {
        var d = JSON.parse(out)
        var list = Array.isArray(d.profiles) && d.profiles.length <= 8 ? d.profiles : []
        for (var i = 0; i < list.length; i++) {
          if (Number(list[i].index) !== Number(d.current_profile)) continue
          var hex = String(list[i].color || "")
          if (/^#[0-9a-fA-F]{6}$/.test(hex)) overlay.tint = hex
        }
      } catch (e) {}
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

    // About 1.3x the old size on a 1536 x 864 screen, growing with bigger ones.
    readonly property real s: overlay.u * 1.5 * overlay.stage
    // Kept clear of the screen edges, the countdown on the right included.
    readonly property real padX: Math.max(90 * s, Math.min(width - 115 * s, overlay.originX))
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
      ScriptAction { script: { show.count = "3"; show.smoking = true; overlay.cue("count") } }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 0.35; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 0.8; duration: 560 }
      }
      ScriptAction { script: { show.count = "2"; overlay.cue("count") } }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 0.65; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 1.6; duration: 560 }
      }
      ScriptAction { script: { show.count = "1"; overlay.cue("count") } }
      ParallelAnimation {
        NumberAnimation { target: show; property: "flame"; to: 1; duration: 560 }
        NumberAnimation { target: show; property: "shake"; to: 2.6; duration: 560 }
      }
      // Liftoff.
      ScriptAction { script: { show.count = ""; readyText.pop(); overlay.cue("liftoff") } }
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
      dot: 3.2 * show.s
      hues: ["#ffffff", "#cfe8ff", overlay.tint]
    }
    Sparks {
      id: pop
      x: show.padX + 25 * show.s * 1.25
      y: show.padY - 74 * show.s * 1.25
      count: 9
      reach: 24 * show.s
      dot: 3.2 * show.s
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
  // Puffco confetti: a burst from the widget, then two cannons firing up from
  // the bottom corners toward the middle, so the whole screen fills. Logo-
  // shaped chips, streamers and a few tiny Peaks in shades of the profile's
  // colour, gold and white. Each piece flips like paper, slows in the air and
  // sways as it settles.
  component ConfettiRain: Item {
    id: rain

    property real t: 0
    readonly property real dur: 5.2
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage * 1.3
    readonly property real dir: overlay.barAtTop ? 1 : -1
    // Pieces from the widget, then from each cannon (under 200 in all), and
    // when the cannons go off (s).
    readonly property int burstCount: 76
    readonly property int cannonCount: 58
    readonly property real cannonAt: 0.3
    readonly property bool cannonsOut: now >= cannonAt
    readonly property var hues: [overlay.tint, Qt.lighter(overlay.tint, 1.5), Qt.darker(overlay.tint, 1.3), "#ffd76a", "#ffffff", Qt.lighter(overlay.tint, 1.2)]

    Component.onCompleted: overlay.cue("pop")
    onCannonsOutChanged: if (cannonsOut) overlay.cue("pop")

    NumberAnimation on t { from: 0; to: 1; duration: 5200; running: true; onFinished: overlay.finished() }

    // A soft flash in each corner as the cannons fire.
    Repeater {
      model: 2

      SoftGlow {
        required property int index
        readonly property real f: Math.max(0, Math.min(1, (rain.now - rain.cannonAt) / 0.5))
        visible: f > 0 && f < 1
        hue: Qt.lighter(overlay.tint, 1.6)
        x: (index ? rain.width : 0) - 50
        y: rain.height - 50
        scale: rain.height * (0.3 + 0.4 * f) / 100
        opacity: 0.6 * (1 - f)
      }
    }

    Repeater {
      model: rain.burstCount + 2 * rain.cannonCount

      Item {
        id: bit
        required property int index
        // Fired by the widget (0), the left cannon (1) or the right one (2).
        readonly property int firedBy: index < rain.burstCount ? 0 : (index < rain.burstCount + rain.cannonCount ? 1 : 2)
        // Every 12th piece is a tiny Peak, every 3rd a streamer, the rest
        // logo chips. Deterministic spread so each burst looks full.
        readonly property int kind: index % 12 === 0 ? 2 : (index % 3 === 0 ? 1 : 0)
        readonly property real spread: ((index * 61) % 100) / 100 - 0.5
        readonly property real power: ((index * 47) % 100) / 100
        readonly property real drag: 2.2 + (index % 5) * 0.25
        // Where it starts, and where a cannon aims: just short of the middle,
        // a quarter of the way down. Drag stops each piece at speed / drag,
        // so the cannon pieces land from halfway there to a little past it.
        readonly property real ox: firedBy === 0 ? overlay.originX : (firedBy === 1 ? 0 : rain.width)
        readonly property real oy: firedBy === 0 ? overlay.barEdge : rain.height
        readonly property real aimX: rain.width * (firedBy === 1 ? 0.46 : 0.54) - ox
        readonly property real aimY: rain.height * 0.25 - oy
        readonly property real angle: firedBy === 0 ? spread * 2.6 : Math.atan2(aimY, aimX) + spread * 0.6
        readonly property real speed: firedBy === 0
          ? rain.height * (0.5 + 0.75 * power)
          : Math.sqrt(aimX * aimX + aimY * aimY) * drag * (0.5 + 0.8 * power)
        readonly property real vx: firedBy === 0 ? Math.sin(angle) * speed : Math.cos(angle) * speed
        readonly property real vy: firedBy === 0 ? Math.cos(angle) * speed * rain.dir : Math.sin(angle) * speed
        readonly property real fall: rain.height * (0.1 + ((index * 29) % 80) / 900)
        readonly property real sway: (14 + (index * 17) % 26) * rain.s
        readonly property real phase: index * 1.7
        readonly property real flipRate: 5 + (index * 13) % 9
        // Seconds since this piece was fired.
        readonly property real tau: Math.max(0, rain.now - (firedBy === 0 ? 0 : rain.cannonAt))
        readonly property real slow: (1 - Math.exp(-drag * tau)) / drag
        readonly property color hue: rain.hues[index % rain.hues.length]

        visible: firedBy === 0 || rain.cannonsOut
        x: ox + vx * slow + Math.sin(tau * 3 + phase) * sway * Math.min(1, tau)
        y: oy + vy * slow + fall * tau
        rotation: (index % 2 ? 1 : -1) * (120 + (index * 37) % 240) * tau
        opacity: rain.t < 0.78 ? 1 : (1 - rain.t) / 0.22
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

        // A tiny Peak Pro, tumbling (only built for the pieces that are one).
        Loader {
          active: bit.kind === 2
          sourceComponent: Component {
            Shape {
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

    Component.onCompleted: overlay.cue("bubbles")
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

    Component.onCompleted: overlay.cue("shimmer")
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
  // Ten shells whistle up across the whole width of the screen and burst in
  // the profile's colour, gold and white: big peonies with a white heart,
  // and two gold willows whose sparks droop and linger. Every spark drags a
  // streak along its flight; each burst flashes and lights up the sky, with
  // a bloom over it all.
  component Fireworks: Item {
    id: fw

    property real t: 0
    readonly property real dur: 6.2
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property var hues: [overlay.tint, "#ffd76a", "#ffffff", Qt.lighter(overlay.tint, 1.5), Color.accent, "#ff6ad5", "#7fe3ff"]
    // The show, in launch order: where each shell bursts (fractions of the
    // screen), when it leaves the ground (s), how far its sparks fly (a
    // fraction of the screen height), its colour (into `hues`), and whether
    // it is a gold willow. Everything is out by about 5.9 s.
    readonly property var basePlan: [
      { "x": 0.50, "y": 0.30, "at": 0.05, "size": 0.26, "hue": 0, "willow": false },
      { "x": 0.18, "y": 0.36, "at": 0.45, "size": 0.21, "hue": 5, "willow": false },
      { "x": 0.80, "y": 0.26, "at": 0.85, "size": 0.24, "hue": 1, "willow": true },
      { "x": 0.34, "y": 0.22, "at": 1.25, "size": 0.19, "hue": 6, "willow": false },
      { "x": 0.64, "y": 0.38, "at": 1.55, "size": 0.23, "hue": 3, "willow": false },
      { "x": 0.10, "y": 0.28, "at": 1.90, "size": 0.18, "hue": 2, "willow": false },
      { "x": 0.42, "y": 0.24, "at": 2.25, "size": 0.27, "hue": 1, "willow": true },
      { "x": 0.90, "y": 0.34, "at": 2.45, "size": 0.22, "hue": 4, "willow": false },
      { "x": 0.26, "y": 0.42, "at": 2.85, "size": 0.20, "hue": 5, "willow": false },
      { "x": 0.70, "y": 0.20, "at": 3.15, "size": 0.28, "hue": 0, "willow": false }
    ]
    // No two shows alike: every shell bursts a little to one side, higher or
    // lower, early or late, bigger or smaller, in another of the colours, and
    // now and then as a willow. Worked out once, when the show starts.
    readonly property var plan: basePlan.map(function(p) {
      return {
        "x": Math.max(0.06, Math.min(0.94, p.x + (Math.random() - 0.5) * 0.12)),
        "y": Math.max(0.16, Math.min(0.46, p.y + (Math.random() - 0.5) * 0.08)),
        "at": Math.max(0, p.at + (Math.random() - 0.5) * 0.16),
        "size": p.size * (0.9 + Math.random() * 0.2),
        "hue": Math.floor(Math.random() * 7),
        "willow": Math.random() < 0.2
      }
    })

    // Seconds a shell takes to climb (higher bursts take longer), and its
    // colour.
    function climbTime(spec) { return 0.55 + 0.55 * (1 - spec.y) }
    function hueOf(spec) { return spec.willow ? "#ffc861" : fw.hues[spec.hue] }

    NumberAnimation on t { from: 0; to: 1; duration: 6200; running: true; onFinished: overlay.finished() }

    // Each burst lights up the sky round it. Drawn straight rather than
    // through the bloom, which would band the wide, faint edge.
    Repeater {
      model: fw.plan.length

      SoftGlow {
        required property int index
        readonly property var spec: fw.plan[index]
        readonly property real f: Math.max(0, Math.min(1, (fw.now - spec.at - fw.climbTime(spec)) / 0.9))
        visible: f > 0 && f < 1
        hue: fw.hueOf(spec)
        x: fw.width * spec.x - 50
        y: fw.height * spec.y - 50
        scale: fw.height * spec.size * 4 / 100
        opacity: 0.2 * (1 - f) * (1 - f)
      }
    }

    // Drawn only through the effects below. Everything in here hides with
    // opacity, never `visible`: a child that starts hidden inside a hidden
    // layer source never shows up in the layer, even once it is visible.
    Item {
      id: night
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Repeater {
        model: fw.plan.length

        Item {
          id: shell
          required property int index
          readonly property var spec: fw.plan[index]
          readonly property bool willow: spec.willow
          readonly property int count: willow ? 32 : 40
          // Seconds to climb, and for the sparks to burn out.
          readonly property real climb: fw.climbTime(spec)
          readonly property real life: willow ? 2.7 : 1.8
          readonly property real bx: fw.width * spec.x
          readonly property real by: fw.height * spec.y
          // Launched a little to one side, so the climb leans.
          readonly property real lx: bx + (index % 2 ? 1 : -1) * fw.width * 0.035
          readonly property real radius: fw.height * spec.size
          readonly property color hue: fw.hueOf(spec)
          readonly property bool launched: fw.now >= spec.at
          // 0..1 through the climb, then seconds since the burst. Both hold
          // still outside their stretch, so idle sparks cost nothing.
          readonly property real rise: Math.max(0, Math.min(1, (fw.now - spec.at) / climb))
          readonly property real age: Math.max(0, Math.min(life, fw.now - spec.at - climb))
          readonly property real burst: age / life
          // Flight, shared by every spark of the shell: air drag slows the
          // spread (the share of its reach covered, and how fast, per second)
          // and gravity pulls toward a terminal fall speed.
          readonly property real drag: willow ? 2.4 : 3.6
          readonly property real spread: 1 - Math.exp(-drag * age)
          readonly property real speed: drag * Math.exp(-drag * age)
          readonly property real fallMax: fw.height * (willow ? 0.17 : 0.09)
          readonly property real drop: fallMax * (age - (1 - Math.exp(-1.5 * age)) / 1.5)
          readonly property real dropRate: fallMax * (1 - Math.exp(-1.5 * age))
          // Each spark's streak: seconds of its flight, and the longest.
          readonly property real trail: willow ? 0.28 : 0.1
          readonly property real maxTrail: fw.height * (willow ? 0.14 : 0.1)
          // Willows linger; late in the burst a third of the sparks glitter.
          readonly property real fade: willow
            ? 1 - Math.pow(Math.max(0, burst - 0.35) / 0.65, 1.6)
            : 1 - Math.pow(Math.max(0, burst - 0.5) / 0.5, 1.3)
          readonly property real glitter: Math.max(0, Math.min(1, (burst - 0.4) / 0.2))

          onLaunchedChanged: if (launched) overlay.cue("firework")

          // The climbing shell: a hot head and its trail, leaning with it.
          Rectangle {
            readonly property real e: 1 - Math.pow(1 - shell.rise, 2)
            opacity: shell.rise > 0 && shell.rise < 1 ? 1 : 0
            width: 4 * fw.s
            height: (40 + 70 * (1 - shell.rise)) * fw.s
            radius: width / 2
            transformOrigin: Item.Top
            rotation: Math.atan2(shell.bx - shell.lx, fw.height - shell.by) * 180 / Math.PI
            x: shell.lx + (shell.bx - shell.lx) * e - width / 2
            y: fw.height - (fw.height - shell.by) * e
            gradient: Gradient {
              GradientStop { position: 0.0; color: "#ffffff" }
              GradientStop { position: 0.12; color: Qt.lighter(shell.hue, 1.4) }
              GradientStop { position: 1.0; color: Util.alpha(shell.hue, 0) }
            }
          }

          // The bang: a white-hot core.
          SoftGlow {
            readonly property real f: Math.min(1, shell.age / 0.3)
            hue: "#ffffff"
            x: shell.bx - 50
            y: shell.by - 50
            scale: shell.radius * (0.4 + 0.6 * f) / 100
            opacity: shell.age > 0 ? 1 - f : 0
          }

          // The sparks.
          Item {
            opacity: shell.age > 0 && shell.age < shell.life ? 1 : 0

            Repeater {
              model: shell.count

              Rectangle {
                id: spark
                required property int index
                readonly property real angle: index / shell.count * Math.PI * 2 + shell.index * 0.7 + ((index * 53) % 10) / 40
                // A ball of sparks seen from the side: most fly out near the
                // rim, the rest toward or away from us and look shorter.
                readonly property real depth: Math.sin((((index * 7) % shell.count) + 0.5) / shell.count * Math.PI)
                // Every 5th spark of a peony is its heart: a tight inner ring.
                readonly property bool heart: !shell.willow && index % 5 === 0
                readonly property real reach: shell.radius * (heart ? 0.4 : depth * (0.88 + ((index * 37) % 25) / 100))
                readonly property real dx: Math.cos(angle) * reach
                readonly property real dy: Math.sin(angle) * reach
                readonly property real vx: dx * shell.speed
                readonly property real vy: dy * shell.speed + shell.dropRate
                readonly property color hue: shell.willow
                  ? (index % 3 ? "#ffc861" : "#ff9f43")
                  : (heart ? (shell.spec.hue === 2 ? "#ffd76a" : "#ffffff") : (index % 6 === 0 ? Qt.lighter(shell.hue, 1.35) : shell.hue))

                // A streak behind the spark, its head at the spark and turned
                // along its flight: long while fast, a dot once it hangs.
                height: (heart ? 2.8 : 3.6) * fw.s
                width: Math.min(shell.maxTrail, Math.max(height, Math.sqrt(vx * vx + vy * vy) * shell.trail))
                radius: height / 2
                transformOrigin: Item.Right
                rotation: Math.atan2(vy, vx) * 180 / Math.PI
                x: shell.bx + dx * shell.spread - width
                y: shell.by + dy * shell.spread + shell.drop - height / 2
                opacity: shell.fade * (index % 3 ? 1 : 1 - shell.glitter * (Math.sin(shell.age * 41 + index * 1.7) > 0 ? 0.85 : 0))
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: Util.alpha(spark.hue, 0) }
                  GradientStop { position: 0.65; color: spark.hue }
                  GradientStop { position: 1.0; color: shell.willow ? "#fff4d6" : "#ffffff" }
                }
              }
            }
          }
        }
      }
    }

    // The bloom, then the sparks themselves, crisp, on top of it.
    MultiEffect {
      anchors.fill: night
      source: night
      blurEnabled: true
      blurMax: 48
      blur: 0.9
      brightness: 0.3
      opacity: 0.9
    }
    MultiEffect {
      anchors.fill: night
      source: night
      blurEnabled: true
      blurMax: 4
      blur: 0.25
    }
  }

  // ============================================================ Smoke rings
  // Big soft rings puff out from the widget one after another, widening,
  // rocking and drifting apart as they thin out.
  component SmokeRings: Item {
    id: smoke

    property real t: 0
    readonly property real s: overlay.u * overlay.stage
    readonly property real dir: overlay.barAtTop ? 1 : -1
    readonly property color hue: Qt.tint("#f2f2f6", Util.alpha(overlay.tint, 0.3))

    Component.onCompleted: overlay.cue("smoke")
    NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: overlay.finished() }

    Repeater {
      model: 7

      // A circle filled with a soft donut of smoke, in place of a blur (a
      // radial gradient: a faint haze inside, densest round the ring's line,
      // gone at the edge), stretched into a rocking ellipse. Drawn at
      // 100 x 100 and sized by its transform, so it never re-tessellates.
      Shape {
        id: ring
        required property int index
        readonly property real p: Math.max(0, Math.min(1, (smoke.t - index * 0.075) / 0.5))
        readonly property real e: 1 - Math.pow(1 - p, 1.6)
        // How wide it is, how flat (breathing a little as it rolls), and
        // which way this one drifts, so the rings fan out.
        readonly property real across: (120 + 520 * e) * smoke.s
        readonly property real flat: 0.36 + 0.04 * Math.sin(p * Math.PI * 3 + index)
        readonly property real drift: ((index * 5) % 7 - 3) * 34 * smoke.s
        visible: p > 0 && p < 1
        width: 100
        height: 100
        x: Math.max(across / 2, Math.min(smoke.width - across / 2, overlay.originX + drift * e + Math.sin(p * Math.PI * 2 + index) * 60 * smoke.s)) - 50
        y: overlay.barEdge + smoke.dir * (60 * smoke.s + smoke.height * 0.6 * e) - 50
        opacity: Math.min(1, p / 0.08) * Math.pow(1 - p, 1.3)
        transform: [
          Scale { origin.x: 50; origin.y: 50; xScale: ring.across / 100; yScale: ring.across * ring.flat / 100 },
          Rotation { origin.x: 50; origin.y: 50; angle: 7 * Math.sin(ring.p * Math.PI * 2 + ring.index * 1.3) }
        ]

        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: 50; centerY: 50; centerRadius: 50
            focalX: 50; focalY: 50
            GradientStop { position: 0.0; color: Util.alpha(smoke.hue, 0.05) }
            GradientStop { position: 0.42; color: Util.alpha(smoke.hue, 0.05) }
            GradientStop { position: 0.6; color: Util.alpha(smoke.hue, 0.2) }
            GradientStop { position: 0.72; color: Util.alpha(smoke.hue, 0.44) }
            GradientStop { position: 0.84; color: Util.alpha(smoke.hue, 0.44) }
            GradientStop { position: 0.94; color: Util.alpha(smoke.hue, 0.14) }
            GradientStop { position: 1.0; color: Util.alpha(smoke.hue, 0) }
          }
          PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
        }
      }
    }
  }

  // ============================================================ Neon sign
  // A neon Peak and READY buzz on in the middle of a dimmed screen, flicker,
  // hum for a moment over their reflection on the floor, then switch off.
  component NeonSign: Item {
    id: neon

    property real t: 0
    readonly property real dur: 5.0
    readonly property real s: overlay.u * 1.45 * overlay.stage
    // Coloured glass round a white-hot core.
    readonly property color glass: Qt.lighter(overlay.tint, 1.3)
    readonly property color core: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.25))
    // On, off, on, stutter, steady... then a fade. Timed in milliseconds, so
    // the flicker-on keeps its rhythm (and stays with its sound).
    readonly property real power: {
      var ms = t * dur * 1000
      if (ms < 90) return 0
      if (ms < 180) return 1
      if (ms < 270) return 0.15
      if (ms < 405) return 1
      if (ms < 450) return 0.4
      if (t > 0.82) return Math.max(0, (1 - t) / 0.18)
      return 0.92 + 0.08 * Math.sin(t * dur * 20)
    }
    // The room going dark behind it as the sign catches, and back as it
    // switches off.
    readonly property real dark: Math.max(0, Math.min(1, t * dur / 0.45, (1 - t) / 0.18))
    // The panel's Peak drawing, in tube.
    readonly property string peakPath: "M12.5,1.5 Q17,0.2 21.5,0.8 L46,93 L9.5,108 Z M8.5,109 L46,93 L70,93 Q72.5,93 72.5,95.5 L72.5,104 C67,107 61,110 56,113.5 C60,126 63,140 64.5,152 Q65,158 60,158 L9.5,158 Q6.5,158 6.5,155 L6.5,111.5 Q6.5,109.8 8.5,109 Z M72.3,104.4 C52,116 24,136 6.8,150.6 M51.5,80.5 H69 Q71,80.5 71,82.5 V89 Q71,91 69,91 H51.5 Q49.5,91 49.5,89 V82.5 Q49.5,80.5 51.5,80.5 Z"

    Component.onCompleted: overlay.cue("neon")
    NumberAnimation on t { from: 0; to: 1; duration: 5000; running: true; onFinished: overlay.finished() }

    TextMetrics {
      id: word
      font.family: overlay.displayFamily
      font.pixelSize: 110 * neon.s
      font.weight: Font.DemiBold
      font.letterSpacing: 6 * neon.s
      text: "READY"
    }

    // Dim the desktop while the sign is lit, so it pops on any wallpaper.
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: 0.32 * neon.dark
    }

    Item {
      id: sign
      // Room round the tubes for the glow and the reflection's blur.
      readonly property real pad: 28 * neon.s
      // The Peak drawing's scale, the tube and its core, and the floor line
      // the Peak stands on.
      readonly property real k: 230 * neon.s / 166
      readonly property real tube: 2.6 * k
      readonly property real wire: 0.9 * k
      readonly property real floor: pad + 161 * k
      width: 2 * pad + 80 * k + 30 * neon.s + word.advanceWidth + 10 * neon.s
      height: 2 * pad + 230 * neon.s
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -neon.height * 0.06
      visible: false
      layer.enabled: true

      // The Peak, in tube outline (the same paths as the panel's drawing).
      Shape {
        x: sign.pad + 3 * sign.k
        y: sign.pad + 3 * sign.k
        width: 80
        height: 160
        transform: Scale { xScale: sign.k; yScale: sign.k }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: neon.glass
          strokeWidth: 2.6
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: neon.peakPath }
        }
        ShapePath {
          strokeColor: neon.core
          strokeWidth: 0.9
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: neon.peakPath }
        }
      }

      // READY, its letters outlined in the same tube, their middle 60% of
      // the way down the sign (PathText puts the top of the letters at y).
      Shape {
        x: sign.pad + 80 * sign.k + 30 * neon.s
        y: sign.pad + 138 * neon.s - word.tightBoundingRect.height / 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: neon.glass
          strokeWidth: sign.tube
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathText { text: word.text; font: word.font }
        }
        ShapePath {
          strokeColor: neon.core
          strokeWidth: sign.wire
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathText { text: word.text; font: word.font }
        }
      }
    }

    // Its light pooling on the floor...
    SoftGlow {
      hue: neon.glass
      x: sign.x + sign.width / 2 - 50
      y: sign.y + sign.floor - 50
      transform: Scale { origin.x: 50; origin.y: 50; xScale: sign.width * 1.2 / 100; yScale: sign.height * 0.3 / 100 }
      opacity: 0.16 * neon.power
    }

    // ...and its reflection: flipped about the floor, squashed, blurred and
    // fading out away from the sign. The fade is drawn unflipped: clear at
    // the top, solid at the floor, nothing below it.
    Item {
      id: floorFade
      width: sign.width
      height: sign.height
      visible: false
      layer.enabled: true

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: sign.floor / sign.height * 0.55; color: Util.alpha("white", 0.2) }
          GradientStop { position: sign.floor / sign.height; color: "white" }
          GradientStop { position: Math.min(1, sign.floor / sign.height + 0.01); color: "transparent" }
        }
      }
    }
    MultiEffect {
      anchors.fill: sign
      source: sign
      transform: Scale { origin.y: sign.floor; yScale: -0.5 }
      autoPaddingEnabled: false
      blurEnabled: true
      blurMax: 24
      blur: 0.6
      maskEnabled: true
      maskSource: floorFade
      opacity: 0.3 * neon.power
    }

    // The glow, wide to tight, and the tubes, crisp, on top of it.
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 64
      blur: 1
      brightness: 0.5
      opacity: neon.power
    }
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 32
      blur: 0.8
      brightness: 0.35
      opacity: neon.power
    }
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 12
      blur: 0.6
      brightness: 0.2
      opacity: neon.power
    }
    MultiEffect {
      anchors.fill: sign
      source: sign
      blurEnabled: true
      blurMax: 4
      blur: 0.2
      opacity: neon.power
    }
  }

  // A soft round glow: `hue` in the middle, fading out to the edge. Drawn at
  // 100 x 100 and sized with `scale`, so it never has to re-tessellate.
  component SoftGlow: Shape {
    id: glow

    property color hue: "white"

    width: 100
    height: 100

    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: 50; centerY: 50; centerRadius: 50
        focalX: 50; focalY: 50
        GradientStop { position: 0.0; color: glow.hue }
        GradientStop { position: 0.3; color: Util.alpha(glow.hue, 0.5) }
        GradientStop { position: 1.0; color: Util.alpha(glow.hue, 0) }
      }
      PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
    }
  }

  // A ring of sparks thrown from a point; `fire()` plays it once.
  component Sparks: Item {
    id: sparks

    property int count: 10
    property real reach: 30
    property real dot: 4 * overlay.u
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
        width: sparks.dot
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
