import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// btop-style detail popup: CPU / memory / swap / disk meters, network
// throughput, and the top processes with a one-click SIGTERM.
Panel {
  id: root
  moduleName: "ibornholz.sysload"
  ipcTarget: "ibornholz.sysload"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var stats: null
  property string sortBy: "cpu"
  property int cursor: -1

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real warnAt: Number(setting("warnAt", 85)) || 85
  readonly property int intervalMs: Math.max(1, Number(setting("interval", 3)) || 3) * 1000
  readonly property string scriptPath: String(Qt.resolvedUrl("sysload-stats")).replace(/^file:\/\//, "")
  readonly property var rows: stats ? (sortBy === "cpu" ? (stats.topCpu || []) : (stats.topMem || [])) : []

  function open() {
    root.controller.show()
    root.cursor = -1
    root.refresh()
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function killPid(pid) {
    if (!pid || killProc.running) return
    killProc.command = ["kill", "-TERM", String(pid)]
    killProc.running = true
  }

  function openBtop() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  function fmtBytes(b) {
    b = Number(b) || 0
    if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GiB"
    if (b >= 1048576) return Math.round(b / 1048576) + " MiB"
    if (b >= 1024) return Math.round(b / 1024) + " KiB"
    return Math.round(b) + " B"
  }

  function fmtRate(b) {
    b = Number(b) || 0
    if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
    if (b >= 1024) return Math.round(b / 1024) + " kB/s"
    return Math.round(b) + " B/s"
  }

  function fmtPct(p) { return Math.round(Number(p) || 0) + "%" }

  function moveCursor(delta) {
    if (rows.length === 0) { cursor = -1; return }
    if (cursor < 0) { cursor = delta > 0 ? 0 : rows.length - 1; return }
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta))
  }

  Process {
    id: statsProc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || ""))
          if (parsed && typeof parsed.cpu === "number") root.stats = parsed
        } catch (e) {}
      }
    }
  }

  Process {
    id: killProc
    onExited: killRefresh.restart()
  }

  Timer {
    id: killRefresh
    interval: 500
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.opened ? Math.min(root.intervalMs, 2000) : root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.sortBy = dx > 0 ? "mem" : "cpu"
      }
      onReturnRequested: root.openBtop()
      onDeleteRequested: if (root.cursor >= 0 && root.cursor < root.rows.length) root.killPid(root.rows[root.cursor].pid)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: icon · title/meta · CPU percent ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: "󰻠"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "System"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.stats
                ? ("UP " + root.stats.uptime + " · LOAD " + root.stats.load.map(function(x) { return Number(x).toFixed(2) }).join(" ")).toUpperCase()
                : "COLLECTING…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.stats ? root.fmtPct(root.stats.cpu) : "—"
            color: root.stats && root.stats.cpu >= root.warnAt ? root.urgent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Meters ----------
        Meter {
          label: "CPU"
          detail: root.stats
            ? (root.stats.cores + " cores" + (root.stats.temp !== null && root.stats.temp !== undefined ? " · " + root.stats.temp + "°C" : ""))
            : ""
          pct: root.stats ? root.stats.cpu : 0
        }

        Meter {
          label: "MEMORY"
          detail: root.stats ? root.fmtBytes(root.stats.mem.used) + " / " + root.fmtBytes(root.stats.mem.total) : ""
          pct: root.stats ? root.stats.mem.pct : 0
        }

        Meter {
          visible: !!root.stats && root.stats.swap.total > 0
          label: "SWAP"
          detail: root.stats ? root.fmtBytes(root.stats.swap.used) + " / " + root.fmtBytes(root.stats.swap.total) : ""
          pct: root.stats ? root.stats.swap.pct : 0
        }

        Meter {
          label: "DISK  /"
          detail: root.stats ? root.fmtBytes(root.stats.disk.used) + " / " + root.fmtBytes(root.stats.disk.total) : ""
          pct: root.stats ? root.stats.disk.pct : 0
        }

        // ---------- Network ----------
        Row {
          width: parent.width
          spacing: Style.space(20)

          Row {
            spacing: Style.space(6)
            Text { text: "󰇚"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Text {
              textFormat: Text.PlainText
              text: root.stats ? root.fmtRate(root.stats.net.rx) : "—"
              color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
          }
          Row {
            spacing: Style.space(6)
            Text { text: "󰕒"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Text {
              textFormat: Text.PlainText
              text: root.stats ? root.fmtRate(root.stats.net.tx) : "—"
              color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Top processes ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(procHeader.implicitHeight, sortRow.implicitHeight)

          PanelSectionHeader {
            id: procHeader
            text: root.stats ? "TOP PROCESSES · " + root.stats.procs + " TOTAL" : "TOP PROCESSES"
            foreground: root.fg
            fontFamily: root.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            id: sortRow
            spacing: Style.space(4)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Button {
              text: "CPU"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              active: root.sortBy === "cpu"
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(2)
              onClicked: root.sortBy = "cpu"
            }
            Button {
              text: "MEM"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              active: root.sortBy === "mem"
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(2)
              onClicked: root.sortBy = "mem"
            }
          }
        }

        Column {
          width: parent.width
          spacing: 0

          Repeater {
            model: root.rows

            Rectangle {
              id: procRow
              required property var modelData
              required property int index
              readonly property bool hot: rowArea.containsMouse || root.cursor === index

              width: parent.width
              height: Style.spacing.popupRowHeight
              radius: Style.cornerRadius
              color: hot ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: root.cursor = procRow.index
              }

              Text {
                id: nameText
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: pidText.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.modelData.name
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width - pidText.implicitWidth - cpuText.width - memText.width - killButton.width - Style.space(40))
              }

              Text {
                id: pidText
                textFormat: Text.PlainText
                anchors.right: cpuText.left
                anchors.verticalCenter: parent.verticalCenter
                text: String(procRow.modelData.pid)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignLeft
                width: Style.space(60)
              }

              Text {
                id: cpuText
                textFormat: Text.PlainText
                anchors.right: memText.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtPct(procRow.modelData.cpu)
                color: root.sortBy === "cpu" ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignRight
                width: Style.space(48)
              }

              Text {
                id: memText
                textFormat: Text.PlainText
                anchors.right: killButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtBytes(procRow.modelData.mem)
                color: root.sortBy === "mem" ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignRight
                width: Style.space(68)
              }

              PanelActionButton {
                id: killButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "✕"
                tooltipText: "End process (SIGTERM)"
                foreground: root.fg
                hoverColor: root.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                opacity: procRow.hot ? 1 : 0.35
                onClicked: root.killPid(procRow.modelData.pid)
              }
            }
          }
        }

        // ---------- Footer ----------
        Button {
          width: parent.width
          iconText: ""
          text: "Open btop"
          fontSize: Style.font.bodySmall
          foreground: root.fg
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openBtop()
        }
      }
    }
  }

  // Label row plus a thin progress track. Turns urgent past warnAt.
  component Meter: Column {
    property string label: ""
    property string detail: ""
    property real pct: 0
    readonly property bool hot: pct >= root.warnAt

    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(meterLabel.implicitHeight, meterDetail.implicitHeight)

      Text {
        id: meterLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }

      Text {
        id: meterDetail
        textFormat: Text.PlainText
        anchors.right: meterPct.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: meterPct
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.fmtPct(pct)
        color: hot ? root.urgent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        horizontalAlignment: Text.AlignRight
        width: Style.space(36)
      }
    }

    Item {
      width: parent.width
      implicitHeight: Style.space(6)

      Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      }

      Rectangle {
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        height: track.height
        radius: track.radius
        color: hot ? root.urgent : root.fg
        width: Math.max(track.height, track.width * Math.max(0, Math.min(1, pct / 100)))
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 220 } }
      }
    }
  }
}
