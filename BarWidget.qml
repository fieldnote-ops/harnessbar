import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.fieldnote-ops.harnessbar"

  // --- state owned here, rendered by Panel.qml -----------------------------
  property var status: ({})
  property bool busy: false
  property string busyLabel: ""
  property string actionError: ""
  property string lastMessage: ""
  property string logsText: ""
  property bool logsBusy: false
  property var updateInfo: ({})

  // --- paths --------------------------------------------------------------
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    url = url.replace(/^file:\/\//, "")
    try { url = decodeURIComponent(url) } catch (e) { /* keep raw */ }
    if (url.length > 1 && url.endsWith("/")) url = url.slice(0, -1)
    return url
  }
  readonly property string helper: pluginDir + "/bin/harnessbar"

  // --- derived status -----------------------------------------------------
  readonly property int refreshMs: Math.max(2, Math.min(300, Number(setting("refreshSec", 5)))) * 1000
  readonly property var st: status || ({})
  readonly property bool running: st.running === true
  readonly property string serviceState: st.state ? String(st.state) : "unknown"
  readonly property string stateLabel: root.stateText(root.serviceState)
  readonly property string version: st.version ? String(st.version) : ""
  readonly property string hostPort: st.port ? (String(st.host || "127.0.0.1") + ":" + String(st.port)) : ""
  readonly property bool managed: st.managed === true
  readonly property bool legacy: st.legacy === true
  readonly property bool unitInstalled: st.unit_installed === true
  readonly property bool supervised: st.supervised === true
  readonly property string serviceError: st.error ? String(st.error) : ""
  readonly property string glyph: String(setting("glyph", "󰚩"))
  readonly property string tooltip: {
    var parts = ["DeepSeek Harness", root.stateLabel]
    if (root.version) parts.push(root.version)
    if (root.hostPort) parts.push(root.hostPort)
    if (root.busy) parts.push("working…")
    else if (root.actionError) parts.push(root.actionError)
    else if (root.serviceError) parts.push(root.serviceError)
    return parts.join(" · ")
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // The bar host sizes each slot from these implicit properties (official bar
  // widgets do the same); without them the widget gets a zero-size slot.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function stateText(value) {
    switch (value) {
      case "running": return "running"
      case "starting": return "starting"
      case "stopped": return "stopped"
      case "degraded": return "degraded"
      case "error": return "error"
      case "stale": return "stopped (stale URL)"
      case "no-dsh": return "dsh not found"
      case "no-service": return "service not installed"
      default: return value ? String(value) : "unknown"
    }
  }

  // --- panel plumbing -----------------------------------------------------
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("settings" in target) target.settings = root.settings
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  // --- commands -----------------------------------------------------------
  function runCommand(label, args) {
    if (busy) return false
    busy = true
    busyLabel = label
    actionError = ""
    lastMessage = ""
    actionProcess.command = [root.helper].concat(args)
    actionProcess.running = true
    actionTimeout.restart()
    return true
  }

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.running = true
  }

  function startService() { return runCommand("starting…", ["start"]) }
  function stopService() { return runCommand("stopping…", ["stop"]) }
  function restartService() { return runCommand("restarting…", ["restart"]) }
  function openUi() { return runCommand("opening…", ["open"]) }
  function copyUrl() { return runCommand("copying…", ["copy-url"]) }
  function setupService() {
    var args = ["setup-service"]
    if (legacy) args.push("--replace-legacy")
    return runCommand("installing service…", args)
  }
  function repairService() { return runCommand("repairing service…", ["setup-service", "--replace-legacy"]) }
  function adoptService() { return runCommand("adopting service…", ["setup-service", "--force"]) }
  function removeService() { return runCommand("removing service…", ["remove-service"]) }
  function applyUpdate() { return runCommand("updating…", ["update"]) }

  function fetchLogs() {
    if (logsBusy) return
    logsBusy = true
    logsProcess.running = true
  }

  function checkUpdates() {
    if (busy) return
    busy = true
    busyLabel = "checking updates…"
    actionError = ""
    updateCheckProcess.running = true
    actionTimeout.restart()
  }

  // --- processes ----------------------------------------------------------
  Process {
    id: statusProcess
    command: [root.helper, "status"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      var text = String(statusOut.text || "").trim()
      var parsed = null
      if (text.charAt(0) === "{") {
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
      }
      if (parsed) {
        root.status = parsed
      } else {
        root.status = { running: false, state: "error", error: "harnessbar status failed; is the plugin intact?" }
      }
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      actionTimeout.stop()
      root.busy = false
      root.busyLabel = ""
      var out = String(actionOut.text || "").trim()
      var parsed = null
      if (out.charAt(0) === "{") {
        try { parsed = JSON.parse(out) } catch (e) { parsed = null }
      }
      if (exitCode !== 0) {
        var message = parsed && parsed.message
          ? String(parsed.message)
          : (String(actionErr.text || "").trim() || ("command failed (exit " + exitCode + ")"))
        root.actionError = message
      } else if (parsed && parsed.message) {
        root.actionError = ""
        root.lastMessage = String(parsed.message)
        clearMessageTimer.restart()
      }
      root.refreshStatus()
    }
  }

  Process {
    id: logsProcess
    command: [root.helper, "logs", "160"]
    stdout: StdioCollector { id: logsOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.logsBusy = false
      root.logsText = String(logsOut.text || "")
    }
  }

  Process {
    id: updateCheckProcess
    command: [root.helper, "update", "--check"]
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    stderr: StdioCollector { id: updateErr; waitForEnd: true }
    onExited: function(exitCode) {
      actionTimeout.stop()
      root.busy = false
      root.busyLabel = ""
      var out = String(updateOut.text || "").trim()
      var parsed = null
      if (out.charAt(0) === "{") {
        try { parsed = JSON.parse(out) } catch (e) { parsed = null }
      }
      if (exitCode !== 0 || !parsed || parsed.ok !== true) {
        root.actionError = parsed && parsed.message
          ? String(parsed.message)
          : "Update check failed; see Logs or the plugin README."
      } else {
        root.actionError = ""
        root.updateInfo = parsed
      }
      root.refreshStatus()
    }
  }

  Timer {
    id: actionTimeout
    interval: 90000
    repeat: false
    onTriggered: {
      root.busy = false
      root.busyLabel = ""
      root.actionError = "The command timed out. Check the service journal for details."
    }
  }

  Timer {
    id: clearMessageTimer
    interval: 8000
    repeat: false
    onTriggered: root.lastMessage = ""
  }

  Timer {
    id: pollTimer
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
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

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    root.refreshStatus()
  }

  IpcHandler {
    target: root.moduleName

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refreshStatus() }
    function start() { root.startService() }
    function stop() { root.stopService() }
    function restart() { root.restartService() }
    function openUi() { root.openUi() }
    function logs() { root.fetchLogs() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: root.tooltip
    active: root.running || root.busy || root.serviceState === "error" || root.serviceState === "no-dsh"
    activeColor: (root.running || root.busy) ? Commons.Color.accent : Commons.Color.urgent
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openUi()
      else if (buttonCode === Qt.MiddleButton) root.refreshStatus()
      else root.toggle()
    }
  }
}
