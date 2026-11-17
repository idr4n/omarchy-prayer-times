import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.idr4n.prayer-times"
  ipcTarget: "io.github.idr4n.prayer-times"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var prayer: null
  property bool showSettings: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string prayerState: prayer ? prayer.state : "loading"
  readonly property var prayerTimes: prayer && prayer.times ? prayer.times : []
  readonly property string viewState: !prayer || prayerState === "loading"
    ? "loading"
    : prayerState === "error"
      ? "error"
      : prayerTimes.length === 0 ? "empty" : "ok"

  function open(settingsRequested) {
    root.controller.show()
    Qt.callLater(function() {
      if (!root.opened) return
      if (settingsRequested === true) root.showSettings = true
      root.setCenterHoverRevealSuppressed(true)
    })
  }
  function openSettings() {
    root.open(true)
  }


  function close() {
    root.showSettings = false
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function refresh() {
    if (root.prayer) root.prayer.refresh(true)
  }

  function formatCountdown(seconds) {
    if (seconds === undefined || seconds === null || seconds < 0) return "--:--:--"
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    var remaining = Math.floor(seconds % 60)
    function pad(value) { return value < 10 ? "0" + value : String(value) }
    return pad(hours) + ":" + pad(minutes) + ":" + pad(remaining)
  }

  function isNextRow(entry) {
    return !!(prayer && entry && entry.isPrayer && prayer.secondsToNext >= 0 && entry.name === prayer.nextName)
  }

  function isCurrentRow(entry) {
    return !!(prayer && entry && entry.isPrayer && prayer.withinElapsed && entry.name === prayer.currentName)
  }

  function isPastRow(entry) {
    if (!entry) return false
    var milliseconds = Date.parse(entry.iso)
    return !isNaN(milliseconds) && milliseconds < Date.now()
  }

  function rowColor(entry) {
    if (!entry) return root.contentForeground
    if (!entry.isPrayer) return Util.alpha(root.contentForeground, 0.48)
    if (root.isCurrentRow(entry)) return Color.accent
    if (root.isNextRow(entry)) return Color.urgent
    if (root.isPastRow(entry)) return Util.alpha(root.contentForeground, 0.5)
    return root.contentForeground
  }

  function footerLocationText() {
    if (!prayer) return ""
    var parts = []
    if (prayer.locationLabel) parts.push(prayer.locationLabel)
    if (prayer.methodName) parts.push(prayer.methodName)
    return parts.join(" · ")
  }

  function freshnessText() {
    if (!prayer) return ""
    if (prayerState === "stale") return "STALE"
    if (prayer.fromCache) return "CACHED"
    return ""
  }

  TextMetrics {
    id: countdownMetrics
    text: "00:00:00"
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.display
    font.bold: true
  }

  TextMetrics {
    id: prayerTimeMetrics
    text: "00:00"
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.title
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false  // Follow the widget as it moves between bar positions.
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(root.showSettings
      ? Style.space(500)
      : root.viewState === "ok" ? prayerColumn.implicitHeight : Style.space(300))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.showSettings && settingsView.blocksPanelKeys
      onCloseRequested: {
        if (root.showSettings) root.showSettings = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (!root.showSettings) root.refresh()
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "s" || text === "S") root.showSettings = !root.showSettings
      }

      Column {
        id: prayerColumn
        anchors.fill: parent
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(34)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0979) + (root.showSettings ? "  PRAYER SETTINGS" : "  PRAYER TIMES")  // nf-md-star-crescent
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.showSettings ? String.fromCodePoint(0xF004D) : String.fromCodePoint(0xF0493)
            tooltipText: root.showSettings ? "Back to prayer times" : "Prayer settings"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            focusable: true
            onClicked: root.showSettings = !root.showSettings
          }

          Text {
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.showSettings
            text: root.prayer && root.prayer.dateText ? root.prayer.dateText : ""
            color: Util.alpha(root.contentForeground, 0.62)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(86)
          radius: Style.cornerRadius
          color: Util.alpha(root.prayer && root.prayer.withinPre ? Color.urgent : Color.accent, 0.1)
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(root.prayer && root.prayer.withinPre ? Color.urgent : Color.accent, 0.45)
          visible: root.viewState === "ok" && !root.showSettings

          Item {
            anchors.fill: parent
            anchors.margins: Style.space(14)

            Column {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "NEXT"
                color: Util.alpha(root.contentForeground, 0.56)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                text: root.prayer && root.prayer.nextLabel ? root.prayer.nextLabel : "—"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                text: root.prayer && root.prayer.nextTime ? "Adhan " + root.prayer.nextTime : ""
                color: Util.alpha(root.contentForeground, 0.58)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: countdown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: countdownMetrics.width
              horizontalAlignment: Text.AlignRight
              text: root.formatCountdown(root.prayer ? root.prayer.secondsToNext : -1)
              color: root.prayer && root.prayer.withinPre ? Color.urgent : Color.accent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              renderType: Text.NativeRendering
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(22)
          visible: root.viewState === "ok" && !root.showSettings

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.prayer && root.prayer.withinElapsed
              ? root.prayer.currentLabel + " · +" + Math.floor(root.prayer.secondsSinceAdhan / 60) + "m since adhan"
              : ""
            color: Color.accent
            opacity: text ? 1 : 0
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: root.viewState === "ok" && !root.showSettings

          Repeater {
            model: root.prayerTimes

            delegate: Item {
              required property var modelData
              width: prayerColumn.width
              height: Style.space(34)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: root.isCurrentRow(modelData) ? Util.alpha(Color.accent, 0.12) : "transparent"
                border.width: root.isNextRow(modelData) ? Style.normalBorderWidth : 0
                border.color: root.isNextRow(modelData) ? Util.alpha(Color.urgent, 0.72) : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.rowColor(modelData)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: root.isNextRow(modelData) || root.isCurrentRow(modelData)
                font.italic: !modelData.isPrayer
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: prayerTimeMetrics.width
                horizontalAlignment: Text.AlignRight
                text: modelData.time
                color: root.rowColor(modelData)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: root.isNextRow(modelData) || root.isCurrentRow(modelData)
                renderType: Text.NativeRendering
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - y - footer.height
          visible: root.viewState !== "ok" && !root.showSettings

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            spacing: Style.space(8)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.viewState === "loading"
                ? "Loading prayer times…"
                : root.viewState === "error"
                  ? (root.prayer && root.prayer.errorText ? root.prayer.errorText : "Prayer data unavailable")
                  : "No prayer data"
              color: root.viewState === "error" ? Color.urgent : Util.alpha(root.contentForeground, 0.65)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Press R to refresh"
              visible: root.viewState === "error"
              color: Util.alpha(root.contentForeground, 0.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PrayerSettings {
          id: settingsView
          width: parent.width
          height: parent.height - y
          visible: root.showSettings
          active: root.showSettings
          prayer: root.prayer
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Item {
          id: footer
          width: parent.width
          height: Style.space(26)
          visible: !root.showSettings

          Text {
            anchors.left: parent.left
            anchors.right: freshness.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.footerLocationText()
            color: Util.alpha(root.contentForeground, 0.54)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: freshness
            anchors.right: refreshHint.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.freshnessText()
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            id: refreshHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "R REFRESH"
            color: Util.alpha(root.contentForeground, 0.42)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
