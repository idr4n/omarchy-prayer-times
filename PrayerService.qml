import QtQuick
import Quickshell
import Quickshell.Io
import "PrayerLogic.js" as PrayerLogic

Scope {
  id: root

  property string state: "loading"
  property string errorText: ""
  property var times: []
  property var tomorrow: null
  property string date: ""
  property string dateText: ""
  property string timezone: ""
  property string methodName: ""
  property string locationLabel: ""
  property bool fromCache: false
  property string hijriDay: ""
  property string hijriMonth: ""
  property string hijriYear: ""
  property string hijriDesignation: ""
  readonly property string hijriDateText: hijriDay && hijriMonth ? hijriDay + " " + hijriMonth : ""
  readonly property string hijriYearText: hijriYear ? hijriYear + (hijriDesignation ? " " + hijriDesignation : "") : ""

  property string nextName: ""
  property string nextLabel: ""
  property string nextTime: ""
  property string nextIso: ""
  property int secondsToNext: -1
  property string currentName: ""
  property string currentLabel: ""
  property int secondsSinceAdhan: -1
  property bool withinPre: false
  property bool withinFlash: false
  property bool withinElapsed: false
  property string countdownText: ""

  property bool loaded: false
  property bool refreshing: false
  property bool settingsReady: false
  property bool settingsSaving: false
  property string settingsError: ""
  property var configuration: PrayerLogic.defaultSettings()
  property string pendingSettingsPayload: ""
  property string savingSettingsPayload: ""

  readonly property var methodOptions: PrayerLogic.METHOD_OPTIONS
  readonly property var schoolOptions: PrayerLogic.SCHOOL_OPTIONS
  readonly property var highLatitudeOptions: PrayerLogic.HIGH_LATITUDE_OPTIONS
  readonly property var textModeOptions: PrayerLogic.TEXT_MODE_OPTIONS
  readonly property var offsetKeys: PrayerLogic.OFFSET_KEYS
  readonly property bool showIcon: !!configuration.showIcon
  readonly property string textMode: String(configuration.textMode || "initial-time")
  readonly property string displayText: PrayerLogic.formatBarText(root, configuration)
  readonly property string configuredLocationText: configuration.locationMode === "manual"
    ? String(configuration.locationName || "")
    : "Automatic"

  function pluginPath(name) {
    var base = Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
    return base + name
  }

  function backendArguments() {
    var config = root.configuration
    var args = [
      root.pluginPath("prayer-times-json"),
      "--method", String(config.method),
      "--school", String(config.school),
      "--high-latitude", String(config.highLatitude),
      "--hijri-adjustment", String(config.hijriAdjustment),
      "--offsets", JSON.stringify(config.offsets),
      "--ramadan-isha", config.ramadanIsha ? "1" : "0"
    ]
    if (config.locationMode === "manual") {
      args.push("--lat", String(config.latitude))
      args.push("--lon", String(config.longitude))
      args.push("--location-label", String(config.locationName || ""))
      if (config.timezone) args.push("--tz", String(config.timezone))
    }
    return args
  }

  function localTodayIso() {
    var now = new Date()
    var year = now.getFullYear()
    var month = String(now.getMonth() + 1).padStart(2, "0")
    var day = String(now.getDate()).padStart(2, "0")
    return year + "-" + month + "-" + day
  }

  function formatDateText(iso) {
    if (!iso) return ""
    var parts = iso.split("-").map(function(part) { return Number(part) })
    if (parts.length !== 3 || parts.some(function(part) { return Number.isNaN(part) })) return iso
    return Qt.formatDate(new Date(parts[0], parts[1] - 1, parts[2]), "ddd, d MMM")
  }

  function recompute() {
    var derived = PrayerLogic.deriveState(root.times, root.tomorrow, Date.now())
    root.nextName = derived.nextName
    root.nextLabel = derived.nextLabel
    root.nextTime = derived.nextTime
    root.nextIso = derived.nextIso
    root.secondsToNext = derived.secondsToNext
    root.currentName = derived.currentName
    root.currentLabel = derived.currentLabel
    root.secondsSinceAdhan = derived.secondsSinceAdhan
    root.withinPre = derived.withinPre
    root.withinFlash = derived.withinFlash
    root.withinElapsed = derived.withinElapsed
    root.countdownText = derived.countdownText
  }

  function handleFailure(message) {
    if (root.loaded) {
      root.state = "stale"
      root.fromCache = true
    } else {
      root.state = "error"
      root.errorText = message || "Prayer backend failed"
      root.times = []
      root.tomorrow = null
      root.hijriDay = ""
      root.hijriMonth = ""
      root.hijriYear = ""
      root.hijriDesignation = ""
      root.recompute()
    }
    retryTimer.restart()
  }

  function refresh() {
    if (!root.settingsReady || root.refreshing) return
    root.refreshing = true
    prayerProcess.exec(root.backendArguments())
  }

  function updateSettings(partial, refetch) {
    root.configuration = PrayerLogic.mergeSettings(root.configuration, partial)
    root.pendingSettingsPayload = JSON.stringify(root.configuration)
    settingsSaveTimer.restart()
    if (refetch) settingsRefreshTimer.restart()
  }

  function updateOffset(name, value) {
    var change = {}
    change[name] = value
    root.updateSettings({ offsets: change }, true)
  }

  function setManualLocation(name, latitude, longitude, locationTimezone) {
    root.updateSettings({
      locationMode: "manual",
      locationName: name,
      latitude: latitude,
      longitude: longitude,
      timezone: locationTimezone || ""
    }, true)
  }

  function useAutomaticLocation() {
    root.updateSettings({
      locationMode: "auto",
      locationName: "",
      latitude: null,
      longitude: null,
      timezone: ""
    }, true)
  }

  function cycleTextMode() {
    root.updateSettings({ textMode: PrayerLogic.nextTextMode(root.textMode) }, false)
  }

  function beginSettingsSave() {
    if (!root.pendingSettingsPayload) return
    if (settingsSaveProcess.running) return
    root.savingSettingsPayload = root.pendingSettingsPayload
    root.settingsSaving = true
    settingsSaveProcess.exec([
      root.pluginPath("prayer-times-json"),
      "--write-settings", root.savingSettingsPayload
    ])
  }

  Component.onCompleted: {
    settingsReadProcess.exec([root.pluginPath("prayer-times-json"), "--read-settings"])
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.recompute()
      if (!root.refreshing && root.date && root.date !== root.localTodayIso()) root.refresh()
    }
  }

  Timer {
    interval: 6 * 60 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    id: retryTimer
    interval: 60000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: settingsSaveTimer
    interval: 120
    repeat: false
    onTriggered: root.beginSettingsSave()
  }

  Timer {
    id: settingsRefreshTimer
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: settingsReadProcess

    stdout: StdioCollector {
      id: settingsOutput
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: settingsReadError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      var parsed = ({})
      if (exitCode === 0) {
        try {
          parsed = JSON.parse(settingsOutput.text.trim() || "{}")
        } catch (error) {
          root.settingsError = "Invalid saved prayer settings"
        }
      } else {
        root.settingsError = settingsReadError.text.trim() || "Unable to read prayer settings"
      }
      root.configuration = PrayerLogic.sanitizeSettings(parsed)
      root.pendingSettingsPayload = JSON.stringify(root.configuration)
      root.settingsReady = true
      root.refresh()
    }
  }

  Process {
    id: settingsSaveProcess

    stderr: StdioCollector {
      id: settingsWriteError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.settingsSaving = false
      if (exitCode !== 0)
        root.settingsError = settingsWriteError.text.trim() || "Unable to save prayer settings"
      else
        root.settingsError = ""
      if (root.pendingSettingsPayload !== root.savingSettingsPayload)
        Qt.callLater(root.beginSettingsSave)
    }
  }

  Process {
    id: prayerProcess

    stdout: StdioCollector {
      id: prayerOutput
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: prayerError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.refreshing = false

      if (exitCode !== 0) {
        root.handleFailure(prayerError.text.trim() || "Prayer backend failed")
        return
      }

      var payload
      try {
        payload = JSON.parse(prayerOutput.text.trim() || "{}")
      } catch (error) {
        root.handleFailure("Invalid prayer JSON")
        return
      }

      root.times = payload.times || []
      root.tomorrow = payload.tomorrow || null
      root.date = payload.date || ""
      root.dateText = root.formatDateText(root.date)
      root.timezone = payload.timezone || ""
      root.methodName = payload.methodName || ""
      root.locationLabel = payload.locationLabel || ""
      root.fromCache = !!payload.fromCache
      root.state = payload.state || "error"
      root.errorText = payload.error || ""
      root.loaded = root.times.length > 0

      if (payload.hijri && typeof payload.hijri === "object") {
        root.hijriDay = String(payload.hijri.day ?? "")
        root.hijriMonth = String(payload.hijri.month ?? "")
        root.hijriYear = String(payload.hijri.year ?? "")
        root.hijriDesignation = String(payload.hijri.designation ?? "")
      } else {
        root.hijriDay = ""
        root.hijriMonth = ""
        root.hijriYear = ""
        root.hijriDesignation = ""
      }

      root.recompute()
      if (root.state === "error" || root.state === "stale") retryTimer.restart()
    }
  }
}
