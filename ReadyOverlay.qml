import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"
import "ready"

// A celebration when the Peak reaches temperature, played over the desktop
// from the bar widget. Full-screen, transparent and click-through (the empty
// mask), so it never gets in the way; it closes itself when done.
//
// Animations are a registry: each show is one file in ready/ (with the
// shared ReadyWord, SoftGlow and Sparks beside them), registered in
// `animations` below and listed in READY_ANIMATIONS (constants.py) and the
// panel's `readyAnimations`. A show reaches this window (size, tint, cues,
// the u/hash helpers) through its `host` property.
//
// Shows play sound cues with `host.cue(name)` (sounds/<name>.ogg). The
// `ready` chime opens every show; the rest are fired by each animation.
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

  Component { id: rocketComponent; RocketLaunch { host: overlay } }
  Component { id: confettiComponent; ConfettiRain { host: overlay } }
  Component { id: lavaComponent; LavaLamp { host: overlay } }
  Component { id: auroraComponent; Aurora { host: overlay } }
  Component { id: fireworksComponent; Fireworks { host: overlay } }
  Component { id: smokeComponent; SmokeRings { host: overlay } }
  Component { id: neonComponent; NeonSign { host: overlay } }
  Component { id: supernovaComponent; Supernova { host: overlay } }
  Component { id: constellationComponent; Constellation { host: overlay } }
  Component { id: firefliesComponent; Fireflies { host: overlay } }
  Component { id: deepseaComponent; DeepSea { host: overlay } }
  Component { id: warpComponent; Warp { host: overlay } }
  Component { id: plasmaComponent; Plasma { host: overlay } }
  Component { id: stormComponent; Storm { host: overlay } }

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
}
