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
  property string dateEndsAt: ""
  property string rolloverRefreshAttempted: ""
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
  property bool refreshQueued: false
  property bool locationRefreshRequested: false
  property real previousTickMs: 0
  property bool settingsReady: false
  property bool settingsSaving: false
  property string settingsError: ""
  property var configuration: PrayerLogic.defaultSettings()
  property string pendingSettingsPayload: ""
  property string savingSettingsPayload: ""
  property var pendingSettingsPatch: ({})
  property var savingSettingsPatch: ({})

  readonly property var methodOptions: PrayerLogic.METHOD_OPTIONS
  readonly property var schoolOptions: PrayerLogic.SCHOOL_OPTIONS
  readonly property var highLatitudeOptions: PrayerLogic.HIGH_LATITUDE_OPTIONS
  readonly property var textModeOptions: PrayerLogic.TEXT_MODE_OPTIONS
  readonly property var verticalTextModeOptions: PrayerLogic.VERTICAL_TEXT_MODE_OPTIONS
  readonly property var offsetKeys: PrayerLogic.OFFSET_KEYS
  readonly property bool showIcon: !!configuration.showIcon
  readonly property string textMode: String(configuration.textMode || "initial-time")
  readonly property string displayText: PrayerLogic.formatBarText(root, configuration)
  readonly property string verticalTextMode: PrayerLogic.effectiveVerticalTextMode(configuration)
  readonly property var verticalLines: PrayerLogic.verticalBarLines(root, configuration)
  readonly property string tooltipText: PrayerLogic.barTooltipText(root, root.locationLabel, false)
  readonly property string verticalTooltipText: PrayerLogic.barTooltipText(root, root.locationLabel, true)
  readonly property string configuredLocationText: configuration.locationMode === "manual"
    ? String(configuration.locationName || "")
    : "Automatic"
  readonly property string settingsPath: {
    var stateHome = Quickshell.env("XDG_STATE_HOME")
    if (!stateHome) stateHome = Quickshell.env("HOME") + "/.local/state"
    return stateHome + "/omarchy/settings/prayer-times.json"
  }

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

  function backendConfigurationKey(config) {
    var value = PrayerLogic.sanitizeSettings(config)
    return JSON.stringify({
      locationMode: value.locationMode,
      locationName: value.locationName,
      latitude: value.latitude,
      longitude: value.longitude,
      timezone: value.timezone,
      method: value.method,
      school: value.school,
      highLatitude: value.highLatitude,
      hijriAdjustment: value.hijriAdjustment,
      ramadanIsha: value.ramadanIsha,
      offsets: value.offsets
    })
  }

  function mergeSettingsPatch(current, partial) {
    var existing = current && typeof current === "object" ? current : ({})
    var update = partial && typeof partial === "object" ? partial : ({})
    var merged = ({})
    var key
    for (key in existing) merged[key] = existing[key]
    for (key in update) merged[key] = update[key]
    if (update.offsets) {
      merged.offsets = ({})
      var existingOffsets = existing.offsets && typeof existing.offsets === "object"
        ? existing.offsets
        : ({})
      for (key in existingOffsets) merged.offsets[key] = existingOffsets[key]
      for (key in update.offsets) merged.offsets[key] = update.offsets[key]
    }
    return merged
  }

  function applySettingsText(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (error) {
      root.settingsError = "Invalid saved prayer settings"
      return
    }

    var previousKey = root.backendConfigurationKey(root.configuration)
    var next = PrayerLogic.sanitizeSettings(parsed)
    if (root.savingSettingsPayload)
      next = PrayerLogic.mergeSettings(next, root.savingSettingsPatch)
    if (root.pendingSettingsPayload)
      next = PrayerLogic.mergeSettings(next, root.pendingSettingsPatch)
    if (JSON.stringify(next) === JSON.stringify(root.configuration)) return

    root.configuration = next
    if (root.settingsReady
        && previousKey !== root.backendConfigurationKey(root.configuration))
      settingsRefreshTimer.restart()
  }

  function finishRefresh() {
    root.refreshing = false
    if (!root.refreshQueued) return
    root.refreshQueued = false
    Qt.callLater(root.refresh)
  }

  function refresh(forceLocation) {
    if (forceLocation === true) root.locationRefreshRequested = true
    if (!root.settingsReady) return
    if (root.refreshing) {
      root.refreshQueued = true
      return
    }
    root.refreshing = true
    var args = root.backendArguments()
    if (root.locationRefreshRequested && root.configuration.locationMode !== "manual") {
      args.push("--refresh-location")
      root.locationRefreshRequested = false
    }
    prayerProcess.exec(args)
  }

  function updateSettings(partial, refetch) {
    root.configuration = PrayerLogic.mergeSettings(root.configuration, partial)
    root.pendingSettingsPatch = root.mergeSettingsPatch(
      root.pendingSettingsPatch, partial
    )
    root.pendingSettingsPayload = JSON.stringify(root.pendingSettingsPatch)
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
    root.locationRefreshRequested = true
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

  function cycleVerticalTextMode() {
    root.updateSettings({
      verticalTextMode: PrayerLogic.nextVerticalTextMode(root.verticalTextMode)
    }, false)
  }

  function beginSettingsSave() {
    if (!root.pendingSettingsPayload || settingsSaveProcess.running) return
    root.savingSettingsPatch = root.pendingSettingsPatch
    root.savingSettingsPayload = root.pendingSettingsPayload
    root.pendingSettingsPatch = ({})
    root.pendingSettingsPayload = ""
    root.settingsSaving = true
    settingsSaveProcess.exec([
      root.pluginPath("prayer-times-json"),
      "--patch-settings", root.savingSettingsPayload
    ])
  }

  Component.onCompleted: {
    settingsReadProcess.exec([root.pluginPath("prayer-times-json"), "--read-settings"])
  }

  FileView {
    id: settingsFile
    path: root.settingsReady ? root.settingsPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettingsText(text())
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      var nowMs = Date.now()
      var woke = PrayerLogic.clockJumped(root.previousTickMs, nowMs)
      root.previousTickMs = nowMs
      root.recompute()
      var expiry = Date.parse(root.dateEndsAt)
      if (!root.refreshing
          && isFinite(expiry)
          && nowMs >= expiry
          && root.rolloverRefreshAttempted !== root.dateEndsAt) {
        root.rolloverRefreshAttempted = root.dateEndsAt
        root.refresh()
      } else if (woke) {
        // Timers use a monotonic clock that stops during suspend; a wall-clock
        // jump means we likely woke up, possibly somewhere else.
        root.refresh()
      }
    }
  }

  Timer {
    interval: 60 * 60 * 1000
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
      if (exitCode === 0)
        root.applySettingsText(settingsOutput.text.trim() || "{}")
      else
        root.settingsError = settingsReadError.text.trim() || "Unable to read prayer settings"
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
      if (exitCode !== 0) {
        root.settingsError = settingsWriteError.text.trim() || "Unable to save prayer settings"
        root.pendingSettingsPatch = root.mergeSettingsPatch(
          root.savingSettingsPatch, root.pendingSettingsPatch
        )
        root.pendingSettingsPayload = JSON.stringify(root.pendingSettingsPatch)
      } else {
        root.settingsError = ""
      }
      root.savingSettingsPatch = ({})
      root.savingSettingsPayload = ""
      if (exitCode === 0 && root.pendingSettingsPayload)
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
      if (exitCode !== 0) {
        root.handleFailure(prayerError.text.trim() || "Prayer backend failed")
        root.finishRefresh()
        return
      }

      var payload
      try {
        payload = JSON.parse(prayerOutput.text.trim() || "{}")
      } catch (error) {
        root.handleFailure("Invalid prayer JSON")
        root.finishRefresh()
        return
      }

      root.times = payload.times || []
      root.tomorrow = payload.tomorrow || null
      root.date = payload.date || ""
      root.dateEndsAt = payload.dateEndsAt || ""
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
      root.finishRefresh()
    }
  }
}
