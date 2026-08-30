import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Io
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property var prayer: null
  property bool active: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var locationSuggestions: []
  property string pendingLocationQuery: ""
  property string activeLocationQuery: ""
  property bool locationSearching: false
  readonly property bool blocksPanelKeys: locationField.activeFocus
    || methodPicker.popupOpen
    || schoolPicker.popupOpen
    || highLatitudePicker.popupOpen
    || textModePicker.popupOpen

  function locationDisplayName(entry) {
    if (!entry) return ""
    var parts = [String(entry.name || "")]
    if (entry.admin1 && entry.admin1 !== entry.name) parts.push(String(entry.admin1))
    if (entry.country) parts.push(String(entry.country))
    return parts.filter(function(part) { return part !== "" }).join(", ")
  }

  function requestLocations() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      root.locationSuggestions = []
      return
    }
    root.pendingLocationQuery = query
    if (!geocodeProcess.running) root.startLocationSearch()
  }

  function startLocationSearch() {
    root.activeLocationQuery = root.pendingLocationQuery
    root.locationSearching = true
    geocodeProcess.command = [
      "curl", "-fsS", "--max-time", "6",
      "https://geocoding-api.open-meteo.com/v1/search?name="
        + encodeURIComponent(root.activeLocationQuery)
        + "&count=5&language=en&format=json"
    ]
    geocodeProcess.running = true
  }

  function selectLocation(entry) {
    if (!entry || !root.prayer) return
    var name = root.locationDisplayName(entry)
    root.prayer.setManualLocation(
      name,
      Number(entry.latitude),
      Number(entry.longitude),
      String(entry.timezone || "")
    )
    locationField.text = name
    root.locationSuggestions = []
  }

  function useAutomaticLocation() {
    if (!root.prayer) return
    root.prayer.useAutomaticLocation()
    locationField.text = ""
    root.locationSuggestions = []
  }

  onActiveChanged: {
    if (!active || !prayer) return
    locationField.text = prayer.configuration.locationMode === "manual"
      ? String(prayer.configuration.locationName || "")
      : ""
    locationSuggestions = []
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    repeat: false
    onTriggered: root.requestLocations()
  }

  Process {
    id: geocodeProcess

    stdout: StdioCollector {
      id: geocodeOutput
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.locationSearching = false
      var suggestions = []
      if (exitCode === 0) {
        try {
          var payload = JSON.parse(geocodeOutput.text.trim() || "{}")
          suggestions = payload.results && Array.isArray(payload.results)
            ? payload.results
            : []
        } catch (error) {
          suggestions = []
        }
      }
      root.locationSuggestions = root.active ? suggestions : []
      if (root.pendingLocationQuery !== root.activeLocationQuery)
        Qt.callLater(root.startLocationSearch)
    }
  }

  Flickable {
    id: settingsScroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    QQC.ScrollBar.vertical: QQC.ScrollBar {
      policy: settingsScroll.contentHeight > settingsScroll.height
        ? QQC.ScrollBar.AsNeeded
        : QQC.ScrollBar.AlwaysOff
    }

    Column {
      id: settingsColumn
      width: settingsScroll.width - (settingsScroll.contentHeight > settingsScroll.height ? Style.space(12) : 0)
      spacing: Style.space(10)

      PanelSectionHeader {
        width: parent.width
        text: "LOCATION"
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: locationField
          width: parent.width - autoLocationButton.width - parent.spacing
          placeholderText: "Search city"
          foreground: root.foreground
          font.family: root.fontFamily
          onTextChanged: if (activeFocus) geocodeDebounce.restart()
          onAccepted: {
            if (root.locationSuggestions.length > 0)
              root.selectLocation(root.locationSuggestions[0])
          }
        }

        Button {
          id: autoLocationButton
          text: "AUTO"
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          selected: root.prayer && root.prayer.configuration.locationMode === "auto"
          onClicked: root.useAutomaticLocation()
        }
      }

      Text {
        width: parent.width
        text: root.prayer && root.prayer.configuration.locationMode === "auto"
          ? "Automatic: " + (root.prayer.locationLabel || "detecting location…")
          : "Selected: " + (root.prayer ? root.prayer.configuration.locationName : "")
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.locationSuggestions.length > 0

        Repeater {
          model: root.locationSuggestions

          delegate: Button {
            required property var modelData
            width: settingsColumn.width
            text: root.locationDisplayName(modelData)
            leftAlign: true
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.selectLocation(modelData)
          }
        }
      }

      Text {
        width: parent.width
        visible: root.locationSearching && root.locationSuggestions.length === 0
        text: "Searching locations…"
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        width: parent.width
        text: "CALCULATION"
      }

      SearchableDropdown {
        id: methodPicker
        width: parent.width
        label: "Method"
        placeholderText: "Search calculation methods"
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: root.prayer ? root.prayer.methodOptions : []
        value: root.prayer ? String(root.prayer.configuration.method) : "4"
        onChanged: function(value) {
          if (root.prayer) root.prayer.updateSettings({ method: Number(value) }, true)
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(10)

        Dropdown {
          id: schoolPicker
          width: (parent.width - parent.spacing) / 2
          label: "Asr school"
          foreground: root.foreground
          fontFamily: root.fontFamily
          options: root.prayer ? root.prayer.schoolOptions : []
          value: root.prayer ? String(root.prayer.configuration.school) : "0"
          onChanged: function(value) {
            if (root.prayer) root.prayer.updateSettings({ school: Number(value) }, true)
          }
        }

        Dropdown {
          id: highLatitudePicker
          width: (parent.width - parent.spacing) / 2
          label: "High-latitude rule"
          foreground: root.foreground
          fontFamily: root.fontFamily
          options: root.prayer ? root.prayer.highLatitudeOptions : []
          value: root.prayer ? String(root.prayer.configuration.highLatitude) : "0"
          onChanged: function(value) {
            if (root.prayer) root.prayer.updateSettings({ highLatitude: Number(value) }, true)
          }
        }
      }

      Toggle {
        width: parent.width
        label: "Ramadan Isha adjustment"
        description: "Use Maghrib +120 minutes during Ramadan with Umm Al-Qura."
        foreground: root.foreground
        fontFamily: root.fontFamily
        checked: root.prayer ? root.prayer.configuration.ramadanIsha : true
        onClicked: if (root.prayer) root.prayer.updateSettings({ ramadanIsha: !checked }, true)
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        width: parent.width
        text: "BAR DISPLAY"
      }

      Dropdown {
        id: textModePicker
        width: parent.width
        label: "Text"
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: root.prayer ? root.prayer.textModeOptions : []
        value: root.prayer ? root.prayer.textMode : "initial-time"
        onChanged: function(value) {
          if (root.prayer) root.prayer.updateSettings({ textMode: value }, false)
        }
      }

      Toggle {
        width: parent.width
        label: "Show crescent icon"
        description: "Place the prayer icon before the selected text."
        foreground: root.foreground
        fontFamily: root.fontFamily
        checked: root.prayer ? root.prayer.showIcon : false
        onClicked: if (root.prayer) root.prayer.updateSettings({ showIcon: !checked }, false)
      }

      Text {
        width: parent.width
        text: "Preview: " + (root.prayer ? root.prayer.displayText : "")
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        width: parent.width
        text: "DATE AND PRAYER OFFSETS"
      }

      NumberField {
        width: Style.space(130)
        fieldWidth: width
        label: "Hijri days"
        from: -2
        to: 2
        value: root.prayer ? root.prayer.configuration.hijriAdjustment : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(value) {
          if (root.prayer) root.prayer.updateSettings({ hijriAdjustment: value }, true)
        }
      }

      Grid {
        id: offsetGrid
        width: parent.width
        columns: 3
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(10)

        Repeater {
          model: [
            { key: "fajr", label: "Fajr min" },
            { key: "sunrise", label: "Sunrise min" },
            { key: "dhuhr", label: "Dhuhr min" },
            { key: "asr", label: "Asr min" },
            { key: "maghrib", label: "Maghrib min" },
            { key: "isha", label: "Isha min" }
          ]

          delegate: NumberField {
            required property var modelData
            width: (offsetGrid.width - offsetGrid.columnSpacing * 2) / 3
            fieldWidth: width
            label: modelData.label
            from: -15
            to: 15
            value: root.prayer ? root.prayer.configuration.offsets[modelData.key] : 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            onModified: function(value) {
              if (root.prayer) root.prayer.updateOffset(modelData.key, value)
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.prayer && (root.prayer.settingsSaving || root.prayer.settingsError !== "")
        text: root.prayer && root.prayer.settingsError
          ? root.prayer.settingsError
          : "Saving settings…"
        color: root.prayer && root.prayer.settingsError ? Color.urgent : Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item {
        width: 1
        height: Style.space(4)
      }
    }
  }
}
