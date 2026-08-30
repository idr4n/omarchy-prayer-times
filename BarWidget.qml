import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.idr4n.prayer-times"

  readonly property string statusText: {
    var parts = []
    if (prayer.showIcon) parts.push(String.fromCodePoint(0xF0979))  // nf-md-star-crescent
    if (prayer.displayText) parts.push(prayer.displayText)
    return parts.join(" ")
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("prayer" in target) target.prayer = prayer
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function openSettings() {
    if (panelLoader.item) panelLoader.item.openSettings()
  }

  function cycleTextMode() {
    prayer.cycleTextMode()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  PrayerService {
    id: prayer
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.statusText
    active: prayer.withinFlash || prayer.state === "error"
    tooltipText: prayer.locationLabel
      ? "Prayer Times · " + prayer.locationLabel + " · Right-click to change format"
      : "Prayer Times · Right-click to change format"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
      else if (buttonCode === Qt.RightButton) root.cycleTextMode()
      else if (buttonCode === Qt.MiddleButton) prayer.refresh()
    }
  }
}
