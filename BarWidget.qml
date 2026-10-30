import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Shapes
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
  property string lastAction: ""
  property bool updateCheckQuiet: false
  property double lastAutoCheckMs: 0
  property string pendingStdin: ""
  property bool pendingStdinActive: false
  readonly property bool updateAvailable: updateInfo && updateInfo.updatable === true

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
  readonly property int refreshMs: {
    var value = Number(setting("refreshSec", 5))
    if (!isFinite(value)) value = 5
    value = Math.max(2, Math.min(300, value))
    return Math.round(value * 1000)
  }
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
  // Empty glyph (the default) shows the DeepSeek mark; any value the user
  // typed keeps working as a plain text label.
  readonly property string glyph: String(setting("glyph", ""))
  readonly property bool useCustomGlyph: root.glyph !== ""
  readonly property string tooltip: {
    var parts = ["DeepSeek Harness", root.stateLabel]
    if (root.version) parts.push(root.version)
    if (root.hostPort) parts.push(root.hostPort)
    if (root.updateAvailable) parts.push("update available")
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
  function runCommand(label, args, actionKey, stdinPayload) {
    if (busy || actionProcess.running || updateCheckProcess.running) return false
    busy = true
    busyLabel = label
    lastAction = actionKey || ""
    actionError = ""
    lastMessage = ""
    pendingStdinActive = !(stdinPayload === undefined || stdinPayload === null)
    pendingStdin = pendingStdinActive ? String(stdinPayload) : ""
    actionProcess.command = [root.helper].concat(args)
    actionProcess.running = true
    actionTimeout.restart()
    return true
  }

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.running = true
  }

  function startService() { return runCommand("starting…", ["start"], "start") }
  function stopService() { return runCommand("stopping…", ["stop"], "stop") }
  function restartService() { return runCommand("restarting…", ["restart"], "restart") }
  function openUi() { return runCommand("opening…", ["open"], "open") }
  function copyUrl() { return runCommand("copying…", ["copy-url"], "copy") }
  function copyInstallCommand(manager) {
    return runCommand("copying…", ["copy-install-command", String(manager)], "copy-install")
  }
  function saveSettings(proxy, port, dshPath, startOnLogin) {
    // Proxy may carry credentials: it goes over stdin, not argv.
    return runCommand("saving settings…", [
      "save-settings",
      "--proxy-stdin",
      "--port", String(port),
      "--dsh-path", String(dshPath),
      "--start-on-login", String(startOnLogin)
    ], "save-settings", String(proxy))
  }
  function setupService() {
    var args = ["setup-service"]
    if (legacy) args.push("--replace-legacy")
    return runCommand("installing service…", args, "setup")
  }
  function repairService() { return runCommand("repairing service…", ["setup-service", "--replace-legacy"], "repair") }
  function adoptService() { return runCommand("adopting service…", ["setup-service", "--force"], "adopt") }
  function removeService() { return runCommand("removing service…", ["remove-service"], "remove") }
  function applyUpdate() { return runCommand("updating…", ["update"], "update") }

  function fetchLogs() {
    if (logsBusy) return
    logsBusy = true
    logsProcess.running = true
  }

  function checkUpdates(quiet) {
    if (busy || updateCheckProcess.running) return
    updateCheckQuiet = quiet === true
    if (!updateCheckQuiet) {
      busy = true
      busyLabel = "checking updates…"
      actionError = ""
      actionTimeout.restart()
    }
    updateCheckProcess.running = true
  }

  // Check once per panel session window without spamming npm.
  function autoCheckUpdates() {
    if (busy || updateCheckProcess.running) return
    var now = Date.now()
    if (now - lastAutoCheckMs < 15 * 60 * 1000) return
    lastAutoCheckMs = now
    checkUpdates(true)
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
    // Quickshell only opens the child's stdin when this is enabled; without it
    // write() is a no-op and the helper would see EOF instead of the proxy.
    stdinEnabled: true
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onStarted: function() {
      if (root.pendingStdinActive) {
        // Always terminate with a newline; an empty line is the explicit
        // "clear the proxy" payload and must still be written.
        actionProcess.write(root.pendingStdin + "\n")
        root.pendingStdin = ""
        root.pendingStdinActive = false
      }
    }
    onExited: function(exitCode) {
      root.pendingStdin = ""
      root.pendingStdinActive = false
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
      if (root.lastAction === "update" && exitCode === 0) {
        root.updateInfo = ({})
        Qt.callLater(root.checkUpdates)
      }
      root.refreshStatus()
    }
  }

  Process {
    id: logsProcess
    command: [root.helper, "logs", "160"]
    stdout: StdioCollector { id: logsOut; waitForEnd: true }
    stderr: StdioCollector { id: logsErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.logsBusy = false
      if (exitCode !== 0) {
        var error = String(logsErr.text || "").trim()
        root.logsText = "Journal unavailable" + (error !== "" ? ": " + error : ".")
      } else {
        root.logsText = String(logsOut.text || "")
      }
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
      var quiet = root.updateCheckQuiet
      root.updateCheckQuiet = false
      if (exitCode !== 0 || !parsed || parsed.ok !== true) {
        if (!quiet) {
          root.actionError = parsed && parsed.message
            ? String(parsed.message)
            : "Update check failed; see Logs or the plugin README."
        }
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
      if (actionProcess.running || updateCheckProcess.running) {
        root.actionError = "The command is taking longer than expected; waiting for it to finish."
        return
      }
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

  // DeepSeek mark, drawn from the brand SVG path. Fixed brand blue: the bar
  // still signals state through the button opacity (1.0 active / 0.55 idle).
  Component {
    id: deepseekLogo
    Shape {
      width: 24
      height: 24
      antialiasing: true
      ShapePath {
        fillColor: "#4D6BFE"
        strokeColor: "transparent"
        PathSvg { path: "M23.748 4.482c-.254-.124-.364.113-.512.234-.051.039-.094.09-.137.136-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.156-.708-.311-.955-.65-.172-.241-.219-.51-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.093.172.187.129.323-.082.28-.18.552-.266.833-.055.179-.137.217-.329.14a5.526 5.526 0 01-1.736-1.18c-.857-.828-1.631-1.742-2.597-2.458a11.365 11.365 0 00-.689-.471c-.985-.957.13-1.743.388-1.836.27-.098.093-.432-.779-.428-.872.004-1.67.295-2.687.684a3.055 3.055 0 01-.465.137 9.597 9.597 0 00-2.883-.102c-1.885.21-3.39 1.102-4.497 2.623C.082 8.606-.231 10.684.152 12.85c.403 2.284 1.569 4.175 3.36 5.653 1.858 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.133-.284 4.994-1.86.47.234.962.327 1.78.397.63.059 1.236-.03 1.705-.128.735-.156.684-.837.419-.961-2.155-1.004-1.682-.595-2.113-.926 1.096-1.296 2.746-2.642 3.392-7.003.05-.347.007-.565 0-.845-.004-.17.035-.237.23-.256a4.173 4.173 0 001.545-.475c1.396-.763 1.96-2.015 2.093-3.517.02-.23-.004-.467-.247-.588zM11.581 18c-2.089-1.642-3.102-2.183-3.52-2.16-.392.024-.321.471-.235.763.09.288.207.486.371.739.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.167-1.361-.802-2.5-1.86-3.301-3.307-.774-1.393-1.224-2.887-1.298-4.482-.02-.386.093-.522.477-.592a4.696 4.696 0 011.529-.039c2.132.312 3.946 1.265 5.468 2.774.868.86 1.525 1.887 2.202 2.891.72 1.066 1.494 2.082 2.48 2.914.348.292.625.514.891.677-.802.09-2.14.11-3.054-.614zm1-6.44a.306.306 0 01.415-.287.302.302 0 01.2.288.306.306 0 01-.31.307.303.303 0 01-.304-.308zm3.11 1.596c-.2.081-.399.151-.59.16a1.245 1.245 0 01-.798-.254c-.274-.23-.47-.358-.552-.758a1.73 1.73 0 01.016-.588c.07-.327-.008-.537-.239-.727-.187-.156-.426-.199-.688-.199a.559.559 0 01-.254-.078c-.11-.054-.2-.19-.114-.358.028-.054.16-.186.192-.21.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.391.451.462.576.685.914.176.265.336.537.445.848.067.195-.019.354-.25.452z" }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.useCustomGlyph ? root.glyph : ""
    iconComponent: root.useCustomGlyph ? null : deepseekLogo
    tooltipText: root.tooltip
    active: root.running || root.busy || root.serviceState === "error" || root.serviceState === "no-dsh"
    activeColor: (root.running || root.busy) ? Commons.Color.accent : Commons.Color.urgent
    opacity: (root.running || root.busy || root.serviceState === "error" || root.serviceState === "no-dsh") ? 1.0 : 0.55
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openUi()
      else if (buttonCode === Qt.MiddleButton) root.refreshStatus()
      else root.toggle()
    }
  }
}
