import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "auxxed.quickpuff"
  ipcTarget: "auxxed.quickpuff"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var statusData: ({})
  property bool refreshPending: false

  // Palette/typography lifted off the bar so every child stops repeating the
  // `bar ? bar.x : fallback` ternary, matching how first-party panels do it.
  readonly property color foreground: root.barForeground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // panel-to-panel Tab handoff has to hand it the host widget's identity.
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (statusProc.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    statusProc.running = true
  }

  // Fire a control command detached through a login shell — the same path
  // bar.run() takes internally — then re-poll shortly after, since the daemon
  // usually reflects a heat/profile change well before the poll interval
  // would catch it. Going straight to Util avoids depending on `bar`, which
  // is null for a beat right after the panel is created.
  function run(cmd) {
    Util.execDetached(cmd)
    kickTimer.restart()
  }

  // Same, for commands carrying user-entered text: argv never passes through
  // a shell that could re-tokenize it, so a profile named `$(reboot)` is a
  // profile name and nothing else.
  function runArgv(argv) {
    Util.execArgv(argv)
    kickTimer.restart()
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
    } else {
      cancelEdit()
      pendingTemps = ({})
      pendingTimes = ({})
      pendingNames = ({})
      pendingColors = ({})
      pendingVapors = ({})
      pendingBoostTemps = ({})
      pendingBoostTimes = ({})
      pendingStealth = undefined
      pendingLantern = undefined
      pendingSaver = undefined
      pendingQtip = undefined
      pendingCleanEvery = -1
      pendingBrightness = -1
      pendingDeviceName = ""
      confirmPowerOff = false
      page = "control"
      deviceTab = "info"
      usageTab = "stats"
      noteKey = ""
      pendingDailyLimit = -1
      pendingRecap = undefined
      pendingPreserve = undefined
      pickerOpen = false
      pendingCycleOn = undefined
      namingLight = false
      renamingLight = ""
      confirmDeleteLight = ""
      pendingLightId = ""
    }
  }

  // ---------------------------------------------------------------- state
  readonly property bool connected: statusData.connected === true
  // Battery saver let go of the Peak; opening this panel reconnects it.
  readonly property bool resting: !connected && statusData.resting === true
  // Handoff gave the Peak to another computer; Connect takes it back.
  readonly property bool handedOff: !connected && !resting && statusData.handed_off === true
  readonly property var profiles: statusData.profiles || []
  readonly property bool hasProfiles: connected && profiles.length > 0

  readonly property int currentProfile: {
    var n = Number(statusData.current_profile)
    return isFinite(n) ? n : -1
  }
  readonly property var activeProfile: {
    for (var i = 0; i < profiles.length; i++) {
      if (Number(profiles[i].index) === root.currentProfile) return profiles[i]
    }
    return null
  }

  // OperatingState ids from quickpuff's constants.py: 7 preheat, 8 at-temp, 9 fade.
  readonly property int stateId: {
    var n = Number(statusData.operating_state_id)
    return isFinite(n) ? n : -1
  }
  readonly property bool preheating: connected && stateId === 7
  readonly property bool atTemp: connected && stateId === 8
  readonly property bool cooling: connected && stateId === 9
  readonly property bool heating: preheating || atTemp

  // `quickpuff` stores the user's unit preference in its own config; the bar label
  // already honors it, so the panel has to as well or the two disagree.
  property string units: "F"
  readonly property bool celsius: units === "C"

  function fToC(f) { return (Number(f) - 32) * 5 / 9 }
  function cToF(c) { return Number(c) * 9 / 5 + 32 }

  // `c` is optional: profile tiles work off Fahrenheit alone (the unit the
  // device stores and the clamp range is expressed in) and convert here.
  function formatTemp(f, c) {
    if (celsius) {
      var vc = Number(c)
      if (!isFinite(vc)) {
        var vf = Number(f)
        if (!isFinite(vf)) return ""
        vc = fToC(vf)
      }
      return Math.round(vc) + "°C"
    }
    var v = Number(f)
    if (!isFinite(v)) return ""
    return Math.round(v) + "°F"
  }

  // A dab temperature as a flame colour: pale amber for a low-temp dab, through
  // orange and ember red, to white-hot at the top of the Peak's range.
  function heatRamp(f) {
    var stops = [
      { "t": 400, "c": "#ffd27a" },
      { "t": 480, "c": "#ffa03c" },
      { "t": 540, "c": "#ff6a3a" },
      { "t": 600, "c": "#ffe9e0" }
    ]
    var v = Number(f)
    if (!isFinite(v)) return root.foreground
    if (v <= stops[0].t) return stops[0].c
    for (var i = 1; i < stops.length; i++) {
      if (v <= stops[i].t) {
        var k = (v - stops[i - 1].t) / (stops[i].t - stops[i - 1].t)
        return Qt.tint(stops[i - 1].c, Util.alpha(stops[i].c, k))
      }
    }
    return stops[stops.length - 1].c
  }

  readonly property string tempLabel: {
    var t = formatTemp(statusData.heater_temp_f, statusData.heater_temp_c)
    return t !== "" ? t : "—"
  }
  readonly property string targetLabel: activeProfile
    ? formatTemp(activeProfile.temp_f, activeProfile.temp_c)
    : ""
  readonly property string deviceName: String(statusData.device_name || "Peak Pro")
  readonly property string batteryLabel: {
    if (!connected) return ""
    var n = Number(statusData.battery)
    var pct = isFinite(n) ? Math.round(n) + "%" : ""
    return pluggedIn ? "\uf0e7 " + pct : pct
  }
  readonly property bool pluggedIn: {
    var src = String(statusData.charge_source || "")
    return connected && src !== "" && src !== "Unplugged"
  }
  readonly property string batteryDetail: {
    if (!connected) return ""
    var n = Number(statusData.battery)
    var bits = []
    if (isFinite(n)) bits.push(Math.round(n) + "%")
    var state = String(statusData.charge_state || "")
    if (state !== "" && state !== "Unplugged") bits.push(state)
    var eta = formatEta(statusData.charge_eta_s)
    if (eta !== "") bits.push("full in " + eta)
    return bits.join(" · ")
  }

  function formatEta(seconds) {
    var n = Number(seconds)
    if (seconds === null || seconds === undefined || !isFinite(n) || n <= 0) return ""
    var mins = Math.max(1, Math.round(n / 60))
    if (mins < 60) return mins + " min"
    var h = Math.floor(mins / 60)
    var m = mins % 60
    return h + " h" + (m ? " " + m + " min" : "")
  }

  // Capacity the Peak's fuel gauge has learned, against the battery's rated size.
  readonly property int batteryRated: Number(statusData.battery_rated_mah) || 1700
  readonly property string batteryHealthLabel: {
    var raw = statusData.battery_capacity_mah
    var mah = Number(raw)
    if (!connected || !raw || !isFinite(mah)) return ""
    // Use the daemon's figure so the panel and `quickpuff status` agree.
    var daemonPct = Number(statusData.battery_health_pct)
    if (statusData.battery_health_pct !== null && isFinite(daemonPct)) return daemonPct + "%"
    return Math.min(100, Math.floor(mah / batteryRated * 100 + 0.5)) + "%"
  }
  readonly property string batteryCapacityLabel: {
    var raw = statusData.battery_capacity_mah
    var mah = Number(raw)
    if (!connected || !raw || !isFinite(mah)) return ""
    return Math.round(mah) + " of " + batteryRated + " mAh"
  }

  property var pendingPreserve: undefined
  readonly property bool preserveSupported: statusData.max_charge !== null && statusData.max_charge !== undefined
  readonly property bool preserveOn: pendingPreserve !== undefined
    ? pendingPreserve === true
    : Number(statusData.max_charge) < 100

  function togglePreserve() {
    var next = !preserveOn
    pendingPreserve = next
    run("quickpuff preserve " + (next ? "on" : "off"))
  }

  // The Peak refuses to heat near 5%; warn a little before that.
  readonly property bool lowHeatBattery: connected && !pluggedIn && Number(statusData.battery) <= 10
  readonly property string metaLabel: {
    if (!connected) return needsSetup ? "Setup needed" : (resting ? "Resting · waking…" : (handedOff ? "On another computer" : (connecting ? "Connecting…" : "Disconnected")))
    var s = String(statusData.operating_state || "Connected")
    if (heating && targetLabel !== "") s += " · " + targetLabel
    else if (chamberLabel !== "") s += " · " + chamberLabel
    return s
  }

  readonly property string chamberLabel: {
    if (!connected) return ""
    var s = String(statusData.chamber || "")
    if (s === "" || s === "No chamber") return ""
    return s
  }
  readonly property string remainingLabel: {
    if (!connected) return ""
    var n = Number(statusData.dabs_remaining)
    if (!isFinite(n) || n < 0) return ""
    return "~" + Math.round(n)
  }

  readonly property var telemetry: statusData.telemetry || ({})
  readonly property bool showStats: {
    if (connected) return true
    if (telemetry.tracking_since) return true
    return Number(telemetry.today) > 0
      || Number(telemetry.this_week) > 0
      || Number(telemetry.this_month) > 0
  }

  function countLabel(value) {
    var n = Number(value)
    return String(isFinite(n) ? Math.round(n) : 0)
  }

  readonly property var dailySeries: telemetry.daily || []
  readonly property var hourSeries: telemetry.hours || []
  readonly property var weekdaySeries: telemetry.weekdays || []
  readonly property var colorSeries: telemetry.colors || []
  readonly property var profileUsage: telemetry.profiles || []

  function profileByIndex(index) {
    for (var i = 0; i < profiles.length; i++) {
      if (Number(profiles[i].index) === Number(index)) return profiles[i]
    }
    return null
  }

  function profileUsageName(index) {
    if (Number(index) < 0) return "Custom temperature"
    var p = profileByIndex(index)
    return p && p.name ? String(p.name) : "Profile " + (Number(index) + 1)
  }

  function profileUsageColor(index) {
    var p = profileByIndex(index)
    return p && typeof p.color === "string" && p.color.charAt(0) === "#" ? p.color : Color.accent
  }
  readonly property int chartPeak: {
    var peak = 1
    for (var i = 0; i < dailySeries.length; i++) {
      var c = Number(dailySeries[i].count)
      if (isFinite(c) && c > peak) peak = c
    }
    return peak
  }
  readonly property int hourPeak: {
    var peak = 1
    for (var i = 0; i < hourSeries.length; i++) {
      var c = Number(hourSeries[i])
      if (isFinite(c) && c > peak) peak = c
    }
    return peak
  }

  function formatHour(hour) {
    if (hour === null || hour === undefined || hour === "") return "—"
    var h = Number(hour)
    if (!isFinite(h)) return "—"
    h = Math.round(h)
    var twelve = h % 12
    if (twelve === 0) twelve = 12
    return twelve + (h < 12 ? "AM" : "PM")
  }

  function formatDuration(seconds) {
    if (seconds === null || seconds === undefined || seconds === "") return "—"
    var s = Number(seconds)
    if (!isFinite(s)) return "—"
    s = Math.max(0, Math.round(s))
    var m = Math.floor(s / 60)
    var r = s % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }

  function formatAvgTemp(temp) {
    if (temp === null || temp === undefined || temp === "") return "—"
    var n = Number(temp)
    if (!isFinite(n)) return "—"
    return formatTemp(n, undefined)
  }

  // Heat timer: the Peak reports seconds spent in the current state and the
  // state's planned length. Between polls the panel ticks the elapsed time
  // forward itself, so the ring moves smoothly instead of jumping every 2 s.
  property real timerSampledAt: 0
  property real nowMs: Date.now()
  readonly property real stateTotalS: {
    var n = Number(statusData.state_total_s)
    return statusData.state_total_s !== null && isFinite(n) && n > 0 ? n : NaN
  }
  readonly property real stateElapsedS: {
    var n = Number(statusData.state_elapsed_s)
    if (statusData.state_elapsed_s === null || !isFinite(n)) return NaN
    return n + Math.max(0, nowMs - timerSampledAt) / 1000
  }
  readonly property bool timerActive: (preheating || atTemp)
    && isFinite(stateTotalS) && isFinite(stateElapsedS)
  readonly property real timerProgress: timerActive
    ? Math.max(0, Math.min(1, stateElapsedS / stateTotalS)) : 0
  readonly property int timerSecondsLeft: timerActive
    ? Math.max(0, Math.ceil(stateTotalS - stateElapsedS)) : 0

  // Fault log: read on request, since the first read walks hundreds of entries.
  property var faultLog: null
  property bool faultsLoading: false
  property bool faultError: false
  property int faultShown: 8

  property bool connecting: false
  property string connectError: ""
  property bool connectFailed: false
  property bool scanning: false
  // null until Find nearby Peaks has run.
  property var nearbyPeaks: null
  readonly property string connectMessage: connectError !== ""
    ? connectError
    : (connectFailed ? "Couldn't connect. Wake the Peak, keep it close, and try again." : "")
  // Set when `quickpuff` isn't installed or its daemon isn't running, e.g. right
  // after `omarchy plugin add` without install.sh.
  property bool needsSetup: false
  readonly property string installScript: Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, "")
  property bool confirmPowerOff: false
  property var pendingStealth: undefined
  property var pendingLantern: undefined
  property var pendingSaver: undefined
  property var pendingQtip: undefined
  property int pendingCleanEvery: -1
  property int pendingBrightness: -1
  property string page: "control"
  property string pendingDeviceName: ""

  readonly property bool onControl: page === "control"
  readonly property bool onLights: page === "lights"
  readonly property bool onUsage: page === "usage"
  readonly property bool onCare: page === "care"
  readonly property bool onDevice: page === "device"

  readonly property var pageOptions: [
    { "value": "control", "label": "Control", "glyph": "\uf1de" },
    { "value": "lights", "label": "Lights", "glyph": "\uf0eb" },
    { "value": "usage", "label": "Usage", "glyph": "\uf201" },
    // A dot on Care while the chamber is due a clean, so it isn't missed from Control.
    { "value": "care", "label": "Care", "glyph": "\uf004", "badge": cleanDue },
    { "value": "device", "label": "Device", "glyph": "\uf2db" }
  ]

  property string deviceTab: "info"
  property string usageTab: "stats"
  readonly property bool onUsageStats: onUsage && usageTab === "stats"
  readonly property bool onUsageHistory: onUsage && usageTab === "history"
  readonly property var usageTabOptions: [
    { "value": "stats", "label": "Stats", "glyph": "\uf080" },
    { "value": "history", "label": "History", "glyph": "\uf1da" }
  ]

  // History: recent dabs with notes, read on demand.
  property var sessionList: null
  property int sessionTotal: 0
  property bool sessionsLoading: false
  property int sessionLimit: 30
  property string noteKey: ""
  // Notes saved but not yet read back from the daemon, by session key.
  property var pendingNotes: ({})
  readonly property int trackedTotal: Number(telemetry.tracked_total) || 0
  onOnUsageHistoryChanged: if (onUsageHistory) loadSessions()
  onTrackedTotalChanged: if (onUsageHistory) loadSessions()

  property int pendingDailyLimit: -1
  readonly property int dailyLimit: pendingDailyLimit >= 0 ? pendingDailyLimit : (Number(statusData.daily_limit) || 0)
  property var pendingRecap: undefined
  readonly property bool recapOn: pendingRecap !== undefined ? pendingRecap === true : statusData.weekly_recap !== false

  function stepDailyLimit(delta) {
    var next = Math.max(0, Math.min(50, dailyLimit + delta))
    pendingDailyLimit = next
    run("quickpuff limit " + next)
  }

  function toggleRecap() {
    var next = !recapOn
    pendingRecap = next
    run("quickpuff recap " + (next ? "on" : "off"))
  }

  function loadSessions() {
    if (sessionsProc.running) return
    sessionsLoading = true
    sessionsProc.command = ["bash", "-lc", "quickpuff --json sessions --limit \"$1\"", "quickpuff-sessions", String(sessionLimit)]
    sessionsProc.running = true
  }

  function editNote(key) {
    noteKey = String(key)
  }

  function closeNote(key) {
    if (noteKey !== key) return
    noteKey = ""
    Qt.callLater(function() { if (root.opened && keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function noteFor(session) {
    var key = String(session.key || "")
    return pendingNotes[key] !== undefined ? pendingNotes[key] : String(session.note || "")
  }

  function saveNote(key, raw) {
    var text = String(raw || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
    var copy = Object.assign({}, pendingNotes)
    copy[key] = text
    pendingNotes = copy
    closeNote(key)
    runArgv(text === "" ? ["quickpuff", "note", key] : ["quickpuff", "note", key, text])
    noteReload.restart()
  }

  function sessionTitle(session) {
    var bits = []
    if (session.profile !== null && session.profile !== undefined) bits.push(profileUsageName(session.profile))
    if (session.temp_f !== null && session.temp_f !== undefined) bits.push(formatTemp(session.temp_f, session.temp_c))
    return bits.length ? bits.join(" \u00b7 ") : "Dab"
  }

  function sessionDetail(session) {
    var bits = []
    if (Number(session.preheat_s) > 0) bits.push("Heated up in " + Math.round(Number(session.preheat_s)) + " s")
    if (Number(session.battery) > 0) bits.push("Battery " + Math.round(Number(session.battery)) + "% after")
    return bits.join(" · ")
  }

  function formatSessionTime(ts) {
    return Qt.formatDateTime(new Date(Number(ts) * 1000), "ddd MMM d, h:mm AP")
  }
  readonly property bool onDeviceInfo: onDevice && deviceTab === "info"
  readonly property bool onDeviceTips: onDevice && deviceTab === "tips"
  readonly property var deviceTabOptions: [
    { "value": "info", "label": "Info", "glyph": "\uf05a" },
    { "value": "tips", "label": "Tips", "glyph": "\uf0eb" }
  ]

  // Factory Peak Pro presets (Connect: Blue / Green / Red / White).
  readonly property var stockHeats: [
    { "name": "Low", "color": "Blue", "temp_f": 490, "note": "Flavor" },
    { "name": "Med", "color": "Green", "temp_f": 510, "note": "Balanced" },
    { "name": "High", "color": "Red", "temp_f": 530, "note": "Vapor" },
    { "name": "Peak", "color": "White", "temp_f": 545, "note": "Clouds" }
  ]

  readonly property var peakTips: [
    { "title": "Load small", "body": "Rice-grain on the bowl floor, not the walls." },
    { "title": "Swab while warm", "body": "Dry Q-tip after every hit. Iso only for leftover residue." },
    { "title": "Iso soak", "body": "90%+ iso, 20 minutes, when it tastes off. Never water in the chamber." },
    { "title": "Fill glass off the base", "body": "Water just above the perc slots. Empty it overnight." },
    { "title": "Slow inhale", "body": "Cap snug. Hard pulls cool the bowl and pull reclaim." },
    { "title": "Sleep it", "body": "Lock or sleep between sessions. Phone app and this panel can't share the Peak." }
  ]

  readonly property var peakLights: [
    { "title": "3 white flashes", "body": "No chamber. Reseat it." },
    { "title": "Red-white", "body": "Chamber error. Iso soak, dry, retry." },
    { "title": "Solid red", "body": "Overheating. Let it sit." }
  ]

  function applyLightColor(hex) {
    if (currentProfile < 0) return
    pendingLantern = true
    // A steady colour replaces any cycle on this profile.
    cycleApplyTimer.stop()
    if (activeCycle !== null || pendingCycleOn === true) pendingCycleOn = false
    pendingLightId = "-"
    var updated = {}
    for (var key in pendingColors) updated[key] = pendingColors[key]
    updated[currentProfile] = hex
    pendingColors = updated
    // Also paints the live lantern, without reselecting the heat profile
    // (which flashes factory green over the new colour).
    runArgv(["quickpuff", "color", hex, "--index", String(currentProfile)])
    clearPendingTimer.restart()
  }

  // ------------------------------------------------------- colour cycle
  // The Peak animates these itself (`quickpuff cycle`). The panel keeps an
  // editable copy seeded from what the active profile is doing; while the
  // cycle is on, every edit is sent once the taps settle.
  // The Puffco app's animations for the Peak Pro (Breathe is from an older
  // app release; Lava Lamp and Confetti run on the Peak's particle engine).
  readonly property var cycleStyles: [
    { "value": "fade", "label": "Fade", "glyph": "" },
    { "value": "spin", "label": "Spin", "glyph": "" },
    { "value": "breathe", "label": "Breathe", "glyph": "" },
    { "value": "disco", "label": "Disco", "glyph": "" },
    { "value": "split", "label": "Split", "glyph": "" },
    { "value": "fill", "label": "Fill", "glyph": "" },
    { "value": "lava", "label": "Lava", "glyph": "" },
    { "value": "confetti", "label": "Confetti", "glyph": "" }
  ]
  readonly property var cyclePalettes: [
    { "name": "Rainbow", "colors": ["#ff0000", "#ffaa00", "#f6f600", "#00e05a", "#0080ff", "#a020ff"] },
    { "name": "Sunset", "colors": ["#ff2d55", "#ff6a1a", "#ffb000"] },
    { "name": "Ocean", "colors": ["#0040ff", "#00b4ff", "#00ffd0"] },
    { "name": "Vapor", "colors": ["#ff4fa3", "#a855f7", "#3b9eff"] },
    { "name": "Fire", "colors": ["#ff1a00", "#ff5a00", "#ffae00"] },
    { "name": "Forest", "colors": ["#1f8f3a", "#8fd400", "#00c090"] }
  ]
  readonly property int maxCycleColors: 6

  property string cycleStyle: "fade"
  property var cycleColors: cyclePalettes[0].colors
  property real cycleTempo: 0.5
  property bool cycleInhale: false
  property var pendingCycleOn: undefined
  readonly property var activeCycle: activeProfile && activeProfile.cycle ? activeProfile.cycle : null
  readonly property bool cycleOn: pendingCycleOn !== undefined ? pendingCycleOn === true : activeCycle !== null

  function seedCycle() {
    var c = activeCycle
    if (!c) return
    // A captured exclusive mood reads as "custom": keep the editor's own
    // style rather than showing none picked.
    for (var i = 0; i < cycleStyles.length; i++)
      if (cycleStyles[i].value === c.style) cycleStyle = String(c.style)
    if (c.colors && c.colors.length) cycleColors = c.colors.slice(0, maxCycleColors)
    var t = Number(c.tempo)
    if (isFinite(t)) cycleTempo = Math.max(0.1, Math.min(1, t))
    cycleInhale = c.inhale === true
  }
  onCurrentProfileChanged: seedCycle()
  onActiveCycleChanged: if (!cycleApplyTimer.running && pendingCycleOn === undefined) seedCycle()

  function sendCycle() {
    if (currentProfile < 0 || cycleColors.length === 0) return
    var argv = ["quickpuff", "cycle", cycleStyle].concat(cycleColors)
    argv.push("--speed", String(Math.round(cycleTempo * 100)), "--index", String(currentProfile))
    if (cycleInhale) argv.push("--inhale")
    pendingLantern = true
    pendingLightId = "-"
    runArgv(argv)
    clearPendingTimer.restart()
  }

  function cycleEdited() {
    if (cycleOn) cycleApplyTimer.restart()
  }

  function setCycleOn(on) {
    cycleApplyTimer.stop()
    pendingCycleOn = on
    if (on) {
      sendCycle()
    } else {
      // Back to a steady light, in the cycle's first colour.
      applyLightColor(cycleColors.length ? cycleColors[0] : "#ffffff")
      pendingCycleOn = false
    }
  }

  function pickCycleStyle(style) { cycleStyle = style; cycleEdited() }
  function pickCyclePalette(colors) { cycleColors = colors.slice(0, maxCycleColors); cycleEdited() }
  function setCycleTempo(t) { cycleTempo = Math.max(0.1, Math.min(1, t)); cycleEdited() }
  function toggleCycleInhale() { cycleInhale = !cycleInhale; cycleEdited() }

  // ---------------------------------------------------- saved lights
  // Lights copied off the Peak (`quickpuff light`), exclusive moods included.
  readonly property var savedLights: statusData.saved_lights || []
  readonly property string activeLightId: activeProfile && activeProfile.light_id ? String(activeProfile.light_id) : ""
  // "-" means an edit just replaced whatever saved light the profile wore.
  property string pendingLightId: ""
  readonly property string wornLightId: pendingLightId !== "" ? pendingLightId : activeLightId
  readonly property bool wearingSaved: {
    for (var i = 0; i < savedLights.length; i++) if (savedLights[i].id === wornLightId) return true
    return false
  }
  property bool namingLight: false
  property string renamingLight: ""
  property string confirmDeleteLight: ""

  function applySavedLight(id) {
    if (currentProfile < 0) return
    cycleApplyTimer.stop()
    pendingLightId = String(id)
    pendingCycleOn = undefined
    pendingLantern = true
    runArgv(["quickpuff", "light", "apply", String(id), "--index", String(currentProfile)])
    clearPendingTimer.restart()
  }

  function cleanLightName(raw) {
    return String(raw || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  }

  function saveCurrentLight(raw) {
    var name = cleanLightName(raw)
    namingLight = false
    refocusPanel()
    if (name === "" || currentProfile < 0) return
    runArgv(["quickpuff", "light", "save", name, "--index", String(currentProfile)])
  }

  function renameSavedLight(id, raw) {
    var name = cleanLightName(raw)
    renamingLight = ""
    refocusPanel()
    if (name === "") return
    runArgv(["quickpuff", "light", "rename", String(id), name])
  }

  function deleteSavedLight(id) {
    if (confirmDeleteLight !== id) {
      confirmDeleteLight = id
      confirmDeleteTimer.restart()
      return
    }
    confirmDeleteLight = ""
    runArgv(["quickpuff", "light", "delete", String(id)])
  }

  function refocusPanel() {
    Qt.callLater(function() { if (root.opened && keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // A second tap on delete within a few seconds confirms it.
  Timer {
    id: confirmDeleteTimer
    interval: 3000
    onTriggered: root.confirmDeleteLight = ""
  }

  function addCycleColor(hex) {
    var h = profileSwatch(hex)
    if (h === "" || cycleColors.length >= maxCycleColors) return
    cycleColors = cycleColors.concat([h.toLowerCase()])
    cycleEdited()
  }

  function removeCycleColor(i) {
    if (cycleColors.length <= 1) return
    var next = cycleColors.slice()
    next.splice(i, 1)
    cycleColors = next
    cycleEdited()
  }

  Timer {
    id: cycleApplyTimer
    interval: 600
    onTriggered: root.sendCycle()
  }

  readonly property bool anyCycle: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].cycle) return true
    return false
  }

  // Drives the panel's previews of the cycle; roughly the Peak's pace.
  property int cycleTick: 0
  readonly property int cycleStepMs: Math.round(1500 - 1250 * cycleTempo)
  readonly property color cycleNow: cycleColors.length
    ? cycleColors[cycleTick % cycleColors.length] : Color.accent
  Timer {
    interval: root.cycleStepMs
    repeat: true
    running: root.opened && (root.cycleOn || root.onLights || root.anyCycle)
    onTriggered: root.cycleTick = (root.cycleTick + 1) % 720
  }

  // ------------------------------------------------ custom colour picker
  // Hue/saturation from the wheel, value from the slider, all 0..1. Seeded
  // from the profile's current colour whenever the picker opens.
  property bool pickerOpen: false
  property real pickH: 0
  property real pickS: 1
  property real pickV: 1
  readonly property color pickColor: Qt.hsva(pickH, pickS, pickV, 1)
  readonly property string pickHex: hexOf(pickColor)
  readonly property string activeLightHex: activeProfile ? profileColor(currentProfile, activeProfile.color) : ""
  readonly property bool customLight: {
    if (activeLightHex === "") return false
    for (var i = 0; i < colorPalette.length; i++)
      if (colorPalette[i].toLowerCase() === activeLightHex.toLowerCase()) return false
    return true
  }

  function hexOf(c) {
    function two(x) {
      var n = Math.max(0, Math.min(255, Math.round(x * 255)))
      return (n < 16 ? "0" : "") + n.toString(16)
    }
    return "#" + two(c.r) + two(c.g) + two(c.b)
  }

  function seedPicker(hex) {
    var s = profileSwatch(hex)
    if (s === "") return
    var c = Qt.color(s)
    pickV = c.hsvValue
    // Grey has no hue; keep whatever the wheel was on instead of snapping to red.
    if (c.hsvSaturation > 0) pickH = Math.max(0, c.hsvHue)
    pickS = c.hsvSaturation
  }

  function togglePicker() {
    if (!pickerOpen) seedPicker(activeLightHex !== "" ? activeLightHex : "#ff0000")
    pickerOpen = !pickerOpen
  }

  // Typed hex ("#12abef", "12abef", "#1af"): lands on the wheel and the Peak.
  function applyTypedHex(raw) {
    var s = String(raw || "").replace(/^\s+|\s+$/g, "").replace(/^#/, "")
    if (/^[0-9a-fA-F]{3}$/.test(s)) s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
    if (!/^[0-9a-fA-F]{6}$/.test(s)) return false
    seedPicker("#" + s)
    pickApplyTimer.stop()
    if (!cycleOn) applyLightColor("#" + s.toLowerCase())
    return true
  }

  // Drags and slides land on the Peak once the pointer lets go, coalesced
  // so a wheel release plus a nudge of the slider is one BLE write.
  function schedulePickApply() { pickApplyTimer.restart() }

  Timer {
    id: pickApplyTimer
    interval: 300
    // While a cycle runs the wheel is a chooser for it, not a solid colour.
    onTriggered: if (!root.cycleOn) root.applyLightColor(root.pickHex)
  }

  readonly property var vaporLevels: [
    { "value": "smooth", "label": "Smooth" },
    { "value": "bold", "label": "Bold" },
    { "value": "intense", "label": "Intense" },
    { "value": "extreme", "label": "Extreme" }
  ]

  function profileVapor(index, fallback) {
    var pending = pendingVapors[index]
    if (pending !== undefined) return pending
    return String(fallback || "")
  }

  function applyVapor(name) {
    if (currentProfile < 0) return
    var updated = {}
    for (var key in pendingVapors) updated[key] = pendingVapors[key]
    updated[currentProfile] = name
    pendingVapors = updated
    runArgv(["quickpuff", "profile", String(currentProfile), "--vapor", name])
    clearPendingTimer.restart()
  }

  readonly property real minBoostTempF: 0
  readonly property real maxBoostTempF: 36
  readonly property int boostTempStepF: 2
  readonly property real minBoostTimeS: 0
  readonly property real maxBoostTimeS: 60
  readonly property int boostTimeStepS: 5
  property var pendingBoostTemps: ({})
  property var pendingBoostTimes: ({})

  function profileBoostTempF(index, fallback) {
    var pending = pendingBoostTemps[index]
    if (pending !== undefined) return pending
    var n = Number(fallback)
    return isFinite(n) ? n : 0
  }

  function profileBoostTime(index, fallback) {
    var pending = pendingBoostTimes[index]
    if (pending !== undefined) return pending
    var n = Number(fallback)
    return isFinite(n) ? n : 0
  }

  function clampBoostTempF(value) {
    return Math.max(minBoostTempF, Math.min(maxBoostTempF, Math.round(value)))
  }

  function clampBoostTime(value) {
    return Math.max(minBoostTimeS, Math.min(maxBoostTimeS, Math.round(value)))
  }

  function formatBoostTemp(f) {
    var n = Number(f)
    if (!isFinite(n)) n = 0
    if (celsius) return "+" + Math.round(n * 5 / 9) + "°C"
    return "+" + Math.round(n) + "°F"
  }

  function canStepBoostTemp(index, fallback, delta) {
    if (index < 0) return false
    var current = profileBoostTempF(index, fallback)
    return clampBoostTempF(current + delta) !== Math.round(current)
  }

  function canStepBoostTime(index, fallback, delta) {
    if (index < 0) return false
    var current = profileBoostTime(index, fallback)
    return clampBoostTime(current + delta) !== Math.round(current)
  }

  function stepBoostTemp(index, fallback, delta) {
    if (!canStepBoostTemp(index, fallback, delta)) return
    var updated = {}
    for (var key in pendingBoostTemps) updated[key] = pendingBoostTemps[key]
    updated[index] = clampBoostTempF(profileBoostTempF(index, fallback) + delta)
    pendingBoostTemps = updated
    commitWriteTimer.restart()
  }

  function stepBoostTime(index, fallback, delta) {
    if (!canStepBoostTime(index, fallback, delta)) return
    var updated = {}
    for (var key in pendingBoostTimes) updated[key] = pendingBoostTimes[key]
    updated[index] = clampBoostTime(profileBoostTime(index, fallback) + delta)
    pendingBoostTimes = updated
    commitWriteTimer.restart()
  }

  function commitBoost() {
    var seen = {}
    for (var key in pendingBoostTemps) seen[key] = true
    for (key in pendingBoostTimes) seen[key] = true
    for (key in seen) {
      var index = Math.round(Number(key))
      if (!isFinite(index) || index < 0) continue
      var args = ["quickpuff", "profile", String(index)]
      if (pendingBoostTemps[key] !== undefined)
        args.push("--boost-temp", String(Math.round(pendingBoostTemps[key])))
      if (pendingBoostTimes[key] !== undefined)
        args.push("--boost-time", String(Math.round(pendingBoostTimes[key])))
      runArgv(args)
    }
  }

  readonly property string shownDeviceName: {
    if (pendingDeviceName !== "") return pendingDeviceName
    return deviceName
  }

  function commitDeviceName(raw) {
    var name = String(raw || "").replace(/^\s+|\s+$/g, "")
    cancelEdit()
    if (name === "") return
    pendingDeviceName = name
    runArgv(["quickpuff", "name", name])
    clearPendingTimer.restart()
  }

  readonly property bool stealthOn: pendingStealth !== undefined
    ? pendingStealth === true
    : statusData.stealth === true
  readonly property bool lanternOn: pendingLantern !== undefined
    ? pendingLantern === true
    : statusData.lantern === true
  readonly property bool qtipOn: pendingQtip !== undefined
    ? pendingQtip === true
    : statusData.qtip_reminder === true
  readonly property bool saverOn: pendingSaver !== undefined
    ? pendingSaver === true
    : statusData.battery_saver === true
  readonly property int cleanEveryMin: 10
  readonly property int cleanEveryMax: 100
  readonly property int cleanEveryStep: 10
  readonly property int cleanEvery: {
    if (pendingCleanEvery >= 0) return pendingCleanEvery
    var n = Number(statusData.clean_every)
    return isFinite(n) && n > 0 ? Math.round(n) : 30
  }
  readonly property int cleanRemaining: {
    var rem = Number(statusData.clean_remaining)
    if (!isFinite(rem)) rem = cleanEvery
    if (pendingCleanEvery < 0) return Math.max(0, Math.round(rem))
    var every = Number(statusData.clean_every)
    if (!isFinite(every) || every <= 0) every = 30
    var used = Math.max(0, every - rem)
    return Math.max(0, pendingCleanEvery - used)
  }
  readonly property bool cleanDue: cleanRemaining <= 0
  readonly property int brightnessLevel: {
    if (pendingBrightness >= 0) return pendingBrightness
    var b = statusData.brightness || ({})
    var n = Number(b.base)
    return isFinite(n) ? Math.round(n) : 80
  }

  function finishSetup() {
    Util.execArgv(["xdg-terminal-exec", "bash", "-c",
      "\"$1\"; echo; read -rp 'Press Enter to close'", "quickpuff-setup", root.installScript])
  }

  function readFaults() {
    if (faultProc.running) return
    faultsLoading = true
    faultError = false
    faultProc.running = true
  }

  function closeFaults() {
    faultLog = null
    faultError = false
    faultShown = 8
  }

  function formatFaultTime(ts) {
    if (ts === null || ts === undefined) return "Before last restart"
    return Qt.formatDateTime(new Date(Number(ts) * 1000), "MMM d, h:mm AP")
  }

  function faultGlyph(code) {
    if (code === 11) return "\uf293"                               // bluetooth
    if (code >= 3 && code <= 8) return "\uf06d"                    // heater
    return "\uf243"                                                // battery
  }

  // `mac` picks one Peak from Find nearby Peaks; without it the daemon uses
  // the last Peak. Runs as a process so a failure can say why.
  function connectDevice(mac) {
    if (connectProc.running) return
    connecting = true
    connectError = ""
    connectFailed = false
    connectGiveUp.restart()
    connectProc.command = mac
      ? ["bash", "-lc", "quickpuff connect --mac \"$1\"", "quickpuff-connect", String(mac)]
      : ["bash", "-lc", "quickpuff connect"]
    connectProc.running = true
  }

  function findPeaks() {
    if (scanProc.running) return
    scanning = true
    connectFailed = false
    scanProc.running = true
  }

  // Frees the Peak's single Bluetooth link for the phone app or another
  // computer; nothing reconnects until Connect is pressed again.
  function disconnectDevice() {
    connecting = false
    connectGiveUp.stop()
    run("quickpuff disconnect")
  }

  function toggleStealth() {
    var next = !stealthOn
    pendingStealth = next
    run("quickpuff stealth " + (next ? "on" : "off"))
  }

  function toggleLantern() {
    var next = !lanternOn
    pendingLantern = next
    run("quickpuff lantern " + (next ? "on" : "off"))
  }

  function toggleQtip() {
    var next = !qtipOn
    pendingQtip = next
    run("quickpuff qtip " + (next ? "on" : "off"))
  }

  function toggleSaver() {
    var next = !saverOn
    pendingSaver = next
    if (next) pendingLantern = false
    run("quickpuff saver " + (next ? "on" : "off"))
  }

  function clampCleanEvery(value) {
    var n = Math.round(Number(value) / cleanEveryStep) * cleanEveryStep
    return Math.max(cleanEveryMin, Math.min(cleanEveryMax, n))
  }

  function canStepCleanEvery(delta) {
    return clampCleanEvery(cleanEvery + delta) !== cleanEvery
  }

  function stepCleanEvery(delta) {
    if (!canStepCleanEvery(delta)) return
    pendingCleanEvery = clampCleanEvery(cleanEvery + delta)
    commitWriteTimer.restart()
  }

  function markCleaned() {
    pendingCleanEvery = -1
    run("quickpuff clean done")
  }

  function setBrightness(value) {
    pendingBrightness = Math.max(0, Math.min(255, Math.round(Number(value))))
    commitBrightnessTimer.restart()
  }

  // ---------------------------------------------------- ready animation
  // Played by the bar widget over the desktop (ReadyOverlay.qml); the choice
  // lives in quickpuff's config.
  readonly property var readyAnimations: [
    { "value": "off", "label": "Off", "glyph": "\uf05e" },
    { "value": "confetti", "label": "Confetti", "glyph": "\uf0d0" },
    { "value": "rocket", "label": "Rocket", "glyph": "\uf135" }
  ]
  property string configReadyAnimation: "rocket"
  property string pendingReadyAnimation: ""
  readonly property string readyAnimation: pendingReadyAnimation !== "" ? pendingReadyAnimation : configReadyAnimation

  function setReadyAnimation(value) {
    pendingReadyAnimation = value
    runArgv(["quickpuff", "ready-anim", value])
  }
  onConfigReadyAnimationChanged: pendingReadyAnimation = ""

  // The show launches right where this panel sits, so get out of its way.
  function previewReadyAnimation() {
    if (readyAnimation === "off" || !hostWidget || typeof hostWidget.playReady !== "function") return
    close()
    previewTimer.restart()
  }

  Timer {
    id: previewTimer
    interval: 450
    onTriggered: if (root.hostWidget) root.hostWidget.playReady(root.readyAnimation)
  }

  // --------------------------------------------------- lantern auto-off
  // The daemon clamps to 1 min – 8 h; the stepper walks these stops.
  readonly property var lanternTimeoutStops: [60, 300, 600, 900, 1800, 3600, 7200, 14400, 28800]
  property real pendingLanternTimeout: -1
  readonly property real lanternTimeout: {
    if (pendingLanternTimeout > 0) return pendingLanternTimeout
    var n = Number(statusData.lantern_timeout)
    return isFinite(n) && n > 0 ? n : 1800
  }
  readonly property int lanternTimeoutStop: {
    var best = 0
    for (var i = 0; i < lanternTimeoutStops.length; i++)
      if (Math.abs(lanternTimeoutStops[i] - lanternTimeout) < Math.abs(lanternTimeoutStops[best] - lanternTimeout)) best = i
    return best
  }

  function formatTimeout(seconds) {
    var m = Math.round(Number(seconds) / 60)
    if (m < 60) return m + " min"
    var h = Math.floor(m / 60), r = m % 60
    return h + " h" + (r ? " " + r + " min" : "")
  }

  function stepLanternTimeout(delta) {
    var i = Math.max(0, Math.min(lanternTimeoutStops.length - 1, lanternTimeoutStop + delta))
    pendingLanternTimeout = lanternTimeoutStops[i]
    lanternTimeoutTimer.restart()
  }

  Timer {
    id: lanternTimeoutTimer
    interval: 450
    onTriggered: {
      root.runArgv(["quickpuff", "lantern", "--timeout", String(Math.round(root.pendingLanternTimeout))])
      clearPendingTimer.restart()
    }
  }

  // ------------------------------------------------------- heat graph
  // The chamber's temperature over the current (or last) session, recorded
  // by the daemon so opening the panel mid-session still shows the climb.
  readonly property var heatTrace: statusData.heat_trace || null
  readonly property var heatPoints: heatTrace && heatTrace.points ? heatTrace.points : []
  readonly property bool heatTraceLive: heatTrace !== null && heatTrace.active === true
  readonly property real heatPeakF: {
    var peak = NaN
    for (var i = 0; i < heatPoints.length; i++) {
      var f = Number(heatPoints[i][1])
      if (isFinite(f) && !(f <= peak)) peak = f
    }
    return peak
  }

  function commitBrightness() {
    if (pendingBrightness < 0) return
    runArgv(["quickpuff", "brightness", String(pendingBrightness)])
    clearPendingTimer.restart()
  }

  // The heat state drives the hero glyph's color, and mirrors the bar widget's
  // own active tint so the two surfaces never disagree at a glance.
  readonly property color heatColor: heating ? urgent : (cooling ? Color.accent : dim)

  // The hero's status dot: warm while heating, the theme accent while idle
  // and connected, faded while there's nothing to talk to.
  readonly property color stateColor: needsSetup ? urgent
    : heating ? urgent
    : connected ? Color.accent
    : dim

  // Tint for the active profile: the colour its lantern glows, else accent.
  readonly property color profileTint: {
    if (!activeProfile) return Color.accent
    var hex = profileColor(currentProfile, activeProfile.color)
    return hex !== "" ? hex : Color.accent
  }

  // How far the chamber has climbed toward the active profile's target, for
  // the hero ring. Full while at temp, empty while idle.
  readonly property real heatProgress: {
    if (!connected) return 0
    if (atTemp) return 1
    if (!preheating && !cooling) return 0
    var t = Number(statusData.heater_temp_f)
    var goal = activeProfile ? Number(activeProfile.temp_f) : NaN
    if (!isFinite(t) || !isFinite(goal) || goal <= 80) return 0
    return Math.max(0, Math.min(1, (t - 80) / (goal - 80)))
  }

  // One friendly line under the device name; the state itself stays in the
  // small-caps meta line above it.
  readonly property string moodLine: {
    if (needsSetup) return "Let's get the background service running"
    if (!connected) {
      if (resting) return "Catching a few z's to save battery"
      if (handedOff) return "Hanging out with another computer"
      if (connecting) return "Reaching out to your Peak…"
      return "Asleep. Wake it up to say hi"
    }
    if (preheating) return "Warming up, hang tight"
    if (atTemp) return "Ready. Slow pull, big flavor"
    if (cooling) return "Cooling off"
    if (lowHeatBattery) return "Running low, plug in soon"
    if (cleanDue) return "Due for a swab"
    return "Ready when you are"
  }

  // Readable glyph colour on top of an arbitrary swatch.
  function inkOn(hex) {
    var c = Qt.color(String(hex))
    return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#161616" : "#ffffff"
  }

  readonly property var stockSwatches: ({ "Blue": "#3b9eff", "Green": "#3dd68c", "Red": "#ff4d4d", "White": "#ffffff" })

  // A celebratory pop the moment the chamber reaches temperature.
  onAtTempChanged: if (atTemp && opened) heroBurst.fire()

  // Profiles carry the LED color the device glows for them; it's how the app's
  // own editor identifies them, so the tiles show the same swatch. Anything
  // that isn't a plain 6-digit hex is dropped rather than handed to QML.
  function profileSwatch(raw) {
    var s = String(raw || "")
    return /^#[0-9A-Fa-f]{6}$/.test(s) ? s : ""
  }

  readonly property var colorPalette: [
    "#3b9eff", "#3dd68c", "#ff4d4d", "#ffffff",
    "#ff6a1a", "#a855f7", "#f6d32d", "#99ffff"
  ]

  function profileColor(index, fallback) {
    var pending = pendingColors[index]
    if (pending !== undefined) return pending
    return profileSwatch(fallback)
  }

  // The device's name field is a fixed-size buffer that a shorter write
  // doesn't clear, so a renamed profile can read back as "New\0ldTail".
  function cleanName(raw) {
    var s = String(raw || "")
    var cut = s.indexOf("\u0000")
    if (cut >= 0) s = s.slice(0, cut)
    return s.replace(/^\s+|\s+$/g, "")
  }

  // ------------------------------------------------- profile temperature
  //
  // The daemon is the one chokepoint that clamps to the Peak Pro's rated
  // range; mirroring it here is what lets the steppers go inert at the ends
  // and typed values land in range instead of being clamped out of sight.
  readonly property real minTempF: 400
  readonly property real maxTempF: 620
  readonly property int tempStepF: 5
  readonly property real minTimeS: 5
  readonly property real maxTimeS: 180
  readonly property int timeStepS: 5

  // Optimistic per-index overrides, so a burst of taps steps by 5 each time
  // instead of each tap recomputing from the same not-yet-refreshed status,
  // and the writes coalesce into one BLE round trip.
  property var pendingTemps: ({})
  property var pendingTimes: ({})
  property var pendingNames: ({})
  property var pendingColors: ({})
  property var pendingVapors: ({})

  function profileTempF(index, fallback) {
    var pending = pendingTemps[index]
    if (pending !== undefined) return pending
    var n = Number(fallback)
    return isFinite(n) ? n : NaN
  }

  function profileTime(index, fallback) {
    var pending = pendingTimes[index]
    if (pending !== undefined) return pending
    var n = Number(fallback)
    return isFinite(n) ? n : NaN
  }

  function profileName(index, fallback) {
    var pending = pendingNames[index]
    if (pending !== undefined) return pending
    return cleanName(fallback)
  }

  function clampTempF(value) {
    return Math.max(minTempF, Math.min(maxTempF, Math.round(value)))
  }

  function clampTime(value) {
    return Math.max(minTimeS, Math.min(maxTimeS, Math.round(value)))
  }

  function setPendingTemp(index, tempF) {
    var updated = {}
    for (var key in pendingTemps) updated[key] = pendingTemps[key]
    updated[index] = tempF
    pendingTemps = updated
    commitWriteTimer.restart()
  }

  function setPendingTime(index, seconds) {
    var updated = {}
    for (var key in pendingTimes) updated[key] = pendingTimes[key]
    updated[index] = seconds
    pendingTimes = updated
    commitWriteTimer.restart()
  }

  function canStepTemp(index, fallback, delta) {
    var current = profileTempF(index, fallback)
    if (index < 0 || !isFinite(current)) return false
    return clampTempF(current + delta) !== Math.round(current)
  }

  function canStepTime(index, fallback, delta) {
    var current = profileTime(index, fallback)
    if (index < 0 || !isFinite(current)) return false
    return clampTime(current + delta) !== Math.round(current)
  }

  function stepTemp(index, fallback, delta) {
    if (!canStepTemp(index, fallback, delta)) return
    setPendingTemp(index, clampTempF(profileTempF(index, fallback) + delta))
  }

  function stepTime(index, fallback, delta) {
    if (!canStepTime(index, fallback, delta)) return
    setPendingTime(index, clampTime(profileTime(index, fallback) + delta))
  }

  function commitTemps() {
    for (var key in pendingTemps) {
      var index = Math.round(Number(key))
      if (!isFinite(index) || index < 0) continue
      runArgv(["quickpuff", "profile", String(index), "--temp-f", String(Math.round(pendingTemps[key]))])
    }
  }

  function commitTimes() {
    for (var key in pendingTimes) {
      var index = Math.round(Number(key))
      if (!isFinite(index) || index < 0) continue
      runArgv(["quickpuff", "profile", String(index), "--time", String(Math.round(pendingTimes[key]))])
    }
  }

  function commitWrites() {
    commitTemps()
    commitTimes()
    commitBoost()
    if (pendingCleanEvery >= 0)
      runArgv(["quickpuff", "clean", "--every", String(pendingCleanEvery)])
    clearPendingTimer.restart()
  }

  // ------------------------------------------------------ inline editing
  property int editIndex: -1
  property string editField: ""
  readonly property bool editing: editField !== ""

  function startEdit(index, field) {
    if (index < 0 && field !== "device") return
    editIndex = index
    editField = field
  }

  function cancelEdit() {
    if (!editing) return
    editIndex = -1
    editField = ""
    // Hand keys back to the panel so Escape closes it again.
    Qt.callLater(function() { if (root.opened && keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Losing focus cancels — but only the edit that field actually owned. A
  // blur fired while tearing the field down (because a *different* field just
  // took over) must not cancel the edit that replaced it.
  function cancelEditFor(index, field) {
    if (editIndex === index && editField === field) cancelEdit()
  }

  function commitName(index, raw) {
    var name = String(raw || "").replace(/^\s+|\s+$/g, "")
    cancelEdit()
    if (index < 0 || name === "") return
    var updated = {}
    for (var key in pendingNames) updated[key] = pendingNames[key]
    updated[index] = name
    pendingNames = updated
    runArgv(["quickpuff", "profile", String(index), "--name", name])
    clearPendingTimer.restart()
  }

  function commitTemp(index, raw) {
    // Read the number out of whatever was typed ("550", "550°F", " 550 ") and
    // refuse anything that isn't one rather than shipping it to the daemon.
    var match = String(raw || "").match(/-?\d+(?:\.\d+)?/)
    cancelEdit()
    if (index < 0 || !match) return
    var typed = Number(match[0])
    if (!isFinite(typed)) return
    setPendingTemp(index, clampTempF(celsius ? cToF(typed) : typed))
  }

  function commitTime(index, raw) {
    var match = String(raw || "").match(/-?\d+(?:\.\d+)?/)
    cancelEdit()
    if (index < 0 || !match) return
    var typed = Number(match[0])
    if (!isFinite(typed)) return
    setPendingTime(index, clampTime(typed))
  }

  Process {
    id: statusProc
    command: ["bash", "-lc", "quickpuff --json status"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }
      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    onExited: function(exitCode) {
      if (exitCode !== 127) return
      root.needsSetup = true
      root.statusData = ({})
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!/daemon is not running/i.test(text)) return
        root.needsSetup = true
        root.statusData = ({})
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text) return
        try {
          root.statusData = JSON.parse(text)
          root.timerSampledAt = Date.now()
          root.nowMs = root.timerSampledAt
          root.needsSetup = false
          if (root.statusData.connected === true) {
            root.connecting = false
            connectGiveUp.stop()
            root.connectError = ""
            root.connectFailed = false
            root.nearbyPeaks = null
          }
        } catch (e) {
          // leave last-known state on a parse failure
        }
      }
    }
  }

  // `quickpuff --json status` waits on the daemon RPC; give up past that so a
  // stalled BLE call can't wedge the panel (a running Process can't be
  // re-run) and let the next poll retry.
  Timer {
    id: stallTimer
    interval: 8000
    onTriggered: {
      statusProc.running = false
      root.refreshPending = true
    }
  }

  Timer {
    id: kickTimer
    interval: 700
    onTriggered: root.refresh()
  }

  // Debounce a run of taps into a single write per profile.
  Timer {
    id: commitWriteTimer
    interval: 450
    onTriggered: root.commitWrites()
  }

  Timer {
    id: commitBrightnessTimer
    interval: 450
    onTriggered: root.commitBrightness()
  }

  Process {
    id: connectProc
    command: ["bash", "-lc", "quickpuff connect"]
    onExited: function(exitCode) {
      root.connecting = false
      connectGiveUp.stop()
      kickTimer.restart()
      if (exitCode !== 0) root.connectFailed = true
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var last = lines[lines.length - 1]
        if (last === "") return
        // Two or more Peaks in range: list them instead of guessing.
        if (/Multiple Peak/i.test(last)) {
          root.connectError = "More than one Peak is nearby. Pick yours below."
          root.findPeaks()
          return
        }
        root.connectError = last
      }
    }
  }

  Process {
    id: sessionsProc
    command: ["bash", "-lc", "quickpuff --json sessions --limit 30"]
    onExited: function(exitCode) {
      root.sessionsLoading = false
      if (exitCode !== 0 && root.sessionList === null) root.sessionList = []
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          root.sessionList = result.sessions || []
          root.sessionTotal = Number(result.total) || 0
          root.pendingNotes = ({})
        } catch (e) {
          if (root.sessionList === null) root.sessionList = []
        }
      }
    }
  }

  // Re-read after a note is saved, once the command has written it.
  Timer {
    id: noteReload
    interval: 1500
    onTriggered: root.loadSessions()
  }

  Process {
    id: scanProc
    command: ["bash", "-lc", "quickpuff --json scan --timeout 8"]
    onExited: function(exitCode) {
      root.scanning = false
      if (exitCode !== 0 && root.nearbyPeaks === null) root.nearbyPeaks = []
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.nearbyPeaks = JSON.parse(text).devices || []
        } catch (e) {
          root.nearbyPeaks = []
        }
      }
    }
  }

  Timer {
    id: connectGiveUp
    interval: 100000
    onTriggered: root.connecting = false
  }

  // Hand the readouts back to the device once the writes have had time to land
  // and be polled back. Never while a tap is still settling, or a nudge made
  // just before this fires would be dropped before it was sent.
  Timer {
    id: clearPendingTimer
    interval: 2500
    onTriggered: {
      if (commitWriteTimer.running || commitBrightnessTimer.running) return
      root.pendingTemps = ({})
      root.pendingTimes = ({})
      root.pendingNames = ({})
      root.pendingColors = ({})
      root.pendingVapors = ({})
      root.pendingBoostTemps = ({})
      root.pendingBoostTimes = ({})
      root.pendingStealth = undefined
      root.pendingLantern = undefined
      root.pendingSaver = undefined
      root.pendingCleanEvery = -1
      root.pendingBrightness = -1
      root.pendingDeviceName = ""
      if (!lanternTimeoutTimer.running) root.pendingLanternTimeout = -1
      if (!cycleApplyTimer.running) root.pendingCycleOn = undefined
      root.pendingLightId = ""
    }
  }

  // Only polls while the panel is open — the bar widget's own poll already
  // covers the compact label the rest of the time.
  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: faultProc
    command: ["bash", "-lc", "quickpuff --json faults"]
    onExited: function(exitCode) {
      root.faultsLoading = false
      if (exitCode !== 0) root.faultError = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text) return
        try {
          root.faultLog = JSON.parse(text).faults || []
          root.faultShown = 8
        } catch (e) {
          root.faultError = true
        }
      }
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.opened && (root.preheating || root.atTemp)
    onTriggered: root.nowMs = Date.now()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/quickpuff/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var cfg = JSON.parse(text() || "{}")
        root.units = String(cfg.units || "F").toUpperCase() === "C" ? "C" : "F"
        root.configReadyAnimation = String(cfg.ready_animation || "rocket")
      } catch (e) {
        root.units = "F"
      }
    }
    onLoadFailed: root.units = "F"
  }

  // Layer-shell panel rather than PopupCard: the tiles have text fields, and
  // an xdg-popup only receives keys once the compositor happens to route focus
  // through its parent surface.
  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: card.fittedContentWidth(Style.space(360))
    contentHeight: card.fittedContentHeight(content.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a tile field is open every key belongs to it, Escape included.
      blocked: root.editing
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: content
          width: scroller.width
          spacing: Style.spacing.panelGap

          // ---------- Hero: heat glyph · device + state · chamber temp ------
          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(heroOrb.height, heroLabels.implicitHeight, heroReadout.implicitHeight)

            HeatOrb {
              id: heroOrb
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(62)
              height: width
              progress: root.heatProgress
              tint: root.heatColor
              lit: root.heating
              climbing: root.preheating
              sleeping: !root.connected && !root.connecting && !root.needsSetup
            }

            Burst {
              id: heroBurst
              anchors.centerIn: heroOrb
              width: heroOrb.width
              height: width
            }

            Column {
              id: heroLabels
              anchors.left: heroOrb.right
              anchors.leftMargin: Style.space(12)
              anchors.right: heroReadout.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.deviceName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  id: stateDot
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.stateColor

                  Behavior on color { ColorAnimation { duration: 260 } }

                  // A soft halo that swells while something is happening.
                  Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width * 2.4
                    height: width
                    radius: width / 2
                    color: Util.alpha(root.stateColor, 0.28)
                    visible: root.heating || root.connecting || root.resting

                    SequentialAnimation on scale {
                      running: parent.visible && root.opened
                      loops: Animation.Infinite
                      NumberAnimation { from: 0.5; to: 1.0; duration: 900; easing.type: Easing.OutSine }
                      NumberAnimation { from: 1.0; to: 0.5; duration: 900; easing.type: Easing.InSine }
                    }
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - stateDot.width - parent.spacing
                  textFormat: Text.PlainText
                  text: root.metaLabel.toUpperCase()
                  color: root.connected ? root.stateColor : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  elide: Text.ElideRight

                  Behavior on color { ColorAnimation { duration: 260 } }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.moodLine
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.italic: true
                elide: Text.ElideRight
              }
            }

            Column {
              id: heroReadout
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              // Counts toward each new reading instead of snapping to it; once
              // it lands it shows the daemon's own label, so the two agree.
              Text {
                id: heroTemp
                anchors.right: parent.right
                textFormat: Text.PlainText

                property real rawF: Number(root.statusData.heater_temp_f)
                property real shownF: isFinite(rawF) ? rawF : 0
                Behavior on shownF { NumberAnimation { id: tempCount; duration: 700; easing.type: Easing.OutCubic } }

                text: !root.connected ? "—"
                  : !isFinite(rawF) || !tempCount.running ? root.tempLabel : root.formatTemp(shownF, undefined)
                color: !root.connected ? root.dim
                  : shownF > 120 ? Qt.tint(root.foreground,
                      Util.alpha(root.heatRamp(shownF), Math.min(1, (shownF - 120) / 200)))
                  : root.heating ? Qt.lighter(root.urgent, 1.15)
                  : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true

                Behavior on color { ColorAnimation { duration: 300 } }
              }

              BatteryPill {
                anchors.right: parent.right
                visible: root.connected && root.batteryLabel !== ""
              }
            }
          }

          Segmented {
            width: parent.width
            visible: root.connected
            options: root.pageOptions
            value: root.page
            onPicked: function(value) { root.page = value }
          }

          // ---------- Disconnected ----------
          Column {
            width: parent.width
            visible: !root.connected
            spacing: Style.spacing.controlGap

            ActionButton {
              width: parent.width
              label: root.needsSetup ? "Finish setup" : (root.resting ? "Waking…" : (root.handedOff ? "Take it back" : (root.connecting ? "Connecting…" : "Connect")))
              glyph: root.needsSetup ? "\uf0ad" : (root.connecting || root.resting ? "\uf110" : "\uf293")
              spinning: !root.needsSetup && (root.connecting || root.resting)
              tall: true
              pulse: !root.needsSetup && !root.connecting
              tint: Color.accent
              emphasized: true
              onActivated: root.needsSetup ? root.finishSetup() : root.connectDevice()
            }

            Text {
              width: parent.width
              visible: root.connectMessage !== "" && !root.connecting && !root.needsSetup
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.connectMessage
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ActionButton {
              width: parent.width
              visible: !root.needsSetup
              label: root.scanning ? "Searching\u2026" : "Find nearby Peaks"
              glyph: root.scanning ? "\uf110" : "\uf002"
              spinning: root.scanning
              onActivated: root.findPeaks()
            }

            Repeater {
              model: root.scanning || !root.nearbyPeaks ? [] : root.nearbyPeaks

              ActionButton {
                required property var modelData
                width: parent ? parent.width : 0
                label: String(modelData.name || "Peak Pro") + "  \u00b7  " + String(modelData.address || "")
                glyph: "\uf293"
                tint: Color.accent
                onActivated: root.connectDevice(modelData.address)
              }
            }

            Text {
              width: parent.width
              visible: root.nearbyPeaks !== null && !root.scanning && root.nearbyPeaks.length === 0
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "No Peaks found. Wake the Peak, keep it close, and disconnect the phone app."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.needsSetup
                ? "QuickPuff's background service isn't set up yet. Setup opens a terminal and installs it for your user; no root access is needed."
                : root.resting
                  ? "Battery saver let the Peak rest to save its battery. Reconnecting now…"
                  : root.handedOff
                    ? "Another computer running QuickPuff has the Peak. Take it back to use it here; that computer will let go and pick it up again when you return to it."
                    : "Wake the Peak and keep it close to this computer. Disconnect the phone app first; the device accepts one connection at a time."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ================================================== Control
          Column {
            id: controlPage
            width: parent.width
            visible: root.onControl && root.connected
            spacing: Style.spacing.panelGap

            Row {
              id: actionRow
              width: parent.width
              spacing: Style.spacing.controlGap

              readonly property real cellWidth: (width - spacing * 2) / 3

              ActionButton {
                width: actionRow.cellWidth
                label: "Heat"
                glyph: "\uf06d"
                tall: true
                tint: Color.accent
                emphasized: !root.heating
                pulse: root.preheating
                onActivated: root.run("quickpuff heat start")
              }

              ActionButton {
                width: actionRow.cellWidth
                label: "Boost"
                glyph: "\uf0e7"
                tall: true
                tint: Qt.tint(Color.accent, Util.alpha(root.urgent, 0.5))
                onActivated: root.run("quickpuff heat boost")
              }

              ActionButton {
                width: actionRow.cellWidth
                label: "Stop"
                glyph: "\uf04d"
                tall: true
                tint: root.urgent
                emphasized: root.heating || root.cooling
                onActivated: root.run("quickpuff heat stop")
              }
            }

            Text {
              width: parent.width
              visible: root.lowHeatBattery && !root.heating
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              text: "\uf071  Battery " + Math.round(Number(root.statusData.battery)) + "%: the Peak may refuse to heat. Plug it in first."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: parent.width
              visible: root.timerActive
              implicitHeight: timerRing.height

              TimerRing {
                id: timerRing
                anchors.left: parent.left
                width: Style.space(84)
                height: width
                progress: root.timerProgress
                fillColor: root.atTemp ? Color.accent : root.urgent
                startColor: root.atTemp ? Qt.lighter(Color.accent, 1.4) : Color.accent

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.formatDuration(root.timerSecondsLeft)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }

              Column {
                anchors.left: timerRing.right
                anchors.leftMargin: Style.space(16)
                anchors.right: parent.right
                anchors.verticalCenter: timerRing.verticalCenter
                spacing: Style.space(4)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.atTemp ? "\uf0c2  Session" : "\uf06d  Heating up"
                  color: root.atTemp ? Color.accent : root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: root.atTemp
                    ? root.formatDuration(root.timerSecondsLeft) + " left before the Peak cools down"
                    : "Ready in about " + root.formatDuration(root.timerSecondsLeft)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            HeatGraph {
              visible: root.heatPoints.length >= 2
            }

            Section {
              visible: root.hasProfiles
              title: "HEAT PROFILES"
              glyph: "\uf06d"

              Grid {
                id: profileGrid
                width: parent.width
                columns: 2
                rowSpacing: Style.spacing.controlGap
                columnSpacing: Style.spacing.controlGap

                readonly property real cellWidth: (width - columnSpacing) / 2

                Repeater {
                  model: root.profiles

                  BorderSurface {
                    id: tile
                    required property var modelData

                    readonly property int profileIndex: {
                      var n = Number(modelData.index)
                      return isFinite(n) ? Math.round(n) : -1
                    }
                    readonly property bool active: profileIndex >= 0 && profileIndex === root.currentProfile
                    readonly property string swatch: root.profileColor(profileIndex, modelData.color)
                    // A cycling profile's dot runs through its colours.
                    readonly property var cycleColors: profileIndex === root.currentProfile
                      ? (root.cycleOn ? root.cycleColors : [])
                      : (modelData.cycle && modelData.cycle.colors ? modelData.cycle.colors : [])
                    readonly property string dotColor: cycleColors.length
                      ? cycleColors[root.cycleTick % cycleColors.length] : swatch
                    readonly property real tempF: root.profileTempF(profileIndex, modelData.temp_f)
                    readonly property real timeS: root.profileTime(profileIndex, modelData.time)
                    readonly property string name: {
                      var n = root.profileName(profileIndex, modelData.name)
                      return n !== "" ? n : ("Profile " + (profileIndex + 1))
                    }

                    readonly property bool editingName: root.editIndex === profileIndex && root.editField === "name"
                    readonly property bool editingTemp: root.editIndex === profileIndex && root.editField === "temp"
                    readonly property bool editingTime: root.editIndex === profileIndex && root.editField === "time"
                    readonly property bool editingThis: editingName || editingTemp || editingTime

                    // Controls inside the tile sit above the tile's own mouse
                    // area, so their hover has to count as the tile's too.
                    readonly property bool hot: tileMouse.containsMouse
                      || renameButton.hovered || lowerStep.hovered || raiseStep.hovered
                      || lowerTime.hovered || raiseTime.hovered
                      || tempTapMouse.containsMouse || timeTapMouse.containsMouse
                      || nameTap.containsMouse

                    width: profileGrid.cellWidth
                    implicitHeight: tileBody.implicitHeight + Style.spacing.controlPaddingY * 2
                    radius: Style.cornerRadius

                    // Each tile wears the colour its lantern glows, so the grid
                    // reads like the Peak's own light ring.
                    readonly property color tint: swatch !== "" ? swatch : Color.accent

                    // Pale swatches (white) wash out fast, so they tint lighter.
                    readonly property real tintStrength: tint.hslLightness > 0.8 ? 0.55 : 1
                    color: tileMouse.pressed ? Util.alpha(tint, 0.22 * tintStrength)
                      : active ? Util.alpha(tint, 0.15 * tintStrength)
                      : hot || editingThis ? Util.alpha(tint, 0.09 * tintStrength)
                      : Util.alpha(tint, 0.045 * tintStrength)

                    borderSpec: active
                      ? Border.flat(tint, Math.max(1, Style.normalBorderWidth))
                      : (hot || editingThis
                         ? Border.flat(Util.alpha(tint, 0.6), Math.max(1, Style.normalBorderWidth))
                         : Border.controlSpec("normal", root.foreground, Color.accent))

                    Behavior on color { ColorAnimation { duration: 160 } }

                    // A little hop when this becomes the active profile.
                    onActiveChanged: if (active && root.opened) tileHop.restart()
                    SequentialAnimation {
                      id: tileHop
                      NumberAnimation { target: tile; property: "scale"; to: 1.045; duration: 110; easing.type: Easing.OutQuad }
                      NumberAnimation { target: tile; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                    }

                    // Colour stripe down the leading edge; it breathes while
                    // this profile is the one heating.
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      anchors.margins: Math.max(1, Style.normalBorderWidth)
                      width: Style.space(3)
                      color: tile.tint
                      opacity: tile.active ? 1 : 0.35

                      Behavior on opacity { NumberAnimation { duration: 200 } }

                      SequentialAnimation on opacity {
                        running: tile.active && root.heating && root.opened
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                      }
                    }

                    // Declared before the body so every control in it swallows
                    // its own taps instead of also reselecting the profile.
                    MouseArea {
                      id: tileMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (tile.profileIndex < 0) return
                        root.runArgv(["quickpuff", "profile", String(tile.profileIndex)])
                      }
                    }

                    Column {
                      id: tileBody
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.spacing.controlPaddingX
                      anchors.rightMargin: Style.spacing.controlPaddingX
                      spacing: Style.spacing.xxs

                      // ----- Name -----
                      Item {
                        width: parent.width
                        implicitHeight: Math.max(Style.space(19), nameRow.implicitHeight)

                        Row {
                          id: nameRow
                          visible: !tile.editingName
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.spacing.md

                          Rectangle {
                            id: swatchDot
                            width: tile.swatch !== "" ? Style.space(8) : 0
                            height: Style.space(8)
                            radius: width / 2
                            visible: tile.swatch !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            color: tile.dotColor !== "" ? tile.dotColor : "transparent"
                            border.width: 1
                            border.color: Util.alpha(root.foreground, 0.25)

                            Behavior on color { ColorAnimation { duration: root.cycleStepMs * 0.9 } }

                            Rectangle {
                              z: -1
                              anchors.centerIn: parent
                              width: parent.width * 1.8
                              height: width
                              radius: width / 2
                              color: Util.alpha(tile.tint, tile.active ? 0.3 : 0)

                              Behavior on color { ColorAnimation { duration: 200 } }
                            }
                          }

                          Text {
                            id: nameLabel
                            textFormat: Text.PlainText
                            width: nameRow.width
                              - (swatchDot.visible ? swatchDot.width + nameRow.spacing : 0)
                              - (tile.hot ? renameButton.width + nameRow.spacing : 0)
                            text: tile.name
                            color: nameTap.containsMouse ? Color.accent : (tile.active ? tile.tint : root.foreground)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: tile.active
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                            MouseArea {
                              id: nameTap
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.IBeamCursor
                              onClicked: root.startEdit(tile.profileIndex, "name")
                            }
                          }

                          TileButton {
                            id: renameButton
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "\uf040"
                            tooltipHot: tile.hot
                            canTap: tile.profileIndex >= 0
                            onActivated: root.startEdit(tile.profileIndex, "name")
                          }
                        }

                        Loader {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          active: tile.editingName

                          sourceComponent: TileEditor {
                            owningIndex: tile.profileIndex
                            owningField: "name"
                            seed: tile.name
                            maxChars: 20
                            onCommitted: function(value) { root.commitName(tile.profileIndex, value) }
                          }
                        }
                      }

                      // ----- Temperature -----
                      Item {
                        width: parent.width
                        implicitHeight: Math.max(lowerStep.implicitHeight, tempReadout.implicitHeight)

                        TileButton {
                          id: lowerStep
                          visible: !tile.editingTemp
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          glyph: "−"
                          canTap: root.canStepTemp(tile.profileIndex, tile.modelData.temp_f, -root.tempStepF)
                          onActivated: root.stepTemp(tile.profileIndex, tile.modelData.temp_f, -root.tempStepF)
                        }

                        Item {
                          visible: !tile.editingTemp
                          anchors.centerIn: parent
                          width: Math.max(tempReadout.implicitWidth + Style.space(10), Style.space(34))
                          height: parent.height

                          Text {
                            id: tempReadout
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: {
                              var t = root.formatTemp(tile.tempF, undefined)
                              return t !== "" ? t : "—"
                            }
                            color: tempTapMouse.containsMouse ? Color.accent
                              : (tile.active ? root.heatRamp(tile.tempF)
                                 : Qt.tint(root.dim, Util.alpha(root.heatRamp(tile.tempF), 0.45)))
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: tile.active

                            Behavior on color { ColorAnimation { duration: 120 } }
                          }

                          MouseArea {
                            id: tempTapMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.startEdit(tile.profileIndex, "temp")
                          }
                        }

                        TileButton {
                          id: raiseStep
                          visible: !tile.editingTemp
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          glyph: "+"
                          canTap: root.canStepTemp(tile.profileIndex, tile.modelData.temp_f, root.tempStepF)
                          onActivated: root.stepTemp(tile.profileIndex, tile.modelData.temp_f, root.tempStepF)
                        }

                        Loader {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          active: tile.editingTemp

                          sourceComponent: TileEditor {
                            owningIndex: tile.profileIndex
                            owningField: "temp"
                            digitsOnly: true
                            horizontalAlignment: TextInput.AlignHCenter
                            seed: isFinite(tile.tempF)
                              ? String(Math.round(root.celsius ? root.fToC(tile.tempF) : tile.tempF))
                              : ""
                            onCommitted: function(value) { root.commitTemp(tile.profileIndex, value) }
                          }
                        }
                      }

                      // ----- Heat time -----
                      Item {
                        width: parent.width
                        implicitHeight: Math.max(lowerTime.implicitHeight, timeReadout.implicitHeight)

                        TileButton {
                          id: lowerTime
                          visible: !tile.editingTime
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          glyph: "−"
                          canTap: root.canStepTime(tile.profileIndex, tile.modelData.time, -root.timeStepS)
                          onActivated: root.stepTime(tile.profileIndex, tile.modelData.time, -root.timeStepS)
                        }

                        Item {
                          visible: !tile.editingTime
                          anchors.centerIn: parent
                          width: Math.max(timeReadout.implicitWidth + Style.space(10), Style.space(34))
                          height: parent.height

                          Text {
                            id: timeReadout
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: isFinite(tile.timeS) ? Math.round(tile.timeS) + "s" : "—"
                            color: timeTapMouse.containsMouse ? Color.accent
                              : (tile.active ? root.foreground : root.dim)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall

                            Behavior on color { ColorAnimation { duration: 120 } }
                          }

                          MouseArea {
                            id: timeTapMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.startEdit(tile.profileIndex, "time")
                          }
                        }

                        TileButton {
                          id: raiseTime
                          visible: !tile.editingTime
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          glyph: "+"
                          canTap: root.canStepTime(tile.profileIndex, tile.modelData.time, root.timeStepS)
                          onActivated: root.stepTime(tile.profileIndex, tile.modelData.time, root.timeStepS)
                        }

                        Loader {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          active: tile.editingTime

                          sourceComponent: TileEditor {
                            owningIndex: tile.profileIndex
                            owningField: "time"
                            digitsOnly: true
                            horizontalAlignment: TextInput.AlignHCenter
                            seed: isFinite(tile.timeS) ? String(Math.round(tile.timeS)) : ""
                            onCommitted: function(value) { root.commitTime(tile.profileIndex, value) }
                          }
                        }
                      }
                      // ----- Where this temperature sits in the Peak's range -----
                      Item {
                        width: parent.width
                        height: Style.space(7)

                        Rectangle {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          height: Style.space(3)
                          radius: height / 2
                          color: Util.alpha(root.foreground, 0.1)

                          Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: isFinite(tile.tempF)
                              ? Math.max(parent.height, parent.width * (tile.tempF - root.minTempF) / (root.maxTempF - root.minTempF))
                              : 0
                            opacity: tile.active ? 1 : 0.55
                            gradient: Gradient {
                              orientation: Gradient.Horizontal
                              GradientStop { position: 0.0; color: Util.alpha(tile.tint, 0.35) }
                              GradientStop { position: 1.0; color: tile.tint }
                            }

                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            Section {
              visible: root.hasProfiles && root.currentProfile >= 0
              title: "VAPOR"
              glyph: "\uf0c2"

              Segmented {
                width: parent.width
                options: root.vaporLevels
                value: root.profileVapor(root.currentProfile,
                  (root.activeProfile && root.activeProfile.vapor) || "")
                onPicked: function(value) { root.applyVapor(value) }
              }
            }

            Section {
              id: boostSection
              visible: root.hasProfiles && root.currentProfile >= 0
              title: "BOOST"
              glyph: "\uf0e7"

              readonly property var active: root.activeProfile || ({})

              // Where a boost lands: the profile's temperature plus the extra.
              readonly property real boostedF: root.profileTempF(root.currentProfile, active.temp_f)
                + root.profileBoostTempF(root.currentProfile, active.boost_temp_f)
              trailing: isFinite(boostedF) ? "Boost peaks at " + root.formatTemp(boostedF, undefined) : ""

              StepperRow {
                width: parent.width
                label: "Extra temperature"
                valueText: root.formatBoostTemp(root.profileBoostTempF(root.currentProfile, boostSection.active.boost_temp_f))
                canLower: root.canStepBoostTemp(root.currentProfile, boostSection.active.boost_temp_f, -root.boostTempStepF)
                canRaise: root.canStepBoostTemp(root.currentProfile, boostSection.active.boost_temp_f, root.boostTempStepF)
                onLower: root.stepBoostTemp(root.currentProfile, boostSection.active.boost_temp_f, -root.boostTempStepF)
                onRaise: root.stepBoostTemp(root.currentProfile, boostSection.active.boost_temp_f, root.boostTempStepF)
              }

              StepperRow {
                width: parent.width
                label: "Extra time"
                valueText: "+" + Math.round(root.profileBoostTime(root.currentProfile, boostSection.active.boost_time)) + "s"
                canLower: root.canStepBoostTime(root.currentProfile, boostSection.active.boost_time, -root.boostTimeStepS)
                canRaise: root.canStepBoostTime(root.currentProfile, boostSection.active.boost_time, root.boostTimeStepS)
                onLower: root.stepBoostTime(root.currentProfile, boostSection.active.boost_time, -root.boostTimeStepS)
                onRaise: root.stepBoostTime(root.currentProfile, boostSection.active.boost_time, root.boostTimeStepS)
              }
            }

            // What plays over the desktop when the Peak is ready. A registry,
            // so another animation is one more entry here and in ReadyOverlay.
            Section {
              glyph: ""
              title: "READY ANIMATION"
              trailing: root.readyAnimation === "off" ? "" : "Plays when it's ready"

              Row {
                width: parent.width
                spacing: Style.spacing.controlGap

                Segmented {
                  width: parent.width - previewButton.width - parent.spacing
                  compact: true
                  options: root.readyAnimations
                  value: root.readyAnimation
                  onPicked: function(value) { root.setReadyAnimation(value) }
                }

                ActionButton {
                  id: previewButton
                  width: Style.space(80)
                  implicitHeight: Style.space(24)
                  label: "Preview"
                  glyph: ""
                  tint: Color.accent
                  opacity: root.readyAnimation === "off" ? 0.4 : 1
                  onActivated: root.previewReadyAnimation()
                }
              }
            }
          }

          // ================================================== Lights
          Column {
            id: lightsPage
            width: parent.width
            visible: root.onLights && root.connected
            spacing: Style.spacing.panelGap

            Section {
              title: "LEDS"
              glyph: "\uf0eb"

              LanternPreview {
                width: parent.width
                glow: root.cycleOn ? root.cycleNow : root.profileTint
                level: root.brightnessLevel / 255
                lit: root.lanternOn
              }

              SwitchRow {
                width: parent.width
                label: "LED"
                checked: root.lanternOn
                onToggled: root.toggleLantern()
              }

              Column {
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: brightnessLabel.implicitHeight

                  Text {
                    id: brightnessLabel
                    anchors.left: parent.left
                    textFormat: Text.PlainText
                    text: "Brightness"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    textFormat: Text.PlainText
                    text: Math.round(root.brightnessLevel / 255 * 100) + "%"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                PanelSlider {
                  width: parent.width
                  bar: root.bar
                  minimum: 0
                  maximum: 255
                  step: 5
                  integer: true
                  value: root.brightnessLevel
                  onMoved: function(v) { root.setBrightness(v) }
                  onReleased: function(v) { root.setBrightness(v) }
                }
              }

              SwitchRow {
                width: parent.width
                label: "Stealth mode"
                checked: root.stealthOn
                onToggled: root.toggleStealth()
              }

              StepperRow {
                width: parent.width
                label: "Turn off after"
                valueText: root.formatTimeout(root.lanternTimeoutStops[root.lanternTimeoutStop])
                canLower: root.lanternTimeoutStop > 0
                canRaise: root.lanternTimeoutStop < root.lanternTimeoutStops.length - 1
                onLower: root.stepLanternTimeout(-1)
                onRaise: root.stepLanternTimeout(1)
              }
            }

            Section {
              glyph: "\uf1fc"
              title: root.activeProfile
                ? "PROFILE LIGHT · " + String(root.cleanName(root.activeProfile.name) || ("Profile " + (root.currentProfile + 1))).toUpperCase()
                : "PROFILE LIGHT"

              Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "The color this profile glows with while it heats."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Grid {
                id: colorGrid
                width: parent.width
                columns: 9
                rowSpacing: Style.space(6)
                columnSpacing: Style.space(6)
                readonly property real cell: (width - columnSpacing * 8) / 9

                Repeater {
                  model: root.colorPalette

                  Rectangle {
                    id: swatchChip
                    required property var modelData
                    readonly property bool picked: root.activeProfile
                      && String(root.profileColor(root.currentProfile, root.activeProfile.color)).toLowerCase() === String(modelData).toLowerCase()
                    width: colorGrid.cell
                    height: colorGrid.cell
                    radius: width / 2
                    color: String(modelData)
                    border.width: picked ? 2 : 1
                    border.color: picked ? root.foreground : Util.alpha(root.foreground, 0.35)
                    scale: swatchMouse.pressed ? 0.9 : (swatchMouse.containsMouse ? 1.15 : (picked ? 1.06 : 1))

                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                    // Glow ring around the colour the profile wears.
                    Rectangle {
                      z: -1
                      anchors.centerIn: parent
                      width: parent.width + Style.space(8)
                      height: width
                      radius: width / 2
                      color: Util.alpha(String(swatchChip.modelData), swatchChip.picked ? 0.3 : 0)

                      Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: swatchChip.picked
                      textFormat: Text.PlainText
                      text: "\uf00c"
                      color: root.inkOn(swatchChip.modelData)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: swatchMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.applyLightColor(String(swatchChip.modelData))
                        if (root.pickerOpen) root.seedPicker(String(swatchChip.modelData))
                      }
                    }
                  }
                }

                // Rainbow chip that opens the colour wheel. Wears the custom
                // colour (with a check) while the profile is on one.
                Item {
                  width: colorGrid.cell
                  height: colorGrid.cell
                  scale: customMouse.pressed ? 0.9 : (customMouse.containsMouse ? 1.15 : (root.pickerOpen || root.customLight ? 1.06 : 1))

                  Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + Style.space(8)
                    height: width
                    radius: width / 2
                    color: Util.alpha(root.customLight ? root.activeLightHex : root.foreground, root.pickerOpen || root.customLight ? 0.3 : 0)

                    Behavior on color { ColorAnimation { duration: 200 } }
                  }

                  ConicalRing {
                    anchors.fill: parent
                    rotating: customMouse.containsMouse || root.pickerOpen
                  }

                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.56
                    height: width
                    radius: width / 2
                    color: root.customLight ? root.activeLightHex : Color.background
                    border.width: 1
                    border.color: Util.alpha(root.foreground, 0.35)

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: root.customLight ? "\uf00c" : (root.pickerOpen ? "\uf00d" : "+")
                      color: root.customLight ? root.inkOn(root.activeLightHex) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  MouseArea {
                    id: customMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePicker()
                  }
                }
              }

              Loader {
                width: parent.width
                active: root.pickerOpen && root.onLights
                visible: active
                sourceComponent: ColorPicker {}
                // Scroll just far enough to bring the whole picker into view.
                onLoaded: Qt.callLater(function() {
                  var bottom = pickerLoader.mapToItem(content, 0, pickerLoader.height).y
                  scroller.contentY = Math.max(scroller.contentY,
                    Math.min(bottom - scroller.height, scroller.contentHeight - scroller.height))
                })
                id: pickerLoader
              }

            }

            CycleSection {}

            MyLightsSection {}

          }

          // ================================================== Care
          Column {
            id: carePage
            width: parent.width
            visible: root.onCare && root.connected
            spacing: Style.spacing.panelGap

            Section {
              title: "BATTERY"
              glyph: "\uf240"
              trailing: root.batteryHealthLabel !== "" ? root.batteryHealthLabel + " health" : ""

              MeterBar {
                width: parent.width
                visible: root.batteryHealthLabel !== ""
                value: parseFloat(root.batteryHealthLabel) / 100
                fill: parseFloat(root.batteryHealthLabel) < 70 ? root.urgent
                  : parseFloat(root.batteryHealthLabel) < 80 ? "#ffb347"
                  : Color.accent
              }

              SwitchRow {
                width: parent.width
                visible: root.preserveSupported
                label: "Charge to 80% only"
                checked: root.preserveOn
                onToggled: root.togglePreserve()
              }

              SwitchRow {
                width: parent.width
                label: "Rest after sessions and 10 min idle"
                checked: root.saverOn
                onToggled: root.toggleSaver()
              }

              Text {
                width: parent.width
                visible: root.preserveSupported && root.preserveOn
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "Stopping at 80% helps the battery last longer."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Section {
              title: "CLEANING"
              glyph: "\uf0c3"
              trailing: root.cleanDue ? "Due" : root.cleanRemaining + " left"

              // Fills up as dabs pile on; turns urgent once a clean is due.
              MeterBar {
                width: parent.width
                value: root.cleanDue ? 1 : 1 - root.cleanRemaining / Math.max(1, root.cleanEvery)
                fill: root.cleanDue ? root.urgent
                  : (1 - root.cleanRemaining / Math.max(1, root.cleanEvery)) > 0.75 ? "#ffb347"
                  : Color.accent
                throb: root.cleanDue
              }

              SwitchRow {
                width: parent.width
                label: "Q-tip reminder after each dab"
                checked: root.qtipOn
                onToggled: root.toggleQtip()
              }

              StepperRow {
                width: parent.width
                label: "Remind every"
                valueText: root.cleanEvery + " dabs"
                canLower: root.canStepCleanEvery(-root.cleanEveryStep)
                canRaise: root.canStepCleanEvery(root.cleanEveryStep)
                onLower: root.stepCleanEvery(-root.cleanEveryStep)
                onRaise: root.stepCleanEvery(root.cleanEveryStep)
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.cleanDue
                  ? "Swab the chamber, then mark it cleaned."
                  : root.cleanRemaining + " dab" + (root.cleanRemaining === 1 ? "" : "s") + " until the reminder."
                color: root.cleanDue ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                width: parent.width
                implicitHeight: cleanButton.implicitHeight

                ActionButton {
                  id: cleanButton
                  width: parent.width
                  label: "Mark cleaned"
                  glyph: "\uf0d0"
                  emphasized: root.cleanDue
                  tint: root.cleanDue ? root.urgent : root.foreground
                  onActivated: {
                    root.markCleaned()
                    cleanBurst.fire()
                  }
                }

                Burst {
                  id: cleanBurst
                  anchors.centerIn: cleanButton
                  width: cleanButton.height * 2
                  height: width
                }
              }
            }

            Section {
              title: "GOALS"
              glyph: "\uf140"
              trailing: root.dailyLimit > 0
                ? Number(root.telemetry.today || 0) + " of " + root.dailyLimit + " today"
                : ""

              StepperRow {
                width: parent.width
                label: "Daily limit"
                valueText: root.dailyLimit > 0 ? root.dailyLimit + " dabs" : "Off"
                canLower: root.dailyLimit > 0
                canRaise: root.dailyLimit < 50
                onLower: root.stepDailyLimit(-1)
                onRaise: root.stepDailyLimit(1)
              }

              MeterBar {
                width: parent.width
                visible: root.dailyLimit > 0
                value: Number(root.telemetry.today || 0) / Math.max(1, root.dailyLimit)
                fill: Number(root.telemetry.today || 0) >= root.dailyLimit ? root.urgent : Color.accent
              }

              Text {
                width: parent.width
                visible: root.dailyLimit > 0
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "You'll get one notification the day you reach it."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              SwitchRow {
                width: parent.width
                label: "Weekly recap on Sunday evening"
                checked: root.recapOn
                onToggled: root.toggleRecap()
              }
            }
          }

          // ================================================== Usage
          Segmented {
            width: parent.width
            visible: root.onUsage && root.connected
            compact: true
            options: root.usageTabOptions
            value: root.usageTab
            onPicked: function(value) {
              root.usageTab = value
              scroller.contentY = 0
            }
          }

          Column {
            id: historyPage
            width: parent.width
            visible: root.onUsageHistory && root.connected
            spacing: Style.spacing.controlGap

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.sessionList === null
                ? (root.sessionsLoading ? "Loading your dabs\u2026" : "")
                : root.sessionList.length === 0
                  ? "No dabs yet. Each one shows up here, ready for a note."
                  : "Tap a dab to add or edit its note."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.sessionList || []

              SessionCard {
                required property var modelData
                width: parent ? parent.width : 0
                session: modelData
              }
            }

            ActionButton {
              width: parent.width
              visible: root.sessionList !== null && root.sessionTotal > root.sessionList.length
              label: root.sessionsLoading ? "Loading\u2026" : "Show more"
              onActivated: {
                root.sessionLimit += 30
                root.loadSessions()
              }
            }
          }

          Column {
            id: usagePage
            width: parent.width
            visible: root.onUsageStats && root.connected
            spacing: Style.spacing.panelGap

            Text {
              width: parent.width
              visible: root.statusData.usage_syncing === true
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: "Reading usage history from this Peak. The first read on a new computer takes a minute or two."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: summaryRow
              width: parent.width
              spacing: Style.spacing.controlGap
              readonly property real cellWidth: (width - spacing * 3) / 4

              SummaryCell { width: summaryRow.cellWidth; title: "Today"; glyph: "\uf185"; highlight: true; value: root.countLabel(root.telemetry.today) }
              SummaryCell { width: summaryRow.cellWidth; title: "Week"; glyph: "\uf073"; value: root.countLabel(root.telemetry.this_week) }
              SummaryCell { width: summaryRow.cellWidth; title: "Month"; glyph: "\uf274"; value: root.countLabel(root.telemetry.this_month) }
              SummaryCell { width: summaryRow.cellWidth; title: "Lifetime"; glyph: "\uf091"; value: root.countLabel(root.statusData.total_dabs) }
            }

            Section {
              id: dailySection
              title: "DAILY"
              glyph: "\uf073"
              // Hovering a bar swaps the average for that day's count.
              property int hoverIndex: -1
              trailing: hoverIndex >= 0 && hoverIndex < root.dailySeries.length
                ? String(root.dailySeries[hoverIndex].day || "") + " \u00b7 " + (Number(root.dailySeries[hoverIndex].count) || 0)
                  + ((Number(root.dailySeries[hoverIndex].count) || 0) === 1 ? " dab" : " dabs")
                : "Avg " + (Number(root.telemetry.avg_per_day) || 0) + "/day"

              Item {
                width: parent.width
                height: Style.space(68)

                Row {
                  id: chartRow
                  anchors.fill: parent
                  spacing: Math.max(1, Style.space(2))

                  Repeater {
                    model: root.dailySeries

                    Item {
                      required property var modelData
                      required property int index
                      width: {
                        var n = Math.max(1, root.dailySeries.length)
                        return (chartRow.width - chartRow.spacing * (n - 1)) / n
                      }
                      height: chartRow.height

                      readonly property int count: Number(modelData.count) || 0
                      readonly property bool isToday: index === root.dailySeries.length - 1
                      readonly property bool hovered: dailySection.hoverIndex === index

                      Rectangle {
                        id: dayBar
                        width: parent.width
                        // Grows up from the baseline when the page opens.
                        height: root.onUsageStats
                          ? Math.max(Style.space(2), parent.height * (parent.count / root.chartPeak))
                          : Style.space(2)
                        anchors.bottom: parent.bottom
                        radius: Math.min(2, Style.cornerRadius)
                        readonly property color barTop: parent.hovered ? Qt.lighter(Color.accent, 1.35)
                          : parent.isToday ? Color.accent
                          : parent.count > 0 ? Util.alpha(Color.accent, 0.75)
                          : Util.alpha(root.foreground, 0.12)
                        gradient: Gradient {
                          GradientStop { position: 0.0; color: dayBar.barTop }
                          GradientStop { position: 1.0; color: Util.alpha(dayBar.barTop, dayBar.barTop.a * 0.45) }
                        }

                        // Bars rise in a left-to-right ripple.
                        Behavior on height {
                          SequentialAnimation {
                            PauseAnimation { duration: Math.min(dayBar.parent.index, 40) * 14 }
                            NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
                          }
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                          if (containsMouse) dailySection.hoverIndex = parent.index
                          else if (dailySection.hoverIndex === parent.index) dailySection.hoverIndex = -1
                        }
                      }
                    }
                  }
                }
              }

              Item {
                width: parent.width
                implicitHeight: firstDay.implicitHeight

                Text {
                  id: firstDay
                  anchors.left: parent.left
                  textFormat: Text.PlainText
                  text: root.dailySeries.length ? String(root.dailySeries[0].day || "") : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.right: parent.right
                  textFormat: Text.PlainText
                  text: root.dailySeries.length ? String(root.dailySeries[root.dailySeries.length - 1].day || "") : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Section {
              title: "HABITS"
              glyph: "\uf005"

              Grid {
                width: parent.width
                columns: 2
                rowSpacing: Style.spacing.controlGap
                columnSpacing: Style.spacing.controlGap

                readonly property real cellWidth: (width - columnSpacing) / 2

                StatCard {
                  width: parent.cellWidth
                  title: "Streak"
                  glyph: "\uf06d"
                  glyphColor: (Number(root.telemetry.streak) || 0) > 0 ? root.urgent : root.dim
                  value: (Number(root.telemetry.streak) || 0) + "d"
                  meta: (Number(root.telemetry.streak_best) || 0) > 0
                    ? "Best " + Math.round(Number(root.telemetry.streak_best)) + "d"
                    : "No streak yet"

                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: root.weekdaySeries
                      Rectangle {
                        required property var modelData
                        width: Style.space(8)
                        height: Style.space(8)
                        radius: width / 2
                        color: Number(modelData.count) > 0 ? Color.accent : "transparent"
                        scale: modelData.today ? 1.2 : 1
                        border.width: modelData.today ? 1 : (Number(modelData.count) > 0 ? 0 : 1)
                        border.color: modelData.today ? Color.accent : Util.alpha(root.foreground, 0.3)
                      }
                    }
                  }
                }

                StatCard {
                  width: parent.cellWidth
                  title: "Peak hour"
                  glyph: "\uf017"
                  value: root.formatHour(root.telemetry.top_hour)
                  meta: Number(root.telemetry.top_hour_share) > 0
                    ? Math.round(Number(root.telemetry.top_hour_share) * 100) + "% of sessions"
                    : "Not enough data"

                  Item {
                    width: parent.width
                    height: Style.space(22)

                    Row {
                      id: hourChart
                      anchors.fill: parent
                      spacing: 1

                      Repeater {
                        model: 24
                        Item {
                          required property int index
                          width: (hourChart.width - 23) / 24
                          height: hourChart.height

                          Rectangle {
                            width: parent.width
                            height: {
                              var c = Number(root.hourSeries[parent.index]) || 0
                              return Math.max(Style.space(2), parent.height * (c / root.hourPeak))
                            }
                            anchors.bottom: parent.bottom
                            radius: 1
                            color: parent.index === Number(root.telemetry.top_hour)
                              ? Color.accent
                              : Util.alpha(root.foreground, (Number(root.hourSeries[parent.index]) || 0) > 0 ? 0.45 : 0.12)
                          }
                        }
                      }
                    }
                  }
                }

                StatCard {
                  width: parent.cellWidth
                  title: "Avg duration"
                  glyph: "\uf252"
                  value: root.formatDuration(root.telemetry.avg_time_s)
                  meta: root.telemetry.avg_time_s == null ? "Not enough data" : "Per session"
                }

                StatCard {
                  width: parent.cellWidth
                  title: "Avg temperature"
                  glyph: "\uf2c9"
                  value: root.formatAvgTemp(root.telemetry.avg_temp_f)
                  meta: root.telemetry.avg_temp_f == null ? "Not enough data" : "Per session"
                }
              }
            }

            Section {
              visible: root.profileUsage.length > 0
              title: "PROFILES"
              glyph: "\uf0ca"
              trailing: "Last " + (Number(root.telemetry.profile_days) || 30) + " days"

              Repeater {
                model: root.profileUsage

                Column {
                  id: usageRow
                  required property var modelData
                  width: parent ? parent.width : 0
                  spacing: Style.space(4)

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(usageName.implicitHeight, usageCount.implicitHeight)

                    Text {
                      id: usageName
                      anchors.left: parent.left
                      anchors.right: usageCount.left
                      anchors.rightMargin: Style.spacing.md
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: root.profileUsageName(usageRow.modelData.index)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      id: usageCount
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: {
                        var d = usageRow.modelData
                        var n = Number(d.count)
                        var s = n + (n === 1 ? " session" : " sessions") + " \u00b7 " + Math.round(Number(d.share) * 100) + "%"
                        if (d.temp_f !== null && d.temp_f !== undefined) s += " \u00b7 " + root.formatTemp(d.temp_f, d.temp_c)
                        return s
                      }
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(6)
                    radius: height / 2
                    color: Style.normalFillFor(root.foreground, Color.accent)

                    Rectangle {
                      id: shareBar
                      readonly property color tint: root.profileUsageColor(usageRow.modelData.index)
                      width: root.onUsageStats
                        ? Math.max(parent.height, parent.width * Math.min(1, Number(usageRow.modelData.share) || 0))
                        : parent.height
                      height: parent.height
                      radius: height / 2
                      gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Util.alpha(shareBar.tint, 0.45) }
                        GradientStop { position: 1.0; color: shareBar.tint }
                      }

                      Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    }
                  }
                }
              }
            }

            Section {
              visible: root.colorSeries.length > 0
              title: "TOP COLORS"
              glyph: "\uf1fb"

              Row {
                width: parent.width
                spacing: Style.space(3)
                Repeater {
                  model: root.colorSeries
                  Rectangle {
                    required property var modelData
                    height: Style.space(12)
                    width: Math.max(Style.space(16), (parent.width - parent.spacing * Math.max(0, root.colorSeries.length - 1)) / Math.max(1, root.colorSeries.length))
                    radius: height / 2
                    color: String(modelData)
                    border.width: 1
                    border.color: Util.alpha(root.foreground, 0.2)
                  }
                }
              }
            }
          }

          // ================================================== Device
          Column {
            id: devicePage
            width: parent.width
            visible: root.onDevice && root.connected
            spacing: Style.spacing.panelGap

            Segmented {
              width: parent.width
              compact: true
              options: root.deviceTabOptions
              value: root.deviceTab
              onPicked: function(value) {
                root.deviceTab = value
                scroller.contentY = 0
              }
            }

            Column {
              width: parent.width
              visible: root.onDeviceInfo
              spacing: Style.spacing.panelGap

            Section {
              title: "NAME"
              glyph: "\uf02b"

              Item {
                width: parent.width
                implicitHeight: Math.max(Style.space(28), deviceNameRow.implicitHeight)

                Row {
                  id: deviceNameRow
                  visible: !(root.editIndex === -1 && root.editField === "device")
                  width: parent.width
                  spacing: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    width: parent.width - deviceRename.width - parent.spacing
                    textFormat: Text.PlainText
                    text: root.shownDeviceName
                    color: deviceNameTap.containsMouse ? Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                      id: deviceNameTap
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.IBeamCursor
                      onClicked: root.startEdit(-1, "device")
                    }
                  }

                  TileButton {
                    id: deviceRename
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\uf040"
                    canTap: true
                    onActivated: root.startEdit(-1, "device")
                  }
                }

                Loader {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  active: root.editIndex === -1 && root.editField === "device"

                  sourceComponent: TileEditor {
                    owningIndex: -1
                    owningField: "device"
                    seed: root.shownDeviceName
                    maxChars: 32
                    onCommitted: function(value) { root.commitDeviceName(value) }
                  }
                }
              }
            }

            Section {
              title: "DETAILS"
              glyph: "\uf05a"

              InfoRow { width: parent.width; label: "Model"; value: (root.statusData.product && root.statusData.product.label) || "" }
              InfoRow { width: parent.width; label: "Chamber"; value: root.chamberLabel }
              InfoRow { width: parent.width; label: "Battery"; value: root.batteryDetail }
              InfoRow { width: parent.width; label: "Battery capacity"; value: root.batteryCapacityLabel }
              InfoRow { width: parent.width; label: "Battery health"; value: root.batteryHealthLabel }
              InfoRow { width: parent.width; label: "Dabs left on charge"; value: root.remainingLabel }
              InfoRow {
                width: parent.width
                label: "Firmware"
                value: {
                  var fw = String(root.statusData.firmware || "")
                  var boot = String(root.statusData.bootloader || "")
                  return fw !== "" && boot !== "" ? fw + " (bootloader " + boot + ")" : fw
                }
              }
              InfoRow { width: parent.width; label: "Serial"; value: String(root.statusData.serial || "") }
              InfoRow { width: parent.width; label: "First used"; value: String(root.statusData.birthday_label || "") }
              InfoRow { width: parent.width; label: "Uptime"; value: String(root.statusData.uptime || "") }
            }

            Section {
              title: "FAULT LOG"
              glyph: "\uf071"
              trailing: root.faultLog !== null && !root.faultsLoading
                ? root.faultLog.length + (root.faultLog.length === 1 ? " fault" : " faults")
                : ""

              Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.faultsLoading ? "Reading the Peak's fault log. The first read takes a minute or two."
                  : root.faultError ? "Couldn't read the fault log. Check the Peak is connected, then try again."
                  : root.faultLog === null ? "Heater, battery and pairing problems the Peak has recorded."
                  : root.faultLog.length === 0 ? "No faults recorded."
                  : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.faultLog && !root.faultsLoading ? root.faultLog.slice(0, root.faultShown) : []

                FaultCard {
                  required property var modelData
                  width: parent ? parent.width : 0
                  fault: modelData
                }
              }

              ActionButton {
                width: parent.width
                visible: !root.faultsLoading && root.faultLog !== null && root.faultLog.length > root.faultShown
                label: "Show " + (root.faultLog ? root.faultLog.length - root.faultShown : 0) + " more"
                onActivated: root.faultShown = root.faultLog.length
              }

              Row {
                width: parent.width
                spacing: Style.spacing.controlGap
                readonly property bool opened: root.faultLog !== null && !root.faultsLoading

                ActionButton {
                  width: parent.opened ? (parent.width - parent.spacing) / 2 : parent.width
                  label: root.faultsLoading ? "Reading…" : (root.faultLog === null ? "Read fault log" : "Refresh")
                  onActivated: root.readFaults()
                }

                ActionButton {
                  visible: parent.opened
                  width: (parent.width - parent.spacing) / 2
                  label: "Close"
                  onActivated: root.closeFaults()
                }
              }
            }

            Section {
              title: "SHOW ON DEVICE"
              glyph: "\uf10b"

              ActionButton {
                width: parent.width
                label: "Battery level"
                glyph: "\uf240"
                onActivated: root.run("quickpuff battery")
              }
            }

            Section {
              title: "CONNECTION"
              glyph: "\uf293"

              Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "The Peak accepts one connection at a time. Disconnect to use it from your phone or another computer."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ActionButton {
                width: parent.width
                label: "Disconnect"
                glyph: "\uf127"
                onActivated: root.disconnectDevice()
              }
            }

            Section {
              title: "POWER"
              glyph: "\uf011"

              ActionButton {
                width: parent.width
                label: "Power off"
                glyph: "\uf011"
                tint: root.urgent
                onActivated: root.confirmPowerOff = true
              }
            }
            }

            Column {
              width: parent.width
              visible: root.onDeviceTips
              spacing: Style.spacing.panelGap

              Section {
                title: "STOCK HEAT"
                glyph: "\uf2c9"
                trailing: "Factory"

                Grid {
                  width: parent.width
                  columns: 2
                  rowSpacing: Style.spacing.controlGap
                  columnSpacing: Style.spacing.controlGap

                  readonly property real cellWidth: (width - columnSpacing) / 2

                  Repeater {
                    model: root.stockHeats

                    SummaryCell {
                      required property var modelData
                      width: parent.cellWidth
                      value: root.formatTemp(modelData.temp_f, undefined)
                      title: modelData.color + " · " + modelData.name
                      stripe: root.stockSwatches[modelData.color] || ""
                    }
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: "Green is the everyday setting. Blue keeps flavor; White is clouds."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Section {
                title: "CARE"
                glyph: "\uf004"

                Repeater {
                  model: root.peakTips

                  TipBlock {
                    required property var modelData
                    width: parent ? parent.width : 0
                    title: String(modelData.title)
                    body: String(modelData.body)
                  }
                }
              }

              Section {
                title: "LIGHTS"
                glyph: "\uf0eb"

                Repeater {
                  model: root.peakLights

                  TipBlock {
                    required property var modelData
                    width: parent ? parent.width : 0
                    title: String(modelData.title)
                    body: String(modelData.body)
                  }
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmPowerOff
        message: "Power off " + root.deviceName + "?"
        confirmText: "Power off"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirmPowerOff = false
        onConfirmed: {
          root.confirmPowerOff = false
          root.run("quickpuff off")
        }
      }
    }
  }

  // Circular progress track; children (the countdown) sit in the middle. The
  // arc runs from `startColor` to `fillColor` and carries a glowing head.
  component TimerRing: Item {
    id: ring

    property real progress: 0
    property color fillColor: Color.accent
    property color startColor: fillColor
    property color trackColor: Util.alpha(root.foreground, 0.12)
    property real thickness: Style.space(6)

    onProgressChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onStartColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2
        var cy = height / 2
        var r = Math.min(width, height) / 2 - ring.thickness
        ctx.lineWidth = ring.thickness
        ctx.lineCap = "round"
        ctx.strokeStyle = ring.trackColor
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, Math.PI * 2)
        ctx.stroke()
        if (ring.progress <= 0) return
        var end = -Math.PI / 2 + Math.PI * 2 * ring.progress
        var grad = ctx.createLinearGradient(0, 0, width, height)
        grad.addColorStop(0, ring.startColor)
        grad.addColorStop(1, ring.fillColor)
        ctx.strokeStyle = grad
        ctx.beginPath()
        ctx.arc(cx, cy, r, -Math.PI / 2, end)
        ctx.stroke()
        var hx = cx + r * Math.cos(end)
        var hy = cy + r * Math.sin(end)
        ctx.fillStyle = Util.alpha(ring.fillColor, 0.3)
        ctx.beginPath()
        ctx.arc(hx, hy, ring.thickness * 1.1, 0, Math.PI * 2)
        ctx.fill()
        ctx.fillStyle = ring.fillColor
        ctx.beginPath()
        ctx.arc(hx, hy, ring.thickness * 0.6, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }

  // The hero's centrepiece: a ring that fills as the chamber climbs toward
  // the profile's target, a flame that flickers while lit, wisps of vapour
  // drifting up while heating, and sleepy z's while the Peak is away.
  component HeatOrb: Item {
    id: orb

    property real progress: 0
    property color tint: Color.accent
    property bool lit: false
    property bool climbing: false
    property bool sleeping: false
    readonly property bool live: root.opened

    // Soft backlight that swells with the heat.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.86
      height: width
      radius: width / 2
      color: Util.alpha(orb.tint, orb.lit ? 0.2 : 0.08)

      Behavior on color { ColorAnimation { duration: 400 } }

      SequentialAnimation on scale {
        running: orb.lit && orb.live
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1.0; to: 1.12; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.12; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
      }
    }

    TimerRing {
      anchors.fill: parent
      thickness: Style.space(4)
      progress: orb.progress
      fillColor: orb.tint
      startColor: Color.accent
      trackColor: Util.alpha(root.foreground, 0.08)

      Behavior on progress { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    }

    // Vapour wisps, only while heating.
    Repeater {
      model: 4

      Rectangle {
        id: wisp
        required property int index
        readonly property real drift: (index % 2 === 0 ? -1 : 1) * orb.width * (0.08 + 0.04 * index)
        x: orb.width / 2 - width / 2
        y: orb.height * 0.34
        width: orb.width * 0.13
        height: width
        radius: width / 2
        color: Util.alpha(root.foreground, 0.5)
        opacity: 0
        visible: orb.lit

        SequentialAnimation {
          running: orb.lit && orb.live
          loops: Animation.Infinite
          PauseAnimation { duration: wisp.index * 420 }
          ParallelAnimation {
            NumberAnimation { target: wisp; property: "y"; from: orb.height * 0.34; to: -orb.height * 0.05; duration: 1600; easing.type: Easing.OutSine }
            NumberAnimation { target: wisp; property: "x"; from: orb.width / 2 - wisp.width / 2; to: orb.width / 2 - wisp.width / 2 + wisp.drift; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { target: wisp; property: "scale"; from: 0.5; to: 1.6; duration: 1600 }
            SequentialAnimation {
              NumberAnimation { target: wisp; property: "opacity"; from: 0; to: 0.55; duration: 300 }
              NumberAnimation { target: wisp; property: "opacity"; to: 0; duration: 1300; easing.type: Easing.InQuad }
            }
          }
        }
      }
    }

    Text {
      id: flame
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: orb.sleeping ? "" : ""
      color: orb.sleeping ? root.dim : orb.tint
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      transformOrigin: Item.Bottom

      Behavior on color { ColorAnimation { duration: 300 } }

      // A lively flicker while lit, a slow breath while climbing to temp.
      SequentialAnimation {
        running: orb.lit && orb.live
        loops: Animation.Infinite
        alwaysRunToEnd: true
        ParallelAnimation {
          NumberAnimation { target: flame; property: "scale"; to: 1.1; duration: 180; easing.type: Easing.OutQuad }
          NumberAnimation { target: flame; property: "rotation"; to: -5; duration: 180 }
        }
        ParallelAnimation {
          NumberAnimation { target: flame; property: "scale"; to: 0.95; duration: 240; easing.type: Easing.InOutQuad }
          NumberAnimation { target: flame; property: "rotation"; to: 4; duration: 240 }
        }
        ParallelAnimation {
          NumberAnimation { target: flame; property: "scale"; to: 1.05; duration: 200 }
          NumberAnimation { target: flame; property: "rotation"; to: -2; duration: 200 }
        }
        ParallelAnimation {
          NumberAnimation { target: flame; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutQuad }
          NumberAnimation { target: flame; property: "rotation"; to: 0; duration: 260 }
        }
      }

      SequentialAnimation on opacity {
        running: orb.climbing && orb.live
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
      }
    }

    // Sleepy z's drifting off to the upper right.
    Repeater {
      model: 3

      Text {
        id: zee
        required property int index
        textFormat: Text.PlainText
        text: "z"
        visible: orb.sleeping
        x: orb.width * 0.62
        y: orb.height * 0.3
        opacity: 0
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption + zee.index * 2
        font.bold: true

        SequentialAnimation {
          running: orb.sleeping && orb.live
          loops: Animation.Infinite
          PauseAnimation { duration: zee.index * 700 }
          ParallelAnimation {
            NumberAnimation { target: zee; property: "x"; from: orb.width * 0.6; to: orb.width * 0.95; duration: 2100; easing.type: Easing.OutSine }
            NumberAnimation { target: zee; property: "y"; from: orb.height * 0.3; to: -orb.height * 0.05; duration: 2100; easing.type: Easing.OutSine }
            SequentialAnimation {
              NumberAnimation { target: zee; property: "opacity"; from: 0; to: 0.9; duration: 400 }
              NumberAnimation { target: zee; property: "opacity"; to: 0; duration: 1700 }
            }
          }
        }
      }
    }
  }

  // Confetti pop. `fire()` flings a ring of dots outward from the centre.
  component Burst: Item {
    id: burst

    property real t: 0
    readonly property var colors: [Color.accent, root.urgent, root.foreground, root.profileTint]

    function fire() { burstAnim.restart() }

    visible: burstAnim.running

    NumberAnimation {
      id: burstAnim
      target: burst
      property: "t"
      from: 0
      to: 1
      duration: 750
      easing.type: Easing.OutCubic
    }

    Repeater {
      model: 14

      Rectangle {
        required property int index
        readonly property real angle: index / 14 * Math.PI * 2 + (index % 2) * 0.2
        readonly property real reach: burst.width * (0.55 + (index % 3) * 0.12) * burst.t
        width: Style.space(index % 3 === 0 ? 5 : 4)
        height: width
        radius: index % 2 === 0 ? width / 2 : 1
        rotation: burst.t * 180
        x: burst.width / 2 + Math.cos(angle) * reach - width / 2
        y: burst.height / 2 + Math.sin(angle) * reach - height / 2
        color: burst.colors[index % burst.colors.length]
        opacity: 1 - burst.t * burst.t
      }
    }
  }

  // Mini battery: a body that fills to the charge, a nub, and the label.
  component BatteryPill: Row {
    id: pill

    readonly property real level: Math.max(0, Math.min(1, Number(root.statusData.battery) / 100 || 0))
    readonly property color fill: level <= 0.15 && !root.pluggedIn ? root.urgent
      : root.pluggedIn ? Color.accent
      : Util.alpha(root.foreground, 0.85)

    spacing: Style.space(5)

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Rectangle {
        width: Style.space(22)
        height: Style.space(11)
        radius: Math.min(3, Style.space(3))
        color: "transparent"
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.55)

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 2
          width: Math.max(0, (parent.width - 4) * pill.level)
          radius: 1
          color: pill.fill

          Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

          // Shimmers while it's taking a charge.
          SequentialAnimation on opacity {
            running: root.pluggedIn && pill.level < 1 && root.opened
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
          }
        }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: Style.space(5)
        radius: 1
        color: Util.alpha(root.foreground, 0.55)
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.batteryLabel
      color: pill.level <= 0.15 && !root.pluggedIn ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  // A glowing orb previewing the lantern: the profile's colour at the chosen
  // brightness, with ripples spreading out while the LEDs are on.
  component LanternPreview: Item {
    id: lantern

    property color glow: Color.accent
    property real level: 1
    property bool lit: true
    readonly property real strength: lit ? 0.3 + 0.7 * level : 0.12

    implicitHeight: Style.space(78)

    Repeater {
      model: 2

      Rectangle {
        id: ripple
        required property int index
        anchors.centerIn: parent
        width: lantern.height * 0.5
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Util.alpha(lantern.glow, 0.6 * lantern.strength)
        opacity: 0
        visible: lantern.lit

        SequentialAnimation {
          running: lantern.lit && root.opened && root.onLights
          loops: Animation.Infinite
          PauseAnimation { duration: ripple.index * 1100 }
          ParallelAnimation {
            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.9; duration: 2200; easing.type: Easing.OutSine }
            NumberAnimation { target: ripple; property: "opacity"; from: 1; to: 0; duration: 2200; easing.type: Easing.InQuad }
          }
        }
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: lantern.height * 0.78
      height: width
      radius: width / 2
      color: Util.alpha(lantern.glow, 0.14 * lantern.strength)

      Behavior on color { ColorAnimation { duration: 300 } }

      // A lit lantern breathes; an off one holds still.
      SequentialAnimation on scale {
        running: lantern.lit && root.opened && root.onLights
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 1.1; duration: 1800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      id: lanternCore
      anchors.centerIn: parent
      width: lantern.height * 0.46
      height: width
      radius: width / 2
      color: Util.alpha(lantern.glow, lantern.strength)
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.25)

      Behavior on color { ColorAnimation { duration: 300 } }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: lantern.lit ? Math.round(lantern.level * 100) + "%" : "off"
        color: lantern.lit ? root.inkOn(lantern.glow) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  // Thin rounded progress bar with a gradient fill that eases to its value.
  component MeterBar: Rectangle {
    id: meter

    property real value: 0
    property color fill: Color.accent
    property bool throb: false
    readonly property real clamped: isFinite(value) ? Math.max(0, Math.min(1, value)) : 0

    implicitHeight: Style.space(6)
    height: implicitHeight
    radius: height / 2
    color: Util.alpha(root.foreground, 0.1)

    Rectangle {
      height: parent.height
      radius: parent.radius
      width: meter.clamped > 0 ? Math.max(parent.height, parent.width * meter.clamped) : 0
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Util.alpha(meter.fill, 0.45) }
        GradientStop { position: 1.0; color: meter.fill }
      }

      Behavior on width { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }

      SequentialAnimation on opacity {
        running: meter.throb && root.opened
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
      }
    }
  }

  // A hue ring painted once, used for the "custom colour" chip.
  component ConicalRing: Canvas {
    id: cring

    property bool rotating: false

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var r = Math.min(width, height) / 2
      var g = ctx.createConicalGradient(width / 2, height / 2, 0)
      var stops = ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
      for (var i = 0; i < stops.length; i++) g.addColorStop(i / (stops.length - 1), stops[i])
      ctx.fillStyle = g
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
      ctx.fill()
    }

    RotationAnimation on rotation {
      running: cring.rotating && root.opened
      loops: Animation.Infinite
      from: 0
      to: 360
      duration: 3000
    }
  }

  // The custom colour picker: a hue/saturation wheel, a brightness slider,
  // a live preview and a hex field. Releasing the wheel or the slider sends
  // the colour to the Peak; so does Enter in the hex field.
  component ColorPicker: BorderSurface {
    id: picker

    radius: Style.cornerRadius
    color: Util.alpha(root.pickColor, 0.06)
    borderSpec: Border.flat(Util.alpha(root.pickColor, 0.45), Math.max(1, Style.normalBorderWidth))
    implicitHeight: pickerRow.implicitHeight + Style.spacing.controlPaddingY * 4

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: pickerRow
      anchors.centerIn: parent
      width: parent.width - Style.spacing.controlPaddingX * 2
      spacing: Style.space(14)

      // ----- Wheel -----
      Item {
        id: wheel
        width: Style.space(140)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        readonly property real radius: width / 2

        // Glow in the picked colour behind the wheel.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + Style.space(10)
          height: width
          radius: width / 2
          color: Util.alpha(root.pickColor, 0.22)
        }

        // Hue runs round the wheel (red at 3 o'clock, counter-clockwise) and
        // saturation out from the white centre, at full value; the slider
        // darkens it. Linear RGB blends between pure hues, and from white to
        // a hue, are exactly HSV at full value, so the colour under the
        // cursor is the one the maths below picks.
        Canvas {
          id: wheelCanvas
          anchors.fill: parent
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, R = Math.min(width, height) / 2
            var hues = ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
            var cone = ctx.createConicalGradient(cx, cy, 0)
            for (var i = 0; i < hues.length; i++) cone.addColorStop(i / (hues.length - 1), hues[i])
            ctx.fillStyle = cone
            ctx.beginPath()
            ctx.arc(cx, cy, R, 0, Math.PI * 2)
            ctx.fill()
            var white = ctx.createRadialGradient(cx, cy, 0, cx, cy, R)
            white.addColorStop(0, "rgba(255,255,255,1)")
            white.addColorStop(1, "rgba(255,255,255,0)")
            ctx.fillStyle = white
            ctx.beginPath()
            ctx.arc(cx, cy, R, 0, Math.PI * 2)
            ctx.fill()
          }
        }

        // Darkens the whole wheel to match the brightness slider.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "black"
          opacity: 1 - root.pickV
        }

        // Cursor.
        Rectangle {
          id: wheelKnob
          readonly property real angle: root.pickH * Math.PI * 2
          readonly property real reach: root.pickS * wheel.radius
          width: Style.space(wheelMouse.pressed ? 20 : 16)
          height: width
          radius: width / 2
          x: wheel.radius + Math.cos(angle) * reach - width / 2
          y: wheel.radius - Math.sin(angle) * reach - height / 2
          color: root.pickColor
          border.width: 2
          border.color: "white"

          Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

          Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Util.alpha("black", 0.5)
          }
        }

        MouseArea {
          id: wheelMouse
          anchors.fill: parent
          cursorShape: Qt.CrossCursor
          preventStealing: true

          function pick(mx, my) {
            var dx = mx - wheel.radius
            var dy = my - wheel.radius
            var hue = Math.atan2(-dy, dx) / (Math.PI * 2)
            if (hue < 0) hue += 1
            root.pickH = hue
            root.pickS = Math.min(1, Math.sqrt(dx * dx + dy * dy) / wheel.radius)
            // A dark colour picked off the wheel is almost never what's meant.
            if (root.pickV < 0.15) root.pickV = 1
          }

          onPressed: function(mouse) { pick(mouse.x, mouse.y) }
          onPositionChanged: function(mouse) { if (pressed) pick(mouse.x, mouse.y) }
          onReleased: root.schedulePickApply()
        }
      }

      // ----- Preview, brightness, hex -----
      Column {
        width: pickerRow.width - wheel.width - pickerRow.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(38)
            height: width
            radius: width / 2
            color: root.pickColor
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.35)

            Rectangle {
              z: -1
              anchors.centerIn: parent
              width: parent.width + Style.space(10)
              height: width
              radius: width / 2
              color: Util.alpha(root.pickColor, 0.3)
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.pickHex.toUpperCase()
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var c = root.pickColor
                return Math.round(c.r * 255) + " · " + Math.round(c.g * 255) + " · " + Math.round(c.b * 255)
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Brightness (HSV value) slider over a black-to-colour gradient.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            implicitHeight: valueLabel.implicitHeight

            Text {
              id: valueLabel
              textFormat: Text.PlainText
              text: "Brightness"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: Math.round(root.pickV * 100) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            id: valueTrack
            width: parent.width
            height: Style.space(16)

            Rectangle {
              anchors.fill: parent
              anchors.topMargin: Style.space(3)
              anchors.bottomMargin: Style.space(3)
              radius: height / 2
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.2)
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "black" }
                GradientStop { position: 1.0; color: Qt.hsva(root.pickH, root.pickS, 1, 1) }
              }
            }

            Rectangle {
              width: Style.space(valueMouse.pressed ? 18 : 14)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              x: root.pickV * (valueTrack.width - width)
              color: root.pickColor
              border.width: 2
              border.color: "white"

              Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
            }

            MouseArea {
              id: valueMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              preventStealing: true

              function set(mx) { root.pickV = Math.max(0, Math.min(1, mx / valueTrack.width)) }

              onPressed: function(mouse) { set(mouse.x) }
              onPositionChanged: function(mouse) { if (pressed) set(mouse.x) }
              onReleased: root.schedulePickApply()
            }
          }
        }

        // Exact colour by hex; Enter applies it.
        TextField {
          id: hexField
          width: parent.width
          foreground: root.foreground
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.xs
          maximumLength: 7
          placeholderText: "#rrggbb"

          property bool bad: false

          // Follows the wheel until you start typing in it.
          Binding on text {
            when: !hexField.activeFocus
            value: root.pickHex.toUpperCase()
          }

          onTextChanged: bad = false
          onAccepted: {
            if (root.applyTypedHex(text)) {
              bad = false
              if (keyCatcher) keyCatcher.forceActiveFocus()
            } else {
              bad = true
            }
          }
          Keys.onEscapePressed: function(event) {
            if (keyCatcher) keyCatcher.forceActiveFocus()
            event.accepted = true
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: hexField.bad ? "That's not a colour. Try #ff6a1a."
            : root.cycleOn ? "Cycling: choose a colour here, then + in Color cycle adds it."
            : "Let go of the wheel or press Enter to send it to the Peak."
          color: hexField.bad ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Colour cycle for the active profile: on/off, a live preview of the
  // animation, the style, palettes, your own colours and the speed.
  component CycleSection: Section {
    id: cycleSection

    glyph: ""
    title: root.activeProfile
      ? "COLOR CYCLE · " + String(root.cleanName(root.activeProfile.name) || ("Profile " + (root.currentProfile + 1))).toUpperCase()
      : "COLOR CYCLE"
    trailing: root.cycleOn ? "On the Peak" : ""

    SwitchRow {
      width: parent.width
      label: "Cycle colors"
      checked: root.cycleOn
      onToggled: root.setCycleOn(!root.cycleOn)
    }

    // A strip of LEDs acting out the chosen style at roughly its pace.
    Item {
      id: ledStrip
      width: parent.width
      height: Style.space(26)
      readonly property int leds: 14
      readonly property int n: Math.max(1, root.cycleColors.length)
      opacity: root.cycleOn ? 1 : 0.55

      Behavior on opacity { NumberAnimation { duration: 250 } }

      Row {
        id: ledRow
        anchors.centerIn: parent
        spacing: Style.space(5)

        SequentialAnimation on opacity {
          running: root.cycleStyle === "breathe" && root.opened && root.onLights
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.25; duration: root.cycleStepMs; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: root.cycleStepMs; easing.type: Easing.InOutSine }
        }

        Repeater {
          model: ledStrip.leds

          Rectangle {
            required property int index
            readonly property int slot: {
              var t = root.cycleTick, i = index, n = ledStrip.n, L = ledStrip.leds
              switch (root.cycleStyle) {
              case "spin": return Math.floor(i * n / L + t) % n
              case "disco": return (i * 7 + t * 3 + (i % 3) * t) % n
              // Two halves, each walking the palette.
              case "split": return (t + (i < L / 2 ? 0 : Math.floor(n / 2))) % n
              // A slow wave of colour rolling one way.
              case "fill": return Math.floor(t / 2 + (L - i) * n / L) % n
              // Big slow blobs drifting.
              case "lava": return Math.floor((Math.sin(i * 0.5 + t * 0.35) + 1) / 2 * n) % n
              // Scattered sparkles.
              case "confetti": return ((i * 13 + t * 7) ^ (t * 3)) % n
              default: return t % n
              }
            }
            readonly property color led: root.cycleColors.length ? root.cycleColors[slot] : Color.accent
            width: (ledStrip.width - ledRow.spacing * (ledStrip.leds - 1)) / ledStrip.leds
            height: Style.space(14)
            radius: height / 2
            color: led

            Behavior on color {
              ColorAnimation {
                duration: ["fade", "breathe", "lava", "fill"].indexOf(root.cycleStyle) >= 0
                  ? root.cycleStepMs * 0.95 : 140
              }
            }

            Rectangle {
              z: -1
              anchors.centerIn: parent
              width: parent.width + Style.space(6)
              height: parent.height + Style.space(6)
              radius: height / 2
              color: Util.alpha(parent.led, 0.3)
            }
          }
        }
      }
    }

    // The app's animations, two rows of four.
    Grid {
      id: styleGrid
      width: parent.width
      columns: 4
      rowSpacing: Style.space(4)
      columnSpacing: Style.space(4)
      readonly property real cell: (width - columnSpacing * 3) / 4

      Repeater {
        model: root.cycleStyles

        Rectangle {
          id: styleChip
          required property var modelData
          readonly property bool picked: root.cycleStyle === modelData.value
          width: styleGrid.cell
          height: Style.space(40)
          radius: Style.cornerRadius
          color: picked ? Util.alpha(Color.accent, 0.2)
            : styleMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
            : Style.normalFillFor(root.foreground, Color.accent)
          border.width: 1
          border.color: picked ? Color.accent : Util.alpha(root.foreground, 0.12)
          scale: styleMouse.pressed ? 0.93 : 1

          Behavior on color { ColorAnimation { duration: 140 } }
          Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: styleChip.modelData.glyph
              color: styleChip.picked ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: styleChip.modelData.label
              color: styleChip.picked ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: styleChip.picked
            }
          }

          MouseArea {
            id: styleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pickCycleStyle(styleChip.modelData.value)
          }
        }
      }
    }

    // Palette presets as gradient pills.
    Grid {
      id: paletteGrid
      width: parent.width
      columns: 3
      rowSpacing: Style.space(6)
      columnSpacing: Style.space(6)
      readonly property real cell: (width - columnSpacing * 2) / 3

      Repeater {
        model: root.cyclePalettes

        Rectangle {
          id: paletteChip
          required property var modelData
          readonly property bool picked: {
            var a = root.cycleColors, b = modelData.colors
            if (a.length !== b.length) return false
            for (var i = 0; i < a.length; i++) if (String(a[i]).toLowerCase() !== b[i]) return false
            return true
          }
          width: paletteGrid.cell
          height: Style.space(26)
          radius: height / 2
          border.width: picked ? 2 : 1
          border.color: picked ? root.foreground : Util.alpha(root.foreground, 0.25)
          scale: paletteMouse.pressed ? 0.94 : (paletteMouse.containsMouse ? 1.05 : 1)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: paletteChip.modelData.colors[0] }
            GradientStop { position: 0.5; color: paletteChip.modelData.colors[Math.floor(paletteChip.modelData.colors.length / 2)] }
            GradientStop { position: 1.0; color: paletteChip.modelData.colors[paletteChip.modelData.colors.length - 1] }
          }

          Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

          Rectangle {
            anchors.centerIn: parent
            width: paletteLabel.implicitWidth + Style.space(12)
            height: paletteLabel.implicitHeight + Style.space(2)
            radius: height / 2
            color: Util.alpha("black", 0.45)

            Text {
              id: paletteLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: (paletteChip.picked ? " " : "") + paletteChip.modelData.name
              color: "white"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            id: paletteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pickCyclePalette(paletteChip.modelData.colors)
          }
        }
      }
    }

    // Your colours: tap one to drop it, + adds the colour on the wheel.
    Item {
      width: parent.width
      implicitHeight: yourRow.height + yourHint.implicitHeight + Style.space(6)

      Row {
        id: yourRow
        spacing: Style.space(8)
        height: Style.space(28)

        Repeater {
          model: root.cycleColors

          Rectangle {
            id: cycleDot
            required property var modelData
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            height: width
            radius: width / 2
            color: String(modelData)
            border.width: root.cycleColors[root.cycleTick % root.cycleColors.length] === modelData && root.cycleOn ? 2 : 1
            border.color: border.width > 1 ? root.foreground : Util.alpha(root.foreground, 0.3)
            scale: dotMouse.containsMouse ? 1.12 : 1

            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

            Text {
              anchors.centerIn: parent
              visible: dotMouse.containsMouse && root.cycleColors.length > 1
              textFormat: Text.PlainText
              text: ""
              color: root.inkOn(cycleDot.modelData)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: dotMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.cycleColors.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.removeCycleColor(cycleDot.index)
            }
          }
        }

        Rectangle {
          visible: root.cycleColors.length < root.maxCycleColors
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(26)
          height: width
          radius: width / 2
          color: addMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
          border.width: 1
          border.color: Util.alpha(root.foreground, 0.45)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "+"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          MouseArea {
            id: addMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.pickerOpen) {
                root.addCycleColor(root.pickHex)
              } else {
                // Open the wheel so the next colour can be picked exactly.
                root.togglePicker()
              }
            }
          }
        }
      }

      Text {
        id: yourHint
        anchors.top: yourRow.bottom
        anchors.topMargin: Style.space(6)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.pickerOpen
          ? "+ adds the colour on the wheel. Tap a colour to drop it."
          : "+ opens the colour wheel. Tap a colour to drop it."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: speedLabel.implicitHeight

        Text {
          id: speedLabel
          textFormat: Text.PlainText
          text: "Speed"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: root.cycleTempo < 0.35 ? "Chill" : root.cycleTempo < 0.7 ? "Groovy" : "Rave"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: 10
        maximum: 100
        step: 5
        integer: true
        value: Math.round(root.cycleTempo * 100)
        onReleased: function(v) { root.setCycleTempo(v / 100) }
      }
    }

    SwitchRow {
      width: parent.width
      label: "React to inhales"
      checked: root.cycleInhale
      onToggled: root.toggleCycleInhale()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.cycleOn
        ? "The Peak runs the animation itself, even when this computer is away. Turn the LED on above to see it."
        : "Pick a style and colours, then switch it on."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Lights saved off the Peak. Exclusive moods (Puffcon, Plasma, ...) only
  // come from Puffco's servers to a signed-in app, so the way to keep one is
  // to put it on a profile in the app once and save it here.
  component MyLightsSection: Section {
    id: lightsSection

    glyph: ""
    title: "MY LIGHTS"
    trailing: root.savedLights.length ? root.savedLights.length + " saved" : ""

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.savedLights.length
        ? "Tap one to put it on " + (root.activeProfile ? root.cleanName(root.activeProfile.name) || "this profile" : "this profile") + "."
        : "Exclusive moods like Puffcon only come from the Puffco app. To keep one: Disconnect here (Device tab), set the mood on a profile in the app, reconnect, then save it below."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.savedLights

      BorderSurface {
        id: lightRow
        required property var modelData
        readonly property bool worn: root.wornLightId === modelData.id
        readonly property bool renaming: root.renamingLight === modelData.id
        readonly property bool confirming: root.confirmDeleteLight === modelData.id
        readonly property var colors: modelData.colors || []

        width: parent ? parent.width : 0
        implicitHeight: Style.space(44)
        radius: Style.cornerRadius
        color: rowMouse.pressed ? Util.alpha(Color.accent, 0.22)
          : worn ? Util.alpha(Color.accent, 0.14)
          : rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
          : Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: worn
          ? Border.flat(Color.accent, Math.max(1, Style.normalBorderWidth))
          : Border.controlSpec(rowMouse.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)

        Behavior on color { ColorAnimation { duration: 140 } }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !lightRow.renaming
          cursorShape: Qt.PointingHandCursor
          onClicked: root.applySavedLight(lightRow.modelData.id)
        }

        // The light's colours as a pill, or a rainbow when it keeps them to itself.
        Item {
          id: lightSwatch
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          height: Style.space(18)

          Rectangle {
            anchors.fill: parent
            visible: lightRow.colors.length > 0
            radius: height / 2
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.25)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: lightRow.colors.length ? lightRow.colors[0] : "black" }
              GradientStop { position: 0.5; color: lightRow.colors.length ? lightRow.colors[Math.floor(lightRow.colors.length / 2)] : "black" }
              GradientStop { position: 1.0; color: lightRow.colors.length ? lightRow.colors[lightRow.colors.length - 1] : "black" }
            }
          }

          ConicalRing {
            anchors.centerIn: parent
            visible: lightRow.colors.length === 0
            width: parent.height
            height: width
            rotating: lightRow.worn
          }
        }

        Column {
          anchors.left: lightSwatch.right
          anchors.leftMargin: Style.space(10)
          anchors.right: lightButtons.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)
          visible: !lightRow.renaming

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: lightRow.modelData.name
            color: lightRow.worn ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              var style = String(lightRow.modelData.style || "")
              var label = style === "custom" ? "Exclusive" : style === "solid" ? "Solid" : style.charAt(0).toUpperCase() + style.slice(1)
              return lightRow.worn ? " On this profile · " + label : label
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Loader {
          anchors.left: lightSwatch.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          active: lightRow.renaming

          sourceComponent: InlineNameField {
            seed: lightRow.modelData.name
            onCommitted: function(value) { root.renameSavedLight(lightRow.modelData.id, value) }
            onCanceled: {
              root.renamingLight = ""
              root.refocusPanel()
            }
          }
        }

        Row {
          id: lightButtons
          visible: !lightRow.renaming
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          TileButton {
            anchors.verticalCenter: parent.verticalCenter
            glyph: ""
            onActivated: {
              root.namingLight = false
              root.renamingLight = lightRow.modelData.id
            }
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: lightRow.confirming ? sureLabel.implicitWidth + Style.space(12) : Style.space(18)
            height: Style.space(18)

            Behavior on width { NumberAnimation { duration: 140 } }

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: lightRow.confirming ? Util.alpha(root.urgent, 0.25)
                : trashMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
            }

            Text {
              id: sureLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: lightRow.confirming ? "Delete?" : ""
              color: lightRow.confirming || trashMouse.containsMouse ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: lightRow.confirming ? Style.font.caption : Style.font.bodySmall
              font.bold: lightRow.confirming
            }

            MouseArea {
              id: trashMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.deleteSavedLight(lightRow.modelData.id)
            }
          }
        }
      }
    }

    // Save whatever this profile wears right now.
    Item {
      width: parent.width
      implicitHeight: root.namingLight ? nameLoader.implicitHeight : saveButton.implicitHeight

      ActionButton {
        id: saveButton
        visible: !root.namingLight
        width: parent.width
        label: root.wearingSaved ? "Already saved" : "Save this profile's light"
        glyph: root.wearingSaved ? "" : ""
        tint: Color.accent
        emphasized: !root.wearingSaved
        onActivated: {
          if (root.wearingSaved || root.currentProfile < 0) return
          root.renamingLight = ""
          root.namingLight = true
        }
      }

      Loader {
        id: nameLoader
        width: parent.width
        active: root.namingLight

        sourceComponent: InlineNameField {
          seed: root.activeCycle && root.activeCycle.style === "custom"
            ? "Exclusive " + (root.savedLights.length + 1)
            : (root.activeProfile ? root.cleanName(root.activeProfile.name) || "My light" : "My light") + " light"
          placeholderText: "Name it, e.g. Puffcon 2026"
          onCommitted: function(value) { root.saveCurrentLight(value) }
          onCanceled: {
            root.namingLight = false
            root.refocusPanel()
          }
        }
      }
    }
  }

  // One-line name editor: Enter commits, Escape or clicking away cancels.
  component InlineNameField: TextField {
    id: nameField

    property string seed: ""
    property bool armed: false
    property bool done: false

    signal committed(string value)
    signal canceled()

    function finish(save) {
      if (done) return
      done = true
      if (save) nameField.committed(nameField.text)
      else nameField.canceled()
    }

    foreground: root.foreground
    accent: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalPadding: Style.spacing.xs
    maximumLength: 32

    Component.onCompleted: {
      text = seed
      Qt.callLater(function() {
        nameField.selectAll()
        nameField.forceActiveFocus()
        nameField.armed = true
      })
    }

    onAccepted: nameField.finish(true)
    Keys.onEscapePressed: function(event) {
      nameField.finish(false)
      event.accepted = true
    }
    onActiveFocusChanged: {
      if (!armed || activeFocus) return
      Qt.callLater(function() { nameField.finish(false) })
    }
  }

  // The session's temperature curve: a gradient area under the climb, the
  // target as a dashed line, Ready and Cooling marked, and a live dot on the
  // newest reading while the Peak heats.
  component HeatGraph: Section {
    id: graph

    glyph: ""
    title: root.heatTraceLive ? "HEAT CURVE" : "LAST SESSION"
    trailing: {
      var pts = root.heatPoints
      if (!pts.length) return ""
      return (root.heatTraceLive ? "Live · " : "") + root.formatDuration(pts[pts.length - 1][0])
    }

    readonly property var pts: root.heatPoints
    readonly property real targetF: root.heatTrace && isFinite(Number(root.heatTrace.target_f)) ? Number(root.heatTrace.target_f) : NaN
    readonly property real readyAt: root.heatTrace && root.heatTrace.ready_at !== null && root.heatTrace.ready_at !== undefined ? Number(root.heatTrace.ready_at) : NaN
    readonly property real fadeAt: root.heatTrace && root.heatTrace.fade_at !== null && root.heatTrace.fade_at !== undefined ? Number(root.heatTrace.fade_at) : NaN
    readonly property real spanS: pts.length ? Math.max(10, Number(pts[pts.length - 1][0])) : 10
    readonly property real lowF: {
      var lo = Infinity
      for (var i = 0; i < pts.length; i++) lo = Math.min(lo, Number(pts[i][1]))
      return isFinite(lo) ? Math.max(0, lo - 20) : 0
    }
    readonly property real highF: {
      var hi = isFinite(targetF) ? targetF : 0
      if (isFinite(root.heatPeakF)) hi = Math.max(hi, root.heatPeakF)
      return hi + 25
    }

    Item {
      id: plot
      width: parent.width
      height: Style.space(96)

      readonly property real padTop: Style.space(6)
      readonly property real padBottom: Style.space(4)
      function xAt(t) { return Math.max(0, Math.min(1, t / graph.spanS)) * width }
      function yAt(f) {
        var frac = (f - graph.lowF) / Math.max(1, graph.highF - graph.lowF)
        return padTop + (1 - Math.max(0, Math.min(1, frac))) * (height - padTop - padBottom)
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.1)
      }

      Canvas {
        id: curve
        anchors.fill: parent

        Connections {
          target: graph
          function onPtsChanged() { curve.requestPaint() }
          function onTargetFChanged() { curve.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var pts = graph.pts
          if (pts.length < 2) return
          var bottom = height - plot.padBottom

          // Area under the curve, hot at the top fading to nothing.
          var fill = ctx.createLinearGradient(0, plot.padTop, 0, bottom)
          fill.addColorStop(0, Util.alpha(root.urgent, 0.45))
          fill.addColorStop(1, Util.alpha(Color.accent, 0.02))
          ctx.fillStyle = fill
          ctx.beginPath()
          ctx.moveTo(plot.xAt(pts[0][0]), bottom)
          for (var i = 0; i < pts.length; i++) ctx.lineTo(plot.xAt(pts[i][0]), plot.yAt(pts[i][1]))
          ctx.lineTo(plot.xAt(pts[pts.length - 1][0]), bottom)
          ctx.closePath()
          ctx.fill()

          // The curve itself, cool accent climbing into the urgent heat colour.
          var stroke = ctx.createLinearGradient(0, bottom, 0, plot.padTop)
          stroke.addColorStop(0, Color.accent)
          stroke.addColorStop(1, root.urgent)
          ctx.strokeStyle = stroke
          ctx.lineWidth = 2
          ctx.lineJoin = "round"
          ctx.lineCap = "round"
          ctx.beginPath()
          for (var j = 0; j < pts.length; j++) {
            var x = plot.xAt(pts[j][0]), y = plot.yAt(pts[j][1])
            if (j === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.stroke()

          // Target temperature, dashed.
          if (isFinite(graph.targetF)) {
            var ty = plot.yAt(graph.targetF)
            ctx.strokeStyle = Util.alpha(root.foreground, 0.45)
            ctx.lineWidth = 1
            ctx.beginPath()
            for (var dx = 0; dx < width; dx += 8) {
              ctx.moveTo(dx, ty)
              ctx.lineTo(Math.min(width, dx + 4), ty)
            }
            ctx.stroke()
          }

          // Phase markers.
          function marker(t, color) {
            if (!isFinite(t)) return
            var mx = plot.xAt(t)
            ctx.strokeStyle = color
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(mx, plot.padTop)
            ctx.lineTo(mx, bottom)
            ctx.stroke()
          }
          marker(graph.readyAt, Util.alpha(Color.accent, 0.8))
          marker(graph.fadeAt, Util.alpha(root.foreground, 0.35))
        }
      }

      Text {
        visible: isFinite(graph.targetF)
        x: Style.space(6)
        y: plot.yAt(graph.targetF) - implicitHeight - 1
        textFormat: Text.PlainText
        text: root.formatTemp(graph.targetF, undefined)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: isFinite(graph.readyAt) && plot.xAt(graph.readyAt) < plot.width - implicitWidth - Style.space(4)
        x: plot.xAt(graph.readyAt) + Style.space(3)
        y: plot.height - implicitHeight - Style.space(3)
        textFormat: Text.PlainText
        text: "Ready"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: isFinite(graph.fadeAt) && plot.xAt(graph.fadeAt) < plot.width - implicitWidth - Style.space(4)
        x: plot.xAt(graph.fadeAt) + Style.space(3)
        y: plot.height - implicitHeight - Style.space(3)
        textFormat: Text.PlainText
        text: "Cooling"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Newest reading, pulsing while live.
      Rectangle {
        id: headDot
        visible: graph.pts.length > 0
        readonly property var last: graph.pts.length ? graph.pts[graph.pts.length - 1] : [0, 0]
        width: Style.space(7)
        height: width
        radius: width / 2
        x: plot.xAt(last[0]) - width / 2
        y: plot.yAt(last[1]) - height / 2
        color: root.heatTraceLive ? Qt.lighter(root.urgent, 1.2) : root.dim

        Rectangle {
          z: -1
          anchors.centerIn: parent
          width: parent.width * 2.6
          height: width
          radius: width / 2
          color: Util.alpha(root.urgent, 0.35)
          visible: root.heatTraceLive

          SequentialAnimation on scale {
            running: root.heatTraceLive && root.opened
            loops: Animation.Infinite
            NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.OutSine }
            NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InSine }
          }
        }
      }
    }

    Row {
      id: graphStats
      width: parent.width
      spacing: Style.spacing.controlGap
      readonly property real cell: (width - spacing * 2) / 3

      SummaryCell {
        width: graphStats.cell
        title: "Heat-up"
        value: isFinite(graph.readyAt) ? root.formatDuration(graph.readyAt) : "…"
      }
      SummaryCell {
        width: graphStats.cell
        title: "Peak"
        value: isFinite(root.heatPeakF) ? root.formatTemp(root.heatPeakF, undefined) : "—"
      }
      SummaryCell {
        width: graphStats.cell
        title: "At temp"
        value: {
          if (!isFinite(graph.readyAt)) return "—"
          var end = isFinite(graph.fadeAt) ? graph.fadeAt : Number(graph.pts[graph.pts.length - 1][0])
          return root.formatDuration(Math.max(0, end - graph.readyAt))
        }
      }
    }
  }

  // Titled block: every group of controls gets the same small-caps header
  // and spacing, which is most of what makes the pages read as one system.
  component Section: Column {
    id: section

    property string title: ""
    property string trailing: ""
    property string glyph: ""
    default property alias body: sectionBody.data

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: Math.max(sectionHeader.implicitHeight, sectionGlyph.implicitHeight)

      Text {
        id: sectionGlyph
        visible: section.glyph !== ""
        width: visible ? implicitWidth : 0
        anchors.left: parent.left
        anchors.verticalCenter: sectionHeader.verticalCenter
        textFormat: Text.PlainText
        text: section.glyph
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSectionHeader {
        id: sectionHeader
        anchors.left: sectionGlyph.right
        anchors.leftMargin: sectionGlyph.visible ? Style.space(6) : 0
        text: section.title
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        visible: section.trailing !== ""
        anchors.right: parent.right
        anchors.bottom: sectionHeader.bottom
        textFormat: Text.PlainText
        text: section.trailing
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: sectionBody
      width: parent.width
      spacing: Style.space(8)
    }
  }

  // Equal-width, mutually exclusive choice row with a highlight pill that
  // slides to the picked option. Options may carry a `glyph` (stacked over
  // the label on the full-size bar, inline on a compact one) and a `badge`.
  component Segmented: Item {
    id: seg

    property var options: []
    property string value: ""
    property bool compact: false

    signal picked(string value)

    readonly property int count: options.length
    readonly property real gap: compact ? Style.space(3) : Style.space(4)
    readonly property real cellWidth: count > 0 ? (width - gap * (count - 1)) / count : 0
    readonly property bool stacked: !compact && count > 0 && options[0].glyph !== undefined
    readonly property int selectedIndex: {
      for (var i = 0; i < options.length; i++)
        if (String(options[i].value) === value) return i
      return -1
    }

    implicitHeight: stacked ? Style.space(42) : (compact ? Style.space(24) : Style.spacing.controlHeight)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.foreground, Color.accent)
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.12)
    }

    Rectangle {
      visible: seg.selectedIndex >= 0
      x: seg.selectedIndex * (seg.cellWidth + seg.gap)
      width: seg.cellWidth
      height: parent.height
      radius: Style.cornerRadius
      color: Util.alpha(Color.accent, 0.2)
      border.width: 1
      border.color: Color.accent

      Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
      Behavior on width { NumberAnimation { duration: 200 } }
    }

    Repeater {
      model: seg.options

      Item {
        id: cell
        required property var modelData
        required property int index
        readonly property bool selected: index === seg.selectedIndex
        readonly property bool hot: cellMouse.containsMouse
        readonly property color ink: selected ? Color.accent : (hot ? root.foreground : root.dim)

        x: index * (seg.cellWidth + seg.gap)
        width: seg.cellWidth
        height: seg.height

        Grid {
          anchors.centerIn: parent
          columns: seg.stacked ? 1 : 2
          spacing: seg.stacked ? Style.space(2) : Style.space(5)
          horizontalItemAlignment: Grid.AlignHCenter
          verticalItemAlignment: Grid.AlignVCenter
          scale: cellMouse.pressed ? 0.92 : (cell.selected && seg.stacked ? 1.04 : 1)

          Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

          Text {
            visible: cell.modelData.glyph !== undefined
            textFormat: Text.PlainText
            text: String(cell.modelData.glyph || "")
            color: cell.ink
            font.family: root.fontFamily
            font.pixelSize: seg.stacked ? Style.font.subtitle : Style.font.caption

            Behavior on color { ColorAnimation { duration: 160 } }
          }

          Text {
            textFormat: Text.PlainText
            text: String(cell.modelData.label)
            color: cell.selected ? root.foreground : cell.ink
            font.family: root.fontFamily
            font.pixelSize: seg.compact || seg.stacked ? Style.font.caption : Style.font.bodySmall
            font.bold: cell.selected

            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }

        Rectangle {
          visible: cell.modelData.badge === true
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: Style.space(5)
          width: Style.space(6)
          height: width
          radius: width / 2
          color: root.urgent

          SequentialAnimation on scale {
            running: parent.visible && root.opened
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 1.4; duration: 600; easing.type: Easing.OutSine }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InSine }
          }
        }

        MouseArea {
          id: cellMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: seg.picked(String(cell.modelData.value))
        }
      }
    }
  }

  component SwitchRow: Item {
    id: switchRow

    property string label: ""
    property bool checked: false

    signal toggled()

    implicitHeight: Math.max(switchLabel.implicitHeight, switchControl.implicitHeight)

    Text {
      id: switchLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: switchRow.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    ToggleSwitch {
      id: switchControl
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      cursorRing: false
      foreground: root.foreground
      onToggled: switchRow.toggled()
    }
  }

  component StepperRow: Item {
    id: stepper

    property string label: ""
    property string valueText: ""
    property bool canLower: true
    property bool canRaise: true

    signal lower()
    signal raise()

    implicitHeight: Math.max(Style.space(24), stepperLabel.implicitHeight)

    Text {
      id: stepperLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: stepper.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      TileButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "−"
        canTap: stepper.canLower
        onActivated: stepper.lower()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(52)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: stepper.valueText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      TileButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "+"
        canTap: stepper.canRaise
        onActivated: stepper.raise()
      }
    }
  }

  component TipBlock: Column {
    id: tip

    property string title: ""
    property string body: ""

    spacing: Style.space(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: tip.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: tip.body
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // One fault: category glyph, what happened, and when.
  component FaultCard: BorderSurface {
    id: faultCard

    property var fault: ({})

    radius: Style.cornerRadius
    color: Style.normalFillFor(Color.urgent, Color.urgent)
    borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)
    implicitHeight: cardRow.implicitHeight + Style.spacing.controlPaddingY * 2

    Item {
      id: cardRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      implicitHeight: Math.max(cardGlyph.implicitHeight, cardText.implicitHeight)

      Text {
        id: cardGlyph
        width: Style.space(20)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.faultGlyph(Number(faultCard.fault.code))
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconSmall
      }

      Column {
        id: cardText
        anchors.left: cardGlyph.right
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(faultCard.fault.label || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.formatFaultTime(faultCard.fault.ts)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // One dab in History: what it was, when, and its note (tap to edit).
  component SessionCard: BorderSurface {
    id: sessionCard

    property var session: ({})
    readonly property string key: String(session.key || "")
    readonly property bool editingNote: root.noteKey === key
    readonly property string note: root.noteFor(session)

    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: Border.controlSpec(sessionMouse.containsMouse || editingNote ? "hover-cursor" : "normal", root.foreground, Color.accent)
    implicitHeight: sessionCol.implicitHeight + Style.spacing.controlPaddingY * 2

    // The profile's colour down the leading edge, like the heat tiles.
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      width: Style.space(3)
      color: sessionCard.session.profile !== null && sessionCard.session.profile !== undefined
        ? root.profileUsageColor(sessionCard.session.profile)
        : Color.accent
      opacity: sessionMouse.containsMouse || sessionCard.editingNote ? 1 : 0.6
    }

    MouseArea {
      id: sessionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: !sessionCard.editingNote
      cursorShape: Qt.PointingHandCursor
      onClicked: root.editNote(sessionCard.key)
    }

    Column {
      id: sessionCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.topMargin: Style.spacing.controlPaddingY
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(sessionTitle.implicitHeight, sessionTime.implicitHeight)

        Text {
          id: sessionTitle
          anchors.left: parent.left
          anchors.right: sessionTime.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.sessionTitle(sessionCard.session)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Text {
          id: sessionTime
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.formatSessionTime(sessionCard.session.ts)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.sessionDetail(sessionCard.session)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: !sessionCard.editingNote
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: sessionCard.note !== "" ? sessionCard.note : "Add a note"
        color: sessionCard.note !== "" ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: sessionCard.note !== "" ? Style.font.bodySmall : Style.font.caption
        font.italic: sessionCard.note === ""
      }

      Loader {
        width: parent.width
        active: sessionCard.editingNote

        sourceComponent: NoteEditor {
          noteKey: sessionCard.key
          seed: sessionCard.note
        }
      }

      Text {
        width: parent.width
        visible: sessionCard.editingNote
        textFormat: Text.PlainText
        text: "Enter or click away to save \u00b7 Esc to cancel"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Unlike TileEditor, losing focus saves: a half-written note shouldn't vanish.
  component NoteEditor: TextField {
    id: noteEditor

    property string noteKey: ""
    property string seed: ""
    property bool armed: false
    property bool done: false

    function finish(save) {
      if (done) return
      done = true
      if (save) root.saveNote(noteKey, text)
      else root.closeNote(noteKey)
    }

    foreground: root.foreground
    accent: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalPadding: Style.spacing.xs
    maximumLength: 500
    placeholderText: "How was it? Flavor, clouds, what you'd change"

    Component.onCompleted: {
      text = seed
      Qt.callLater(function() {
        if (noteEditor.cursorPosition !== undefined) noteEditor.cursorPosition = noteEditor.text.length
        noteEditor.forceActiveFocus()
        noteEditor.armed = true
      })
    }

    onAccepted: noteEditor.finish(true)
    Keys.onEscapePressed: function(event) {
      noteEditor.finish(false)
      event.accepted = true
    }
    onActiveFocusChanged: {
      if (!armed || activeFocus) return
      Qt.callLater(function() { noteEditor.finish(true) })
    }
  }

  component InfoRow: Item {
    id: info

    property string label: ""
    property string value: ""

    visible: value !== ""
    implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

    Text {
      id: infoLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: info.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: infoValue
      anchors.left: infoLabel.right
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: info.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  component SummaryCell: BorderSurface {
    id: cell

    property string title: ""
    property string value: ""
    property string glyph: ""
    property bool highlight: false
    // Optional colour bar along the bottom (the factory heat presets).
    property string stripe: ""

    // Plain counts tick up to their value; anything else shows as given.
    readonly property bool numeric: /^\d+$/.test(value)
    property real shown: numeric ? Number(value) : 0
    Behavior on shown { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    radius: Style.cornerRadius
    color: highlight ? Util.alpha(Color.accent, 0.12) : Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: highlight
      ? Border.flat(Util.alpha(Color.accent, 0.7), Math.max(1, Style.normalBorderWidth))
      : Border.controlSpec("normal", root.foreground, Color.accent)
    implicitHeight: cellCol.implicitHeight + Style.spacing.controlPaddingY * 2 + (stripe !== "" ? Style.space(3) : 0)

    Column {
      id: cellCol
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: cell.glyph !== ""
        textFormat: Text.PlainText
        text: cell.glyph
        color: cell.highlight ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: cell.numeric ? String(Math.round(cell.shown)) : cell.value
        color: cell.highlight ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: cell.title
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      visible: cell.stripe !== ""
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      height: Style.space(3)
      color: cell.stripe !== "" ? cell.stripe : "transparent"
    }
  }

  // Compact metric tile: title, big value, caption, optional extra
  // (weekday dots, hour histogram).
  component StatCard: BorderSurface {
    id: metric

    property string title: ""
    property string value: ""
    property string meta: ""
    property string glyph: ""
    property color glyphColor: Color.accent
    default property alias extra: extraSlot.data

    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    implicitHeight: metricCol.implicitHeight + Style.spacing.controlPaddingY * 2

    Column {
      id: metricCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.topMargin: Style.spacing.controlPaddingY
      spacing: Style.space(4)

      Row {
        spacing: Style.space(5)

        Text {
          visible: metric.glyph !== ""
          textFormat: Text.PlainText
          text: metric.glyph
          color: metric.glyphColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          text: metric.title
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Text {
        textFormat: Text.PlainText
        text: metric.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        visible: metric.meta !== ""
        textFormat: Text.PlainText
        text: metric.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
      Column {
        id: extraSlot
        width: parent.width
        spacing: Style.space(6)
      }
    }
  }

  // Inline field for a profile tile. Commits on Enter, abandons on Escape or
  // on losing focus — the identity guard means a blur fired while this field
  // is torn down can't cancel whichever edit replaced it.
  component TileEditor: TextField {
    id: editor

    property int owningIndex: -1
    property string owningField: ""
    property string seed: ""
    property bool digitsOnly: false
    property int maxChars: 0
    // Ignore the blur that fires while the field is still taking focus, or
    // the editor vanishes the instant it appears.
    property bool armed: false

    signal committed(string value)

    foreground: root.foreground
    accent: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalPadding: Style.spacing.xs
    verticalPadding: 0
    inputMethodHints: digitsOnly ? Qt.ImhDigitsOnly : Qt.ImhNone
    maximumLength: maxChars > 0 ? maxChars : 32767
    placeholderText: digitsOnly ? "" : "Name"

    Component.onCompleted: {
      text = seed
      Qt.callLater(function() {
        editor.selectAll()
        editor.forceActiveFocus()
        editor.armed = true
      })
    }

    onAccepted: editor.committed(editor.text)
    Keys.onEscapePressed: function(event) {
      root.cancelEditFor(editor.owningIndex, editor.owningField)
      event.accepted = true
    }
    onActiveFocusChanged: {
      if (!armed || activeFocus) return
      var index = editor.owningIndex
      var field = editor.owningField
      Qt.callLater(function() { root.cancelEditFor(index, field) })
    }
  }

  // Borderless nudge/rename target that only resolves into a control under
  // the cursor, so the profile grid reads as four tiles, not a dozen buttons.
  component TileButton: Item {
    id: tap

    property string glyph: ""
    property bool canTap: true
    // When set, the button only paints once the row it belongs to is hovered.
    property var tooltipHot: undefined

    signal activated()

    readonly property bool hovered: tapMouse.containsMouse
    readonly property bool hot: canTap && hovered
    readonly property bool revealed: tooltipHot === undefined || tooltipHot === true

    implicitWidth: Style.space(18)
    implicitHeight: Style.space(18)
    opacity: (canTap ? 1 : 0.35) * (revealed ? 1 : 0)

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: tap.hot ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: tap.glyph
      color: tap.hot ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: tapMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: tap.canTap ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (tap.canTap) tap.activated()
    }
  }

  // Outlined chip: neutral at rest, tinted on hover/press, softly filled while
  // it's the action the current state calls for. `tint` makes Stop read as
  // destructive (urgent) and Heat as primary (accent). `tall` stacks the glyph
  // over the label, `pulse` makes it glow for attention, `spinning` turns the
  // glyph, and every press sends a ripple out from the cursor.
  component ActionButton: BorderSurface {
    id: chip

    property string label: ""
    property string glyph: ""
    property color tint: root.foreground
    property bool emphasized: false
    property bool tall: false
    property bool pulse: false
    property bool spinning: false

    signal activated()

    readonly property bool hot: chipMouse.containsMouse
    readonly property bool lit: hot || emphasized

    implicitHeight: tall
      ? Math.max(Style.space(50), chipBody.implicitHeight + Style.spacing.controlPaddingY * 2)
      : Math.max(Style.spacing.controlHeight, chipBody.implicitHeight + Style.spacing.controlPaddingY * 2)
    radius: Style.cornerRadius
    clip: true
    scale: chipMouse.pressed ? 0.96 : 1

    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    color: chipMouse.pressed ? Style.pressedFillFor(tint, tint)
      : hot ? Style.hoverFillFor(tint, tint)
      : emphasized ? Style.selectedFillFor(tint, tint)
      : Style.normalFillFor(tint, tint)

    borderSpec: hot || pulse
      ? Border.flat(Util.alpha(tint, hot ? 0.8 : 0.6), Math.max(1, Style.normalBorderWidth))
      : Border.controlSpec("normal", tint, tint)

    Behavior on color { ColorAnimation { duration: 120 } }

    // Attention glow.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: chip.tint
      opacity: 0
      visible: chip.pulse

      SequentialAnimation on opacity {
        running: chip.pulse && root.opened
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 0; to: 0.16; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.16; to: 0; duration: 800; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      id: ripple
      property real cx: 0
      property real cy: 0
      width: 0
      height: width
      radius: width / 2
      x: cx - width / 2
      y: cy - height / 2
      color: chip.tint
      opacity: 0
    }

    ParallelAnimation {
      id: rippleAnim
      NumberAnimation { target: ripple; property: "width"; from: 0; to: Math.max(chip.width, chip.height) * 2.2; duration: 520; easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "opacity"; from: 0.3; to: 0; duration: 520; easing.type: Easing.InQuad }
    }

    Grid {
      id: chipBody
      anchors.centerIn: parent
      columns: chip.tall ? 1 : 2
      spacing: chip.tall ? Style.space(3) : Style.spacing.md
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Text {
        id: chipGlyph
        textFormat: Text.PlainText
        visible: chip.glyph !== ""
        text: chip.glyph
        color: chip.lit || chip.tall ? chip.tint : root.foreground
        font.family: root.fontFamily
        font.pixelSize: chip.tall ? Style.font.heading : (chip.label === "" ? Style.font.icon : Style.font.iconSmall)

        Behavior on color { ColorAnimation { duration: 120 } }

        RotationAnimation on rotation {
          running: chip.spinning && root.opened
          loops: Animation.Infinite
          from: 0
          to: 360
          duration: 1000
          onRunningChanged: if (!running) chipGlyph.rotation = 0
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: chip.label !== ""
        text: chip.label
        color: chip.lit ? chip.tint : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: chip.emphasized

        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        ripple.cx = mouse.x
        ripple.cy = mouse.y
        rippleAnim.restart()
        chip.activated()
      }
    }
  }
}
