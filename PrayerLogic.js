.pragma library

var PRE = 900
var FLASH = 420
var ELAPSED = 1200

var TEXT_MODES = ["full-time", "full-relative", "initial-time", "initial-relative"]
var OFFSET_KEYS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

var METHOD_OPTIONS = [
  { value: "4", label: "Umm Al-Qura University, Makkah" },
  { value: "3", label: "Muslim World League" },
  { value: "5", label: "Egyptian General Authority of Survey" },
  { value: "2", label: "Islamic Society of North America (ISNA)" },
  { value: "1", label: "University of Islamic Sciences, Karachi" },
  { value: "8", label: "Gulf Region" },
  { value: "9", label: "Kuwait" },
  { value: "10", label: "Qatar" },
  { value: "11", label: "Majlis Ugama Islam Singapura" },
  { value: "13", label: "Diyanet İşleri Başkanlığı, Turkey" },
  { value: "12", label: "Union Organization Islamic de France" },
  { value: "14", label: "Spiritual Administration of Muslims of Russia" },
  { value: "15", label: "Moonsighting Committee Worldwide" },
  { value: "16", label: "Dubai" },
  { value: "17", label: "Jabatan Kemajuan Islam Malaysia" },
  { value: "18", label: "Tunisia" },
  { value: "19", label: "Algeria" },
  { value: "20", label: "Kementerian Agama Republik Indonesia" },
  { value: "21", label: "Morocco" },
  { value: "22", label: "Comunidade Islamica de Lisboa" },
  { value: "23", label: "Ministry of Awqaf, Jordan" },
  { value: "7", label: "Institute of Geophysics, University of Tehran" },
  { value: "0", label: "Shia Ithna-Ashari, Leva Institute, Qum" }
]

var SCHOOL_OPTIONS = [
  { value: "0", label: "Standard (Shafi'i, Maliki, Hanbali)" },
  { value: "1", label: "Hanafi" }
]

var HIGH_LATITUDE_OPTIONS = [
  { value: "0", label: "None / astronomical" },
  { value: "1", label: "Angle-based" },
  { value: "2", label: "One-seventh" },
  { value: "3", label: "Middle of the night" }
]

var TEXT_MODE_OPTIONS = [
  { value: "full-time", label: "Asr 15:24" },
  { value: "full-relative", label: "Asr in 3m" },
  { value: "initial-time", label: "A 15:24" },
  { value: "initial-relative", label: "A in 3m" }
]

function parseMs(iso) {
  if (!iso) return NaN
  return Date.parse(iso)
}

function countdownText(seconds) {
  if (seconds < 0) return ""
  if (seconds < 60) return "<1m"
  var minutes = Math.ceil(seconds / 60)
  return Math.max(1, minutes) + "m"
}

function relativeText(seconds) {
  if (seconds < 0) return ""
  if (seconds < 60) return "<1m"
  var totalMinutes = Math.ceil(seconds / 60)
  if (totalMinutes < 60) return totalMinutes + "m"
  var hours = Math.floor(totalMinutes / 60)
  var minutes = totalMinutes % 60
  return hours + "h" + (minutes ? " " + minutes + "m" : "")
}

function emptyState() {
  return {
    nextName: "",
    nextLabel: "",
    nextTime: "",
    nextIso: "",
    secondsToNext: -1,
    currentName: "",
    currentLabel: "",
    secondsSinceAdhan: -1,
    withinPre: false,
    withinFlash: false,
    withinElapsed: false,
    countdownText: ""
  }
}

function deriveState(times, tomorrow, nowMs) {
  var result = emptyState()
  var now = typeof nowMs === "number" && isFinite(nowMs) ? nowMs : Date.now()
  var prayers = []

  if (times && times.length) {
    for (var i = 0; i < times.length; i++) {
      var entry = times[i]
      if (!entry || !entry.isPrayer) continue
      var ms = parseMs(entry.iso)
      if (isNaN(ms)) continue
      prayers.push({
        name: entry.name || "",
        label: entry.label || "",
        time: entry.time || "",
        iso: entry.iso,
        ms: ms
      })
    }
  }

  var next = null
  for (var j = 0; j < prayers.length; j++) {
    if (prayers[j].ms > now) {
      next = prayers[j]
      break
    }
  }

  if (!next && tomorrow && tomorrow.fajr) {
    var fajr = tomorrow.fajr
    var fajrMs = parseMs(fajr.iso)
    if (!isNaN(fajrMs) && fajrMs > now) {
      next = {
        name: fajr.name || "",
        label: fajr.label || "",
        time: fajr.time || "",
        iso: fajr.iso,
        ms: fajrMs
      }
    }
  }

  if (next) {
    var secondsToNext = Math.round((next.ms - now) / 1000)
    if (secondsToNext < 0) secondsToNext = 0
    result.nextName = next.name
    result.nextLabel = next.label
    result.nextTime = next.time
    result.nextIso = next.iso
    result.secondsToNext = secondsToNext
    result.withinPre = secondsToNext <= PRE
    result.withinFlash = secondsToNext <= FLASH
    result.countdownText = countdownText(secondsToNext)
  }

  var current = null
  var currentDelta = -1
  for (var k = 0; k < prayers.length; k++) {
    var delta = Math.round((now - prayers[k].ms) / 1000)
    if (delta >= 0 && delta <= ELAPSED) {
      current = prayers[k]
      currentDelta = delta
    }
  }

  if (current) {
    result.currentName = current.name
    result.currentLabel = current.label
    result.secondsSinceAdhan = currentDelta
    result.withinElapsed = true
  }

  return result
}

function defaultOffsets() {
  return { fajr: 0, sunrise: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 0 }
}

function defaultSettings() {
  return {
    locationMode: "auto",
    locationName: "",
    latitude: null,
    longitude: null,
    timezone: "",
    method: 4,
    school: 0,
    highLatitude: 0,
    hijriAdjustment: 0,
    ramadanIsha: true,
    offsets: defaultOffsets(),
    showIcon: false,
    textMode: "initial-time"
  }
}

function boundedInteger(value, fallback, minimum, maximum) {
  var parsed = parseInt(value, 10)
  if (!isFinite(parsed)) return fallback
  return Math.max(minimum, Math.min(maximum, parsed))
}

function supportedMethod(value) {
  var text = String(value)
  for (var i = 0; i < METHOD_OPTIONS.length; i++) {
    if (METHOD_OPTIONS[i].value === text) return Number(text)
  }
  return 4
}

function supportedTextMode(value) {
  var text = String(value || "")
  return TEXT_MODES.indexOf(text) >= 0 ? text : "initial-time"
}

function sanitizeSettings(value) {
  var defaults = defaultSettings()
  var input = value && typeof value === "object" && !Array.isArray(value) ? value : ({})
  var latitude = Number(input.latitude)
  var longitude = Number(input.longitude)
  var manualCoordinates = isFinite(latitude) && latitude >= -90 && latitude <= 90
    && isFinite(longitude) && longitude >= -180 && longitude <= 180
  var offsets = defaultOffsets()
  var inputOffsets = input.offsets && typeof input.offsets === "object" ? input.offsets : ({})

  for (var i = 0; i < OFFSET_KEYS.length; i++) {
    var key = OFFSET_KEYS[i]
    offsets[key] = boundedInteger(inputOffsets[key], 0, -15, 15)
  }

  return {
    locationMode: input.locationMode === "manual" && manualCoordinates ? "manual" : "auto",
    locationName: typeof input.locationName === "string" ? input.locationName.trim().substring(0, 120) : "",
    latitude: manualCoordinates ? latitude : null,
    longitude: manualCoordinates ? longitude : null,
    timezone: typeof input.timezone === "string" ? input.timezone.trim().substring(0, 80) : "",
    method: supportedMethod(input.method),
    school: boundedInteger(input.school, defaults.school, 0, 1),
    highLatitude: boundedInteger(input.highLatitude, defaults.highLatitude, 0, 3),
    hijriAdjustment: boundedInteger(input.hijriAdjustment, defaults.hijriAdjustment, -2, 2),
    ramadanIsha: input.ramadanIsha === undefined ? defaults.ramadanIsha : !!input.ramadanIsha,
    offsets: offsets,
    showIcon: input.showIcon === undefined ? defaults.showIcon : !!input.showIcon,
    textMode: supportedTextMode(input.textMode)
  }
}

function mergeSettings(current, partial) {
  var merged = {}
  var existing = sanitizeSettings(current)
  var update = partial && typeof partial === "object" ? partial : ({})
  var key

  for (key in existing) merged[key] = existing[key]
  for (key in update) merged[key] = update[key]
  if (update.offsets) {
    merged.offsets = {}
    for (key in existing.offsets) merged.offsets[key] = existing.offsets[key]
    for (key in update.offsets) merged.offsets[key] = update.offsets[key]
  }
  return sanitizeSettings(merged)
}

function nextTextMode(mode) {
  var current = TEXT_MODES.indexOf(supportedTextMode(mode))
  return TEXT_MODES[(current + 1) % TEXT_MODES.length]
}

function displayName(label, mode) {
  var value = String(label || "")
  return mode.indexOf("initial-") === 0 && value ? value.charAt(0).toUpperCase() : value
}

function formatBarText(state, settings) {
  if (!state) return ""
  var config = sanitizeSettings(settings)
  var mode = config.textMode

  if (state.state === "error") return "--"

  if (state.withinElapsed && state.currentLabel) {
    var current = displayName(state.currentLabel, mode)
    var elapsedMinutes = Math.floor(Math.max(0, state.secondsSinceAdhan) / 60)
    return elapsedMinutes === 0 ? current + " now" : current + " " + elapsedMinutes + "m ago"
  }

  if (!state.nextLabel) return ""
  var next = displayName(state.nextLabel, mode)
  if (mode.indexOf("-relative") >= 0)
    return next + " in " + relativeText(state.secondsToNext)
  return state.nextTime ? next + " " + state.nextTime : next
}
