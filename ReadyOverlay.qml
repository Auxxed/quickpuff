import QtQuick
import QtQuick.Shapes
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

  readonly property var animations: ({ "rocket": rocketComponent, "confetti": confettiComponent })
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

  // ================================================================ Rocket
  // The Peak assembles on a launch pad (base, glass, carb cap), lights up,
  // grows fins, counts down and blasts off through the bar.
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

    // ---- The Peak (drawn in a 70×190 box, scaled; bottom sits on the pad)
    Item {
      id: rocket
      width: 70
      height: 190
      x: show.padX - width / 2 + show.shakeX
      y: show.padY - height + show.liftY
      scale: show.s
      transformOrigin: Item.Bottom
      opacity: show.fadeAll > 0 ? 1 : 0

      // Soft halo so the dark body reads on any wallpaper.
      Rectangle {
        x: -25
        y: 70
        width: 120
        height: 130
        radius: 60
        color: Util.alpha(overlay.tint, 0.08 + 0.14 * show.ledOn)
        opacity: show.baseIn
      }

      // Flames, stacked outer to inner.
      Repeater {
        model: [
          { "w": 38, "h": 74, "top": "#ff9a3c", "bottom": "#ff2a00" },
          { "w": 26, "h": 54, "top": "#ffe27a", "bottom": "#ff7a1a" },
          { "w": 13, "h": 32, "top": "#ffffff", "bottom": "#ffd84a" }
        ]

        Shape {
          required property var modelData
          x: 35 - modelData.w / 2
          y: 184
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

      // Fins, sliding out from behind the base.
      Repeater {
        model: [-1, 1]

        Shape {
          required property var modelData
          width: 70
          height: 190
          x: -modelData * (1 - show.finOut) * 14
          opacity: show.finOut
          preferredRendererType: Shape.CurveRenderer

          ShapePath {
            strokeColor: Util.alpha("white", 0.35)
            strokeWidth: 1
            fillGradient: LinearGradient {
              x1: 0; y1: 150; x2: 0; y2: 196
              GradientStop { position: 0.0; color: Qt.lighter(overlay.tint, 1.3) }
              GradientStop { position: 1.0; color: Qt.darker(overlay.tint, 1.6) }
            }
            PathSvg {
              path: modelData < 0
                ? "M 12 146 L 10 186 L -13 196 Q -17 178 -3 160 Z"
                : "M 58 146 L 60 186 L 83 196 Q 87 178 73 160 Z"
            }
          }
        }
      }

      // Base: the onyx body, springing up from the pad.
      Item {
        x: 3
        y: 120
        width: 64
        height: 70
        opacity: Math.min(1, show.baseIn * 2)
        transform: Scale { origin.x: 32; origin.y: 70; xScale: show.baseIn; yScale: show.baseIn }

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: "#6a6d76"
            strokeWidth: 1
            fillGradient: LinearGradient {
              x1: 0; y1: 0; x2: 64; y2: 0
              GradientStop { position: 0.0; color: "#3b3d44" }
              GradientStop { position: 0.35; color: "#1b1c20" }
              GradientStop { position: 0.8; color: "#2d2f35" }
              GradientStop { position: 1.0; color: "#16171a" }
            }
            PathSvg { path: "M 8 70 L 56 70 Q 64 70 62 60 L 54 14 Q 52 4 42 4 L 22 4 Q 12 4 10 14 L 2 60 Q 0 70 8 70 Z" }
          }
        }
        // Sheen.
        Rectangle { x: 13; y: 14; width: 4; height: 42; radius: 2; rotation: 8; color: Util.alpha("white", 0.18) }
        // Chamber opening on top.
        Rectangle { x: 18; y: 3; width: 28; height: 5; radius: 2.5; color: "#0b0b0d" }
        // Logo light.
        Rectangle {
          x: 29; y: 28; width: 6; height: 6; radius: 3
          color: overlay.tint
          opacity: show.ledOn
          Rectangle { z: -1; anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: Util.alpha(overlay.tint, 0.45) }
        }
        // Light strip round the foot.
        Rectangle {
          x: 9; y: 59; width: 46; height: 3; radius: 1.5
          color: overlay.tint
          opacity: show.ledOn
          Rectangle { z: -1; anchors.centerIn: parent; width: 58; height: 11; radius: 5.5; color: Util.alpha(overlay.tint, 0.4) }
        }
      }

      // Glass, dropping onto the base.
      Item {
        x: 13
        y: 40 + show.glassDrop
        width: 44
        height: 86
        opacity: show.glassOn

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Util.alpha("white", 0.7)
            strokeWidth: 1.5
            fillColor: Util.alpha("#cfe8ff", 0.16)
            PathSvg { path: "M 12 86 L 32 86 Q 34 80 36 72 Q 46 52 36 38 Q 29 30 28 16 L 28 4 Q 28 0 24 0 L 20 0 Q 16 0 16 4 L 16 16 Q 15 30 8 38 Q -2 52 8 72 Q 10 80 12 86 Z" }
          }
        }
        // Water in the bulb, tinted by the lights below.
        Rectangle { x: 8; y: 55; width: 28; height: 17; radius: 8; color: Util.alpha(Qt.tint("#6fc3ff", Util.alpha(overlay.tint, 0.5 * show.ledOn)), 0.4) }
        // Highlight.
        Rectangle { x: 9; y: 42; width: 3; height: 20; radius: 1.5; rotation: 12; color: Util.alpha("white", 0.55) }
      }

      // Carb cap, spinning down onto the glass.
      Item {
        x: 24
        y: 26 + show.capDrop
        width: 22
        height: 16
        opacity: show.capOn
        rotation: show.capSpin

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: "#8a9099"
            strokeWidth: 1
            fillGradient: LinearGradient {
              x1: 0; y1: 0; x2: 22; y2: 0
              GradientStop { position: 0.0; color: "#f2f4f7" }
              GradientStop { position: 0.6; color: "#aab0b8" }
              GradientStop { position: 1.0; color: "#7c828b" }
            }
            PathSvg { path: "M 0 16 L 22 16 L 22 10 Q 22 0 11 0 Q 0 0 0 10 Z" }
          }
        }
      }

      // Speed streaks while flying.
      Repeater {
        model: 6

        Rectangle {
          id: streak
          required property int index
          visible: show.trailOn > 0 && show.liftY < -20
          width: 2
          height: 26 + (index * 17) % 30
          radius: 1
          x: index % 2 ? -18 - index * 4 : 88 + index * 4
          color: Util.alpha("white", 0.5)

          NumberAnimation on y {
            running: streak.visible
            loops: Animation.Infinite
            from: 40 + streak.index * 12
            to: 260
            duration: 260 + streak.index * 35
          }
        }
      }
    }

    // Sparks where glass meets base, and a pop as the cap lands.
    Sparks {
      id: clink
      x: show.padX
      y: show.padY - 70 * show.s
      count: 12
      reach: 34 * show.s
      hues: ["#ffffff", "#cfe8ff", overlay.tint]
    }
    Sparks {
      id: pop
      x: show.padX
      y: show.padY - 160 * show.s
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
      font.family: overlay.fontFamily
      font.pixelSize: 48 * show.s
      font.bold: true

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
      text: " READY"
      color: Qt.lighter(overlay.tint, 1.4)
      style: Text.Outline
      styleColor: Util.alpha("black", 0.55)
      font.family: overlay.fontFamily
      font.pixelSize: 30 * show.s
      font.bold: true
      font.letterSpacing: 3

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
  // A burst of confetti from the widget that tumbles down the screen.
  component ConfettiRain: Item {
    id: rain

    property real t: 0
    readonly property real s: overlay.u
    readonly property var colors: [overlay.tint, Color.accent, "#ff4d4d", "#f6d32d", "#3dd68c", "#3b9eff", "#ff4fa3", "#ffffff"]

    Component.onCompleted: fall.start()

    NumberAnimation {
      id: fall
      target: rain
      property: "t"
      from: 0
      to: 1
      duration: 2800
      onFinished: overlay.finished()
    }

    Repeater {
      model: 64

      Rectangle {
        required property int index
        // Deterministic spread so every burst looks full.
        readonly property real vx: (((index * 73) % 100) / 100 - 0.5) * 520 * rain.s
        readonly property real vy: (((index * 41) % 100) / 100) * 260 * rain.s + 60 * rain.s
        readonly property real gravity: 900 * rain.s
        readonly property real sp: (index % 2 ? 1 : -1) * (360 + (index * 53) % 540)
        width: (index % 3 ? 7 : 5) * rain.s
        height: (index % 3 ? 3 : 5) * rain.s
        radius: index % 4 === 0 ? width / 2 : 1
        color: rain.colors[index % rain.colors.length]
        x: overlay.originX + vx * rain.t * (1.2 - 0.4 * rain.t)
        y: (overlay.barAtTop ? overlay.barEdge : overlay.barEdge - 20 * rain.s)
          + (overlay.barAtTop ? 1 : -1) * vy * rain.t * 1.6 + gravity * rain.t * rain.t
        rotation: sp * rain.t
        opacity: rain.t < 0.8 ? 1 : (1 - rain.t) / 0.2
      }
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
