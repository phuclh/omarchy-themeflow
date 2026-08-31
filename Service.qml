import QtQuick
import Quickshell
import Quickshell.Io
import "Schedule.js" as Schedule

Item {
  id: root

  // Injected by the Omarchy shell service loader.
  property var shell: null
  property var manifest: null

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || homeDir + "/.config"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || homeDir + "/.local/state"
  readonly property string configDir: configHome + "/themeflow"
  readonly property string settingsPath: configDir + "/settings.json"
  readonly property string currentThemePath: stateHome + "/omarchy/current/theme.name"
  readonly property string weatherLocationPath: stateHome + "/omarchy/settings/weather.json"
  readonly property string codexRefreshScript: resolvedLocalPath(
    "scripts/refresh-codex-tui.sh")

  property bool configReady: false
  property bool settingsLoaded: false
  property bool pendingPersist: false

  property bool enabled: false
  property string scheduleMode: "fixed"
  property string dayTheme: "Catppuccin Latte"
  property string nightTheme: "Tokyo Night"
  property string dayTime: "07:00"
  property string nightTime: "19:00"
  property real latitude: 0
  property real longitude: 0
  property bool solarLocationConfigured: false
  property string solarLocationMode: "automatic"
  property string solarLocationName: ""
  property string solarLocationSource: ""
  property double solarLocationUpdatedAtMs: 0
  property bool automaticLocationLoading: false
  property bool automaticLocationResolved: false
  property double automaticLocationLastAttemptMs: 0
  property bool wallpaperRotationEnabled: true
  property int wallpaperIntervalMinutes: 60

  property var themes: []
  readonly property var themeOptions: themes.map(function(theme) {
    return { value: theme, label: theme }
  })
  property string currentTheme: ""
  property string activePeriod: "night"
  property double nextTransitionMs: 0
  property string scheduleSource: "fixed"
  property double lastWallpaperAtMs: Date.now()
  property string lastAction: "Themeflow is ready"
  property string lastError: ""
  property string pendingTheme: ""
  property string applyingTheme: ""

  readonly property string activeTheme: activePeriod === "day" ? dayTheme : nightTheme
  readonly property string periodLabel: activePeriod === "day" ? "Day" : "Night"
  readonly property string modeLabel: scheduleMode === "solar" ? "Sunrise & sunset" : "Fixed times"
  readonly property string statusLabel: !settingsLoaded
    ? "Loading settings…"
    : (!enabled
      ? "Automation is off"
      : periodLabel + " · " + activeTheme)
  readonly property string nextTransitionLabel: nextTransitionMs > 0
    ? Qt.formatDateTime(new Date(nextTransitionMs), "ddd HH:mm")
    : "—"
  readonly property string solarLocationLabel: automaticLocationLoading
    ? "Detecting location…"
    : (solarLocationConfigured
      ? (solarLocationName !== ""
        ? solarLocationName
        : Number(latitude).toFixed(3) + ", " + Number(longitude).toFixed(3))
      : "Location unavailable")
  readonly property bool busy: applyThemeProcess.running || wallpaperProcess.running

  function resolvedLocalPath(relativePath) {
    var value = String(Qt.resolvedUrl(relativePath))
    if (value.indexOf("file://") === 0) return decodeURIComponent(value.substring(7))
    return value
  }

  function normalizeTheme(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/[_-]+/g, " ")
      .replace(/\s+/g, " ")
  }

  function titleFromSlug(value) {
    return String(value || "")
      .trim()
      .replace(/[_-]+/g, " ")
      .replace(/(^|\s)([a-z])/g, function(match, space, letter) {
        return space + letter.toUpperCase()
      })
  }

  function validClock(value) {
    return /^([01]?\d|2[0-3]):([0-5]\d)$/.test(String(value || "").trim())
  }

  function boundedNumber(value, minimum, maximum, fallback) {
    var number = Number(value)
    if (!isFinite(number) || number < minimum || number > maximum) return fallback
    return number
  }

  function matchingTheme(value) {
    var wanted = normalizeTheme(value)
    for (var i = 0; i < themes.length; i++) {
      if (normalizeTheme(themes[i]) === wanted) return String(themes[i])
    }
    return ""
  }

  function firstAvailable(candidates) {
    for (var i = 0; i < candidates.length; i++) {
      var match = matchingTheme(candidates[i])
      if (match !== "") return match
    }
    return themes.length > 0 ? String(themes[0]) : ""
  }

  function resolveThemeChoices() {
    if (themes.length === 0) return
    var resolvedDay = matchingTheme(dayTheme)
    var resolvedNight = matchingTheme(nightTheme)
    if (resolvedDay === "")
      resolvedDay = firstAvailable(["Catppuccin Latte", "Flexoki Light", "White", currentTheme])
    if (resolvedNight === "")
      resolvedNight = firstAvailable(["Tokyo Night", "Catppuccin", "Matte Black", currentTheme])

    var changed = resolvedDay !== dayTheme || resolvedNight !== nightTheme
    dayTheme = resolvedDay
    nightTheme = resolvedNight
    if (changed) persistSettings()
  }

  function parseThemeList(raw) {
    var found = []
    var seen = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var theme = lines[i].trim()
      var key = normalizeTheme(theme)
      if (theme === "" || seen[key]) continue
      seen[key] = true
      found.push(theme)
    }
    found.sort(function(a, b) { return a.localeCompare(b) })
    themes = found
    resolveThemeChoices()
  }

  function applySettings(raw) {
    var parsed = ({})
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (error) {
      lastError = "Settings were invalid; safe defaults are in use."
    }

    enabled = parsed.enabled === undefined ? false : !!parsed.enabled
    scheduleMode = String(parsed.scheduleMode) === "solar" ? "solar" : "fixed"
    dayTheme = String(parsed.dayTheme || "Catppuccin Latte")
    nightTheme = String(parsed.nightTheme || "Tokyo Night")
    dayTime = validClock(parsed.dayTime) ? String(parsed.dayTime) : "07:00"
    nightTime = validClock(parsed.nightTime) ? String(parsed.nightTime) : "19:00"
    latitude = boundedNumber(parsed.latitude, -90, 90, 0)
    longitude = boundedNumber(parsed.longitude, -180, 180, 0)
    solarLocationConfigured = parsed.solarLocationConfigured === true
    if (String(parsed.solarLocationMode) === "manual"
        || String(parsed.solarLocationMode) === "automatic") {
      solarLocationMode = String(parsed.solarLocationMode)
    } else {
      // Version 1 only had manually entered coordinates.
      solarLocationMode = solarLocationConfigured ? "manual" : "automatic"
    }
    solarLocationName = String(parsed.solarLocationName || "")
    solarLocationSource = String(parsed.solarLocationSource || "")
    solarLocationUpdatedAtMs = Math.max(0, Number(parsed.solarLocationUpdatedAtMs) || 0)
    wallpaperRotationEnabled = parsed.wallpaperRotationEnabled === undefined
      ? true : !!parsed.wallpaperRotationEnabled
    wallpaperIntervalMinutes = Math.round(
      boundedNumber(parsed.wallpaperIntervalMinutes, 5, 1440, 60))
    settingsLoaded = true
    resolveThemeChoices()
    evaluateSchedule()
  }

  function serializedSettings() {
    return JSON.stringify({
      version: 2,
      enabled: enabled,
      scheduleMode: scheduleMode,
      dayTheme: dayTheme,
      nightTheme: nightTheme,
      dayTime: dayTime,
      nightTime: nightTime,
      latitude: latitude,
      longitude: longitude,
      solarLocationConfigured: solarLocationConfigured,
      solarLocationMode: solarLocationMode,
      solarLocationName: solarLocationName,
      solarLocationSource: solarLocationSource,
      solarLocationUpdatedAtMs: solarLocationUpdatedAtMs,
      wallpaperRotationEnabled: wallpaperRotationEnabled,
      wallpaperIntervalMinutes: wallpaperIntervalMinutes
    }, null, 2) + "\n"
  }

  function persistSettings() {
    if (!settingsLoaded) return
    if (!configReady) {
      pendingPersist = true
      return
    }
    pendingPersist = false
    settingsFile.setText(serializedSettings())
  }

  function evaluateSchedule(forceApply) {
    if (!settingsLoaded) return
    if (scheduleMode === "solar" && solarLocationMode === "automatic")
      requestAutomaticLocation(false)
    var result = Schedule.evaluate(new Date(), {
      scheduleMode: scheduleMode,
      dayTime: dayTime,
      nightTime: nightTime,
      latitude: solarLocationConfigured ? latitude : 999,
      longitude: solarLocationConfigured ? longitude : 999
    })
    activePeriod = result.period
    nextTransitionMs = result.nextAt.getTime()
    scheduleSource = result.source

    // Do not briefly apply the fixed fallback while the first automatic
    // location lookup is still in flight.
    if (scheduleMode === "solar" && solarLocationMode === "automatic"
        && automaticLocationLoading && !solarLocationConfigured) return
    if (!enabled && forceApply !== true) return
    var target = activeTheme
    if (target !== "" && (forceApply === true
        || normalizeTheme(target) !== normalizeTheme(currentTheme))) {
      requestTheme(target)
      return
    }
    maybeRotateWallpaper()
  }

  function requestTheme(theme) {
    var target = String(theme || "").trim()
    if (target === "") return
    if (applyThemeProcess.running) {
      pendingTheme = target
      return
    }

    lastError = ""
    applyingTheme = target
    applyThemeProcess.command = ["omarchy", "theme", "set", target]
    applyThemeProcess.running = true
    lastAction = "Applying " + target + "…"
  }

  function maybeRotateWallpaper(force) {
    if (!settingsLoaded) return
    if (force !== true && (!enabled || !wallpaperRotationEnabled)) return
    if (applyThemeProcess.running || wallpaperProcess.running) return
    var intervalMs = Math.max(5, wallpaperIntervalMinutes) * 60000
    if (force !== true && Date.now() - lastWallpaperAtMs < intervalMs) return

    lastError = ""
    wallpaperProcess.running = true
    lastAction = "Changing wallpaper…"
  }

  function setEnabled(value) {
    enabled = !!value
    lastAction = enabled ? "Automation enabled" : "Automation paused"
    persistSettings()
    evaluateSchedule(enabled)
  }

  function setScheduleMode(value) {
    scheduleMode = String(value) === "solar" ? "solar" : "fixed"
    persistSettings()
    if (scheduleMode === "solar" && solarLocationMode === "automatic")
      requestAutomaticLocation(false)
    evaluateSchedule()
  }

  function setDayTheme(value) {
    var match = matchingTheme(value)
    if (match === "") return false
    dayTheme = match
    persistSettings()
    evaluateSchedule()
    return true
  }

  function setNightTheme(value) {
    var match = matchingTheme(value)
    if (match === "") return false
    nightTheme = match
    persistSettings()
    evaluateSchedule()
    return true
  }

  function setDayTime(value) {
    var next = String(value || "").trim()
    if (!validClock(next)) {
      lastError = "Day time must use 24-hour HH:MM format."
      return false
    }
    dayTime = next.length === 4 ? "0" + next : next
    lastError = ""
    persistSettings()
    evaluateSchedule()
    return true
  }

  function setNightTime(value) {
    var next = String(value || "").trim()
    if (!validClock(next)) {
      lastError = "Night time must use 24-hour HH:MM format."
      return false
    }
    nightTime = next.length === 4 ? "0" + next : next
    lastError = ""
    persistSettings()
    evaluateSchedule()
    return true
  }

  function setLocation(latitudeValue, longitudeValue) {
    var nextLatitude = Number(latitudeValue)
    var nextLongitude = Number(longitudeValue)
    if (!isFinite(nextLatitude) || nextLatitude < -90 || nextLatitude > 90
        || !isFinite(nextLongitude) || nextLongitude < -180 || nextLongitude > 180) {
      lastError = "Latitude must be −90…90 and longitude −180…180."
      return false
    }
    latitude = nextLatitude
    longitude = nextLongitude
    solarLocationConfigured = true
    solarLocationMode = "manual"
    solarLocationName = ""
    solarLocationSource = "manual"
    solarLocationUpdatedAtMs = Date.now()
    lastError = ""
    persistSettings()
    evaluateSchedule()
    return true
  }

  function setAutomaticLocation(value) {
    solarLocationMode = value ? "automatic" : "manual"
    if (!value) {
      automaticLocationLoading = false
      if (automaticLocationProcess.running) automaticLocationProcess.running = false
    }
    persistSettings()
    if (value) requestAutomaticLocation(true)
    else evaluateSchedule()
  }

  function validLocation(latitudeValue, longitudeValue) {
    var lat = Number(latitudeValue)
    var lon = Number(longitudeValue)
    return isFinite(lat) && lat >= -90 && lat <= 90
      && isFinite(lon) && lon >= -180 && lon <= 180
  }

  function requestAutomaticLocation(force) {
    if (solarLocationMode !== "automatic" || automaticLocationLoading) return
    var freshForMs = 24 * 60 * 60 * 1000
    var retryAfterMs = 15 * 60 * 1000
    if (force !== true && solarLocationConfigured
        && Date.now() - solarLocationUpdatedAtMs < freshForMs) return
    if (force !== true && Date.now() - automaticLocationLastAttemptMs < retryAfterMs) return

    automaticLocationLastAttemptMs = Date.now()
    automaticLocationLoading = true
    automaticLocationResolved = false
    lastError = ""
    lastAction = "Detecting location…"
    weatherLocationFile.reload()
  }

  function applyWeatherLocation(raw) {
    if (!automaticLocationLoading) return
    var parsed = ({})
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (error) {
      parsed = ({})
    }
    if (validLocation(parsed.latitude, parsed.longitude)) {
      finishAutomaticLocation(
        String(parsed.name || "Omarchy Weather location"),
        parsed.latitude,
        parsed.longitude,
        "omarchy-weather")
      return
    }
    startAutomaticLocationLookup()
  }

  function startAutomaticLocationLookup() {
    if (automaticLocationProcess.running) return
    automaticLocationResolved = false
    automaticLocationProcess.running = true
  }

  function applyAutomaticLocationResponse(raw) {
    var parsed = ({})
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (error) {
      return
    }
    var area = parsed.nearest_area && parsed.nearest_area.length > 0
      ? parsed.nearest_area[0] : null
    if (!area || !validLocation(area.latitude, area.longitude)) return

    var name = "Approximate location"
    if (area.areaName && area.areaName.length > 0 && area.areaName[0].value)
      name = String(area.areaName[0].value)
    if (area.region && area.region.length > 0 && area.region[0].value)
      name += ", " + String(area.region[0].value)
    automaticLocationResolved = true
    finishAutomaticLocation(name, area.latitude, area.longitude, "network")
  }

  function finishAutomaticLocation(name, latitudeValue, longitudeValue, source) {
    if (!validLocation(latitudeValue, longitudeValue)) return
    latitude = Number(latitudeValue)
    longitude = Number(longitudeValue)
    solarLocationConfigured = true
    solarLocationMode = "automatic"
    solarLocationName = String(name || "Approximate location")
    solarLocationSource = String(source || "automatic")
    solarLocationUpdatedAtMs = Date.now()
    automaticLocationLoading = false
    lastError = ""
    lastAction = "Location detected: " + solarLocationName
    persistSettings()
    evaluateSchedule()
  }

  function setWallpaperRotationEnabled(value) {
    wallpaperRotationEnabled = !!value
    lastWallpaperAtMs = Date.now()
    persistSettings()
  }

  function setWallpaperInterval(value) {
    wallpaperIntervalMinutes = Math.round(boundedNumber(value, 5, 1440, 60))
    lastWallpaperAtMs = Date.now()
    persistSettings()
  }

  Process {
    id: configDirectoryProcess
    command: ["mkdir", "-p", root.configDir]
    onExited: function(exitCode) {
      root.configReady = exitCode === 0
      if (!root.configReady) {
        root.lastError = "Could not create the Themeflow settings folder."
        return
      }
      settingsFile.reload()
      if (root.pendingPersist) root.persistSettings()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: {
      if (!root.settingsLoaded) root.applySettings("{}")
      if (root.configReady) root.persistSettings()
    }
  }

  FileView {
    id: weatherLocationFile
    path: root.weatherLocationPath
    printErrors: false
    onLoaded: root.applyWeatherLocation(text())
    onLoadFailed: if (root.automaticLocationLoading)
      root.startAutomaticLocationLookup()
  }

  FileView {
    id: currentThemeFile
    path: root.currentThemePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.currentTheme = root.titleFromSlug(text())
      root.evaluateSchedule()
    }
  }

  Process {
    id: themeListProcess
    command: ["omarchy", "theme", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseThemeList(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
  }

  Process {
    id: applyThemeProcess
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
    onExited: function(exitCode) {
      var finishedTheme = root.applyingTheme
      root.applyingTheme = ""
      if (exitCode === 0) {
        root.currentTheme = finishedTheme
        root.lastWallpaperAtMs = Date.now()
        root.lastAction = finishedTheme + " applied"
        codexRefreshTimer.restart()
        currentThemeFile.reload()
      } else if (root.lastError === "") {
        root.lastError = "Could not apply " + finishedTheme + "."
      }

      if (root.pendingTheme !== "") {
        var queued = root.pendingTheme
        root.pendingTheme = ""
        root.requestTheme(queued)
      }
    }
  }

  Process {
    id: wallpaperProcess
    command: ["omarchy", "theme", "bg", "next"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
    onExited: function(exitCode) {
      root.lastWallpaperAtMs = Date.now()
      if (exitCode === 0) root.lastAction = "Wallpaper changed"
      else if (root.lastError === "") root.lastError = "Could not change the wallpaper."
    }
  }

  // Codex caches terminal foreground/background colors inside a running TUI.
  // A standard resize notification makes it redraw after Ghostty reloads its
  // palette without restarting the session or issuing an API request.
  Timer {
    id: codexRefreshTimer
    interval: 250
    repeat: false
    onTriggered: if (!codexRefreshProcess.running)
      codexRefreshProcess.running = true
  }

  Process {
    id: codexRefreshProcess
    command: [root.codexRefreshScript]
  }

  Process {
    id: automaticLocationProcess
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAutomaticLocationResponse(text)
    }
    onExited: function(exitCode) {
      if (root.solarLocationMode !== "automatic") return
      if (root.automaticLocationResolved) return
      root.automaticLocationLoading = false
      root.lastError = exitCode === 0
        ? "Automatic location could not be determined."
        : "Automatic location is unavailable; check the network connection."
      root.lastAction = root.solarLocationConfigured
        ? "Using cached location" : "Using fixed-time fallback"
      root.evaluateSchedule()
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.settingsLoaded
    onTriggered: root.evaluateSchedule()
  }

  Component.onCompleted: {
    configDirectoryProcess.running = true
    themeListProcess.running = true
    currentThemeFile.reload()
  }

  IpcHandler {
    target: "themeflow"

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        period: root.activePeriod,
        activeTheme: root.activeTheme,
        currentTheme: root.currentTheme,
        mode: root.scheduleMode,
        locationMode: root.solarLocationMode,
        location: root.solarLocationLabel,
        latitude: root.latitude,
        longitude: root.longitude,
        nextTransition: root.nextTransitionMs,
        wallpaperRotationEnabled: root.wallpaperRotationEnabled,
        wallpaperIntervalMinutes: root.wallpaperIntervalMinutes,
        action: root.lastAction,
        error: root.lastError
      })
    }

    function enable(): string {
      root.setEnabled(true)
      return "enabled"
    }

    function disable(): string {
      root.setEnabled(false)
      return "disabled"
    }

    function toggle(): string {
      root.setEnabled(!root.enabled)
      return root.enabled ? "enabled" : "disabled"
    }

    function apply(): string {
      root.evaluateSchedule(true)
      return root.activeTheme
    }

    function nextWallpaper(): string {
      root.maybeRotateWallpaper(true)
      return "changing"
    }
  }
}
