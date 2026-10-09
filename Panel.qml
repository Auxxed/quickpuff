import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "components"
import "pages"
import "components/plain.js" as Plain

Panel {
  id: root
  moduleName: "auxxed.quickpuff"
  ipcTarget: "auxxed.quickpuff"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var statusData: ({})
  // Handed to the pages, which scroll the panel and measure against it.
  readonly property Item scrollView: scroller
  readonly property Item contentColumn: content
  property bool refreshPending: false

  // Palette/typography lifted off the bar so every child stops repeating the
  // `bar ? bar.x : fallback` ternary, matching how first-party panels do it.
  readonly property color foreground: root.barForeground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Puffco's own display face (Rajdhani, OFL, bundled in fonts/): big numbers
  // and headings, as the Puffco app sets them. Body text keeps the theme's font.
  readonly property string displayFamily: displayFont.status === FontLoader.Ready ? displayFont.name : fontFamily
  readonly property bool hasDisplayFont: displayFont.status === FontLoader.Ready
  // Rajdhani runs small for its size; this keeps it level with the theme font.
  readonly property real displayScale: hasDisplayFont ? 1.3 : 1.0

  FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/Rajdhani-SemiBold.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Rajdhani-Medium.ttf") }

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
    statusProc.launch(cli.argv(["--json", "status"]))
  }

  QuickpuffCli { id: cli }

  // Fire a control command, then re-poll shortly after, since the daemon
  // usually reflects a heat/profile change well before the poll interval
  // would catch it. argv[0] is "quickpuff" and the rest reach the CLI as
  // argv, never through a shell, so a profile named `$(reboot)` is a profile
  // name and nothing else. Typed text always follows `--` or an `=`, so it
  // can't be read as an option either.
  function runArgv(argv) {
    if (argv.length === 0 || argv[0] !== "quickpuff") return
    cli.fire(argv.slice(1))
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
      pendingSurprise = undefined
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
  // The Peak's own battery colours (three clicks of its button): green down
  // to 60%, yellow to 30%, red below; the Puffco app's bars use the same.
  function batteryColor(level) {
    var l = Number(level)
    if (!isFinite(l)) return dim
    return l >= 0.6 ? "#16a909" : l >= 0.3 ? "#ffcb02" : "#ef2b2b"
  }

  readonly property bool preserveSupported: statusData.max_charge !== null && statusData.max_charge !== undefined
  readonly property bool preserveOn: pendingPreserve !== undefined
    ? pendingPreserve === true
    : Number(statusData.max_charge) < 100

  function togglePreserve() {
    var next = !preserveOn
    pendingPreserve = next
    runArgv(["quickpuff", "preserve", next ? "on" : "off"])
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
  // Heat-up and battery-per-dab trends (wear.py), for the Care tab.
  readonly property var wear: telemetry.wear || ({})
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
  property var pendingSurprise: undefined
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
    runArgv(["quickpuff", "limit", String(next)])
  }

  function toggleRecap() {
    var next = !recapOn
    pendingRecap = next
    runArgv(["quickpuff", "recap", next ? "on" : "off"])
  }

  // History pages in 30 at a time, up to this many.
  readonly property int maxSessions: 600

  function loadSessions() {
    if (sessionsProc.running) return
    sessionsLoading = true
    sessionsProc.limit = Math.max(1, Math.min(maxSessions, sessionLimit))
    sessionsProc.launch(cli.argv(["--json", "sessions", "--limit", String(sessionsProc.limit)]))
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
    runArgv(text === "" ? ["quickpuff", "note", "--", key] : ["quickpuff", "note", "--", key, text])
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
    if (currentProfile < 0 || !/^#[0-9a-fA-F]{6}$/.test(hex)) return
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
    runArgv(["quickpuff", "light", "apply", "--index", String(currentProfile), "--", String(id)])
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
    runArgv(["quickpuff", "light", "save", "--index", String(currentProfile), "--", name])
  }

  function renameSavedLight(id, raw) {
    var name = cleanLightName(raw)
    renamingLight = ""
    refocusPanel()
    if (name === "") return
    runArgv(["quickpuff", "light", "rename", "--", String(id), name])
  }

  function deleteSavedLight(id) {
    if (confirmDeleteLight !== id) {
      confirmDeleteLight = id
      confirmDeleteTimer.restart()
      return
    }
    confirmDeleteLight = ""
    runArgv(["quickpuff", "light", "delete", "--", String(id)])
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
    runArgv(["quickpuff", "profile", String(currentProfile), "--vapor=" + name])
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
    runArgv(["quickpuff", "name", "--", name])
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
  readonly property bool surpriseOn: pendingSurprise !== undefined
    ? pendingSurprise === true
    : statusData.surprise_light === true
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

  // Runs install.sh in a terminal you can watch. The script is a constant;
  // its path only ever lands in $1.
  function finishSetup() {
    Quickshell.execDetached(["/usr/bin/xdg-terminal-exec", "/usr/bin/bash", "-c",
      "\"$1\"; echo; read -rp 'Press Enter to close'", "quickpuff-setup", root.installScript])
  }

  function readFaults() {
    if (faultProc.running) return
    faultsLoading = true
    faultError = false
    faultProc.launch(cli.argv(["--json", "faults"]))
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
    // A Bluetooth address or nothing; anything else isn't from the scan.
    if (mac && !/^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/.test(String(mac))) return
    connecting = true
    connectError = ""
    connectFailed = false
    connectGiveUp.restart()
    connectProc.launch(cli.argv(mac ? ["connect", "--mac=" + String(mac)] : ["connect"]))
  }

  function findPeaks() {
    if (scanProc.running) return
    scanning = true
    connectFailed = false
    scanProc.launch(cli.argv(["--json", "scan", "--timeout", "8"]))
  }

  // Frees the Peak's single Bluetooth link for the phone app or another
  // computer; nothing reconnects until Connect is pressed again.
  function disconnectDevice() {
    connecting = false
    connectGiveUp.stop()
    runArgv(["quickpuff", "disconnect"])
  }

  function toggleStealth() {
    var next = !stealthOn
    pendingStealth = next
    runArgv(["quickpuff", "stealth", next ? "on" : "off"])
  }

  function toggleLantern() {
    var next = !lanternOn
    pendingLantern = next
    runArgv(["quickpuff", "lantern", next ? "on" : "off"])
  }

  function toggleQtip() {
    var next = !qtipOn
    pendingQtip = next
    runArgv(["quickpuff", "qtip", next ? "on" : "off"])
  }

  function toggleSurprise() {
    var next = !surpriseOn
    pendingSurprise = next
    runArgv(["quickpuff", "surprise", next ? "on" : "off"])
  }

  function toggleSaver() {
    var next = !saverOn
    pendingSaver = next
    if (next) pendingLantern = false
    runArgv(["quickpuff", "saver", next ? "on" : "off"])
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
    runArgv(["quickpuff", "clean", "done"])
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
    { "value": "rocket", "label": "Rocket", "glyph": "\uf135" },
    { "value": "lava", "label": "Lava Lamp", "glyph": "\uf06d" },
    { "value": "aurora", "label": "Aurora", "glyph": "\uf186" },
    { "value": "fireworks", "label": "Fireworks", "glyph": "\uf005" },
    { "value": "smoke", "label": "Smoke Rings", "glyph": "\uf0c2" },
    { "value": "neon", "label": "Neon", "glyph": "\uf0eb" }
  ]
  property string configReadyAnimation: "rocket"
  property string pendingReadyAnimation: ""
  readonly property string readyAnimation: pendingReadyAnimation !== "" ? pendingReadyAnimation : configReadyAnimation

  function setReadyAnimation(value) {
    pendingReadyAnimation = value
    runArgv(["quickpuff", "ready-anim", value])
  }
  onConfigReadyAnimationChanged: pendingReadyAnimation = ""

  // ---------------------------------------------------- showtime & sound
  // Showtime (SessionOverlay.qml) plays the heat cycle over the desktop;
  // both settings live in quickpuff's config, like the ready animation.
  readonly property var showtimeOptions: [
    { "value": "off", "label": "Off", "glyph": "\uf05e" },
    { "value": "corner", "label": "Corner", "glyph": "\uf2d2" },
    { "value": "stage", "label": "Stage", "glyph": "\uf26c" }
  ]
  property string configShowtime: "corner"
  property string pendingShowtime: ""
  readonly property string showtimeMode: pendingShowtime !== "" ? pendingShowtime : configShowtime
  onConfigShowtimeChanged: pendingShowtime = ""
  function setShowtime(value) {
    pendingShowtime = value
    runArgv(["quickpuff", "showtime", value])
  }

  property bool configSounds: true
  property var pendingSounds: undefined
  readonly property bool soundsOn: pendingSounds !== undefined ? pendingSounds === true : configSounds
  onConfigSoundsChanged: pendingSounds = undefined
  function toggleSounds() {
    var next = !soundsOn
    pendingSounds = next
    runArgv(["quickpuff", "sounds", next ? "on" : "off"])
  }

  // A simulated heat cycle: the bar, this panel and the overlays play it
  // exactly like a real one, and nothing is sent to the Peak.
  function runDemo() {
    close()
    runArgv(["quickpuff", "demo"])
  }

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
    runArgv(["quickpuff", "profile", String(index), "--name=" + name])
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

  // `quickpuff --json status` waits on the daemon RPC; past 8s the run is
  // stopped so a stalled BLE call can't wedge the panel, and it's retried.
  // A status is about 8 KiB; 256 KiB is far past anything the daemon sends.
  BoundedProcess {
    id: statusProc
    maxBytes: 262144
    timeoutMs: 8000
    onDone: function(ok, code, out, err) {
      if (code === -1) {
        root.refreshPending = true
        return
      }
      if (code === 127 || /daemon is not running/i.test(err)) {
        root.needsSetup = true
        root.statusData = ({})
        return
      }
      if (ok) root.applyStatus(out)
    }
    onRunningChanged: if (!running && root.refreshPending) root.refresh()
  }

  // Every list the pages draw, and the most the daemon ever sends of it.
  function statusFits(d) {
    if (!d || typeof d !== "object" || Array.isArray(d)) return false
    var tel = d.telemetry && typeof d.telemetry === "object" ? d.telemetry : ({})
    var trace = d.heat_trace && typeof d.heat_trace === "object" ? d.heat_trace : ({})
    var lists = [[d.profiles, 8], [d.saved_lights, 40], [trace.points, 360], [tel.daily, 400],
                 [tel.weekdays, 7], [tel.hours, 24], [tel.colors, 64], [tel.profiles, 16]]
    for (var i = 0; i < lists.length; i++) {
      var v = lists[i][0]
      if (v !== undefined && v !== null && (!Array.isArray(v) || v.length > lists[i][1])) return false
    }
    return true
  }

  // A status that doesn't fit is dropped whole (not trimmed into shape), and
  // the last good one stays up.
  function applyStatus(out) {
    if (!out) return
    var data
    try {
      data = JSON.parse(out)
    } catch (e) {
      return
    }
    if (!statusFits(data)) return
    root.statusData = data
    root.timerSampledAt = Date.now()
    root.nowMs = root.timerSampledAt
    root.needsSetup = false
    root.applyUi(data.ui)
    if (data.connected === true) {
      root.connecting = false
      connectGiveUp.stop()
      root.connectError = ""
      root.connectFailed = false
      root.nearbyPeaks = null
    }
  }

  // The panel's own settings, as the CLI reads them from config.json (the
  // shell doesn't read that file itself). Each is checked against what it
  // can be; anything else leaves the current value.
  function applyUi(ui) {
    if (!ui || typeof ui !== "object") return
    if (ui.units === "F" || ui.units === "C") root.units = ui.units
    for (var i = 0; i < readyAnimations.length; i++)
      if (readyAnimations[i].value === ui.ready_animation) root.configReadyAnimation = ui.ready_animation
    if (["off", "corner", "stage"].indexOf(ui.showtime) >= 0) root.configShowtime = ui.showtime
    if (typeof ui.sounds === "boolean") root.configSounds = ui.sounds
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

  // Connecting can take a scan and a pairing; it gets as long as the
  // Connecting… state does. Only stderr's last line is used, as the reason.
  BoundedProcess {
    id: connectProc
    maxBytes: 16384
    timeoutMs: 100000
    onDone: function(ok, code, out, err) {
      root.connecting = false
      connectGiveUp.stop()
      kickTimer.restart()
      if (!ok) root.connectFailed = true
      var lines = String(err || "").trim().split("\n")
      var last = Plain.plain(lines[lines.length - 1], 200).trim()
      if (last === "") return
      // Two or more Peaks in range: list them instead of guessing.
      if (/Multiple Peak/i.test(last)) {
        root.connectError = "More than one Peak is nearby. Pick yours below."
        Qt.callLater(root.findPeaks)
        return
      }
      root.connectError = last
    }
  }

  // About 230 bytes a dab; 1 MiB covers maxSessions many times over. More
  // dabs than were asked for means the answer isn't the daemon's.
  BoundedProcess {
    id: sessionsProc
    property int limit: 30
    maxBytes: 1048576
    timeoutMs: 15000
    onDone: function(ok, code, out) {
      root.sessionsLoading = false
      var result = null
      if (ok) {
        try { result = JSON.parse(out) } catch (e) {}
      }
      var list = result && typeof result === "object" ? Plain.list(result.sessions, sessionsProc.limit) : null
      if (list === null) {
        if (root.sessionList === null) root.sessionList = []
        return
      }
      root.sessionList = list
      root.sessionTotal = Number(result.total) || 0
      root.pendingNotes = ({})
    }
  }

  // Re-read after a note is saved, once the command has written it.
  Timer {
    id: noteReload
    interval: 1500
    onTriggered: root.loadSessions()
  }

  // An 8 s scan; a room with more than 32 Peaks in it is not a real room.
  BoundedProcess {
    id: scanProc
    maxBytes: 65536
    timeoutMs: 20000
    onDone: function(ok, code, out) {
      root.scanning = false
      var result = null
      if (ok) {
        try { result = JSON.parse(out) } catch (e) {}
      }
      var list = result && typeof result === "object" ? Plain.list(result.devices, 32) : null
      root.nearbyPeaks = list === null ? [] : list
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
      root.pendingSurprise = undefined
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

  // The Peak's fault log: a few hundred entries at most.
  BoundedProcess {
    id: faultProc
    maxBytes: 262144
    timeoutMs: 20000
    onDone: function(ok, code, out) {
      root.faultsLoading = false
      if (!ok) {
        root.faultError = true
        return
      }
      if (!out) return
      var result = null
      try { result = JSON.parse(out) } catch (e) {}
      var list = result && typeof result === "object" ? Plain.list(result.faults, 512) : null
      if (list === null) {
        root.faultError = true
        return
      }
      root.faultLog = list
      root.faultShown = 8
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.opened && (root.preheating || root.atTemp)
    onTriggered: root.nowMs = Date.now()
  }

  // Watches config.json only, never reads it: a change re-polls the status,
  // whose `ui` block carries the settings (see applyUi).
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickpuff/config.json"
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
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

          // ---------- Hero: the Peak on its stage · name, state, temperature ------
          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(heroArt.height + Style.space(14), heroLabels.implicitHeight + Style.space(14))

            // How brightly the Peak's light ring burns: off while it's away,
            // a slow breath while preheating, full at temperature.
            property real glow: !root.connected ? 0.08
              : root.heating ? 1
              : root.lanternOn ? 0.8
              : 0.45
            Behavior on glow { NumberAnimation { duration: 500 } }
            property real breath: 1
            SequentialAnimation on breath {
              running: root.preheating && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: 0.35; duration: 850; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: 850; easing.type: Easing.InOutSine }
            }

            // The stage: a soft wash of the profile's light from below.
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Util.alpha(root.connected ? root.profileTint : root.dim, 0.05 + 0.1 * hero.glow * hero.breath) }
              }
            }

            PeakArt {
              id: heroArt
              panel: root
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(2)
              width: Style.space(62)
              height: width * 2
              colorway: root.statusData.product ? String(root.statusData.product.marketing_name || "") : ""
              tint: root.connected ? root.profileTint : root.dim
              glow: hero.glow * hero.breath
              vapor: root.atTemp
              asleep: !root.connected
            }

            Burst {
              panel: root
              id: heroBurst
              anchors.centerIn: heroArt
              width: heroArt.width * 1.6
              height: width
            }

            Column {
              id: heroLabels
              anchors.left: heroArt.right
              anchors.leftMargin: Style.space(18)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Item {
                width: parent.width
                height: nameText.implicitHeight

                Text {
                  id: nameText
                  anchors.left: parent.left
                  anchors.right: heroBattery.left
                  anchors.rightMargin: Style.space(8)
                  textFormat: Text.PlainText
                  text: root.deviceName
                  color: root.foreground
                  font.family: root.displayFamily
                  font.pixelSize: Math.round(Style.font.subtitle * root.displayScale)
                  font.weight: Font.DemiBold
                  font.capitalization: root.hasDisplayFont ? Font.AllUppercase : Font.MixedCase
                  font.letterSpacing: root.hasDisplayFont ? 1.2 : 0
                  elide: Text.ElideRight
                }

                BatteryPill {
                  id: heroBattery
                  panel: root
                  anchors.right: parent.right
                  anchors.verticalCenter: nameText.verticalCenter
                  visible: root.connected && root.batteryLabel !== ""
                }
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

              // The chamber, big, as the Puffco app's session screen shows it.
              // Counts toward each new reading instead of snapping to it; once
              // it lands it shows the daemon's own label, so the two agree.
              Row {
                id: heroTempRow
                spacing: Style.space(2)

                property real rawF: Number(root.statusData.heater_temp_f)
                property real shownF: isFinite(rawF) ? rawF : 0
                Behavior on shownF { NumberAnimation { id: tempCount; duration: 700; easing.type: Easing.OutCubic } }
                readonly property string label: !root.connected ? ""
                  : !isFinite(rawF) || !tempCount.running ? root.tempLabel : root.formatTemp(shownF, undefined)
                readonly property color tone: !root.connected ? root.dim
                  : shownF > 120 ? Qt.tint(root.foreground,
                      Util.alpha(root.heatRamp(shownF), Math.min(1, (shownF - 120) / 200)))
                  : root.heating ? Qt.lighter(root.urgent, 1.15)
                  : root.foreground

                Text {
                  id: heroTemp
                  textFormat: Text.PlainText
                  text: heroTempRow.label === "" ? "—" : heroTempRow.label.replace(/°[CF]$/, "")
                  color: heroTempRow.tone
                  font.family: root.displayFamily
                  font.pixelSize: Math.round(Style.font.display * root.displayScale * 1.55)
                  font.weight: Font.DemiBold
                  Behavior on color { ColorAnimation { duration: 300 } }
                }
                Text {
                  y: heroTemp.height * 0.16
                  visible: heroTempRow.label !== ""
                  textFormat: Text.PlainText
                  text: root.celsius ? "°C" : "°F"
                  color: Util.alpha(heroTempRow.tone, 0.7)
                  font.family: root.displayFamily
                  font.pixelSize: Math.round(Style.font.title * root.displayScale)
                  font.weight: Font.DemiBold
                }
              }

              // Climb toward the target while heating.
              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                visible: root.connected && (root.preheating || root.atTemp)
                color: Util.alpha(root.foreground, 0.1)

                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: parent.width * root.heatProgress
                  color: root.profileTint
                  Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: {
                  if (!root.connected || !root.activeProfile) return root.moodLine
                  var name = String(root.cleanName(root.activeProfile.name) || "").toUpperCase()
                  var target = root.formatTemp(root.profileTempF(root.currentProfile, root.activeProfile.temp_f), undefined)
                  return (root.heating ? "→ " : "") + name + (target !== "" ? "  ·  " + target : "")
                }
                color: root.connected ? Qt.tint(root.dim, Util.alpha(root.profileTint, 0.35)) : root.dim
                font.family: root.connected ? root.displayFamily : root.fontFamily
                font.pixelSize: root.connected ? Math.round(Style.font.caption * root.displayScale) : Style.font.caption
                font.weight: Font.DemiBold
                font.letterSpacing: root.connected && root.hasDisplayFont ? 1 : 0
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: root.connected
                textFormat: Text.PlainText
                text: root.moodLine
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.italic: true
                elide: Text.ElideRight
              }
            }
          }

          Segmented {
            panel: root
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
              panel: root
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
              panel: root
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
                panel: root
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
          ControlPage { panel: root }

          // ================================================== Lights
          LightsPage { panel: root }

          // ================================================== Care
          CarePage { panel: root }

          // ================================================== Usage
          UsagePage { panel: root }

          // ================================================== Device
          DevicePage { panel: root }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmPowerOff
        message: "Power off " + Plain.plain(root.deviceName, 32) + "?"
        confirmText: "Power off"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirmPowerOff = false
        onConfirmed: {
          root.confirmPowerOff = false
          root.runArgv(["quickpuff", "off"])
        }
      }
    }
  }

}
