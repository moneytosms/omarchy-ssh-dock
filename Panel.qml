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
  manageIpc: false

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: {
    var p = Qt.resolvedUrl("omarchy-ssh-dock-helper").toString()
    return p.replace(/^file:\/\//, "")
  }
  readonly property string notificationsDir: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/notifications"

  property var state: ({ servers: [], sessions: [] })
  readonly property var servers: state && Array.isArray(state.servers) ? state.servers : []
  readonly property var sessions: state && Array.isArray(state.sessions) ? state.sessions : []
  readonly property int sessionCount: sessions.length
  readonly property color statusColor: sessionCount > 0 ? Color.accent : foreground
  readonly property string barText: sessionCount > 0 ? "" + sessionCount : ""

  // Persisted override/manual records (settings.serversJson).
  readonly property var persistedServers: parseServersJson(setting("serversJson", "[]"))

  // Alert state: alias -> { summary, body, ts }.
  property var alerts: ({})
  property int alertsRevision: 0
  property real lastAlertTs: 0
  readonly property int alertCount: Object.keys(alerts).length

  // Panel UI state.
  property string filterText: ""
  property bool addFormOpen: false
  property string editingAlias: ""
  property string statusMessage: ""

  readonly property var mergedServersList: mergedServers()
  readonly property int mergedCount: mergedServersList.length
  readonly property var filteredServers: filterServers(mergedServersList, filterText)

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: lastAlertTs = Date.now()

  // ------------------------------------------------------------------ data

  function parseServersJson(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }

  // Imported hosts first, then fold persisted records in as overrides keyed
  // by case-insensitive alias. Never mutates the imports.
  function mergedServers() {
    var records = persistedServers
    var out = []
    var seen = {}
    for (var i = 0; i < servers.length; i++) {
      var imp = servers[i] || {}
      var alias = String(imp.alias || "")
      if (alias === "") continue
      var rec = recordFor(records, alias)
      if (rec && rec.hidden === true) continue
      out.push({
        alias: alias,
        name: String(rec && rec.name ? rec.name : ""),
        host: String(rec && rec.host ? rec.host : (imp.host || alias)),
        user: String(rec && rec.user ? rec.user : (imp.user || "")),
        port: Number(rec && rec.port ? rec.port : (imp.port || 22)),
        mode: String(rec && rec.mode ? rec.mode : "default"),
        terminal: String(rec && rec.terminal ? rec.terminal : ""),
        glyph: String(rec && rec.glyph ? rec.glyph : ""),
        color: String(rec && rec.color ? rec.color : ""),
        keywords: rec && Array.isArray(rec.keywords) ? rec.keywords.slice() : [],
        hidden: false,
        manual: false
      })
      seen[alias.toLowerCase()] = true
    }
    for (var j = 0; j < records.length; j++) {
      var r = records[j]
      if (!r) continue
      var rAlias = String(r.alias || "")
      if (rAlias === "" || seen[rAlias.toLowerCase()] || r.hidden === true) continue
      out.push({
        alias: rAlias,
        name: String(r.name || ""),
        host: String(r.host || rAlias),
        user: String(r.user || ""),
        port: Number(r.port || 22),
        mode: String(r.mode || "default"),
        terminal: String(r.terminal || ""),
        glyph: String(r.glyph || ""),
        color: String(r.color || ""),
        keywords: Array.isArray(r.keywords) ? r.keywords.slice() : [],
        hidden: false,
        manual: true
      })
    }
    return out
  }

  function displayLabel(entry) {
    if (!entry) return ""
    var name = String(entry.name || "").trim()
    if (name !== "") return name
    var host = String(entry.host || "").trim()
    if (host !== "" && host !== entry.alias) return host
    var user = String(entry.user || "").trim()
    if (user !== "") return user
    return String(entry.alias || "")
  }

  function recordFor(records, alias) {
    var needle = String(alias || "").toLowerCase()
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      if (r && String(r.alias || "").toLowerCase() === needle) return r
    }
    return null
  }

  function recordIndexFor(records, alias) {
    var needle = String(alias || "").toLowerCase()
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      if (r && String(r.alias || "").toLowerCase() === needle) return i
    }
    return -1
  }

  function filterServers(list, query) {
    var q = String(query || "").toLowerCase()
    if (q === "") return list
    var out = []
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      var hay = (String(e.alias || "") + " " + String(e.name || "") + " " + String(e.host || "") + " " +
                 (Array.isArray(e.keywords) ? e.keywords.join(" ") : "")).toLowerCase()
      if (hay.indexOf(q) !== -1) out.push(e)
    }
    return out
  }

  // ------------------------------------------------------------ persistence

  function persistServers(records) {
    var next = Object.assign({}, root.settings)
    next.serversJson = JSON.stringify(records)

    // Local-first: instant feedback, shell write fans out to other instances.
    root.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function saveRecord(originalAlias, record) {
    var records = persistedServers.slice()
    var idx = recordIndexFor(records, originalAlias)
    if (idx >= 0) records[idx] = record
    else records.push(record)
    persistServers(records)
  }

  function removeRecord(alias) {
    var records = persistedServers.slice()
    var idx = recordIndexFor(records, alias)
    if (idx < 0) return false
    records.splice(idx, 1)
    persistServers(records)
    return true
  }

  function splitKeywords(text) {
    var parts = String(text || "").split(",")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var kw = parts[i].trim()
      if (kw !== "") out.push(kw)
    }
    return out
  }

  function joinKeywords(keywords) {
    return Array.isArray(keywords) ? keywords.join(", ") : ""
  }

  // --------------------------------------------------------- connect engine

  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    return v === true || v === "true"
  }

  function sanitizeSessionName(alias) {
    return String(alias || "").toLowerCase().replace(/[^a-z0-9_-]/g, "-")
  }

  function escapeRegExp(s) {
    return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  function entryTarget(entry) {
    var host = String(entry.host || "")
    var user = String(entry.user || "")
    return user !== "" ? user + "@" + host : host
  }

  function buildCommand(entry) {
    var target = entryTarget(entry)
    var portArgs = Number(entry.port || 22) !== 22 ? ["-p", String(Number(entry.port))] : []

    var mode = effectiveMode(entry)

    if (mode === "tmux") {
      var session = sanitizeSessionName(entry.alias)
      return ["ssh", "-t"].concat(portArgs, [target, "tmux attach || tmux new -s " + session])
    }
    if (mode === "herdr") return ["herdr", "--remote", target]
    if (mode === "custom") {
      var tpl = String(setting("customCommand", ""))
      var key = entry.key !== undefined && entry.key !== null ? String(entry.key) : ""
      return [tpl.replace(/\{alias\}/g, String(entry.alias))
                 .replace(/\{host\}/g, String(entry.host))
                 .replace(/\{user\}/g, String(entry.user))
                 .replace(/\{port\}/g, String(Number(entry.port || 22)))
                 .replace(/\{key\}/g, key)]
    }
    return ["ssh"].concat(portArgs, [target])
  }

  function effectiveMode(entry) {
    var mode = String((entry && entry.mode) || "")
    if (mode === "" || mode === "default") mode = String(setting("connectMode", "plain"))
    return mode
  }

  function terminalPrefix(entry) {
    var prefix = String((entry && entry.terminal) || "")
    if (prefix === "") prefix = String(setting("terminalCommand", ""))
    if (prefix === "") prefix = "omarchy-launch-terminal"
    return prefix
  }

  function renderCommand(entry, argv) {
    var parts = [terminalPrefix(entry)]
    for (var i = 0; i < argv.length; i++) parts.push(Util.shellQuote(argv[i]))
    return parts.join(" ")
  }

  function commandFor(entry) {
    // Custom templates are user-authored shell text: render raw so the
    // terminal receives normal words instead of one quoted blob.
    if (effectiveMode(entry) === "custom")
      return terminalPrefix(entry) + " " + buildCommand(entry)[0]
    return renderCommand(entry, buildCommand(entry))
  }

  function launch(entry) {
    if (!entry) return false
    var cmd = commandFor(entry)
    if (boolSetting("dryRun", false)) {
      console.warn("[ssh-dock] DRY RUN:", cmd)
      showStatus("DRY RUN: " + cmd)
      return false
    }
    Util.execDetached(cmd)
    return true
  }

  function connectEntry(entry) {
    if (!entry) return
    clearAlerts(String(entry.alias))
    if (launch(entry)) showStatus("Connected " + String(entry.alias))
  }

  function findByAlias(alias) {
    var needle = String(alias || "").toLowerCase()
    if (needle === "") return null
    var list = mergedServersList
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].alias || "").toLowerCase() === needle) return list[i]
    }
    return null
  }

  // ----------------------------------------------------------- inventory

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

  // -------------------------------------------------------------- alerts

  function scanAlerts() {
    if (alertProcess.running) return
    alertProcess.command = [helperPath, "alerts", String(Math.floor(lastAlertTs))]
    alertProcess.running = true
  }

  function wordHit(haystack, needle) {
    var n = String(needle || "").trim().toLowerCase()
    if (n === "") return false
    try {
      return new RegExp("\\b" + escapeRegExp(n) + "\\b").test(haystack)
    } catch (e) {
      return haystack.indexOf(n) !== -1
    }
  }

  function matchesServer(matchText, server) {
    if (wordHit(matchText, String(server.alias || ""))) return true
    var kws = Array.isArray(server.keywords) ? server.keywords : []
    for (var i = 0; i < kws.length; i++) {
      if (wordHit(matchText, String(kws[i]))) return true
    }
    return false
  }

  function parseAlerts(raw) {
    var records = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) records = parsed
    } catch (e) {
      return
    }
    if (records.length === 0) return

    var list = mergedServersList
    var hits = {}
    var maxTs = lastAlertTs
    for (var i = 0; i < records.length; i++) {
      var rec = records[i] || {}
      var ts = Number(rec.ts || 0)
      if (ts > maxTs) maxTs = ts
      var matchText = (String(rec.app || "") + " " + String(rec.summary || "") + " " +
                       String(rec.body || "")).toLowerCase()
      for (var j = 0; j < list.length; j++) {
        if (matchesServer(matchText, list[j])) {
          hits[String(list[j].alias)] = {
            summary: String(rec.summary || ""),
            body: String(rec.body || ""),
            ts: ts
          }
        }
      }
    }
    lastAlertTs = maxTs
    var hitKeys = Object.keys(hits)
    if (hitKeys.length === 0) return
    alerts = Object.assign({}, alerts, hits)
    alertsRevision++
  }

  function clearAlerts(aliasOrAll) {
    var which = String(aliasOrAll || "all").toLowerCase()
    var next = {}
    var had = false
    for (var k in alerts) {
      if (which !== "all" && k.toLowerCase() !== which) next[k] = alerts[k]
      else had = true
    }
    if (!had) return
    alerts = next
    alertsRevision++
  }

  function alertFor(alias) {
    return alerts[String(alias || "")]
  }

  // -------------------------------------------------------------- status

  function showStatus(message) {
    statusMessage = String(message || "")
    statusTimer.restart()
  }

  function entryColor(entry) {
    var c = String((entry && entry.color) || "")
    if (c === "") return Color.accent
    try {
      return Qt.color(c)
    } catch (e) {
      return Color.accent
    }
  }

  function focusFilter() {
    if (mergedCount === 0) return
    Qt.callLater(function() { if (opened) filterField.forceActiveFocus() })
  }

  function submitNewServer() {
    var alias = addAliasField.text.trim()
    if (alias === "") {
      showStatus("Alias required")
      return
    }
    if (findByAlias(alias)) {
      showStatus("Alias already exists: " + alias)
      return
    }
    persistServers(persistedServers.concat([{
      alias: alias,
      host: addHostField.text.trim(),
      user: addUserField.text.trim(),
      port: parseInt(addPortField.text.trim(), 10) || 22,
      mode: "default",
      terminal: "",
      color: "",
      glyph: "",
      keywords: [],
      hidden: false
    }]))
    addAliasField.text = ""
    addHostField.text = ""
    addUserField.text = ""
    addPortField.text = "22"
    addFormOpen = false
    showStatus("Added " + alias)
  }

  onOpenedChanged: if (opened) {
    refresh()
    clearAlerts("all")
    filterField.text = ""
    focusFilter()
  }

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

  Process {
    id: alertProcess
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseAlerts(text)
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("io.github.moneytosms.ssh-dock: alerts exited", exitCode)
    }
  }

  // Toast files land in this directory; the watcher + short debounce turns
  // each write batch into one alert scan.
  FileView {
    path: root.notificationsDir
    watchChanges: true
    printErrors: false
    onFileChanged: alertScanDelay.restart()
  }

  Timer {
    id: alertScanDelay
    interval: 300
    onTriggered: root.scanAlerts()
  }

  Timer {
    id: statusTimer
    interval: 4000
    onTriggered: root.statusMessage = ""
  }

  Timer {
    interval: Math.max(5, parseInt(String(root.setting("pollIntervalSec", 15)), 10) || 15) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function ping(): string { return "ok" }

    function pick(): string {
      root.open()
      root.focusFilter()
      return "ok"
    }

    function refresh(): string {
      root.refresh()
      return "ok"
    }

    function connect(alias: string): string {
      var entry = root.findByAlias(alias)
      if (!entry) return "unknown"
      root.connectEntry(entry)
      return "ok"
    }

    function echo(alias: string): string {
      var entry = root.findByAlias(alias)
      if (!entry) return "unknown"
      return root.commandFor(entry)
    }

    function clear(alias: string): string {
      root.clearAlerts(alias)
      return "ok"
    }

    function status(): string {
      var connected = []
      var alertsOut = {}
      for (var i = 0; i < root.mergedServersList.length; i++) {
        var entry = root.mergedServersList[i]
        var alias = String(entry.alias || "")
        if (root.hasSession(entry)) connected.push(alias)
        var alert = root.alertFor(alias)
        if (alert) alertsOut[alias] = { summary: alert.summary, ts: alert.ts }
      }
      return JSON.stringify({
        servers: root.mergedServersList.length,
        sessions: root.sessions,
        alerts: alertsOut,
        connected: connected,
        filterHint: "connect <alias>"
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.alertCount > 0 || root.sessionCount > 0
    activeColor: root.alertCount > 0 ? root.urgent : Color.accent
    fontSize: Style.font.bodySmall
    horizontalMargin: 3.5
    tooltipText: "SSH Dock"

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
      blocked: filterField.activeFocus || root.addFormOpen || root.editingAlias !== ""
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
            meta: root.mergedCount > 0 ? ("SERVERS · " + root.mergedCount) : "NO SERVERS"
            detail: root.sessionCount > 0 ? root.sessionCount + " active session" + (root.sessionCount === 1 ? "" : "s") : "Ready to connect"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: ""
                color: root.statusColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          TextField {
            id: filterField
            width: parent.width
            placeholderText: "Filter servers…"
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.filterText = text
            Keys.onEscapePressed: function(event) {
              if (text !== "") text = ""
              else keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }

          PanelSeparator {
            visible: true
            foreground: root.foreground
          }

          Item {
            width: parent.width
            height: Math.max(serversHeader.implicitHeight, addButton.height)

            PanelSectionHeader {
              id: serversHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "SERVERS  ·  " + root.mergedCount
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            PanelActionButton {
              id: addButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.addFormOpen ? "󰅖" : ""
              foreground: root.foreground
              hoverColor: Color.accent
              tooltipText: root.addFormOpen ? "Cancel" : "Add server"
              onClicked: root.addFormOpen = !root.addFormOpen
            }
          }

          Column {
            visible: root.addFormOpen
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: addAliasField
                width: (parent.width - parent.spacing) * 0.6
                placeholderText: "alias *"
                foreground: root.foreground
                font.family: root.fontFamily
                Keys.onEscapePressed: function(event) {
                  if (text !== "") text = ""
                  else keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              TextField {
                id: addPortField
                width: parent.width - parent.spacing - addAliasField.width
                placeholderText: "port"
                text: "22"
                foreground: root.foreground
                font.family: root.fontFamily
                Keys.onEscapePressed: function(event) {
                  if (text !== "22") text = "22"
                  else keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            TextField {
              id: addHostField
              width: parent.width
              placeholderText: "host (blank = alias)"
              foreground: root.foreground
              font.family: root.fontFamily
              Keys.onEscapePressed: function(event) {
                if (text !== "") text = ""
                else keyCatcher.forceActiveFocus()
                event.accepted = true
              }
            }

            TextField {
              id: addUserField
              width: parent.width
              placeholderText: "user (optional)"
              foreground: root.foreground
              font.family: root.fontFamily
              Keys.onEscapePressed: function(event) {
                if (text !== "") text = ""
                else keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) { root.submitNewServer(); event.accepted = true }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Save"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.submitNewServer()
              }

              Button {
                text: "Cancel"
                foreground: root.dim
                fontFamily: root.fontFamily
                onClicked: {
                  addAliasField.text = ""
                  addHostField.text = ""
                  addUserField.text = ""
                  addPortField.text = "22"
                  root.addFormOpen = false
                }
              }
            }
          }

          Repeater {
            model: root.filteredServers

            ServerRow {
              width: parent ? parent.width : 0
              entry: modelData
              rowIndex: index
            }
          }

          Text {
            visible: root.mergedCount === 0
            width: parent.width
            text: "No servers yet — add Host entries to ~/.ssh/config\nor press + to add one manually"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(24)
            bottomPadding: Style.space(24)
          }

          Text {
            visible: root.filteredServers.length === 0 && root.mergedCount > 0
            width: parent.width
            text: "No matches for \"" + root.filterText + "\""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(8)
          }

          Text {
            visible: root.statusMessage !== ""
            width: parent.width
            text: root.statusMessage
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
            maximumLineCount: 1
          }
        }
      }
    }
  }

  component ServerRow: Column {
    id: serverRow
    property var entry: ({})
    property int rowIndex: 0
    property bool rowHovered: false

    readonly property bool connected: root.hasSession(serverRow.entry)
    readonly property bool alerted: root.alertFor(String(serverRow.entry.alias || "")) !== undefined
    readonly property string alias: String(serverRow.entry.alias || "?")
    readonly property string hostLabel: String(serverRow.entry.user || "") + (serverRow.entry.user ? "@" : "") + String(serverRow.entry.host || "")
    readonly property bool editorOpen: root.editingAlias === serverRow.alias

    spacing: Style.space(8)

    onEditorOpenChanged: if (editorOpen) populateEditor()

    function populateEditor() {
      var e = serverRow.entry
      editName.text = String(e.name || "")
      editHost.text = String(e.host || "")
      editUser.text = String(e.user || "")
      editPort.text = String(e.port || 22)
      editMode.value = String(e.mode || "default")
      editTerminal.text = String(e.terminal || "")
      editColor.text = String(e.color || "")
      editGlyph.text = String(e.glyph || "")
      editKeywords.text = root.joinKeywords(e.keywords)
      editHidden.checked = e.hidden === true
    }

    function commitEdit() {
      root.saveRecord(serverRow.alias, {
        alias: serverRow.alias,
        name: editName.text.trim(),
        host: editHost.text.trim(),
        user: editUser.text.trim(),
        port: parseInt(editPort.text.trim(), 10) || 22,
        mode: String(editMode.value || "default"),
        terminal: editTerminal.text.trim(),
        color: editColor.text.trim(),
        glyph: editGlyph.text.trim(),
        keywords: root.splitKeywords(editKeywords.text),
        hidden: editHidden.checked
      })
      root.showStatus("Saved " + serverRow.alias)
      root.editingAlias = ""
    }

    function toggleEditor() {
      root.editingAlias = serverRow.editorOpen ? "" : serverRow.alias
    }

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
        color: serverRow.alerted ? root.urgent
             : (serverRow.connected ? root.entryColor(serverRow.entry) : root.dim)
      }

      Column {
        id: rowLabels
        anchors.left: rowDot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: serverRow.rowHovered || serverRow.editorOpen ? Style.space(30) : 0
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: (String(serverRow.entry.glyph || "") !== "" ? String(serverRow.entry.glyph) + " " : "") + root.displayLabel(serverRow.entry)
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

        Text {
          visible: serverRow.alerted
          width: parent.width
          text: {
            var a = root.alertFor(serverRow.alias)
            return a ? (a.summary || a.body || "") : ""
          }
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: serverRow.rowHovered = containsMouse
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) serverRow.toggleEditor()
          else root.connectEntry(serverRow.entry)
        }
      }

      PanelActionButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: serverRow.rowHovered || serverRow.editorOpen
        iconText: "󰏫"
        foreground: root.foreground
        hoverColor: Color.accent
        tooltipText: "Edit"
        onClicked: serverRow.toggleEditor()
      }
    }

    Column {
      visible: serverRow.editorOpen
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: editName
        width: parent.width
        placeholderText: "display name (blank = host/user/alias)"
        foreground: root.foreground
        font.family: root.fontFamily
      }

      Dropdown {
        id: editMode
        width: parent.width
        label: ""
        value: "default"
        options: ["default", "plain", "tmux", "herdr", "custom"]
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: editUser
          width: (parent.width - parent.spacing) * 0.4
          placeholderText: "user"
          foreground: root.foreground
          font.family: root.fontFamily
        }

        TextField {
          id: editPort
          width: parent.width - parent.spacing - editUser.width
          placeholderText: "port"
          foreground: root.foreground
          font.family: root.fontFamily
        }
      }

      TextField {
        id: editHost
        width: parent.width
        placeholderText: "host"
        foreground: root.foreground
        font.family: root.fontFamily
      }

      TextField {
        id: editTerminal
        width: parent.width
        placeholderText: "terminal override (blank = global)"
        foreground: root.foreground
        font.family: root.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: editColor
          width: (parent.width - parent.spacing) * 0.55
          placeholderText: "color #hex"
          foreground: root.foreground
          font.family: root.fontFamily
        }

        TextField {
          id: editGlyph
          width: parent.width - parent.spacing - editColor.width
          placeholderText: "glyph"
          foreground: root.foreground
          font.family: root.fontFamily
        }
      }

      TextField {
        id: editKeywords
        width: parent.width
        placeholderText: "alert keywords, comma-separated"
        foreground: root.foreground
        font.family: root.fontFamily
      }

      Toggle {
        id: editHidden
        width: parent.width
        label: "Hidden"
        description: "Hide this imported host from the list"
        checked: false
        foreground: root.foreground
        accent: Color.accent
        fontFamily: root.fontFamily
        onClicked: checked = !checked
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: "Save"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: serverRow.commitEdit()
        }

        Button {
          text: "Remove"
          foreground: root.foreground
          accent: root.urgent
          fontFamily: root.fontFamily
          onClicked: {
            root.removeRecord(serverRow.alias)
            root.showStatus("Removed " + serverRow.alias)
            root.editingAlias = ""
          }
        }

        Button {
          text: "Done"
          foreground: root.dim
          fontFamily: root.fontFamily
          onClicked: root.editingAlias = ""
        }
      }
    }
  }
}
