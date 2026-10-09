import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons

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
  // A stall kill also exits non-zero; that is a slow BLE call, not a missing install.
  property bool stalled: false

  function refresh() {
    if (proc.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    proc.running = true
  }

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
    // Plays a given ready animation (rocket, confetti, lava, ...).
    function preview(name: string): void { root.playReady(name) }
    // Opens Showtime now (it closes itself when no heat cycle is running).
    function showtime(): void { root.openShowtime() }
    // Opens the panel on a tab: control, lights, usage, care or device.
    function openPage(name: string): void {
      root.open()
      if (panelLoader.item && "page" in panelLoader.item) panelLoader.item.page = name
    }
  }

  visible: outputText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Goes through a login shell, same as bar.run()/execDetached and the
  // built-in custom-command module, so it finds `quickpuff` on PATH regardless
  // of how omarchy-shell itself was launched.
  Process {
    id: proc
    command: ["bash", "-lc", "quickpuff waybar"]
    // No output means `quickpuff` is missing or its daemon is down; stay visible
    // so the panel's Finish setup is reachable instead of vanishing.
    onExited: function(exitCode) {
      if (exitCode === 0 || root.stalled) {
        root.stalled = false
        return
      }
      root.outputText = "QuickPuff"
      root.outputTooltip = "QuickPuff needs setup — click to finish"
      root.outputActive = false
      root.outputOffline = true
      root.outputClass = ""
    }
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }
      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text) return
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          return
        }
        // `quickpuff waybar` pads its idle label with a double space, a waybar
        // convention for separating two fields. The Omarchy bar already gaps
        // its widgets, so that reads as two widgets here — collapse it.
        var cls = String(data.class || "")
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
        root.outputText = String(data.text || "").replace(/\s+/g, " ").trim()
        root.outputTooltip = String(data.tooltip || "")
        root.outputClass = String(data.class || "")
        root.outputActive = data.class === "preheat" || data.class === "ready" || data.class === "clean"
        root.outputOffline = data.class === "disconnected"
      }
    }
  }

  // `quickpuff waybar` waits up to 5s on the daemon RPC; give up past that so a
  // stalled BLE call can't wedge the widget (a running Process can't be
  // re-run) and let the next poll retry.
  Timer {
    id: stallTimer
    interval: 6000
    onTriggered: {
      root.stalled = true
      proc.running = false
      root.refreshPending = true
    }
  }

  // Faster while preheating, so the ready animation lands close to the
  // moment the Peak gets there.
  Timer {
    interval: root.outputClass === "preheat" ? 1000 : 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A flame joins the label while the Peak is heating.
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
        if (root.bar) root.bar.run("quickpuff heat start")
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
    if (stepProc.running) return
    stepProc.command = ["bash", "-lc", "quickpuff profile \"$1\"", "quickpuff-step", direction]
    stepProc.running = true
  }

  Process {
    id: stepProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.flash("\uf05e Can't switch now")
      root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name !== "") root.flash("\uf1de " + name)
      }
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

  FileView {
    path: Quickshell.env("HOME") + "/.config/quickpuff/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var cfg = JSON.parse(text() || "{}")
        root.readyAnimation = String(cfg.ready_animation || "rocket")
        root.showtimeMode = String(cfg.showtime || "corner")
        root.soundsOn = cfg.sounds !== false
        var vol = Number(cfg.sound_volume)
        root.soundVolume = isFinite(vol) ? Math.max(0, Math.min(100, vol)) / 100 : 0.7
        root.overlayScreen = String(cfg.overlay_screen || "focused")
      } catch (e) {}
    }
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
    if (which === "off" || which === "") return
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
    onPressed: if (root.bar) root.bar.run("quickpuff heat boost")
  }
}
