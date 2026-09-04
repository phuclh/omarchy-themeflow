import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "Schedule.js" as Schedule
import "Safety.js" as Safety

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
  readonly property string themesDir: configHome + "/omarchy/themes"
  readonly property string weatherLocationPath: stateHome + "/omarchy/settings/weather.json"
  readonly property string themeListScript: resolvedLocalPath(
    "scripts/list-themes-bounded.sh")
  readonly property int maxSettingsBytes: Safety.maxSettingsBytes()
  readonly property int maxWeatherFileBytes: Safety.maxWeatherFileBytes()
  readonly property int maxCurrentThemeBytes: Safety.maxCurrentThemeBytes()
  readonly property int maxThemeListBytes: Safety.maxThemeListBytes()
  readonly property int maxWeatherResponseBytes: Safety.maxWeatherResponseBytes()

  property bool configReady: false
  property bool settingsLoaded: false
  property bool pendingPersist: false
  property bool themesLoaded: false

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
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
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
    var safe = Safety.singleLine(value, Safety.maxThemeNameLength(), "")
    if (safe === "") return ""
    return safe
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

  function resolveThemeChoices(allowPersist) {
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
    if (changed && allowPersist !== false) persistSettings()
  }

  function parseThemeList(raw) {
    var found = Safety.themeList(raw)
    if (found.length === 0) {
      themesLoaded = false
      lastError = "No valid themes were returned by Omarchy."
      return
    }
    themes = found
    themesLoaded = true
    resolveThemeChoices()
    evaluateSchedule()
  }

  function applySettings(raw, allowPersist) {
    var parsed = Safety.settingsObject(raw)
    if (!parsed) {
      parsed = ({})
      allowPersist = false
      lastError = "Settings were invalid; safe defaults are in use."
    }

    enabled = parsed.enabled === undefined ? false : !!parsed.enabled
    scheduleMode = String(parsed.scheduleMode) === "solar" ? "solar" : "fixed"
    dayTheme = Safety.singleLine(
      parsed.dayTheme, Safety.maxThemeNameLength(), "Catppuccin Latte")
    nightTheme = Safety.singleLine(
      parsed.nightTheme, Safety.maxThemeNameLength(), "Tokyo Night")
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
    solarLocationName = Safety.optionalSingleLine(
      parsed.solarLocationName, Safety.maxLocationNameLength())
    solarLocationSource = Safety.locationSource(parsed.solarLocationSource)
    solarLocationUpdatedAtMs = boundedNumber(
      parsed.solarLocationUpdatedAtMs, 0, Date.now(), 0)
    wallpaperRotationEnabled = parsed.wallpaperRotationEnabled === undefined
      ? true : !!parsed.wallpaperRotationEnabled
    wallpaperIntervalMinutes = Math.round(
      boundedNumber(parsed.wallpaperIntervalMinutes, 5, 1440, 60))
    settingsLoaded = true
    resolveThemeChoices(allowPersist)
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
    var target = themesLoaded ? matchingTheme(activeTheme) : ""
    if (target !== "" && (forceApply === true
        || normalizeTheme(target) !== normalizeTheme(currentTheme))) {
      requestTheme(target)
      return
    }
    maybeRotateWallpaper()
  }

  function requestTheme(theme) {
    var target = matchingTheme(theme)
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
    reloadWeatherLocation()
  }

  function reloadSettings() {
    if (!settingsReadProcess.running) settingsReadProcess.running = true
  }

  function reloadWeatherLocation() {
    if (!weatherLocationReadProcess.running)
      weatherLocationReadProcess.running = true
  }

  function reloadCurrentTheme() {
    if (!currentThemeReadProcess.running) currentThemeReadProcess.running = true
  }

  function reloadThemes() {
    if (!themeListProcess.running) themeListProcess.running = true
  }

  function applyWeatherLocation(raw) {
    if (!automaticLocationLoading) return
    var location = Safety.storedLocation(raw)
    if (location && validLocation(location.latitude, location.longitude)) {
      finishAutomaticLocation(
        location.name,
        location.latitude,
        location.longitude,
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
    var location = Safety.networkLocation(raw)
    if (!location || !validLocation(location.latitude, location.longitude)) return
    automaticLocationResolved = true
    finishAutomaticLocation(
      location.name, location.latitude, location.longitude, "network")
  }

  function finishAutomaticLocation(name, latitudeValue, longitudeValue, source) {
    if (!validLocation(latitudeValue, longitudeValue)) return
    latitude = Number(latitudeValue)
    longitude = Number(longitudeValue)
    solarLocationConfigured = true
    solarLocationMode = "automatic"
    solarLocationName = Safety.singleLine(
      name, Safety.maxLocationNameLength(), "Approximate location")
    solarLocationSource = Safety.locationSource(source)
    if (solarLocationSource === "") solarLocationSource = "automatic"
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
      root.reloadSettings()
      if (root.pendingPersist) root.persistSettings()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    preload: false
    blockAllReads: true
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadSettings()
  }

  FileView {
    id: weatherLocationFile
    path: root.weatherLocationPath
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: if (root.automaticLocationLoading)
      root.reloadWeatherLocation()
  }

  FileView {
    id: currentThemeFile
    path: root.currentThemePath
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadCurrentTheme()
  }

  // Themes are directories under ~/.config/omarchy/themes, so the list read at
  // startup goes stale the moment one is installed or removed. An install drops
  // any existing directory before cloning the new one, which arrives here as two
  // changes; the debounce collapses them into one listing once the clone lands.
  FolderListModel {
    id: themeDirectories
    folder: "file://" + encodeURI(root.themesDir)
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    onCountChanged: themeListDebounce.restart()
  }

  Timer {
    id: themeListDebounce
    interval: 750
    onTriggered: root.reloadThemes()
  }

  Process {
    id: settingsReadProcess
    command: [
      "head", "-c", String(root.maxSettingsBytes + 1), root.settingsPath
    ]
    stdout: StdioCollector {
      id: settingsReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (!root.settingsLoaded) root.applySettings("{}")
        if (root.configReady) root.persistSettings()
        return
      }
      if (settingsReadOutput.data.length > root.maxSettingsBytes) {
        if (!root.settingsLoaded) root.applySettings("{}", false)
        root.lastError = "Settings exceed the 16 KiB safety limit; defaults are in use."
        return
      }
      root.applySettings(settingsReadOutput.text)
    }
  }

  Process {
    id: weatherLocationReadProcess
    command: [
      "head", "-c", String(root.maxWeatherFileBytes + 1),
      root.weatherLocationPath
    ]
    stdout: StdioCollector {
      id: weatherLocationReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (!root.automaticLocationLoading) return
      if (exitCode === 0
          && weatherLocationReadOutput.data.length <= root.maxWeatherFileBytes) {
        root.applyWeatherLocation(weatherLocationReadOutput.text)
      } else {
        root.startAutomaticLocationLookup()
      }
    }
  }

  Process {
    id: currentThemeReadProcess
    command: [
      "head", "-c", String(root.maxCurrentThemeBytes + 1),
      root.currentThemePath
    ]
    stdout: StdioCollector {
      id: currentThemeReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0
          || currentThemeReadOutput.data.length > root.maxCurrentThemeBytes) return
      var nextTheme = root.titleFromSlug(currentThemeReadOutput.text)
      if (nextTheme === "") return
      root.currentTheme = nextTheme
      root.evaluateSchedule()
    }
  }

  Process {
    id: themeListProcess
    command: [root.themeListScript]
    stdout: StdioCollector {
      id: themeListOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "Could not read the installed Omarchy themes."
        return
      }
      if (themeListOutput.data.length > root.maxThemeListBytes) {
        root.lastError = "The Omarchy theme list exceeded its 32 KiB safety limit."
        return
      }
      root.parseThemeList(themeListOutput.text)
    }
  }

  Process {
    id: applyThemeProcess
    onExited: function(exitCode) {
      var finishedTheme = root.applyingTheme
      root.applyingTheme = ""
      if (exitCode === 0) {
        root.currentTheme = finishedTheme
        root.lastWallpaperAtMs = Date.now()
        root.lastAction = finishedTheme + " applied"
        root.reloadCurrentTheme()
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
    onExited: function(exitCode) {
      root.lastWallpaperAtMs = Date.now()
      if (exitCode === 0) root.lastAction = "Wallpaper changed"
      else if (root.lastError === "") root.lastError = "Could not change the wallpaper."
    }
  }

  Process {
    id: automaticLocationProcess
    command: [
      "curl", "-fsS",
      "--connect-timeout", "4",
      "--max-time", "8",
      "--max-filesize", String(root.maxWeatherResponseBytes),
      "--range", "0-" + String(root.maxWeatherResponseBytes - 1),
      "--header", "Accept: application/json",
      "https://wttr.in/?format=j1"
    ]
    stdout: StdioCollector {
      id: automaticLocationOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (root.solarLocationMode !== "automatic") return
      if (exitCode === 0
          && automaticLocationOutput.data.length <= root.maxWeatherResponseBytes) {
        root.applyAutomaticLocationResponse(automaticLocationOutput.text)
      }
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
    root.reloadThemes()
    root.reloadCurrentTheme()
  }

  IpcHandler {
    target: "themeflow"

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        period: root.activePeriod,
        activeTheme: root.activeTheme,
        currentTheme: root.currentTheme,
        themes: root.themes.length,
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
