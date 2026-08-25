import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.moneytosms.ssh-dock"
  ipcTarget: "io.github.moneytosms.ssh-dock"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: {
    var p = Qt.resolvedUrl("omarchy-ssh-dock-helper").toString()
    return p.replace(/^file:\/\//, "")
  }

  property var state: ({ servers: [], sessions: [] })
  readonly property var servers: state && Array.isArray(state.servers) ? state.servers : []
  readonly property var sessions: state && Array.isArray(state.sessions) ? state.sessions : []
  readonly property int sessionCount: sessions.length
  readonly property color statusColor: sessionCount > 0 ? Color.accent : foreground
  readonly property string barText: sessionCount > 0 ? " " + sessionCount : " "

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (stateProcess.running) return
    stateProcess.command = [helperPath]
    stateProcess.running = true
  }

  function parseState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object" && parsed.state === "ok") state = parsed
    } catch (e) {
      console.warn("io.github.moneytosms.ssh-dock: invalid helper output", e)
    }
  }

  function hasSession(entry) {
    var needle = String((entry && (entry.host || entry.alias)) || "").toLowerCase()
    if (needle === "") return false
    for (var i = 0; i < sessions.length; i++) {
      var s = String(sessions[i] || "").toLowerCase()
      if (s === needle || s.endsWith("@" + needle) || s.indexOf(needle) !== -1) return true
    }
    return false
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: stateProcess
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("io.github.moneytosms.ssh-dock: helper exited", exitCode)
    }
  }

  Timer {
    interval: Math.max(5, parseInt(String(root.setting("pollIntervalSec", 15)), 10) || 15) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.sessionCount > 0
    activeColor: root.statusColor
    fontSize: Style.font.bodySmall
    horizontalMargin: 3.5
    tooltipText: ""

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }

      Flickable {
        id: serverFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: serverFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "SSH Dock"
            meta: root.servers.length > 0 ? ("SERVERS · " + root.servers.length) : "NO SERVERS"
            detail: root.sessionCount > 0 ? root.sessionCount + " active session" + (root.sessionCount === 1 ? "" : "s") : "Ready to connect"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: ""
                color: root.statusColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator {
            visible: root.servers.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.servers.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              width: parent.width
              text: "SERVERS  ·  " + root.servers.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.servers

              ServerRow {
                width: parent ? parent.width : 0
                entry: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: root.servers.length === 0
            width: parent.width
            text: "No hosts found in ~/.ssh/config"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(24)
            bottomPadding: Style.space(24)
          }
        }
      }
    }
  }

  component ServerRow: Column {
    id: serverRow
    property var entry: ({})
    property int rowIndex: 0

    readonly property bool connected: root.hasSession(serverRow.entry)
    readonly property string alias: String(serverRow.entry.alias || "?")
    readonly property string hostLabel: String(serverRow.entry.user || "") + (serverRow.entry.user ? "@" : "") + String(serverRow.entry.host || "")

    spacing: Style.space(8)

    PanelSeparator {
      visible: serverRow.rowIndex > 0
      foreground: root.foreground
      strength: 0.07
    }

    Item {
      width: serverRow.width
      implicitHeight: Math.max(rowDot.implicitHeight, rowLabels.implicitHeight)

      Rectangle {
        id: rowDot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: width
        radius: width / 2
        color: serverRow.connected ? Color.accent : root.dim
      }

      Column {
        id: rowLabels
        anchors.left: rowDot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: serverRow.alias
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: serverRow.connected
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: serverRow.hostLabel + (serverRow.entry.port && serverRow.entry.port !== 22 ? ":" + serverRow.entry.port : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
