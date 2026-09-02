// Bounds and sanitizers for every value loaded from files or subprocesses.

var SETTINGS_BYTES = 16 * 1024
var WEATHER_FILE_BYTES = 8 * 1024
var CURRENT_THEME_BYTES = 1024
var THEME_LIST_BYTES = 32 * 1024
var WEATHER_RESPONSE_BYTES = 64 * 1024
var THEME_ITEMS = 256
var THEME_NAME_LENGTH = 128
var LOCATION_NAME_LENGTH = 160
var LOCATION_PART_LENGTH = 80
var LOCATION_ARRAY_ITEMS = 8
var SETTINGS_FIELDS = 32

function maxSettingsBytes() { return SETTINGS_BYTES }
function maxWeatherFileBytes() { return WEATHER_FILE_BYTES }
function maxCurrentThemeBytes() { return CURRENT_THEME_BYTES }
function maxThemeListBytes() { return THEME_LIST_BYTES }
function maxWeatherResponseBytes() { return WEATHER_RESPONSE_BYTES }
function maxThemeNameLength() { return THEME_NAME_LENGTH }
function maxLocationNameLength() { return LOCATION_NAME_LENGTH }

function singleLine(value, maximum, fallback) {
  if (value === undefined || value === null) return fallback
  var text = String(value)
  if (text.length > maximum || /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(text))
    return fallback
  text = text.trim()
  return text === "" ? fallback : text
}

function optionalSingleLine(value, maximum) {
  return singleLine(value, maximum, "")
}

function locationSource(value) {
  var source = optionalSingleLine(value, 32)
  return source === "manual"
      || source === "automatic"
      || source === "network"
      || source === "omarchy-weather"
    ? source : ""
}

function normalizedTheme(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
}

function themeList(raw) {
  var input = String(raw || "")
  if (input.length > THEME_LIST_BYTES) return []

  var found = []
  var seen = ({})
  var lines = input.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var theme = singleLine(lines[i], THEME_NAME_LENGTH, "")
    if (theme === "") continue
    var key = normalizedTheme(theme)
    if (seen[key]) continue
    if (found.length >= THEME_ITEMS) return []
    seen[key] = true
    found.push(theme)
  }
  found.sort(function(a, b) { return a.localeCompare(b) })
  return found
}

function parseObject(raw, maximum) {
  var input = String(raw || "")
  if (input.length > maximum) return null
  try {
    var parsed = JSON.parse(input || "{}")
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed : null
  } catch (error) {
    return null
  }
}

function settingsObject(raw) {
  var parsed = parseObject(raw, SETTINGS_BYTES)
  if (!parsed || Object.keys(parsed).length > SETTINGS_FIELDS) return null
  return parsed
}

function validCoordinate(latitudeValue, longitudeValue) {
  var latitude = Number(latitudeValue)
  var longitude = Number(longitudeValue)
  return isFinite(latitude) && latitude >= -90 && latitude <= 90
    && isFinite(longitude) && longitude >= -180 && longitude <= 180
}

function boundedArray(value) {
  return Array.isArray(value) && value.length > 0
      && value.length <= LOCATION_ARRAY_ITEMS
    ? value : null
}

function storedLocation(raw) {
  var parsed = parseObject(raw, WEATHER_FILE_BYTES)
  if (!parsed || !validCoordinate(parsed.latitude, parsed.longitude)) return null
  return {
    name: singleLine(
      parsed.name, LOCATION_NAME_LENGTH, "Omarchy Weather location"),
    latitude: Number(parsed.latitude),
    longitude: Number(parsed.longitude)
  }
}

function firstLocationPart(value) {
  var items = boundedArray(value)
  if (!items || !items[0] || typeof items[0] !== "object") return ""
  return optionalSingleLine(items[0].value, LOCATION_PART_LENGTH)
}

function networkLocation(raw) {
  var parsed = parseObject(raw, WEATHER_RESPONSE_BYTES)
  if (!parsed) return null
  var areas = boundedArray(parsed.nearest_area)
  if (!areas || !areas[0] || typeof areas[0] !== "object") return null
  var area = areas[0]
  if (!validCoordinate(area.latitude, area.longitude)) return null

  var areaName = firstLocationPart(area.areaName)
  var region = firstLocationPart(area.region)
  var name = areaName || "Approximate location"
  if (region !== "") name += ", " + region
  if (name.length > LOCATION_NAME_LENGTH) name = "Approximate location"

  return {
    name: name,
    latitude: Number(area.latitude),
    longitude: Number(area.longitude)
  }
}
