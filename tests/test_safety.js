const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawnSync } = require("node:child_process")

const root = path.join(__dirname, "..")
const source = fs.readFileSync(path.join(root, "Safety.js"), "utf8")
const safety = { console }
vm.createContext(safety)
vm.runInContext(source, safety)

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

assert.equal(safety.maxSettingsBytes(), 16 * 1024)
assert.equal(safety.maxThemeListBytes(), 32 * 1024)
assert.equal(safety.maxWeatherResponseBytes(), 64 * 1024)

assert.deepEqual(plain(safety.settingsObject('{"enabled":true}')), { enabled: true })
const excessiveSettings = Object.fromEntries(
  Array.from({ length: 33 }, (_, index) => [`key${index}`, index]))
assert.equal(safety.settingsObject(JSON.stringify(excessiveSettings)), null)

assert.deepEqual(
  plain(safety.themeList("Tokyo Night\nCatppuccin\nTokyo Night\n")),
  ["Catppuccin", "Tokyo Night"])
assert.deepEqual(plain(safety.themeList("Safe\nBad\u0007Name\n")), ["Safe"])
assert.deepEqual(
  plain(safety.themeList("x".repeat(safety.maxThemeNameLength() + 1))), [])

const tooManyThemes = Array.from({ length: 257 }, (_, index) => `Theme ${index}`)
  .join("\n")
assert.deepEqual(plain(safety.themeList(tooManyThemes)), [])

const stored = safety.storedLocation(JSON.stringify({
  name: "San Francisco",
  latitude: 37.7749,
  longitude: -122.4194
}))
assert.deepEqual(plain(stored), {
  name: "San Francisco",
  latitude: 37.7749,
  longitude: -122.4194
})
assert.equal(safety.storedLocation(JSON.stringify({ latitude: 91, longitude: 0 })), null)

const network = safety.networkLocation(JSON.stringify({
  nearest_area: [{
    latitude: "37.7749",
    longitude: "-122.4194",
    areaName: [{ value: "San Francisco" }],
    region: [{ value: "California" }]
  }]
}))
assert.deepEqual(plain(network), {
  name: "San Francisco, California",
  latitude: 37.7749,
  longitude: -122.4194
})

const excessiveItems = {
  nearest_area: Array.from({ length: 9 }, () => ({
    latitude: 0,
    longitude: 0,
    areaName: [{ value: "Area" }],
    region: [{ value: "Region" }]
  }))
}
assert.equal(safety.networkLocation(JSON.stringify(excessiveItems)), null)
assert.equal(
  safety.networkLocation("x".repeat(safety.maxWeatherResponseBytes() + 1)), null)

const temp = fs.mkdtempSync(path.join(os.tmpdir(), "themeflow-safety-"))
try {
  const fakeOmarchy = path.join(temp, "omarchy")
  fs.writeFileSync(fakeOmarchy, `#!/bin/bash
if [[ \${THEMEFLOW_TEST_MODE:-} == large ]]; then
  head -c 40000 /dev/zero | tr '\\0' x
else
  printf 'Catppuccin\\nTokyo Night\\n'
fi
`)
  fs.chmodSync(fakeOmarchy, 0o755)
  const command = path.join(root, "scripts", "list-themes-bounded.sh")
  const env = { ...process.env, PATH: `${temp}:${process.env.PATH}` }

  let result = spawnSync(command, { env })
  assert.equal(result.status, 0)
  assert.equal(result.stdout.toString(), "Catppuccin\nTokyo Night\n")

  result = spawnSync(command, {
    env: { ...env, THEMEFLOW_TEST_MODE: "large" }
  })
  assert.equal(result.status, 0)
  assert.equal(result.stdout.length, safety.maxThemeListBytes() + 1)
} finally {
  fs.rmSync(temp, { recursive: true, force: true })
}

const serviceQml = fs.readFileSync(path.join(root, "Service.qml"), "utf8")
assert.equal((serviceQml.match(/blockAllReads: true/g) || []).length, 3)
assert.match(serviceQml, /--max-filesize/)
assert.doesNotMatch(serviceQml, /stderr:\s*StdioCollector/)

const widgetQml = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
const textItems = (widgetQml.match(/\bText\s*\{/g) || []).length
const plainTextItems = (widgetQml.match(/textFormat:\s*Text\.PlainText/g) || []).length
assert.equal(plainTextItems, textItems)

console.log("Themeflow safety tests passed")
