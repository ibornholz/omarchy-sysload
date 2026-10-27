import QtQuick
import qs.Commons
import qs.Ui

// Bar pill showing CPU (and optionally memory) percent. Click opens the
// detail panel; middle click refreshes; right click launches btop directly.
BarWidget {
  id: root
  moduleName: "ibornholz.sysload"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property var stats: panelLoader.item ? panelLoader.item.stats : null
  readonly property bool showMemory: setting("showMemory", true) === true
  readonly property real warnAt: Number(setting("warnAt", 85)) || 85
  readonly property string cpuText: stats ? Math.round(stats.cpu) + "%" : "–"
  readonly property string memText: stats && stats.mem ? Math.round(stats.mem.pct) + "%" : "–"
  readonly property bool hot: !!stats && (stats.cpu >= warnAt || (stats.mem && stats.mem.pct >= warnAt))

  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    text: root.vertical
      ? "󰻠"
      : ("󰻠 " + root.cpuText + (root.showMemory ? "  󰍛 " + root.memText : ""))
    active: root.hot
    horizontalMargin: 8.75
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-launch-or-focus-tui btop")
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
