const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")

// Exercise the actual QML exit handlers with the ArrayBuffer exposed by
// StdioCollector.data. String length would miss multibyte payloads.
function run(processId, outputId, text, overrides = {}, exitCode = 0) {
  const match = source.match(new RegExp(
    `id: ${processId}\\b[\\s\\S]*?onExited: function\\(exitCode\\) \\{([\\s\\S]*?)\\n    \\}`))
  assert.ok(match, `Missing exit handler: ${processId}`)
  const calls = []
  const root = {
    maxSettingsBytes: 16 * 1024,
    maxWeatherFileBytes: 8 * 1024,
    maxCurrentThemeBytes: 1024,
    maxThemeListBytes: 32 * 1024,
    maxWeatherResponseBytes: 64 * 1024,
    settingsLoaded: true,
    automaticLocationLoading: true,
    automaticLocationResolved: false,
    solarLocationMode: "automatic",
    solarLocationConfigured: false,
    currentTheme: "Previous theme",
    lastError: "",
    applySettings: value => calls.push(["settings", value]),
    persistSettings: () => calls.push(["persist"]),
    applyWeatherLocation: value => calls.push(["weather", value]),
    startAutomaticLocationLookup: () => calls.push(["lookup"]),
    titleFromSlug: value => value.trim(),
    evaluateSchedule: () => calls.push(["schedule"]),
    parseThemeList: value => calls.push(["themes", value]),
    applyAutomaticLocationResponse: value => {
      calls.push(["network", value])
      root.automaticLocationResolved = true
    },
    ...overrides
  }
  const output = { text, data: Uint8Array.from(Buffer.from(text, "utf8")).buffer }
  const handler = vm.runInNewContext(`(function(exitCode) {${match[1]}\n})`, {
    root, [outputId]: output
  })
  handler(exitCode)
  return { root, calls }
}

let result = run("settingsReadProcess", "settingsReadOutput", '{"enabled":false}')
assert.deepEqual(result.calls, [["settings", '{"enabled":false}']])
result = run("settingsReadProcess", "settingsReadOutput", " ".repeat(16 * 1024 + 1))
assert.deepEqual(result.calls, [])
assert.match(result.root.lastError, /16 KiB/)

const stored = '{"name":"Test location","latitude":10,"longitude":20}'
result = run("weatherLocationReadProcess", "weatherLocationReadOutput", stored)
assert.deepEqual(result.calls, [["weather", stored]])
result = run("weatherLocationReadProcess", "weatherLocationReadOutput", " ".repeat(8 * 1024 + 1))
assert.deepEqual(result.calls, [["lookup"]])
result = run("weatherLocationReadProcess", "weatherLocationReadOutput", "", {}, 1)
assert.deepEqual(result.calls, [["lookup"]])

result = run("currentThemeReadProcess", "currentThemeReadOutput", "Test theme")
assert.equal(result.root.currentTheme, "Test theme")
assert.deepEqual(result.calls, [["schedule"]])
result = run("currentThemeReadProcess", "currentThemeReadOutput", "x".repeat(1025))
assert.equal(result.root.currentTheme, "Previous theme")
assert.deepEqual(result.calls, [])

result = run("themeListProcess", "themeListOutput", "Test theme\n")
assert.deepEqual(result.calls, [["themes", "Test theme\n"]])
result = run("themeListProcess", "themeListOutput", "x".repeat(32 * 1024 + 1))
assert.deepEqual(result.calls, [])
assert.match(result.root.lastError, /32 KiB/)

const network = '{"nearest_area":[{"latitude":"10","longitude":"20"}]}'
result = run("automaticLocationProcess", "automaticLocationOutput", network)
assert.deepEqual(result.calls, [["network", network]])
assert.equal(result.root.lastError, "")
result = run("automaticLocationProcess", "automaticLocationOutput", "x".repeat(64 * 1024 + 1))
assert.deepEqual(result.calls, [["schedule"]])
assert.equal(result.root.automaticLocationLoading, false)
assert.match(result.root.lastError, /could not be determined/)
result = run("automaticLocationProcess", "automaticLocationOutput", "", {}, 28)
assert.deepEqual(result.calls, [["schedule"]])
assert.match(result.root.lastError, /check the network/)

// This has fewer than 64 Ki characters but more than 64 Ki bytes.
const multibyte = "é".repeat(33 * 1024)
assert.ok(multibyte.length < 64 * 1024)
assert.ok(Buffer.byteLength(multibyte) > 64 * 1024)
result = run("automaticLocationProcess", "automaticLocationOutput", multibyte)
assert.deepEqual(result.calls, [["schedule"]])
assert.match(result.root.lastError, /could not be determined/)

console.log("Themeflow collector tests passed")
