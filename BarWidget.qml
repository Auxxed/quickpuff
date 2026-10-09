import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "components"
import "components/plain.js" as Plain

BarWidget {
  id: root
  moduleName: "auxxed.quickpuff"

  property string outputText: ""
  property string outputTooltip: ""
  property bool outputActive: false
  property bool outputOffline: true
  property string outputClass: ""
  readonly property bool heatingNow: outputClass === "preheat" || outputClass === "ready"
  property bool refreshPending: false

  function refresh() {
    if (proc.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    proc.launch(cli.argv(["waybar"]))
  }

  QuickpuffCli { id: cli }

  readonly property var readyAnimations: ["rocket", "confetti", "lava", "aurora", "fireworks", "smoke", "neon"]
  readonly property var pages: ["control", "lights", "usage", "care", "device"]

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Bar.findPanelWidget requires open/close/opened on the bar-widget root,
  // and the popout coordinator compares against slot.activeItem — so this
  // widget, not the nested panel, is the identity the bar tracks.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  Component.onCompleted: refresh()
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "auxxed.quickpuff"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    // Plays the ready animation now, for trying it out.
    function celebrate(): void { root.playReady("") }
    // Plays a given ready animation (rocket, confetti, lava, ...); any other
    // name is ignored.
    function preview(name: string): void {
      if (root.readyAnimations.indexOf(name) >= 0) root.playReady(name)
    }
    // Opens Showtime now (it closes itself when no heat cycle is running).
    function showtime(): void { root.openShowtime() }
    // Opens the panel on a tab: control, lights, usage, care or device.
    function openPage(name: string): void {
      if (root.pages.indexOf(name) < 0) return
      root.open()
      if (panelLoader.item && "page" in panelLoader.item) panelLoader.item.page = name
    }
  }

  visible: outputText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // `quickpuff waybar` waits up to 5s on the daemon RPC; past 6s the run is
  // stopped so a stalled BLE call can't wedge the widget, and the next poll
  // retries. Its answer is a few hundred bytes; 16 KiB is plenty.
  BoundedProcess {
    id: proc
    maxBytes: 16384
    timeoutMs: 6000
    onDone: function(ok, code, out) {
      if (ok) {
        root.applyWaybar(out)
        return
      }
      // Stopped for running long: a slow BLE call, not a missing install.
      if (code === -1) {
        root.refreshPending = true
        return
      }
      // No answer means `quickpuff` is missing or its daemon is down; stay
      // visible so the panel's Finish setup is reachable instead of vanishing.
      root.outputText = "QuickPuff"
      root.outputTooltip = "QuickPuff needs setup — click to finish"
      root.outputActive = false
      root.outputOffline = true
      root.outputClass = ""
    }
    onRunningChanged: if (!running && root.refreshPending) root.refresh()
  }

  function applyWaybar(out) {
    if (!out) return
    var data
    try {
      data = JSON.parse(out)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    var cls = typeof data.class === "string" && /^[a-z-]{0,24}$/.test(data.class) ? data.class : ""
    // Reached temperature: celebrate, on the overlay monitor. While
    // Showtime is up it calls the moment itself, off the live feed.
    if (root.outputClass === "preheat" && cls === "ready" && root.isOverlayScreen() && !showtimeLoader.active) root.playReady("")
    // A heat cycle began: raise the curtain (once per cycle).
    if (cls === "preheat" || cls === "ready") {
      if (!root.showtimeThisCycle && root.showtimeMode !== "off" && root.isOverlayScreen()) root.openShowtime()
      root.showtimeThisCycle = true
    } else {
      root.showtimeThisCycle = false
    }
    // `quickpuff waybar` pads its idle label with a double space, a waybar
    // convention for separating two fields. The Omarchy bar already gaps
    // its widgets, so that reads as two widgets here — collapse it.
    root.outputText = Plain.plain(data.text, 48).replace(/\s+/g, " ").trim()
    root.outputTooltip = Plain.plain(data.tooltip, 1024, true)
    root.outputClass = cls
    root.outputActive = cls === "preheat" || cls === "ready" || cls === "clean"
    root.outputOffline = cls === "disconnected"
    root.applyUi(data.ui)
  }

  // The overlay settings, as `quickpuff waybar` reads them from config.json
  // (the shell doesn't read that file itself). Each value is checked against
  // what it can be; anything else leaves the current one.
  function applyUi(ui) {
    if (!ui || typeof ui !== "object") return
    if (ui.ready_animation === "off" || root.readyAnimations.indexOf(ui.ready_animation) >= 0) root.readyAnimation = ui.ready_animation
    if (["off", "corner", "stage"].indexOf(ui.showtime) >= 0) root.showtimeMode = ui.showtime
    if (typeof ui.sounds === "boolean") root.soundsOn = ui.sounds
    if (typeof ui.sound_volume === "number" && ui.sound_volume >= 0 && ui.sound_volume <= 100) root.soundVolume = ui.sound_volume / 100
    if (typeof ui.overlay_screen === "string" && /^(focused|[A-Za-z0-9][A-Za-z0-9._-]{0,31})$/.test(ui.overlay_screen)) root.overlayScreen = ui.overlay_screen
  }

  // Faster while preheating, so the ready animation lands close to the
  // moment the Peak gets there.
  Timer {
    interval: root.outputClass === "preheat" ? 1000 : 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // The daemon also pushes every status it takes (several a second while
  // heating) over its socket. Listening means a heat cycle raises Showtime
  // and refreshes the label the moment it starts, not at the next poll.
  property int liveState: -1
  DaemonFeed {
    id: live
    connected: socketPath !== ""
    onStatus: function(d) {
      var s = d.connected === false ? -1 : Number(d.operating_state_id)
      if (!isFinite(s) || s === root.liveState) return
      var was = root.liveState
      root.liveState = s
      // A cycle just began (or was found running): curtain up, once.
      if ((s === 7 || s === 8) && !root.showtimeThisCycle) {
        root.showtimeThisCycle = true
        if (root.showtimeMode !== "off" && root.isOverlayScreen()) root.openShowtime()
      } else if (s !== 7 && s !== 8 && s !== 9) {
        root.showtimeThisCycle = false
      }
      if (was !== -1 || s !== -1) root.refresh()
    }
  }
  // The daemon restarts now and then; pick the socket back up when it does.
  Timer {
    interval: 5000
    running: !live.connected && live.socketPath !== ""
    repeat: true
    onTriggered: live.connected = true
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A flame joins the label while the Peak is heating. The shell draws
    // both strings itself, so they're plain()ed where they're set.
    text: root.flashText !== "" ? root.flashText
      : root.heatingNow ? "\uf06d " + root.outputText : root.outputText
    tooltipText: root.outputTooltip
    active: root.outputActive || root.opened
    // Recede while there's no device to report on, the same way the shell's
    // own widgets dim when their subject is idle. Never while the panel is
    // open, so the label stays legible next to its own popup.
    dimmed: root.outputOffline && !root.opened
    // Matches the clock, the bar's other text-bearing widget; the label is
    // read as data, not as a compact tag like the keyboard-layout pill.
    fontSize: Style.font.body

    // Scroll down for the next heat profile, up for the previous one.
    onWheelMoved: function(delta) { root.wheelStep(delta) }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        cli.fire(["heat", "start"])
      } else if (b === Qt.MiddleButton) {
        root.broadcast("refresh")
      } else {
        root.togglePanel()
      }
    }
  }

  // ----------------------------------------------- scroll to switch profile
  // The label briefly shows the profile it landed on. Touchpads send many
  // small deltas, so they add up to one notch (120) per step, and a step
  // still in flight swallows the rest of that flick.
  property string flashText: ""
  property int wheelAccum: 0

  function flash(text) {
    flashText = text
    flashTimer.restart()
  }

  function wheelStep(delta) {
    if (root.outputOffline) return
    if (root.heatingNow) {
      flash("\uf06d Heating")
      return
    }
    wheelAccum += delta
    if (Math.abs(wheelAccum) < 120) return
    var direction = wheelAccum < 0 ? "--next" : "--prev"
    wheelAccum = 0
    stepProc.launch(cli.argv(["profile", direction]))
  }

  // Prints the name of the profile it landed on.
  BoundedProcess {
    id: stepProc
    maxBytes: 1024
    timeoutMs: 10000
    onDone: function(ok, code, out) {
      var name = ok ? Plain.plain(out, 40).trim() : ""
      if (name !== "") root.flash("\uf1de " + name)
      else if (!ok) root.flash("\uf05e Can't switch now")
      Qt.callLater(root.refresh)
    }
  }

  Timer {
    id: flashTimer
    interval: 1800
    onTriggered: root.flashText = ""
  }

  // ------------------------------------------------------ ready animation
  // Played over the desktop by ReadyOverlay.qml when the Peak reaches
  // temperature; which one comes from `quickpuff ready-anim`.
  property string readyAnimation: "rocket"
  // Showtime (SessionOverlay.qml): off, corner or stage.
  property string showtimeMode: "corner"
  property bool soundsOn: true
  property real soundVolume: 0.7
  // Which monitor overlays play on: "focused" or an output name.
  property string overlayScreen: "focused"
  property bool showtimeThisCycle: false

  // Watches config.json only, never reads it: a change re-polls `quickpuff
  // waybar`, which reads the file (bounded, no symlinks) and hands back the
  // settings above in its `ui` block.
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickpuff/config.json"
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  // The monitor overlays play on: the one named in overlay_screen when it's
  // connected, otherwise whichever you're looking at.
  function isOverlayScreen() {
    var win = button.QsWindow.window
    if (root.overlayScreen !== "focused" && win && win.screen) {
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === root.overlayScreen) return win.screen.name === root.overlayScreen
    }
    return root.onFocusedScreen()
  }

  function onFocusedScreen() {
    var win = button.QsWindow.window
    var focused = Hyprland.focusedMonitor
    if (!win || !win.screen || !focused) return true
    return focused.name === win.screen.name
  }

  // `name` "" plays the configured one; the panel's Preview passes its pick.
  function playReady(name) {
    var which = name !== "" ? name : root.readyAnimation
    if (root.readyAnimations.indexOf(which) < 0) return
    readyLoader.active = false
    readyLoader.active = true
    var show = readyLoader.item
    if (!show) return
    var win = button.QsWindow.window
    if (win && win.screen) show.screen = win.screen
    var p = button.mapToItem(null, button.width / 2, 0)
    var atTop = !root.bar || root.bar.position !== "bottom"
    var screenH = win && win.screen ? win.screen.height : 0
    show.barAtTop = atTop
    show.originX = p.x
    show.barEdge = atTop ? p.y + button.height : screenH - (win ? win.height : 0) + p.y
    show.fontFamily = root.bar ? root.bar.fontFamily : Style.font.family
    if ("soundsOn" in show) show.soundsOn = root.soundsOn
    if ("soundVolume" in show) show.soundVolume = root.soundVolume
    show.animation = which
    show.armed = true
  }

  // Showtime: the heat cycle played out over the desktop.
  function openShowtime() {
    showtimeLoader.active = false
    showtimeLoader.active = true
    var show = showtimeLoader.item
    if (!show) return
    var win = button.QsWindow.window
    if (win && win.screen) show.screen = win.screen
    var p = button.mapToItem(null, button.width / 2, 0)
    var atTop = !root.bar || root.bar.position !== "bottom"
    var screenH = win && win.screen ? win.screen.height : 0
    show.barAtTop = atTop
    show.originX = p.x
    show.barEdge = atTop ? p.y + button.height : screenH - (win ? win.height : 0) + p.y
    show.mode = root.showtimeMode
    show.soundsOn = root.soundsOn
    show.soundVolume = root.soundVolume
    // On the stage the rocket is the stage's own Peak lifting off.
    show.launch = root.showtimeMode === "stage" && root.readyAnimation === "rocket"
    // Hold the stage long enough for the ready animation to play on it.
    show.chimeOnReady = root.readyAnimation === "off" || show.launch
    show.holdAfterReady = root.readyAnimation === "off" ? 2.2 : root.readyAnimation === "rocket" ? 7.4 : 6.2
    show.armed = true
  }

  LazyLoader {
    id: showtimeLoader
    active: false
    source: Qt.resolvedUrl("SessionOverlay.qml")
  }

  Connections {
    target: showtimeLoader.item
    function onFinished() { showtimeLoader.active = false }
    function onReadyMoment() {
      var show = showtimeLoader.item
      if (show && !show.launch) root.playReady("")
    }
  }

  LazyLoader {
    id: readyLoader
    active: false
    source: Qt.resolvedUrl("ReadyOverlay.qml")
  }

  Connections {
    target: readyLoader.item
    function onFinished() { readyLoader.active = false }
  }

  // Breathes while the chamber climbs, so a glance at the bar says "almost".
  SequentialAnimation on opacity {
    running: root.outputClass === "preheat"
    loops: Animation.Infinite
    alwaysRunToEnd: true
    onRunningChanged: if (!running) root.opacity = 1
    NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
  }

  // WidgetButton only accepts left/right/middle, so catch mouse 5 (forward
  // side button) on an overlay. Other buttons and hover fall through to it.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.ForwardButton
    hoverEnabled: false
    onPressed: cli.fire(["heat", "boost"])
  }
}
