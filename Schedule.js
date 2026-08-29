// Pure scheduling helpers shared by the QML service and the Node test suite.

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function parseClock(value, fallbackMinutes) {
  var match = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(value || "").trim())
  if (!match) return fallbackMinutes
  return Number(match[1]) * 60 + Number(match[2])
}

function clockLabel(minutes) {
  var safe = ((Math.round(Number(minutes) || 0) % 1440) + 1440) % 1440
  var hour = Math.floor(safe / 60)
  var minute = safe % 60
  return (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute
}

function atLocalMinutes(reference, minutes, dayOffset) {
  return new Date(
    reference.getFullYear(),
    reference.getMonth(),
    reference.getDate() + (dayOffset || 0),
    0,
    Math.round(minutes),
    0,
    0
  )
}

function fixedSchedule(now, dayValue, nightValue) {
  var dayMinutes = parseClock(dayValue, 7 * 60)
  var nightMinutes = parseClock(nightValue, 19 * 60)
  if (dayMinutes === nightMinutes) nightMinutes = (dayMinutes + 12 * 60) % 1440

  var dayToday = atLocalMinutes(now, dayMinutes, 0)
  var nightToday = atLocalMinutes(now, nightMinutes, 0)
  var period = "night"
  var nextAt = dayToday

  if (dayMinutes < nightMinutes) {
    if (now >= dayToday && now < nightToday) {
      period = "day"
      nextAt = nightToday
    } else {
      period = "night"
      nextAt = now < dayToday ? dayToday : atLocalMinutes(now, dayMinutes, 1)
    }
  } else {
    // A reversed pair intentionally supports a day period spanning midnight.
    if (now >= dayToday || now < nightToday) {
      period = "day"
      nextAt = now < nightToday ? nightToday : atLocalMinutes(now, nightMinutes, 1)
    } else {
      period = "night"
      nextAt = dayToday
    }
  }

  return {
    period: period,
    nextAt: nextAt,
    dayStart: dayToday,
    nightStart: nightToday,
    source: "fixed"
  }
}

function solarEvents(reference, latitudeValue, longitudeValue) {
  var latitude = Number(latitudeValue)
  var longitude = Number(longitudeValue)
  if (!isFinite(latitude) || !isFinite(longitude)
      || latitude < -90 || latitude > 90
      || longitude < -180 || longitude > 180) return null

  // UTC calendar dates avoid the one-hour discontinuity introduced by DST.
  var dayOfYear = Math.round((
    Date.UTC(reference.getFullYear(), reference.getMonth(), reference.getDate())
      - Date.UTC(reference.getFullYear(), 0, 0)
  ) / 86400000)
  var gamma = 2 * Math.PI / 365 * (dayOfYear - 1)
  var equationOfTime = 229.18 * (
    0.000075
      + 0.001868 * Math.cos(gamma)
      - 0.032077 * Math.sin(gamma)
      - 0.014615 * Math.cos(2 * gamma)
      - 0.040849 * Math.sin(2 * gamma)
  )
  var declination = 0.006918
    - 0.399912 * Math.cos(gamma)
    + 0.070257 * Math.sin(gamma)
    - 0.006758 * Math.cos(2 * gamma)
    + 0.000907 * Math.sin(2 * gamma)
    - 0.002697 * Math.cos(3 * gamma)
    + 0.00148 * Math.sin(3 * gamma)

  var latitudeRadians = latitude * Math.PI / 180
  var zenithRadians = 90.833 * Math.PI / 180
  var hourAngleCosine = (
    Math.cos(zenithRadians) / (Math.cos(latitudeRadians) * Math.cos(declination))
  ) - Math.tan(latitudeRadians) * Math.tan(declination)
  if (hourAngleCosine < -1 || hourAngleCosine > 1) return null

  var hourAngleDegrees = Math.acos(clamp(hourAngleCosine, -1, 1)) * 180 / Math.PI
  var utcOffsetMinutes = -reference.getTimezoneOffset()
  var solarNoonMinutes = 720 - 4 * longitude - equationOfTime + utcOffsetMinutes
  var sunriseMinutes = solarNoonMinutes - 4 * hourAngleDegrees
  var sunsetMinutes = solarNoonMinutes + 4 * hourAngleDegrees

  return {
    sunrise: atLocalMinutes(reference, sunriseMinutes, 0),
    sunset: atLocalMinutes(reference, sunsetMinutes, 0),
    sunriseMinutes: sunriseMinutes,
    sunsetMinutes: sunsetMinutes
  }
}

function solarSchedule(now, latitude, longitude) {
  var today = solarEvents(now, latitude, longitude)
  if (!today) return null

  if (now < today.sunrise) {
    return {
      period: "night",
      nextAt: today.sunrise,
      dayStart: today.sunrise,
      nightStart: today.sunset,
      source: "solar"
    }
  }

  if (now < today.sunset) {
    return {
      period: "day",
      nextAt: today.sunset,
      dayStart: today.sunrise,
      nightStart: today.sunset,
      source: "solar"
    }
  }

  var tomorrowReference = new Date(
    now.getFullYear(), now.getMonth(), now.getDate() + 1, 12, 0, 0, 0)
  var tomorrow = solarEvents(tomorrowReference, latitude, longitude)
  if (!tomorrow) return null
  return {
    period: "night",
    nextAt: tomorrow.sunrise,
    dayStart: today.sunrise,
    nightStart: today.sunset,
    source: "solar"
  }
}

function evaluate(now, settings) {
  var fixed = fixedSchedule(now, settings.dayTime, settings.nightTime)
  if (String(settings.scheduleMode || "fixed") !== "solar") return fixed

  var solar = solarSchedule(now, settings.latitude, settings.longitude)
  if (solar) return solar
  fixed.source = "fixed-fallback"
  return fixed
}
