const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Schedule.js"), "utf8")
const schedule = { Date, Math, Number, String, isFinite }
vm.createContext(schedule)
vm.runInContext(source, schedule)

function localDate(year, month, day, hour, minute) {
  return new Date(year, month - 1, day, hour, minute, 0, 0)
}

assert.equal(schedule.parseClock("07:05", 0), 425)
assert.equal(schedule.parseClock("24:00", 9), 9)
assert.equal(schedule.clockLabel(425), "07:05")

let result = schedule.fixedSchedule(localDate(2026, 8, 29, 12, 0), "07:00", "19:00")
assert.equal(result.period, "day")
assert.equal(result.nextAt.getHours(), 19)

result = schedule.fixedSchedule(localDate(2026, 8, 29, 22, 0), "07:00", "19:00")
assert.equal(result.period, "night")
assert.equal(result.nextAt.getDate(), 30)
assert.equal(result.nextAt.getHours(), 7)

result = schedule.fixedSchedule(localDate(2026, 8, 29, 2, 0), "18:00", "06:00")
assert.equal(result.period, "day")
assert.equal(result.nextAt.getHours(), 6)

const solar = schedule.solarEvents(localDate(2026, 6, 21, 12, 0), 37.7749, -122.4194)
assert.ok(solar)
assert.ok(solar.sunrise.getHours() >= 5 && solar.sunrise.getHours() <= 6)
assert.ok(solar.sunset.getHours() >= 20 && solar.sunset.getHours() <= 21)

result = schedule.evaluate(localDate(2026, 8, 29, 12, 0), {
  scheduleMode: "solar",
  latitude: 999,
  longitude: 999,
  dayTime: "08:00",
  nightTime: "18:00"
})
assert.equal(result.source, "fixed-fallback")
assert.equal(result.period, "day")

console.log("Themeflow schedule tests passed")
