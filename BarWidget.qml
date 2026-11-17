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

  // A left or right bar is only an icon wide, so the status stacks one short
  // row per icon slot instead, as the clock does there.
  readonly property var verticalLines: root.vertical ? prayer.verticalLines : []
  readonly property bool verticalIconOnly: root.vertical && prayer.verticalTextMode === "icon"
  readonly property bool verticalStack: root.vertical && !root.verticalIconOnly
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

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
    if (root.vertical) prayer.cycleVerticalTextMode()
    else prayer.cycleTextMode()
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
    // Icon-only on a vertical bar hands the bare glyph to the button, whose
    // own icon path sizes and centers it like any other bar icon.
    text: root.verticalStack ? "" : (root.verticalIconOnly ? (root.verticalLines[0] || "") : root.statusText)
    labelVisible: !root.verticalStack
    hasVisualContent: root.verticalStack ? root.verticalLines.length > 0 : button.text !== ""
    fixedHeight: root.verticalStack ? root.verticalLines.length * Style.bar.iconSlot : -1
    active: prayer.withinFlash || prayer.state === "error"
    tooltipText: root.vertical ? prayer.verticalTooltipText : prayer.tooltipText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
      else if (buttonCode === Qt.RightButton) root.cycleTextMode()
      else if (buttonCode === Qt.MiddleButton) prayer.refresh(true)
    }

    Column {
      visible: root.verticalStack
      anchors.fill: parent
      scale: button.pressScale

      Repeater {
        model: root.verticalStack ? root.verticalLines : []

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          // The crescent row is drawn as a bar icon, the text rows as text.
          paintedSize: button.isIconGlyph(modelData) ? Style.bar.iconSize : 0
          color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        }
      }
    }
  }
}
