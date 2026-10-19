import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
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
    "neon": neonComponent,
    "supernova": supernovaComponent,
    "constellation": constellationComponent,
    "fireflies": firefliesComponent,
    "deepsea": deepseaComponent,
    "warp": warpComponent,
    "plasma": plasmaComponent,
    "storm": stormComponent
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
  Component { id: supernovaComponent; Supernova {} }
  Component { id: constellationComponent; Constellation {} }
  Component { id: firefliesComponent; Fireflies {} }
  Component { id: deepseaComponent; DeepSea {} }
  Component { id: warpComponent; Warp {} }
  Component { id: plasmaComponent; Plasma {} }
  Component { id: stormComponent; Storm {} }

  // Repeatable noise in 0..1, so a show scatters its stars the same way
  // every frame without storing them.
  function hash(x) {
    var v = Math.sin(x * 12.9898 + 78.233) * 43758.5453
    return v - Math.floor(v)
  }

  // The profile's colour turned round the colour wheel by `dh` (0-1), at the
  // given saturation and lightness; greys and white count as a cool blue.
  function hueTurn(dh, sat, light) {
    var q = Qt.color(overlay.tint)
    var h = q.hslHue < 0 ? 0.58 : q.hslHue
    return Qt.hsla(((h + dh) % 1 + 1) % 1, sat, light, 1)
  }

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
      ScriptAction { script: { show.count = ""; readyText.pop(); overlay.cue("liftoff"); blastAnim.restart() } }
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
        border.color: Util.alpha(Qt.tint("#ffd9a8", Util.alpha(overlay.tint, 0.4)), modelData.a)
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

    // Hidden by opacity, not `visible`: a hidden layer source whose blobs
    // all start transparent never renders into its layer on Qt 6.12, and
    // the lamp stayed blank.
    Item {
      id: wax
      anchors.fill: parent
      opacity: 0
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
          y: lava.height + size * 0.35 - eased * (lava.height + 1.75 * size)
          color: lava.hues[index % lava.hues.length]
          opacity: p <= 0 || p >= 1 ? 0 : Math.min(1, p / 0.1, (1 - p) / 0.15)
        }
      }
    }

    // Wax: the blobs blurred together, then cut at a threshold so they
    // merge and pull apart with clean, rounded edges, like the real thing.
    // A soft halo of the same wax glows behind it.
    MultiEffect {
      id: waxBlur
      anchors.fill: wax
      source: wax
      visible: false
      layer.enabled: true
      blurEnabled: true
      blurMax: 64
      blur: 1
    }
    MultiEffect {
      anchors.fill: wax
      source: wax
      blurEnabled: true
      blurMax: 64
      blur: 1
      brightness: 0.15
      opacity: 0.35
    }
    MultiEffect {
      anchors.fill: wax
      source: waxBlur
      maskEnabled: true
      maskSource: waxBlur
      maskThresholdMin: 0.42
      maskSpreadAtMin: 0.08
      saturation: 0.15
      opacity: 0.92
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

  // ============================================================ Supernova
  // Deep space falls over the desktop. A star gathers light in a slow
  // spiral and feeds with a heartbeat, collapses to a pinprick, then
  // detonates: a flash, a shockwave, a lens flare across the screen, rays
  // wheeling out of the core, debris and embers flung wide, and a nebula
  // blooming (a glowing shell of gas in the profile's colour and its
  // neighbours, veined with dark dust, star dust glittering in it) while
  // READY condenses out of the light.
  component Supernova: Item {
    id: nova

    property real t: 0
    readonly property real dur: 6.4
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real cx: width * 0.5
    readonly property real cy: height * 0.45
    readonly property real blastAt: 1.9
    // Seconds since the blast; negative before it.
    readonly property real since: now - blastAt
    readonly property real dark: Math.min(1, now / 0.7) * Math.max(0, Math.min(1, (dur - now) / 1.0))
    // How far the remnant has spread: fast at first, then drifting.
    readonly property real spread: since <= 0 ? 0 : 1 - Math.exp(-since / 1.1)
    readonly property var cloud: [overlay.tint, overlay.hueTurn(0.07, 0.95, 0.62), overlay.hueTurn(-0.09, 0.9, 0.55),
      overlay.hueTurn(0.5, 0.85, 0.6), overlay.hueTurn(0.42, 0.8, 0.5), overlay.hueTurn(0.15, 0.9, 0.65)]
    property bool blown: false

    NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: overlay.finished() }
    onSinceChanged: if (since >= 0 && !blown) {
      blown = true
      debris.burst(360)
      embers.burst(70)
      overlay.cue("firework")
    }

    // Deep space, and its far stars.
    Rectangle { anchors.fill: parent; color: "#03020a"; opacity: 0.76 * nova.dark }
    Repeater {
      model: 130
      Rectangle {
        required property int index
        readonly property real a: overlay.hash(index * 1.31)
        readonly property real b: overlay.hash(index * 7.17)
        readonly property real c: overlay.hash(index * 3.3)
        width: (0.8 + 2 * c * c) * nova.s
        height: width
        radius: width / 2
        x: a * nova.width
        y: b * nova.height
        color: index % 5 ? "#dfe6ff" : Qt.lighter(overlay.tint, 1.6)
        opacity: nova.dark * (0.3 + 0.7 * Math.abs(Math.sin(nova.now * (0.7 + 2 * a) + index)))
      }
    }

    // Gathering: motes of light spiralling in to feed the star.
    Repeater {
      model: 80
      Rectangle {
        required property int index
        readonly property real seedA: overlay.hash(index * 2.71)
        readonly property real seedB: overlay.hash(index * 9.13)
        readonly property real start: 0.1 + seedA * 0.9
        readonly property real g: Math.max(0, Math.min(1, (nova.now - start) / (nova.blastAt - 0.2 - start)))
        readonly property real r: (0.14 + 0.36 * seedB) * nova.height * Math.pow(1 - g, 1.5)
        readonly property real a: seedB * 6.283 + (1 - Math.pow(1 - g, 2)) * 5.5
        width: (1.6 + 3 * seedA) * nova.s
        height: width
        radius: width / 2
        x: nova.cx + Math.cos(a) * r - width / 2
        y: nova.cy + Math.sin(a) * r * 0.8 - height / 2
        color: index % 3 ? Qt.lighter(overlay.tint, 1.5) : "#ffffff"
        opacity: g > 0 && g < 1 ? Math.min(1, g * 5) * nova.dark : 0
      }
    }

    // The star: swelling as it feeds, a heartbeat in its light, a pinprick
    // for an instant before the blast.
    readonly property real coreSize: {
      if (since >= 0) return 0
      if (now > blastAt - 0.18) return 3 * s
      var feed = Math.min(1, now / (blastAt - 0.2))
      return (5 + 24 * feed) * s * (1 + 0.2 * Math.sin(now * 13) * feed)
    }
    SoftGlow {
      hue: Qt.lighter(overlay.tint, 1.35)
      x: nova.cx - 50
      y: nova.cy - 50
      scale: nova.coreSize * 5 / 100
      opacity: nova.since < 0 ? nova.dark : 0
    }
    Rectangle {
      width: nova.coreSize
      height: width
      radius: width / 2
      x: nova.cx - width / 2
      y: nova.cy - height / 2
      color: "#ffffff"
      visible: nova.since < 0
    }

    // The nebula, turning slowly, blurred into gas.
    Item {
      anchors.fill: parent
      opacity: nova.since >= 0 ? Math.min(1, nova.since / 0.3) * nova.dark : 0
      transform: Rotation { origin.x: nova.cx; origin.y: nova.cy; angle: 7 * Math.max(0, nova.since) }
      layer.enabled: nova.since >= 0
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 40
        blur: 0.7
        saturation: 0.15
      }

      // A faint glow of hot gas inside, in the profile's colour, darker
      // toward the middle the way a shell nebula is hollow.
      SoftGlow {
        hue: Util.alpha(overlay.tint, 0.3)
        x: nova.cx - 50
        y: nova.cy - 50
        opacity: 0.6
        transform: Scale { origin.x: 50; origin.y: 50; xScale: nova.height * (0.12 + 0.6 * nova.spread) / 100; yScale: nova.height * (0.1 + 0.5 * nova.spread) / 100 }
      }
      // The shell: clumps of glowing gas strung unevenly round the blast
      // front, stretched along it and overlapping, with a second, fainter
      // layer just inside in other colours.
      Repeater {
        model: 44
        SoftGlow {
          required property int index
          readonly property bool inner: index % 3 === 2
          readonly property real a: overlay.hash(index * 2.9) * 6.283
          readonly property real r: nova.height * (0.07 + 0.3 * nova.spread) * (inner ? 0.72 : 1) * (0.78 + 0.44 * overlay.hash(index * 5.3))
          readonly property real len: nova.height * (0.1 + 0.18 * overlay.hash(index * 1.7)) * (0.3 + 0.7 * nova.spread)
          hue: Util.alpha(nova.cloud[(index * 5 + (inner ? 3 : 0)) % nova.cloud.length], inner ? 0.35 : 0.55)
          x: nova.cx + Math.cos(a) * r - 50
          y: nova.cy + Math.sin(a) * r * 0.84 - 50
          opacity: 0.6
          transform: [
            Scale { origin.x: 50; origin.y: 50; xScale: len / 100; yScale: len * (0.28 + 0.2 * overlay.hash(index * 8.1)) / 100 },
            Rotation { origin.x: 50; origin.y: 50; angle: a * 180 / Math.PI + 90 + (overlay.hash(index * 4.4) - 0.5) * 30 }
          ]
        }
      }
      // Dark dust lanes crossing it, for depth.
      Repeater {
        model: 4
        SoftGlow {
          required property int index
          readonly property real a: overlay.hash(index * 7.7) * 6.283
          readonly property real len: nova.height * (0.22 + 0.2 * overlay.hash(index * 3.9)) * nova.spread
          hue: Util.alpha("#020106", 0.7)
          x: nova.cx + Math.cos(a) * nova.height * 0.12 * nova.spread - 50
          y: nova.cy + Math.sin(a) * nova.height * 0.1 * nova.spread - 50
          opacity: 0.6
          transform: [
            Scale { origin.x: 50; origin.y: 50; xScale: len / 100; yScale: len * 0.18 / 100 },
            Rotation { origin.x: 50; origin.y: 50; angle: overlay.hash(index * 9.1) * 180 }
          ]
        }
      }
    }

    // Rays wheeling out of the core.
    Repeater {
      model: 16
      Rectangle {
        required property int index
        readonly property real len: nova.height * (0.22 + 0.32 * overlay.hash(index * 3.7)) * (0.4 + 0.6 * nova.spread)
        x: nova.cx
        y: nova.cy - height / 2
        width: len
        height: (2 + 4 * overlay.hash(index * 1.1)) * nova.s
        radius: height / 2
        rotation: index / 16 * 360 + overlay.hash(index) * 14 + 6 * Math.max(0, nova.since)
        transformOrigin: Item.Left
        opacity: nova.since >= 0 ? 0.5 * Math.min(1, nova.since / 0.15) * Math.max(0, 1 - nova.since / 3.2) * nova.dark : 0
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#ffffff" }
          GradientStop { position: 0.3; color: Util.alpha(Qt.lighter(overlay.tint, 1.6), 0.6) }
          GradientStop { position: 1.0; color: Util.alpha(overlay.tint, 0) }
        }
      }
    }

    // The blast's white heart, and the core left behind, still burning.
    SoftGlow {
      hue: "#ffffff"
      x: nova.cx - 50
      y: nova.cy - 50
      readonly property real f: Math.max(0, Math.min(1, nova.since / 1.6))
      scale: nova.height * (0.12 + 0.3 * Math.sqrt(f)) / 100
      opacity: nova.since >= 0 ? Math.pow(1 - f, 1.6) : 0
    }
    SoftGlow {
      hue: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.3))
      x: nova.cx - 50
      y: nova.cy - 50
      scale: (22 + 4 * Math.sin(nova.now * 9)) * nova.s / 100
      opacity: nova.since >= 0 ? nova.dark : 0
    }

    // The shockwave: a bright thin ring and a soft wide one.
    Repeater {
      model: [{ "w": 0.008, "a": 0.6, "sp": 1.0 }, { "w": 0.05, "a": 0.18, "sp": 0.88 }]
      Rectangle {
        required property var modelData
        readonly property real p: Math.max(0, Math.min(1, nova.since / 1.5))
        readonly property real e: 1 - Math.pow(1 - p, 3)
        width: nova.height * (0.06 + 2.1 * e) * modelData.sp
        height: width
        radius: width / 2
        x: nova.cx - width / 2
        y: nova.cy - height / 2
        color: "transparent"
        border.width: Math.max(1, nova.height * modelData.w * (1 - 0.6 * e))
        border.color: Util.alpha(Qt.lighter(overlay.tint, 1.5), modelData.a)
        opacity: nova.since >= 0 && p < 1 ? Math.pow(1 - p, 1.4) : 0
      }
    }

    // Lens flare: a streak of light across the whole screen through the core.
    Repeater {
      model: [{ "h": 3, "a": 1.0 }, { "h": 40, "a": 0.2 }]
      Rectangle {
        required property var modelData
        readonly property real p: Math.max(0, Math.min(1, nova.since / 1.6))
        width: nova.width * (0.25 + 0.9 * Math.sqrt(p))
        height: modelData.h * nova.s * (1 - 0.5 * p)
        radius: height / 2
        x: nova.cx - width / 2
        y: nova.cy - height / 2
        opacity: nova.since >= 0 ? modelData.a * Math.pow(1 - p, 1.5) : 0
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(overlay.tint, 1.6), 0) }
          GradientStop { position: 0.5; color: "#ffffff" }
          GradientStop { position: 1.0; color: Util.alpha(Qt.lighter(overlay.tint, 1.6), 0) }
        }
      }
    }

    // Debris, embers and star dust.
    Item {
      anchors.fill: parent
      opacity: nova.dark

      ParticleSystem { id: novaSys; anchors.fill: parent }
      ImageParticle {
        system: novaSys
        groups: ["debris"]
        source: Qt.resolvedUrl("particles/glow.png")
        color: Qt.lighter(overlay.tint, 1.45)
        colorVariation: 0.3
        alpha: 0.95
      }
      ImageParticle {
        system: novaSys
        groups: ["embers", "dust"]
        source: Qt.resolvedUrl("particles/spark.png")
        color: Qt.tint("#fff6e8", Util.alpha(overlay.tint, 0.25))
        colorVariation: 0.15
        rotationVariation: 30
        alpha: 1
      }
      Emitter {
        id: debris
        system: novaSys
        group: "debris"
        x: nova.cx - 2; y: nova.cy - 2; width: 4; height: 4
        emitRate: 0
        lifeSpan: 2600; lifeSpanVariation: 900
        size: 9 * nova.s; sizeVariation: 6 * nova.s; endSize: 2 * nova.s
        velocity: AngleDirection { angleVariation: 180; magnitude: 640 * nova.s; magnitudeVariation: 480 * nova.s }
      }
      Emitter {
        id: embers
        system: novaSys
        group: "embers"
        x: nova.cx - 2; y: nova.cy - 2; width: 4; height: 4
        emitRate: 0
        lifeSpan: 3000; lifeSpanVariation: 800
        size: 16 * nova.s; sizeVariation: 8 * nova.s; endSize: 3 * nova.s
        velocity: AngleDirection { angleVariation: 180; magnitude: 360 * nova.s; magnitudeVariation: 260 * nova.s }
      }
      Emitter {
        system: novaSys
        group: "dust"
        x: nova.cx - width / 2; y: nova.cy - height / 2
        width: nova.height * 0.85; height: nova.height * 0.6
        shape: EllipseShape { fill: true }
        emitRate: nova.since >= 0.4 && nova.now < nova.dur - 1.2 ? 42 : 0
        lifeSpan: 1500; lifeSpanVariation: 600
        size: 10 * nova.s; sizeVariation: 7 * nova.s; endSize: 0
        velocity: PointDirection { xVariation: 16 * nova.s; yVariation: 16 * nova.s }
      }
      Friction { system: novaSys; groups: ["debris", "embers"]; factor: 1.8 }
    }

    // READY, condensing out of the light: wide tracking pulling in.
    Item {
      readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (nova.since - 0.6) / 1.3)), 3)
      anchors.horizontalCenter: parent.horizontalCenter
      y: nova.cy + nova.height * 0.27
      width: readyWord.implicitWidth
      height: readyWord.implicitHeight
      opacity: nova.since > 0.6 ? e * nova.dark : 0

      SoftGlow {
        hue: Util.alpha(overlay.tint, 0.28)
        anchors.centerIn: parent
        transform: Scale { origin.x: 50; origin.y: 50; xScale: readyWord.implicitWidth * 1.3 / 100; yScale: readyWord.implicitHeight * 1.3 / 100 }
      }
      Text {
        id: readyWord
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "READY"
        color: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.2))
        font.family: overlay.displayFamily
        font.pixelSize: 56 * nova.s
        font.weight: Font.DemiBold
        font.letterSpacing: (14 + 50 * (1 - parent.e)) * nova.s
      }
    }
  }

  // ========================================================= Constellation
  // Night falls over the desktop: the Milky Way spills across it and its
  // stars come out. Then stars ignite one after another, each with a ripple
  // of light, and draw your Peak Pro between them in fine glowing lines. A
  // shooting star dives in and lights its ring in the profile's colour; the
  // figure fills softly with light, as if it had come alive, and READY
  // appears beside it like a name on a star chart.
  component Constellation: Item {
    id: sky

    property real t: 0
    readonly property real dur: 6.6
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
    // The Peak's outline as stars, on the panel drawing's 80 x 160 grid,
    // going round from the top of the glass. Edge 8 → 9 is the light ring;
    // edge 12 is the glass's chrome seat, drawn last.
    readonly property var pts: [[12.5, 1.5], [21.5, 0.8], [46, 93], [49.5, 80.5], [71, 80.5], [72.5, 104],
      [56, 113.5], [64.5, 152], [60, 158], [9.5, 158], [6.5, 111.5], [9.5, 108]]
    readonly property var edges: [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 0], [11, 2]]
    readonly property real k: height * 0.6 / 160
    readonly property real ox: width * 0.46 - 40 * k
    readonly property real oy: height * 0.48 - 80 * k
    function px(i) { return ox + pts[i][0] * k }
    function py(i) { return oy + pts[i][1] * k }
    function litAt(i) { return 0.8 + i * 0.16 }
    function edgeAt(e) { return e < 12 ? litAt(e) + 0.08 : litAt(11) + 0.35 }
    readonly property real shootAt: litAt(11) + 0.6
    readonly property real shotP: Math.max(0, Math.min(1, (now - shootAt) / 0.5))
    // The ring lighting up once the shooting star lands, and the figure
    // filling with light after it.
    readonly property real ringK: Math.max(0, Math.min(1, (now - shootAt - 0.5) / 0.35))
    readonly property real alive: Math.max(0, Math.min(1, (now - shootAt - 0.7) / 0.9))
    property bool shot: false

    NumberAnimation on t { from: 0; to: 1; duration: 6600; running: true; onFinished: overlay.finished() }
    onRingKChanged: if (ringK > 0 && !shot) { shot = true; overlay.cue("shimmer"); ringSparks.fire() }

    // Night.
    Rectangle {
      anchors.fill: parent
      opacity: sky.dark
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#02030f", 0.9) }
        GradientStop { position: 0.6; color: Util.alpha("#040920", 0.8) }
        GradientStop { position: 1.0; color: Util.alpha("#060c26", 0.62) }
      }
    }

    // The Milky Way: a faint, misty river of light across the sky, veined
    // with dark dust and thick with stars.
    Item {
      anchors.fill: parent
      opacity: sky.dark * Math.min(1, sky.now / 1.4)
      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 48; blur: 0.8 }
        Repeater {
          model: 16
          SoftGlow {
            required property int index
            readonly property real f: overlay.hash(index * 3.7)
            hue: Util.alpha(index % 4 === 1 ? "#a99cff" : "#b8c8ff", 0.09 + 0.07 * overlay.hash(index * 1.3))
            x: sky.width * (-0.05 + 1.1 * f) + (overlay.hash(index * 6.1) - 0.5) * sky.height * 0.05 - 50
            y: sky.height * (0.85 - 0.75 * f) + (overlay.hash(index * 5.3) - 0.5) * sky.height * 0.1 - 50
            transform: [
              Scale { origin.x: 50; origin.y: 50; xScale: sky.width * (0.16 + 0.18 * overlay.hash(index * 2.9)) / 100; yScale: sky.height * (0.1 + 0.14 * overlay.hash(index * 7.3)) / 100 },
              Rotation { origin.x: 50; origin.y: 50; angle: -34 + (overlay.hash(index * 8.8) - 0.5) * 16 }
            ]
          }
        }
        Repeater {
          model: 5
          SoftGlow {
            required property int index
            readonly property real f: 0.12 + index * 0.19 + (overlay.hash(index * 4.1) - 0.5) * 0.08
            hue: Util.alpha("#010208", 0.45)
            x: sky.width * (-0.05 + 1.1 * f) - 50
            y: sky.height * (0.85 - 0.75 * f) - 50
            transform: [
              Scale { origin.x: 50; origin.y: 50; xScale: sky.width * 0.14 / 100; yScale: sky.height * 0.025 / 100 },
              Rotation { origin.x: 50; origin.y: 50; angle: -30 }
            ]
          }
        }
      }
      Repeater {
        model: 260
        Rectangle {
          required property int index
          readonly property real f: overlay.hash(index * 2.17)
          // Gathered close about the river's middle, thinning out from it.
          readonly property real off: (overlay.hash(index * 6.61) + overlay.hash(index * 9.03) - 1) * sky.height * 0.16
          width: (0.7 + 1.3 * overlay.hash(index * 4.4)) * sky.s
          height: width
          radius: width / 2
          x: sky.width * (-0.05 + 1.1 * f) + off * 0.56
          y: sky.height * (0.85 - 0.75 * f) + off * 0.83
          color: "#e0e7ff"
          opacity: 0.25 + 0.6 * Math.abs(Math.sin(sky.now * (1 + overlay.hash(index)) + index))
        }
      }
    }

    // Far stars, coming out one by one and twinkling, a few of them big.
    Repeater {
      model: 120
      Item {
        required property int index
        readonly property real a: overlay.hash(index * 1.77)
        readonly property real b: overlay.hash(index * 5.03)
        readonly property real c: overlay.hash(index * 9.41)
        readonly property bool big: index % 12 === 0
        readonly property real twinkle: 0.3 + 0.7 * Math.abs(Math.sin(sky.now * (0.8 + 2.2 * a) + index * 1.3))
        x: a * sky.width
        y: b * sky.height * 0.92
        opacity: sky.dark * Math.min(1, Math.max(0, (sky.now - c * 1.2) / 0.6)) * twinkle

        Rectangle {
          width: (1 + 2 * c * c) * sky.s
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: c > 0.85 ? "#fff1d6" : "#dbe5ff"
        }
        Image {
          visible: parent.big
          source: Qt.resolvedUrl("particles/spark.png")
          width: (16 + 10 * parent.twinkle) * sky.s
          height: width
          x: -width / 2
          y: -height / 2
          smooth: true
        }
      }
    }

    // The figure filling with light, once it's alive.
    Shape {
      anchors.fill: parent
      opacity: 0.22 * sky.alive * sky.dark
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: sky.py(0); x2: 0; y2: sky.py(8)
          GradientStop { position: 0.0; color: Util.alpha("#bcd0ff", 0.4) }
          GradientStop { position: 1.0; color: overlay.tint }
        }
        PathPolyline {
          path: {
            var out = []
            for (var i = 0; i <= sky.pts.length; i++) out.push(Qt.point(sky.px(i % sky.pts.length), sky.py(i % sky.pts.length)))
            return out
          }
        }
      }
    }

    // The lines between the stars, drawing themselves once both ends burn.
    Repeater {
      model: sky.edges.length
      Item {
        required property int index
        readonly property int i0: sky.edges[index][0]
        readonly property int i1: sky.edges[index][1]
        readonly property real x0: sky.px(i0)
        readonly property real y0: sky.py(i0)
        readonly property real x1: sky.px(i1)
        readonly property real y1: sky.py(i1)
        readonly property real len: Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
        readonly property real p: Math.max(0, Math.min(1, (sky.now - sky.edgeAt(index)) / 0.32))
        readonly property bool ring: index === 8
        readonly property color ink: ring ? Qt.tint("#cfdcff", Util.alpha(overlay.tint, sky.ringK))
          : Qt.tint("#cfdcff", Util.alpha(overlay.tint, 0.35 * sky.alive))
        x: x0
        y: y0
        rotation: Math.atan2(y1 - y0, x1 - x0) * 180 / Math.PI
        transformOrigin: Item.TopLeft
        opacity: sky.dark * (index === 12 ? 0.7 : 1)

        Rectangle {
          y: -height / 2
          width: parent.len * parent.p
          height: (parent.ring ? 10 + 16 * sky.ringK : 9) * sky.s
          radius: height / 2
          color: Util.alpha(parent.ink, parent.ring ? 0.2 + 0.25 * sky.ringK : 0.17 + 0.08 * sky.alive)
        }
        Rectangle {
          y: -height / 2
          width: parent.len * parent.p
          height: (parent.ring ? 2 + 2.4 * sky.ringK : 1.7) * sky.s
          radius: height / 2
          color: parent.ink
        }
      }
    }

    // Light pooling under the ring once it's lit.
    SoftGlow {
      hue: overlay.tint
      x: (sky.px(8) + sky.px(9)) / 2 - 50
      y: sky.py(8) - 50
      opacity: 0.5 * sky.ringK * sky.dark
      transform: Scale { origin.x: 50; origin.y: 50; xScale: (sky.px(8) - sky.px(9)) * 1.9 / 100; yScale: 70 * sky.s / 100 }
    }

    // The stars themselves: a ripple and a flare as each ignites, then a
    // steady twinkle.
    Repeater {
      model: 12
      Item {
        required property int index
        readonly property real f: Math.max(0, Math.min(1, (sky.now - sky.litAt(index)) / 0.6))
        readonly property real flare: f <= 0 ? 0 : (f < 0.2 ? f / 0.2 : 1 - 0.72 * (f - 0.2) / 0.8)
        x: sky.px(index)
        y: sky.py(index)
        opacity: f > 0 ? sky.dark : 0

        Rectangle {
          readonly property real rp: Math.min(1, parent.f * 1.4)
          width: (10 + 90 * rp) * sky.s
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: "transparent"
          border.width: Math.max(1, 1.4 * sky.s)
          border.color: Util.alpha("#cfdcff", 0.7)
          opacity: rp < 1 ? Math.pow(1 - rp, 1.5) : 0
        }
        SoftGlow {
          hue: Util.alpha(Qt.tint("#bcd0ff", Util.alpha(overlay.tint, 0.5 * sky.alive)), 0.75)
          x: -50
          y: -50
          scale: (18 + 44 * parent.flare + 8 * sky.alive) * sky.s / 100
        }
        Image {
          source: Qt.resolvedUrl("particles/spark.png")
          width: (16 + 56 * parent.flare + 6 * Math.sin(sky.now * 5 + parent.index)) * sky.s
          height: width
          x: -width / 2
          y: -height / 2
          rotation: 40 * (1 - parent.f)
          smooth: true
        }
        Rectangle {
          width: 4.5 * sky.s
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: "#ffffff"
        }
      }
    }

    // The shooting star, diving in from the top right to the end of the ring.
    Item {
      id: comet
      readonly property real sx: sky.width * 0.97
      readonly property real sy: sky.height * 0.02
      readonly property real ex: sky.px(8)
      readonly property real ey: sky.py(8)
      readonly property real e: sky.shotP * sky.shotP
      x: sx + (ex - sx) * e
      y: sy + (ey - sy) * e
      visible: sky.shotP > 0 && sky.shotP < 1
      rotation: Math.atan2(ey - sy, ex - sx) * 180 / Math.PI

      Rectangle {
        x: -width
        y: -height / 2
        width: 420 * sky.s
        height: 14 * sky.s
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha(overlay.tint, 0) }
          GradientStop { position: 1.0; color: Util.alpha(Qt.lighter(overlay.tint, 1.5), 0.35) }
        }
      }
      Rectangle {
        x: -width
        y: -height / 2
        width: 380 * sky.s
        height: 3.5 * sky.s
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0) }
          GradientStop { position: 1.0; color: "#ffffff" }
        }
      }
      SoftGlow { hue: "#ffffff"; x: -50; y: -50; scale: 40 * sky.s / 100 }
    }
    Sparks {
      id: ringSparks
      x: sky.px(8)
      y: sky.py(8)
      count: 16
      reach: 90 * sky.s
      dot: 4.5 * sky.s
      hues: ["#ffffff", Qt.lighter(overlay.tint, 1.5), overlay.tint]
    }

    // READY, like a name on a star chart.
    Text {
      readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (sky.now - sky.shootAt - 0.8) / 1.0)), 3)
      x: sky.px(5) + 54 * sky.s
      y: sky.py(5) - height / 2
      opacity: e * sky.dark
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#e4ecff", Util.alpha(overlay.tint, 0.35))
      font.family: overlay.displayFamily
      font.pixelSize: 44 * sky.s
      font.weight: Font.DemiBold
      font.letterSpacing: (10 + 26 * (1 - e)) * sky.s
    }
  }

  // ============================================================= Fireflies
  // A swarm of fireflies pours out of the bar and wheels across the screen
  // like a murmuration. They gather into the shape of your Peak Pro and
  // flash together, its ring in the profile's colour, then scatter into the
  // dark and wink out.
  component Fireflies: Item {
    id: ff

    property real t: 0
    readonly property real dur: 6.8
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property int count: 150
    readonly property real dark: Math.min(1, now / 0.6) * Math.max(0, Math.min(1, (dur - now) / 0.8))
    readonly property real k: height * 0.58 / 160
    readonly property real ox: width * 0.5 - 40 * k
    readonly property real oy: height * 0.49 - 80 * k
    readonly property real formAt: 2.6
    readonly property real holdAt: 3.8
    readonly property real scatterAt: 5.2
    // Where each firefly lands: points spread evenly round the Peak's
    // outline (and the glass's chrome seat), the light ring's flagged.
    readonly property var targets: {
      var P = [[12.5, 1.5], [21.5, 0.8], [46, 93], [49.5, 80.5], [71, 80.5], [72.5, 104],
               [56, 113.5], [64.5, 152], [60, 158], [9.5, 158], [6.5, 111.5], [9.5, 108]]
      var segs = []
      for (var i = 0; i < P.length; i++) segs.push([P[i], P[(i + 1) % P.length], i === 8])
      segs.push([[9.5, 108], [46, 93], false])
      var total = 0
      for (i = 0; i < segs.length; i++) {
        var dx = segs[i][1][0] - segs[i][0][0], dy = segs[i][1][1] - segs[i][0][1]
        segs[i].push(Math.sqrt(dx * dx + dy * dy))
        total += segs[i][3]
      }
      var out = []
      for (var n = 0; n < count; n++) {
        var d = n / count * total, g = 0
        while (g < segs.length - 1 && d > segs[g][3]) { d -= segs[g][3]; g++ }
        var f = segs[g][3] > 0 ? d / segs[g][3] : 0
        out.push([segs[g][0][0] + (segs[g][1][0] - segs[g][0][0]) * f, segs[g][0][1] + (segs[g][1][1] - segs[g][0][1]) * f, segs[g][2]])
      }
      return out
    }
    // The swarm's heart wanders the middle of the screen.
    readonly property real flockX: width * (0.5 + 0.17 * Math.sin(now * 0.8 + 0.4))
    readonly property real flockY: height * (0.45 + 0.12 * Math.sin(now * 1.25))
    readonly property real turn: now * 0.55
    readonly property real aspect: 0.42 + 0.22 * Math.sin(now * 0.9)
    // Once they're in shape, light chases round the outline; then, just
    // before they scatter, they all flash together.
    readonly property real flashAt: scatterAt - 0.55
    function glow(index) {
      if (now > flashAt) return 0.6 + 0.4 * Math.sin(Math.min(1, (now - flashAt) / 0.5) * Math.PI)
      return 0.4 + 0.6 * Math.pow(0.5 + 0.5 * Math.sin(now * 5.5 - index * 0.22), 3)
    }

    NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: overlay.finished() }
    Component.onCompleted: overlay.cue("shimmer")

    Rectangle { anchors.fill: parent; color: "#02060a"; opacity: 0.7 * ff.dark }

    // Drawn once through a bloom, once crisp: the glow is the point.
    Item {
      id: swarm
      anchors.fill: parent
      opacity: 0
      layer.enabled: true

      Repeater {
        model: ff.count
        Item {
          id: fly
          required property int index
          readonly property real a: overlay.hash(index * 1.37)
          readonly property real b: overlay.hash(index * 4.91)
          readonly property real c: overlay.hash(index * 8.29)
          readonly property var target: ff.targets[index]
          readonly property real tx: ff.ox + target[0] * ff.k
          readonly property real ty: ff.oy + target[1] * ff.k
          // Out of the bar, into the swarm.
          readonly property real pe: 1 - Math.pow(1 - Math.max(0, Math.min(1, (ff.now - a * 0.9) / 1.0)), 3)
          readonly property real ang: c * 6.283 + ff.now * (0.9 + 0.9 * a) * (index % 3 ? 1 : -1)
          // The flock ripples (lobes running round it), breathes and turns.
          readonly property real rad: (50 + 240 * b) * ff.s * (0.72 + 0.3 * Math.sin(ang * 3 + ff.now * 2.2) + 0.15 * Math.sin(ff.now * 1.3 + index * 0.1))
          readonly property real lx: Math.cos(ang) * rad
          readonly property real ly: Math.sin(ang) * rad * ff.aspect
          readonly property real fx: ff.flockX + lx * Math.cos(ff.turn) - ly * Math.sin(ff.turn)
          readonly property real fy: ff.flockY + lx * Math.sin(ff.turn) + ly * Math.cos(ff.turn)
          readonly property real sx: overlay.originX + (fx - overlay.originX) * pe
          readonly property real sy: overlay.barEdge + (fy - overlay.barEdge) * pe
          // Into the Peak's shape.
          readonly property real pfRaw: Math.max(0, Math.min(1, (ff.now - ff.formAt - c * 0.45) / 1.0))
          readonly property real pf: pfRaw < 0.5 ? 2 * pfRaw * pfRaw : 1 - Math.pow(-2 * pfRaw + 2, 2) / 2
          readonly property real hx: sx + (tx - sx) * pf + Math.sin(ff.now * 3 + index) * 3 * ff.s * pf
          readonly property real hy: sy + (ty - sy) * pf + Math.cos(ff.now * 2.6 + index) * 3 * ff.s * pf
          // Away into the dark.
          readonly property real ps: Math.max(0, Math.min(1, (ff.now - ff.scatterAt - b * 0.3) / 1.3))
          readonly property real ex: (tx - ff.width * 0.5) * 0.004 + (a - 0.5)
          readonly property real ey: -0.6 - b
          readonly property real blink: ff.now > ff.holdAt - 0.2 && ps === 0
            ? ff.glow(index)
            : 0.35 + 0.65 * Math.pow(0.5 + 0.5 * Math.sin(ff.now * (2.5 + 3 * a) + index * 2.1), 3)
          readonly property color hue: target[2] && pf > 0 ? Qt.tint("#efff8a", Util.alpha(overlay.tint, pf))
            : (index % 4 === 0 ? "#fff1a8" : "#e2ff76")
          x: hx + ex * 420 * ff.s * Math.pow(ps, 1.4)
          y: hy + ey * 260 * ff.s * Math.pow(ps, 1.4)
          opacity: (ff.now > a * 0.9 ? 1 : 0) * blink * (1 - ps)

          Rectangle {
            width: 26 * ff.s
            height: width
            radius: width / 2
            x: -width / 2
            y: -height / 2
            color: Util.alpha(fly.hue, 0.22)
          }
          Rectangle {
            width: (3 + 2 * fly.c) * ff.s
            height: width
            radius: width / 2
            x: -width / 2
            y: -height / 2
            color: Qt.lighter(fly.hue, 1.25)
          }
        }
      }
    }

    MultiEffect {
      anchors.fill: swarm
      source: swarm
      blurEnabled: true
      blurMax: 40
      blur: 0.9
      brightness: 0.35
      opacity: ff.dark
    }
    MultiEffect {
      anchors.fill: swarm
      source: swarm
      opacity: ff.dark
    }

    // READY, in the shows' common lockup.
    Text {
      readonly property real e: Math.max(0, Math.min(1, (ff.now - ff.holdAt) / 0.3)) * Math.max(0, Math.min(1, (ff.scatterAt + 0.6 - ff.now) / 0.5))
      anchors.horizontalCenter: parent.horizontalCenter
      y: ff.oy + 160 * ff.k + 22 * ff.s + (1 - Math.min(1, Math.max(0, (ff.now - ff.holdAt) / 0.3))) * 12 * ff.s
      opacity: 0.92 * e
      visible: e > 0
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha("#ffe9a0", 0.35))
      font.family: overlay.displayFamily
      font.pixelSize: 64 * ff.s
      font.weight: Font.DemiBold
      font.letterSpacing: 15 * ff.s
    }
  }

  // ============================================================== Deep sea
  // The desktop sinks underwater: light ripples down from the surface,
  // plankton glitters, bubbles wobble up, whale sharks cruise past (one huge
  // and close, one far off in the blue), and bioluminescent jellyfish rise
  // out of the deep, their bells pulsing (each beat a push upward) and their
  // tentacles trailing, in the profile's colour, cyan and violet.
  component DeepSea: Item {
    id: sea

    property real t: 0
    readonly property real dur: 6.8
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
    readonly property var hues: [overlay.tint, "#58f0ff", "#b38cff", Qt.lighter(overlay.tint, 1.4), "#7affd2", "#ff8ad8"]

    NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: overlay.finished() }
    Component.onCompleted: overlay.cue("deep")

    // The water, darker the deeper it goes.
    Rectangle {
      anchors.fill: parent
      opacity: sea.dark
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#003048", 0.6) }
        GradientStop { position: 0.5; color: Util.alpha("#00182c", 0.74) }
        GradientStop { position: 1.0; color: Util.alpha("#000710", 0.88) }
      }
    }

    // Whale sharks: one far off in the blue, small and hazy, cruising the
    // other way; one close by, gliding slowly across the whole scene behind
    // the jellyfish, the light shafts falling across its back.
    WhaleShark {
      len: sea.width * 0.27
      haze: 0.68
      facing: -1
      swim: sea.now * 1.15
      pitch: 1.5 * Math.sin(sea.now * 0.5)
      x: sea.width * (1.12 - 0.62 * sea.now / sea.dur)
      y: sea.height * 0.27 + Math.sin(sea.now * 0.7) * 6 * sea.s
      opacity: 0.8 * sea.dark
    }
    WhaleShark {
      readonly property real p: Math.max(0, (sea.now - 0.15) / (sea.dur - 0.15))
      len: sea.width * 0.6
      haze: 0.12
      facing: 1
      swim: sea.now
      pitch: 2.5 + 1.2 * Math.sin(sea.now * 0.6)
      x: -len * 0.45 + (sea.width + len * 0.2) * p
      y: sea.height * (0.6 - 0.08 * p) + Math.sin(sea.now * 0.55) * 10 * sea.s
      opacity: Math.min(1, sea.now / 0.6) * sea.dark
    }

    // Light from the surface, in slow swaying shafts.
    Repeater {
      model: 8
      Rectangle {
        required property int index
        readonly property real a: overlay.hash(index * 3.17)
        readonly property real b: overlay.hash(index * 7.71)
        width: (50 + 130 * a) * sea.s
        height: sea.height * 0.95
        x: sea.width * (0.06 + 0.88 * b) - width / 2 + Math.sin(sea.now * 0.5 + index) * 30 * sea.s
        y: -sea.height * 0.04
        rotation: (b - 0.5) * 26 + Math.sin(sea.now * 0.45 + index * 1.3) * 3
        transformOrigin: Item.Top
        opacity: sea.dark * (0.55 + 0.45 * Math.sin(sea.now * 0.9 + index * 1.7))
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha("#a6ecff", 0.17) }
          GradientStop { position: 0.55; color: Util.alpha("#a6ecff", 0.05) }
          GradientStop { position: 1.0; color: Util.alpha("#a6ecff", 0) }
        }
      }
    }

    // Plankton glittering as it drifts.
    Item {
      anchors.fill: parent
      opacity: sea.dark
      ParticleSystem { id: seaSys; anchors.fill: parent }
      ImageParticle {
        system: seaSys
        source: Qt.resolvedUrl("particles/glow.png")
        color: "#8af4ff"
        colorVariation: 0.25
        alpha: 0.85
        alphaVariation: 0.4
      }
      Emitter {
        system: seaSys
        anchors.fill: parent
        emitRate: sea.now < sea.dur - 1.4 ? 55 : 0
        lifeSpan: 2600; lifeSpanVariation: 1000
        size: 7 * sea.s; sizeVariation: 5 * sea.s; endSize: 1 * sea.s
        velocity: PointDirection { y: -14 * sea.s; xVariation: 10 * sea.s; yVariation: 10 * sea.s }
      }
      Wander { system: seaSys; xVariance: 40 * sea.s; pace: 60 * sea.s }
    }

    // Bubbles wobbling up to the surface.
    Repeater {
      model: 16
      Rectangle {
        required property int index
        readonly property real a: overlay.hash(index * 5.9)
        readonly property real b: overlay.hash(index * 2.3)
        readonly property real p: ((sea.now * (0.16 + 0.12 * a)) + b) % 1
        width: (5 + 12 * a) * sea.s
        height: width
        radius: width / 2
        x: sea.width * (0.05 + 0.9 * overlay.hash(index * 9.7)) + Math.sin(p * 18 + index) * 8 * sea.s
        y: sea.height * (1.05 - 1.15 * p)
        color: Util.alpha("#c8f6ff", 0.06)
        border.width: Math.max(1, 1.2 * sea.s)
        border.color: Util.alpha("#c8f6ff", 0.5)
        opacity: sea.dark * Math.min(1, p / 0.1)
      }
    }

    // The jellyfish, drawn through a bloom.
    Item {
      id: deep
      anchors.fill: parent
      opacity: 0
      layer.enabled: true

      Repeater {
        model: 11
        Item {
          id: jelly
          required property int index
          // The first few are far off: small, faint and slow, behind the rest.
          readonly property bool far: index < 5
          readonly property real a: overlay.hash(index * 2.31)
          readonly property real b: overlay.hash(index * 6.07)
          readonly property color hue: sea.hues[index % sea.hues.length]
          readonly property real size: (78 + 86 * a) * sea.s * (far ? 0.42 : 1)
          readonly property real period: 1.25 + 0.55 * b
          readonly property real start: (far ? index * 0.2 : (index - 5) * 0.3) + a * 0.25
          readonly property real life: Math.max(0, sea.now - start)
          readonly property real beat: life / period
          readonly property real phase: beat - Math.floor(beat)
          // A beat: a quick squeeze, then a long relax.
          readonly property real squeeze: phase < 0.28 ? Math.sin(phase / 0.28 * Math.PI / 2) : Math.cos((phase - 0.28) / 0.72 * Math.PI / 2)
          // Each squeeze is a push upward, on top of a slow drift.
          readonly property real push: Math.floor(beat) + (1 - Math.pow(1 - Math.min(1, phase / 0.4), 2))
          readonly property real climb: (48 * life + (115 + 60 * b) * push) * sea.s * (far ? 0.5 : 1)
          readonly property real w: size / 2 * (1 - 0.2 * squeeze)
          readonly property real h: size * 0.5 * (1 + 0.24 * squeeze)
          x: sea.width * (0.08 + 0.84 * ((index * 0.37 + a * 0.31) % 1)) + Math.sin(life * 0.6 + index) * 46 * sea.s
          y: sea.height + size * 0.6 - climb
          rotation: Math.sin(life * 0.8 + index * 2) * 8
          opacity: (life > 0 ? Math.min(1, life / 0.5) : 0) * (far ? 0.45 : 1)

          // Tentacles: trailing, bunching on each squeeze, a wave running
          // down them; brighter near the bell.
          Repeater {
            model: 6
            Shape {
              id: tentacle
              required property int index
              readonly property real rootX: -jelly.w * 0.78 + index * (jelly.w * 1.56 / 5)
              readonly property real len: jelly.size * (1.3 + 0.8 * overlay.hash(jelly.index * 3.1 + index))
              preferredRendererType: Shape.CurveRenderer
              function wave(lo, hi) {
                var out = []
                for (var k = lo; k <= hi; k++) {
                  var f = k / 10
                  out.push(Qt.point(rootX * (1 + 0.3 * f * jelly.squeeze) + Math.sin(k * 0.8 - jelly.life * 4 + index * 1.4) * 11 * sea.s * f,
                                    jelly.h * 0.08 + len * f * (1 - 0.16 * jelly.squeeze)))
                }
                return out
              }
              ShapePath {
                strokeColor: Util.alpha(Qt.lighter(jelly.hue, 1.2), 0.75)
                strokeWidth: 1.6 * sea.s
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: tentacle.wave(0, 5) }
              }
              ShapePath {
                strokeColor: Util.alpha(jelly.hue, 0.32)
                strokeWidth: 1.2 * sea.s
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: tentacle.wave(5, 10) }
              }
            }
          }

          // The bell: a dome over a scalloped rim, glowing from inside.
          Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeColor: Util.alpha(Qt.lighter(jelly.hue, 1.35), 0.9)
              strokeWidth: 1.7 * sea.s
              joinStyle: ShapePath.RoundJoin
              fillGradient: RadialGradient {
                centerX: 0; centerY: -jelly.h * 0.45; centerRadius: jelly.w * 1.15
                focalX: 0; focalY: -jelly.h * 0.6
                GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(jelly.hue, 1.5), 0.6) }
                GradientStop { position: 0.6; color: Util.alpha(jelly.hue, 0.28) }
                GradientStop { position: 1.0; color: Util.alpha(jelly.hue, 0.1) }
              }
              PathSvg {
                path: {
                  var w = jelly.w, h = jelly.h
                  return "M " + (-w) + " 0 C " + (-w) + " " + (-h * 1.3) + " " + w + " " + (-h * 1.3) + " " + w + " 0"
                    + " Q " + (w * 0.75) + " " + (h * 0.2) + " " + (w * 0.5) + " " + (h * 0.06)
                    + " Q " + (w * 0.25) + " " + (h * 0.22) + " 0 " + (h * 0.08)
                    + " Q " + (-w * 0.25) + " " + (h * 0.22) + " " + (-w * 0.5) + " " + (h * 0.06)
                    + " Q " + (-w * 0.75) + " " + (h * 0.2) + " " + (-w) + " 0 Z"
                }
              }
            }
          }
          // Its glowing heart, brightest at the end of each squeeze.
          SoftGlow {
            hue: Qt.lighter(jelly.hue, 1.5)
            x: -50
            y: -jelly.h * 0.5 - 50
            scale: jelly.w * (0.9 + 0.3 * jelly.squeeze) / 100
            opacity: 0.55 + 0.35 * jelly.squeeze
          }
          // Lights along the rim.
          Repeater {
            model: 7
            Rectangle {
              required property int index
              width: 3.2 * sea.s
              height: width
              radius: width / 2
              x: -jelly.w + index * (2 * jelly.w / 6) - width / 2
              y: (index % 2 ? jelly.h * 0.1 : 0) - height / 2
              color: Qt.lighter(jelly.hue, 1.6)
              opacity: 0.6 + 0.4 * Math.sin(sea.now * 6 + index + jelly.index)
            }
          }
        }
      }
    }

    MultiEffect {
      anchors.fill: deep
      source: deep
      blurEnabled: true
      blurMax: 48
      blur: 0.85
      brightness: 0.3
      opacity: sea.dark
    }
    MultiEffect {
      anchors.fill: deep
      source: deep
      opacity: sea.dark
    }

    // READY, in the shows' common lockup.
    Text {
      readonly property real e: Math.max(0, Math.min(1, (sea.now - 1.4) / 0.3)) * Math.max(0, Math.min(1, (sea.dur - 0.9 - sea.now) / 0.5))
      anchors.horizontalCenter: parent.horizontalCenter
      y: sea.height * 0.6 + (1 - Math.min(1, Math.max(0, (sea.now - 1.4) / 0.3))) * 12 * sea.s
      opacity: 0.92 * e
      visible: e > 0
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha("#9ff4ff", 0.3))
      font.family: overlay.displayFamily
      font.pixelSize: 64 * sea.s
      font.weight: Font.DemiBold
      font.letterSpacing: 15 * sea.s
    }
  }

  // ================================================================== Warp
  // The screen falls into space and the stars stretch into hyperspace,
  // faster and faster, out of a point in the middle. Then it drops out of
  // warp, and a spiral galaxy hangs there, tilted toward you: a blazing core,
  // arms of stars and glowing dust in the profile's colour winding round it
  // as it turns (the inner stars faster than the outer ones), with READY
  // under it.
  component Warp: Item {
    id: warp

    property real t: 0
    readonly property real dur: 6.8
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real cx: width * 0.5
    readonly property real cy: height * 0.45
    readonly property real dark: Math.min(1, now / 0.5) * Math.max(0, Math.min(1, (dur - now) / 1.0))
    readonly property real dropAt: 1.8
    readonly property real since: now - dropAt
    // How far through the stars: the speed building as the square of time
    // until the drop, then braking hard.
    readonly property real travelled: {
      var a = 0.22, b = 2.4
      if (now < dropAt) return a * now + b * now * now * now / (3 * dropAt * dropAt)
      var atDrop = a * dropAt + b * dropAt / 3
      var brake = Math.min(since, 0.35)
      return atDrop + (a + b) * (brake - brake * brake / (2 * 0.35))
    }
    readonly property real speed: now < dropAt ? 0.22 + 2.4 * Math.pow(now / dropAt, 2) : Math.max(0, 2.62 * (1 - since / 0.35))
    readonly property real galaxyIn: Math.max(0, Math.min(1, since / 2.0))
    readonly property real grow: 0.35 + 0.65 * (1 - Math.pow(1 - galaxyIn, 3))
    // The disc's tilt: squashed to this fraction top to bottom, then turned.
    readonly property real tilt: 0.38
    readonly property real lean: -18 * Math.PI / 180
    readonly property real rMin: height * 0.03
    readonly property real rMax: height * 0.46

    // Where a point on the disc (polar, in the disc's own plane) lands on
    // screen, and how near the viewer it is (0 back, 1 front).
    function sx(a, r) { var x = Math.cos(a) * r * grow, y = Math.sin(a) * r * grow * tilt; return cx + x * Math.cos(lean) - y * Math.sin(lean) }
    function sy(a, r) { var x = Math.cos(a) * r * grow, y = Math.sin(a) * r * grow * tilt; return cy + x * Math.sin(lean) + y * Math.cos(lean) }
    // Turned by now: the inner disc faster than the outer.
    function spin(r) { return Math.max(0, since) * (0.18 + 0.75 * rMin * 3 / Math.max(r, rMin)) }

    NumberAnimation on t { from: 0; to: 1; duration: 6800; running: true; onFinished: overlay.finished() }
    // One cue for the whole trip: the drive spooling up, the drop, the galaxy.
    Component.onCompleted: overlay.cue("warp")

    Rectangle { anchors.fill: parent; color: "#010208"; opacity: 0.8 * warp.dark }

    // Hyperspace: streaks rushing out of the vanishing point.
    Repeater {
      model: 170
      Rectangle {
        required property int index
        readonly property real ang: overlay.hash(index * 1.91) * 6.283
        readonly property real rate: 0.6 + 0.8 * overlay.hash(index * 4.37)
        readonly property real u: (overlay.hash(index * 8.53) + warp.travelled * rate) % 1
        readonly property real reach: Math.max(warp.width, warp.height) * 0.75
        readonly property real r: (0.02 + 0.98 * u * u) * reach
        readonly property real streak: Math.max(2 * warp.s, warp.speed * r * 0.28)
        x: warp.cx + Math.cos(ang) * r
        y: warp.cy + Math.sin(ang) * r - height / 2
        width: streak
        height: (1 + 1.6 * u) * warp.s
        radius: height / 2
        rotation: ang * 180 / Math.PI
        transformOrigin: Item.Left
        opacity: warp.dark * Math.min(1, u * 3) * (warp.since < 0 ? 1 : Math.max(0, 1 - warp.since / 0.8))
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha("#cfe0ff", 0) }
          GradientStop { position: 1.0; color: index % 6 ? "#e8f0ff" : Qt.lighter(overlay.tint, 1.5) }
        }
      }
    }

    // Dropping out of warp: a bloom of light from the middle.
    SoftGlow {
      hue: Qt.lighter(overlay.tint, 1.8)
      x: warp.cx - 50
      y: warp.cy - 50
      readonly property real f: Math.max(0, Math.min(1, warp.since / 0.7))
      scale: warp.height * (0.3 + 1.2 * f) / 100
      opacity: warp.since >= 0 ? 0.55 * Math.pow(1 - f, 2) : 0
    }

    // The galaxy, drawn through a bloom.
    Item {
      id: space
      anchors.fill: parent
      opacity: 0
      layer.enabled: true

      Item {
        anchors.fill: parent
        opacity: warp.galaxyIn > 0 ? Math.min(1, warp.since / 0.7) : 0

        // A faint halo, and the dust of the arms: soft clouds laid along
        // the spirals, squashed and turned with the disc.
        Item {
          x: warp.cx
          y: warp.cy
          transform: [
            Scale { xScale: warp.grow; yScale: warp.grow * warp.tilt },
            Rotation { angle: warp.lean * 180 / Math.PI }
          ]
          SoftGlow { hue: Util.alpha("#8ea6ff", 0.09); x: -50; y: -50; scale: warp.rMax * 2.4 / 100 }
          Repeater {
            model: 52
            SoftGlow {
              required property int index
              readonly property real rr: warp.rMin * 2 + (warp.rMax - warp.rMin * 2) * Math.pow(overlay.hash(index * 3.3), 0.8)
              readonly property real a: (index % 2) * Math.PI + Math.log(rr / warp.rMin) * 2.1 + warp.spin(rr)
                + (overlay.hash(index * 6.7) - 0.5) * 0.45
              // Blue-white starlight, with knots of the profile's colour
              // where new stars are being born.
              hue: index % 4 === 0 ? Util.alpha(Qt.lighter(overlay.tint, 1.25), 0.32)
                : Util.alpha(index % 2 ? "#a9bdff" : "#d4dcff", 0.2)
              x: Math.cos(a) * rr - 50
              y: Math.sin(a) * rr - 50
              transform: [
                Scale { origin.x: 50; origin.y: 50; xScale: (26 + rr * 0.3) / 100; yScale: (12 + rr * 0.1) / 100 },
                Rotation { origin.x: 50; origin.y: 50; angle: a * 180 / Math.PI + 70 }
              ]
            }
          }
        }

        // The stars, each placed on the disc and projected, so they stay
        // round however the disc leans; nearer ones a touch bigger.
        Repeater {
          model: 520
          Rectangle {
            required property int index
            readonly property real q: overlay.hash(index * 1.37)
            readonly property real rr: warp.rMin + (warp.rMax - warp.rMin) * Math.sqrt(q)
            readonly property int arm: index % 2
            readonly property bool scattered: index % 4 === 3
            readonly property real th: (scattered ? overlay.hash(index * 5.9) * 6.283
              : arm * Math.PI + Math.log(rr / warp.rMin) * 2.1 + (overlay.hash(index * 2.9) - 0.5) * (0.25 + 0.6 * q))
              + warp.spin(rr)
            readonly property real near: 0.5 + 0.5 * Math.sin(th)
            width: (1.2 + 2.6 * overlay.hash(index * 7.7)) * warp.s * (0.8 + 0.4 * near) * (0.6 + 0.4 * warp.grow)
            height: width
            radius: width / 2
            x: warp.sx(th, rr) - width / 2
            y: warp.sy(th, rr) - height / 2
            color: q < 0.12 ? "#fff1d2" : (index % 5 === 0 ? Qt.lighter(overlay.tint, 1.5) : "#dbe7ff")
            opacity: (scattered ? 0.5 : 0.8) * (0.6 + 0.4 * Math.abs(Math.sin(warp.now * 2 + index)))
          }
        }

        // The core: blazing white at the heart of a warm glow.
        SoftGlow {
          hue: Util.alpha(Qt.tint("#ffe6c4", Util.alpha(overlay.tint, 0.25)), 0.5)
          x: warp.cx - 50
          y: warp.cy - 50
          transform: Scale { origin.x: 50; origin.y: 50; xScale: warp.rMax * 0.6 * warp.grow / 100; yScale: warp.rMax * 0.34 * warp.grow / 100 }
        }
        SoftGlow {
          hue: "#fff6e4"
          x: warp.cx - 50
          y: warp.cy - 50
          scale: warp.rMax * 0.24 * warp.grow / 100
        }
      }
    }

    MultiEffect {
      anchors.fill: space
      source: space
      blurEnabled: true
      blurMax: 40
      blur: 0.75
      brightness: 0.25
      opacity: warp.dark
    }
    MultiEffect {
      anchors.fill: space
      source: space
      opacity: warp.dark
    }

    Text {
      readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (warp.since - 1.1) / 1.2)), 3)
      anchors.horizontalCenter: parent.horizontalCenter
      y: warp.cy + warp.height * 0.29
      opacity: warp.since > 1.1 ? e * warp.dark : 0
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.25))
      font.family: overlay.displayFamily
      font.pixelSize: 50 * warp.s
      font.weight: Font.DemiBold
      font.letterSpacing: (14 + 40 * (1 - e)) * warp.s
    }
  }

  // ================================================================ Plasma
  // A plasma globe materialises over the desktop on a dark base whose ring
  // glows in the profile's colour. Its core ignites and tendrils of light
  // reach out to the glass, forking and wandering, flickering, with bright
  // points where they touch; READY sits under the base.
  component Plasma: Item {
    id: globe

    property real t: 0
    readonly property real dur: 6.4
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real cx: width * 0.5
    readonly property real cy: height * 0.42
    readonly property real r: height * 0.27
    readonly property real dark: Math.min(1, now / 0.6) * Math.max(0, Math.min(1, (dur - now) / 0.9))
    // The core lighting, then the tendrils reaching out to the glass.
    readonly property real ignite: Math.max(0, Math.min(1, (now - 0.55) / 0.35))
    readonly property real reach: 1 - Math.pow(1 - Math.max(0, Math.min(1, (now - 0.7) / 0.8)), 3)
    readonly property color hot: Qt.lighter(overlay.tint, 1.5)
    readonly property color cool: overlay.hueTurn(0.75, 0.85, 0.65)
    readonly property int count: 9

    NumberAnimation on t { from: 0; to: 1; duration: 6400; running: true; onFinished: overlay.finished() }
    Component.onCompleted: overlay.cue("plasma")

    // Where tendril `i` leaves the glass now, and its points out from the
    // core: a wandering angle, a fast jitter along its length.
    function angleOf(i) {
      var a = overlay.hash(i * 3.7) * 6.283
      return a + 0.7 * Math.sin(now * (0.5 + 0.4 * overlay.hash(i * 1.3)) + i) + 0.25 * Math.sin(now * 1.7 + i * 2.3)
    }
    function tendril(i, from, to, n) {
      var a = angleOf(i), out = []
      var r0 = r * 0.1, r1 = r0 + (r * 0.97 - r0) * reach
      for (var k = from; k <= to; k++) {
        var f = k / n
        var jitter = (Math.sin(k * 1.7 + now * 11 + i * 3) * 0.07 + Math.sin(k * 3.3 - now * 17 + i) * 0.04) * f
        var rr = r0 + (r1 - r0) * f
        out.push(Qt.point(cx + Math.cos(a + jitter) * rr, cy + Math.sin(a + jitter) * rr))
      }
      return out
    }
    function forkOf(i) {
      var a = angleOf(i) + (i % 2 ? 0.32 : -0.32), out = []
      var base = tendril(i, 11, 11, 16)[0]
      var r0 = Math.sqrt((base.x - cx) * (base.x - cx) + (base.y - cy) * (base.y - cy))
      for (var k = 0; k <= 4; k++) {
        var rr = r0 + (r * 0.95 * reach - r0) * (k / 4) * 0.85
        out.push(k === 0 ? base : Qt.point(cx + Math.cos(a + Math.sin(k * 2 + now * 13) * 0.03) * rr, cy + Math.sin(a + Math.sin(k * 2 + now * 13) * 0.03) * rr))
      }
      return out
    }

    Rectangle { anchors.fill: parent; color: "#05020c"; opacity: 0.66 * globe.dark }

    // The base, with its ring of light.
    Shape {
      anchors.fill: parent
      opacity: globe.dark
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: Util.alpha("#ffffff", 0.12)
        strokeWidth: 1
        fillGradient: LinearGradient {
          x1: 0; y1: globe.cy + globe.r * 0.9; x2: 0; y2: globe.cy + globe.r * 1.45
          GradientStop { position: 0.0; color: "#26232c" }
          GradientStop { position: 1.0; color: "#08070a" }
        }
        PathSvg {
          path: {
            var x0 = globe.cx, y0 = globe.cy + globe.r * 0.92, w = globe.r * 0.55, w2 = globe.r * 0.8, h = globe.r * 0.5
            return "M " + (x0 - w) + " " + y0 + " L " + (x0 + w) + " " + y0 + " L " + (x0 + w2) + " " + (y0 + h)
              + " L " + (x0 - w2) + " " + (y0 + h) + " Z"
          }
        }
      }
    }
    Rectangle {
      x: globe.cx - globe.r * 0.78
      y: globe.cy + globe.r * 1.38
      width: globe.r * 1.56
      height: Math.max(2, 3 * globe.s)
      radius: height / 2
      color: Qt.tint(overlay.tint, Util.alpha("#ffffff", 0.25))
      opacity: globe.dark * globe.ignite
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 1.05
        height: parent.height * 6
        radius: height / 2
        color: Util.alpha(overlay.tint, 0.25)
        z: -1
      }
    }

    // The glass: a faint violet body with a rim and a highlight.
    Rectangle {
      x: globe.cx - globe.r
      y: globe.cy - globe.r
      width: globe.r * 2
      height: width
      radius: width / 2
      opacity: globe.dark
      color: Util.alpha(Qt.tint("#140a24", Util.alpha(overlay.tint, 0.15)), 0.55)
      border.width: Math.max(1, 1.5 * globe.s)
      border.color: Util.alpha("#e8deff", 0.3)
    }
    SoftGlow {
      hue: Util.alpha("#ffffff", 0.22)
      x: globe.cx - globe.r * 0.42 - 50
      y: globe.cy - globe.r * 0.55 - 50
      opacity: globe.dark
      transform: [
        Scale { origin.x: 50; origin.y: 50; xScale: globe.r * 0.6 / 100; yScale: globe.r * 0.28 / 100 },
        Rotation { origin.x: 50; origin.y: 50; angle: -38 }
      ]
    }

    // The tendrils and the core, drawn through a bloom.
    Item {
      id: plasma
      anchors.fill: parent
      opacity: 0
      layer.enabled: true

      SoftGlow {
        hue: Util.alpha(globe.cool, 0.35)
        x: globe.cx - 50
        y: globe.cy - 50
        scale: globe.r * 1.6 / 100
        opacity: globe.ignite * (0.6 + 0.2 * Math.sin(globe.now * 3))
      }
      Repeater {
        model: globe.count
        Shape {
          required property int index
          anchors.fill: parent
          visible: globe.reach > 0
          opacity: 0.55 + 0.45 * Math.pow(Math.sin(globe.now * (14 + index) + index * 5), 2)
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Util.alpha(index % 3 === 0 ? globe.cool : overlay.tint, 0.4)
            strokeWidth: 9 * globe.s
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: globe.tendril(index, 0, 16, 16) }
          }
          ShapePath {
            strokeColor: Qt.tint(globe.hot, Util.alpha("#ffffff", 0.55))
            strokeWidth: 1.8 * globe.s
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: globe.tendril(index, 0, 16, 16) }
          }
          ShapePath {
            strokeColor: Util.alpha(globe.hot, 0.75)
            strokeWidth: 1.1 * globe.s
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: globe.reach > 0.6 ? globe.forkOf(index) : [Qt.point(0, 0), Qt.point(0, 0)] }
          }
        }
      }
      // Where each one touches the glass.
      Repeater {
        model: globe.count
        SoftGlow {
          required property int index
          readonly property real a: globe.angleOf(index)
          hue: Qt.tint(globe.hot, Util.alpha("#ffffff", 0.4))
          x: globe.cx + Math.cos(a) * globe.r * 0.97 - 50
          y: globe.cy + Math.sin(a) * globe.r * 0.97 - 50
          scale: (14 + 6 * Math.sin(globe.now * 9 + index)) * globe.s / 100
          opacity: globe.reach > 0.95 ? 0.9 : 0
        }
      }
      // The core.
      SoftGlow {
        hue: "#ffffff"
        x: globe.cx - 50
        y: globe.cy - 50
        scale: globe.r * (0.16 + 0.03 * Math.sin(globe.now * 7)) / 100
        opacity: globe.ignite
      }
      SoftGlow {
        hue: globe.hot
        x: globe.cx - 50
        y: globe.cy - 50
        scale: globe.r * 0.42 / 100
        opacity: 0.7 * globe.ignite
      }
    }
    MultiEffect {
      anchors.fill: plasma
      source: plasma
      blurEnabled: true
      blurMax: 40
      blur: 0.8
      brightness: 0.3
      opacity: globe.dark
    }
    MultiEffect {
      anchors.fill: plasma
      source: plasma
      opacity: globe.dark
    }

    Text {
      readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, (globe.now - 1.6) / 1.2)), 3)
      anchors.horizontalCenter: parent.horizontalCenter
      y: globe.cy + globe.r * 1.62
      opacity: e * globe.dark
      textFormat: Text.PlainText
      text: "READY"
      color: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.3))
      style: Text.Outline
      styleColor: Util.alpha(overlay.tint, 0.4)
      font.family: overlay.displayFamily
      font.pixelSize: 50 * globe.s
      font.weight: Font.DemiBold
      font.letterSpacing: (14 + 36 * (1 - e)) * globe.s
    }
  }

  // ================================================================= Storm
  // A storm rolls in: dark clouds gather over the top of the screen and rain
  // slants down. Lightning strikes, forked bolts lighting the clouds from
  // inside and flashing the screen; the last strike lands in the middle and
  // READY is left crackling there.
  component Storm: Item {
    id: storm

    property real t: 0
    readonly property real dur: 6.6
    readonly property real now: t * dur
    readonly property real s: overlay.u * overlay.stage
    readonly property real dark: Math.min(1, now / 0.8) * Math.max(0, Math.min(1, (dur - now) / 1.0))
    // When each bolt strikes (s), and where along the screen it lands; the
    // last one is the big one, into the middle.
    readonly property var strikes: [
      { "at": 1.0, "x": 0.18 + Math.random() * 0.1 },
      { "at": 1.85, "x": 0.78 + Math.random() * 0.1 },
      { "at": 2.55, "x": 0.34 + Math.random() * 0.1 },
      { "at": 3.5, "x": 0.5, "big": true }
    ]
    property var bolts: []
    property int fired: 0
    readonly property real readyAt: strikes[3].at

    NumberAnimation on t { from: 0; to: 1; duration: 6600; running: true; onFinished: overlay.finished() }
    Component.onCompleted: overlay.cue("rain")
    onNowChanged: {
      while (fired < strikes.length && now >= strikes[fired].at) {
        var sp = strikes[fired]
        var made = bolts.slice()
        var main = bolt(sp.x, sp.big === true)
        made.push({ "at": sp.at, "x": sp.x, "big": sp.big === true, "main": main, "forks": forksFor(main, sp.big === true) })
        bolts = made
        fired++
        // The big one cracks overhead; the others roll in from further off.
        if (sp.big === true) overlay.cue("thunder")
        else overlay.cue("rumble")
      }
    }

    // A bolt from the clouds to its landing point, by midpoint displacement:
    // each segment's middle pushed sideways at random, smaller each round.
    function bolt(fx, big) {
      var x0 = width * (fx + (Math.random() - 0.5) * 0.08), y0 = height * 0.1
      var x1 = width * fx, y1 = big ? height * 0.52 : height * (0.75 + Math.random() * 0.2)
      var pts = [Qt.point(x0, y0), Qt.point(x1, y1)]
      var spread = (y1 - y0) * 0.22
      for (var round = 0; round < 6; round++) {
        var next = [pts[0]]
        for (var i = 0; i < pts.length - 1; i++) {
          var a = pts[i], b = pts[i + 1]
          next.push(Qt.point((a.x + b.x) / 2 + (Math.random() - 0.5) * spread, (a.y + b.y) / 2 + (Math.random() - 0.5) * spread * 0.25))
          next.push(b)
        }
        pts = next
        spread *= 0.55
      }
      return pts
    }
    // Forks off a main bolt's path, angling down and away.
    function forksFor(main, big) {
      var out = [], n = big ? 4 : 2
      for (var f = 0; f < n; f++) {
        var start = main[Math.floor(main.length * (0.2 + Math.random() * 0.5))]
        var side = Math.random() < 0.5 ? -1 : 1
        var len = height * (0.08 + Math.random() * 0.12)
        var end = Qt.point(start.x + side * len * (0.5 + Math.random() * 0.5), start.y + len)
        var pts = [start, end]
        var spread = len * 0.3
        for (var round = 0; round < 4; round++) {
          var next = [pts[0]]
          for (var i = 0; i < pts.length - 1; i++) {
            var a = pts[i], b = pts[i + 1]
            next.push(Qt.point((a.x + b.x) / 2 + (Math.random() - 0.5) * spread, (a.y + b.y) / 2 + (Math.random() - 0.5) * spread * 0.3))
            next.push(b)
          }
          pts = next
          spread *= 0.55
        }
        out.push(pts)
      }
      return out
    }
    // A bolt itself: a flicker, a second flash, then fading.
    function flashOf(age) {
      if (age < 0) return 0
      if (age < 0.06) return 1
      if (age < 0.12) return 0.3
      if (age < 0.2) return 0.85
      return Math.max(0, 1 - (age - 0.2) / 0.5)
    }
    // The light it throws on the sky and the screen: one soft flash per
    // strike (a quick rise, a slow fade), never a strobe.
    function glowOf(age) {
      if (age < 0) return 0
      if (age < 0.04) return age / 0.04
      return Math.max(0, 1 - (age - 0.04) / 0.45)
    }
    readonly property real lastAge: fired > 0 ? now - strikes[fired - 1].at : -1
    readonly property real flash: glowOf(lastAge)

    // The sky darkening.
    Rectangle {
      anchors.fill: parent
      opacity: storm.dark
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha("#0a0d16", 0.85) }
        GradientStop { position: 0.5; color: Util.alpha("#0a0d16", 0.6) }
        GradientStop { position: 1.0; color: Util.alpha("#05060a", 0.5) }
      }
    }
    // Clouds rolling in along the top, lit from inside by each strike.
    Repeater {
      model: 14
      SoftGlow {
        required property int index
        readonly property real a: overlay.hash(index * 2.9)
        readonly property real b: overlay.hash(index * 7.3)
        hue: Qt.tint("#1b2130", Util.alpha(Qt.lighter(overlay.tint, 1.6), 0.55 * storm.flash * Math.max(0, 1 - Math.abs(a - (storm.fired > 0 ? storm.strikes[storm.fired - 1].x : 0.5)) * 2.5)))
        x: storm.width * (a * 1.2 - 0.1) + storm.now * (10 + 20 * b) * storm.s - 50
        y: storm.height * (0.02 + 0.12 * b) - 50
        opacity: storm.dark * 0.95
        transform: Scale { origin.x: 50; origin.y: 50; xScale: storm.width * (0.25 + 0.2 * b) / 100; yScale: storm.height * (0.16 + 0.1 * a) / 100 }
      }
    }
    // Rain, slanting.
    Repeater {
      model: 140
      Rectangle {
        required property int index
        readonly property real a: overlay.hash(index * 1.7)
        readonly property real b: overlay.hash(index * 5.1)
        readonly property real p: (storm.now * (1.1 + 0.6 * b) + a) % 1
        width: Math.max(1, 1.2 * storm.s)
        height: (14 + 16 * b) * storm.s
        x: storm.width * ((index / 140 + p * 0.12) % 1)
        y: storm.height * (p * 1.2 - 0.1)
        rotation: 14
        color: Util.alpha("#c8d6ff", 0.25 + 0.2 * b)
        opacity: storm.dark * Math.min(1, storm.now / 1.2)
      }
    }
    // The screen flashing with each strike.
    Rectangle {
      anchors.fill: parent
      color: Qt.tint("#dfe8ff", Util.alpha(overlay.tint, 0.2))
      opacity: 0.08 * storm.flash * storm.dark
    }

    // The bolts, drawn through a bloom.
    Item {
      id: sky
      anchors.fill: parent
      opacity: 0
      layer.enabled: true

      Repeater {
        model: storm.bolts.length
        Shape {
          required property int index
          readonly property var b: storm.bolts[index]
          readonly property real age: storm.now - b.at
          anchors.fill: parent
          opacity: storm.flashOf(age) * (b.big ? 1 : 0.9)
          visible: opacity > 0.01
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Util.alpha(Qt.lighter(overlay.tint, 1.5), 0.45)
            strokeWidth: (b.big ? 12 : 8) * storm.s
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: b.main }
          }
          ShapePath {
            strokeColor: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.15))
            strokeWidth: (b.big ? 3 : 2) * storm.s
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: b.main }
          }
          ShapePath {
            strokeColor: Util.alpha(Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.3)), 0.8)
            strokeWidth: 1.4 * storm.s
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            capStyle: ShapePath.RoundCap
            PathMultiline { paths: b.forks }
          }
        }
      }

      // READY, crackling where the last bolt landed.
      Text {
        id: stormWord
        readonly property real e: Math.max(0, Math.min(1, (storm.now - storm.readyAt) / 0.3))
        anchors.horizontalCenter: parent.horizontalCenter
        y: storm.height * 0.52
        opacity: storm.now > storm.readyAt ? e : 0
        textFormat: Text.PlainText
        text: "READY"
        color: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.35))
        font.family: overlay.displayFamily
        font.pixelSize: 84 * storm.s
        font.weight: Font.DemiBold
        font.letterSpacing: 12 * storm.s
      }
    }
    MultiEffect {
      anchors.fill: sky
      source: sky
      blurEnabled: true
      blurMax: 40
      blur: 0.85
      brightness: 0.4
      opacity: storm.dark
    }
    MultiEffect {
      anchors.fill: sky
      source: sky
      opacity: storm.dark
    }

    // Little arcs jumping between READY's letters while it crackles.
    property var wordArcs: []
    Timer {
      interval: 300
      repeat: true
      running: storm.now > storm.readyAt + 0.2 && storm.now < storm.dur - 1.0
      onTriggered: {
        var out = []
        var x0 = stormWord.x, w = stormWord.width, y0 = stormWord.y + stormWord.height * 0.35, h = stormWord.height * 0.45
        for (var n = 0; n < 2; n++) {
          var ax = x0 + Math.random() * w, ay = y0 + Math.random() * h
          var pts = [Qt.point(ax, ay)]
          for (var k = 1; k <= 4; k++) pts.push(Qt.point(ax + k * (10 + Math.random() * 8) * storm.s * (n ? -1 : 1), ay + (Math.random() - 0.5) * 18 * storm.s))
          out.push(pts)
        }
        storm.wordArcs = out
      }
    }
    Shape {
      anchors.fill: parent
      visible: storm.now > storm.readyAt + 0.2 && storm.now < storm.dur - 1.0 && storm.wordArcs.length > 0
      opacity: storm.dark
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: Qt.tint("#ffffff", Util.alpha(overlay.tint, 0.4))
        strokeWidth: 1.4 * storm.s
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathMultiline { paths: storm.wordArcs }
      }
    }
  }

  // A whale shark in side view, gliding: the broad flat head and wide mouth,
  // gill slits, ridges running down its flanks, the white checkerboard of
  // spots, a tall dorsal fin, a pectoral that rows gently and a crescent tail
  // sweeping as it swims, with a remora under its belly and pilot fish riding
  // its bow wave. Drawn on a body 1000 units long (head to the right, centred
  // on 500, 120) and scaled to `len` pixels; `haze` (0-1) sinks it into the
  // blue with distance.
  component WhaleShark: Item {
    id: shark

    property real len: 600
    property real haze: 0
    // 1 swims right, -1 left.
    property int facing: 1
    // Seconds, driving the tail and fins.
    property real swim: 0
    // Degrees, nose up.
    property real pitch: 0

    readonly property color water: "#0b3550"
    function hazed(c, amount) { return Qt.tint(c, Util.alpha(water, Math.min(1, haze * amount))) }
    readonly property real stroke: Math.sin(swim * 2 * Math.PI / 2.6)
    readonly property color back: hazed("#4d6a7c", 1)
    readonly property color flank: hazed("#213646", 1)
    readonly property color belly: hazed("#93a8b4", 0.9)
    readonly property color mark: hazed("#e8f4ff", 0.85)

    // The outline, as its top and bottom edges from tail to snout.
    readonly property var topEdge: [[90, 114], [130, 108], [200, 92], [300, 70], [420, 47], [560, 33], [700, 35],
      [850, 48], [950, 70], [985, 88], [1000, 104]]
    readonly property var bottomEdge: [[90, 128], [160, 132], [260, 148], [380, 172], [500, 192], [640, 200],
      [780, 196], [900, 177], [960, 153], [990, 136], [1000, 124]]
    function edgeAt(edge, x) {
      for (var i = 0; i < edge.length - 1; i++) {
        if (x <= edge[i + 1][0]) {
          var f = (x - edge[i][0]) / (edge[i + 1][0] - edge[i][0])
          return edge[i][1] + (edge[i + 1][1] - edge[i][1]) * f
        }
      }
      return edge[edge.length - 1][1]
    }
    // A closed path through the outline's points, smoothed through their
    // midpoints.
    readonly property string bodyPath: {
      var pts = topEdge.slice().reverse().concat([[80, 121]]).concat(bottomEdge)
      pts.splice(0, 0, [1003, 114])
      var d = "M " + pts[0][0] + " " + pts[0][1]
      for (var i = 1; i < pts.length - 1; i++)
        d += " Q " + pts[i][0] + " " + pts[i][1] + " " + (pts[i][0] + pts[i + 1][0]) / 2 + " " + (pts[i][1] + pts[i + 1][1]) / 2
      return d + " L " + pts[pts.length - 1][0] + " " + pts[pts.length - 1][1] + " Z"
    }
    // The spots: loose columns over the back and upper flank, small and
    // close on the head, each nudged and sized a little differently (and a
    // few missing) so they read as a pattern, not a grid; pale stripes
    // between the columns, and the ridges running along the flank.
    readonly property string spotPath: {
      var d = ""
      function dot(x, y, r) { d += " M " + (x - r) + " " + y + " a " + r + " " + r + " 0 1 0 " + (2 * r) + " 0 a " + r + " " + r + " 0 1 0 " + (-2 * r) + " 0" }
      var c = 0, n = 0
      for (var x = 140; x < 960; c++) {
        var head = x > 820
        var t = edgeAt(topEdge, x), b = edgeAt(bottomEdge, x)
        var low = t + (b - t) * (head ? 0.75 : 0.62)
        var gap = head ? 13 : 18
        var r = (head ? 2.2 : 3.4) * (0.75 + 0.25 * Math.min(1, x / 400))
        for (var y = t + 9 + (c % 2) * gap / 2; y < low; y += gap) {
          n++
          if (overlay.hash(n * 2.71) < 0.1) continue
          var jx = (overlay.hash(n * 1.37) - 0.5) * (head ? 5 : 9)
          var jy = (overlay.hash(n * 3.11) - 0.5) * (head ? 4 : 7)
          dot(x + jx, Math.min(low, y + jy), r * (0.7 + 0.6 * overlay.hash(n * 0.83)))
        }
        x += (head ? 15 : 26) * (0.85 + 0.3 * overlay.hash(c * 5.3))
      }
      return d
    }
    readonly property string barPath: {
      var d = ""
      for (var x = 262; x <= 820; x += 34 + 10 * overlay.hash(x * 0.17)) {
        var t = edgeAt(topEdge, x), b = edgeAt(bottomEdge, x)
        var bow = (overlay.hash(x * 0.29) - 0.5) * 6
        d += " M " + x + " " + (t + 5) + " Q " + (x + 2 + bow) + " " + (t + (b - t) * 0.3) + " " + (x + 4) + " " + (t + (b - t) * 0.58)
      }
      // The ridges along the flank.
      for (var k = 0; k < 2; k++) {
        var f = k ? 0.42 : 0.26
        d += " M 300 " + (edgeAt(topEdge, 300) + (edgeAt(bottomEdge, 300) - edgeAt(topEdge, 300)) * f)
        for (var rx = 360; rx <= 820; rx += 60) {
          var rt = edgeAt(topEdge, rx), rb = edgeAt(bottomEdge, rx)
          d += " L " + rx + " " + (rt + (rb - rt) * f)
        }
      }
      return d
    }

    Item {
      width: 1000
      height: 400
      transform: [
        Translate { x: -500; y: -120 },
        Scale { xScale: shark.len / 1000 * shark.facing; yScale: shark.len / 1000 },
        Rotation { angle: -shark.pitch * shark.facing }
      ]

      // The tail, sweeping from the root of the body.
      Shape {
        width: 1000
        height: 400
        preferredRendererType: Shape.CurveRenderer
        transform: Rotation { origin.x: 92; origin.y: 121; angle: shark.stroke * 8 }
        ShapePath {
          strokeColor: "transparent"
          fillGradient: LinearGradient {
            x1: 0; y1: -60; x2: 0; y2: 215
            GradientStop { position: 0.0; color: shark.back }
            GradientStop { position: 1.0; color: shark.flank }
          }
          PathSvg { path: "M 102 110 C 70 80 20 20 -78 -58 C -62 -10 -46 40 -14 104 L -10 121 C -30 155 -42 185 -52 214 C 10 186 58 156 102 132 Z" }
        }
      }

      // The fins along the back and belly, their roots under the body.
      Shape {
        width: 1000
        height: 400
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillGradient: LinearGradient {
            x1: 0; y1: -58; x2: 0; y2: 226
            GradientStop { position: 0.0; color: shark.back }
            GradientStop { position: 0.5; color: shark.flank }
            GradientStop { position: 1.0; color: Qt.darker(shark.belly, 1.4) }
          }
          PathSvg { path: "M 585 36 C 552 -6 512 -40 474 -58 C 466 -50 462 -32 460 -14 C 456 10 446 32 425 49 Z M 262 81 C 250 68 236 58 222 52 C 220 66 214 80 205 93 Z M 432 182 C 417 198 402 213 384 226 C 386 210 388 192 390 178 Z M 264 149 C 252 161 238 173 224 181 C 224 169 224 158 222 146 Z" }
        }
      }

      // The body: lit from above, dark down the flank, pale underneath.
      Shape {
        width: 1000
        height: 400
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Util.alpha(shark.mark, 0.12)
          strokeWidth: 1.2
          fillGradient: LinearGradient {
            x1: 0; y1: 30; x2: 0; y2: 202
            GradientStop { position: 0.0; color: shark.back }
            GradientStop { position: 0.55; color: shark.flank }
            GradientStop { position: 1.0; color: shark.belly }
          }
          PathSvg { path: shark.bodyPath }
        }
        // Spots and pale bars.
        ShapePath {
          strokeColor: "transparent"
          fillColor: Util.alpha(shark.mark, 0.62 * (1 - 0.4 * shark.haze))
          PathSvg { path: shark.spotPath }
        }
        ShapePath {
          strokeColor: Util.alpha(shark.mark, 0.2 * (1 - 0.5 * shark.haze))
          strokeWidth: 2.4
          capStyle: ShapePath.RoundCap
          fillColor: "transparent"
          PathSvg { path: shark.barPath }
        }
        // Ridges down the flank.
        ShapePath {
          strokeColor: Util.alpha(shark.mark, 0.22 * (1 - 0.5 * shark.haze))
          strokeWidth: 1.6
          capStyle: ShapePath.RoundCap
          fillColor: "transparent"
          PathSvg { path: "M 905 72 Q 600 44 180 100 M 885 106 Q 600 110 165 117 M 860 150 Q 600 166 210 134" }
        }
        // Gill slits, the mouth and the eye.
        ShapePath {
          strokeColor: Util.alpha("#05121b", 0.55)
          strokeWidth: 2.2
          capStyle: ShapePath.RoundCap
          fillColor: "transparent"
          PathSvg { path: "M 842 90 Q 832 132 842 172 M 855 88 Q 845 130 855 169 M 868 86 Q 858 128 868 166 M 881 84 Q 872 125 881 162 M 894 82 Q 886 122 894 158 M 1003 122 Q 980 134 952 138" }
        }
        ShapePath {
          strokeColor: "transparent"
          fillColor: Util.alpha("#05121b", 0.8)
          PathSvg { path: "M 928 102 a 4.5 4.5 0 1 0 9 0 a 4.5 4.5 0 1 0 -9 0" }
        }
      }

      // The near pectoral fin, rowing slowly.
      Shape {
        width: 1000
        height: 400
        preferredRendererType: Shape.CurveRenderer
        transform: Rotation { origin.x: 735; origin.y: 194; angle: Math.sin(shark.swim * 2 * Math.PI / 2.6 + 1) * 5 }
        ShapePath {
          strokeColor: Util.alpha(shark.mark, 0.1)
          strokeWidth: 1
          fillGradient: LinearGradient {
            x1: 0; y1: 190; x2: 0; y2: 312
            GradientStop { position: 0.0; color: shark.flank }
            GradientStop { position: 1.0; color: Qt.darker(shark.flank, 1.3) }
          }
          PathSvg { path: "M 778 190 C 748 240 702 284 605 312 C 612 302 640 278 668 244 C 682 226 690 210 695 198 Z" }
        }
      }

      // A remora riding under the belly, and pilot fish in the bow wave.
      Shape {
        width: 1000
        height: 400
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillColor: shark.hazed("#2c3c46", 1)
          PathSvg { path: "M 600 206 C 618 200 650 200 672 205 C 650 211 618 212 600 206 Z M 600 206 L 588 200 L 590 212 Z" }
        }
      }
      Repeater {
        model: 5
        Shape {
          required property int index
          width: 40
          height: 20
          x: 1030 + (index % 3) * 26 + Math.sin(shark.swim * 1.7 + index) * 5
          y: 110 + index * 14 + Math.cos(shark.swim * 1.3 + index * 2) * 4
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: "transparent"
            fillColor: shark.hazed("#c9d6dd", 1)
            PathSvg { path: "M 4 10 C 12 4 26 4 34 10 C 26 16 12 16 4 10 Z M 4 10 L -4 5 L -4 15 Z" }
          }
          ShapePath {
            strokeColor: Util.alpha(shark.hazed("#1d2a33", 1), 0.8)
            strokeWidth: 2
            fillColor: "transparent"
            PathSvg { path: "M 12 6 L 12 14 M 20 5 L 20 15 M 28 6 L 28 14" }
          }
        }
      }
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
