import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.fieldnote-ops.harnessbar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var host: hostWidget
  readonly property var st: host ? (host.status || ({})) : ({})
  readonly property bool running: st.running === true
  readonly property string serviceState: st.state ? String(st.state) : "unknown"
  readonly property string stateLabel: root.stateText(root.serviceState)
  readonly property string version: st.version ? String(st.version) : ""
  readonly property string hostPort: host && host.hostPort ? String(host.hostPort) : ""
  readonly property bool managed: st.managed === true
  readonly property bool legacy: st.legacy === true
  readonly property bool unitInstalled: st.unit_installed === true
  readonly property bool supervised: st.supervised === true
  readonly property bool busy: host ? host.busy === true : false
  readonly property string busyLabel: host && host.busyLabel ? String(host.busyLabel) : ""
  readonly property string actionError: host && host.actionError ? String(host.actionError) : ""
  readonly property string lastMessage: host && host.lastMessage ? String(host.lastMessage) : ""
  readonly property string serviceError: st.error ? String(st.error) : ""
  readonly property string logsText: host ? String(host.logsText || "") : ""
  readonly property bool logsBusy: host ? host.logsBusy === true : false
  readonly property var updateInfo: host ? (host.updateInfo || ({})) : ({})

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.62)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accent: Commons.Color.accent

  property bool showLogs: false
  property string pendingAction: ""
  property string pendingMessage: ""

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

  function serviceLine() {
    if (legacy) return "Legacy dsh-web service from ~/.local/bin detected."
    if (managed) return supervised ? "Background service: managed by harnessbar." : "Background service installed."
    if (unitInstalled) return "Background service present but not managed by harnessbar."
    return "No background service installed. Install it to manage dsh web from the panel."
  }

  function updateLine() {
    if (updateInfo && updateInfo.current) {
      var text = "dsh " + updateInfo.current
      if (updateInfo.latest) text += " → " + updateInfo.latest
      if (updateInfo.manager) text += " (" + updateInfo.manager + ")"
      return text
    }
    return version ? "dsh " + version : "dsh version unknown"
  }

  function execute(action) {
    if (!host || busy) return
    switch (action) {
      case "open": host.openUi(); break
      case "copy": host.copyUrl(); break
      case "start": host.startService(); break
      case "stop": host.stopService(); break
      case "restart": host.restartService(); break
      case "install-service": host.setupService(); break
      case "repair-service": host.repairService(); break
      case "adopt-service": host.adoptService(); break
      case "remove-service": host.removeService(); break
      case "update": host.applyUpdate(); break
      case "check-updates": host.checkUpdates(); break
      case "logs": root.showLogs = !root.showLogs; if (root.showLogs) host.fetchLogs(); break
      case "refresh-logs": host.fetchLogs(); break
    }
  }

  function requestAction(action) {
    if (!host || busy) return
    switch (action) {
      case "stop":
        pendingAction = "stop"
        pendingMessage = "Stop dsh web? Running agent tasks will be interrupted."
        break
      case "restart":
        pendingAction = "restart"
        pendingMessage = "Restart dsh web? Open sessions will disconnect and running tasks may be interrupted."
        break
      case "update":
        pendingAction = "update"
        pendingMessage = "Update dsh and restart the service? Open sessions will disconnect."
        break
      case "remove-service":
        pendingAction = "remove-service"
        pendingMessage = "Remove the harnessbar-managed dsh-web.service? The running web UI will stop and DeepSeek Harness data in ~/.dsh stays untouched."
        break
    }
  }

  function confirmPending() {
    var action = pendingAction
    pendingAction = ""
    pendingMessage = ""
    execute(action)
  }

  function cancelPending() {
    pendingAction = ""
    pendingMessage = ""
  }

  function refreshAll() {
    if (!host) return
    host.refreshStatus()
    if (showLogs) host.fetchLogs()
  }

  onOpenedChanged: {
    pendingAction = ""
    pendingMessage = ""
    if (opened) refreshAll()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(4), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.pendingAction !== "") root.cancelPending()
        else root.close()
      }
      onTextKey: function(t) {
        if (root.pendingAction !== "") return
        if (t === "o" || t === "O") root.execute("open")
        else if (t === "s" || t === "S") root.requestAction(root.running ? "stop" : "start")
        else if (t === "r" || t === "R") root.requestAction("restart")
        else if (t === "g" || t === "G") root.execute("logs")
        else if (t === "u" || t === "U") root.execute("check-updates")
        else if (t === "c" || t === "C") root.execute("copy")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ColumnLayout {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                text: "DEEPSEEK HARNESS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              RowLayout {
                spacing: Style.space(6)

                Rectangle {
                  Layout.preferredWidth: Style.space(8)
                  Layout.preferredHeight: Style.space(8)
                  Layout.alignment: Qt.AlignVCenter
                  radius: width / 2
                  color: root.running
                    ? root.accent
                    : (root.serviceState === "error" || root.serviceState === "no-dsh" ? root.urgent : Util.alpha(root.foreground, 0.35))
                }

                Text {
                  text: root.stateLabel
                  color: root.running ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  visible: root.version !== ""
                  text: "v" + root.version
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            Button {
              text: "Refresh"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.refreshAll()
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.hostPort
              ? root.hostPort + (root.supervised ? " · systemd user service" : " · unsupervised")
              : "No listener detected"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Rectangle {
            Layout.fillWidth: true
            visible: root.actionError !== "" || root.serviceError !== ""
            implicitHeight: errorText.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Util.alpha(root.urgent, 0.12)
            border.width: 1
            border.color: Util.alpha(root.urgent, 0.45)

            Text {
              id: errorText
              anchors.fill: parent
              anchors.margins: Style.space(7)
              text: root.actionError !== "" ? root.actionError : root.serviceError
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.lastMessage !== ""
            text: root.lastMessage
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Button {
              text: "Open UI"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("open")
            }
            Button {
              text: "Copy URL"
              focusable: true
              bordered: true
              tooltipText: "Copies the tokenized launch URL; treat it as a credential."
              enabled: !!root.host && !root.busy && root.running
              onClicked: root.execute("copy")
            }
            Button {
              text: root.running ? "Stop" : "Start"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.running ? root.requestAction("stop") : root.execute("start")
            }
            Button {
              text: "Restart"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy && root.unitInstalled
              onClicked: root.requestAction("restart")
            }
            Button {
              text: root.showLogs ? "Hide logs" : "Logs"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("logs")
            }
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Util.alpha(root.foreground, 0.12)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: root.serviceLine()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              visible: !root.unitInstalled && !root.legacy
              text: "Install service"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("install-service")
            }
            Button {
              visible: root.unitInstalled && !root.managed && !root.legacy
              text: "Adopt service"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("adopt-service")
            }
            Button {
              visible: root.legacy
              text: "Repair service"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("repair-service")
            }
            Button {
              visible: root.managed
              text: "Remove service"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.requestAction("remove-service")
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: root.updateLine()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              visible: !root.updateInfo || !root.updateInfo.latest
              text: "Check updates"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.execute("check-updates")
            }
            Button {
              visible: root.updateInfo && root.updateInfo.updatable === true
              text: "Update & restart"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.busy
              onClicked: root.requestAction("update")
            }
          }

          Rectangle {
            Layout.fillWidth: true
            visible: root.showLogs
            implicitHeight: Style.space(170)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.05)

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: logText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              TextEdit {
                id: logText
                width: parent.width
                readOnly: true
                selectByMouse: true
                text: root.logsText
                color: root.foreground
                font.family: "monospace"
                font.pixelSize: Style.font.caption
                wrapMode: TextEdit.WrapAnywhere
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.logsText === ""
              text: root.logsBusy ? "loading logs…" : "No log output yet"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          RowLayout {
            Layout.fillWidth: true
            visible: root.showLogs
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: "Tokens in the journal are redacted."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              text: "Refresh logs"
              focusable: true
              bordered: true
              enabled: !!root.host && !root.logsBusy
              onClicked: root.execute("refresh-logs")
            }
          }

          Rectangle {
            Layout.fillWidth: true
            visible: root.pendingAction !== ""
            implicitHeight: confirmColumn.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.urgent, 0.10)
            border.width: 1
            border.color: Util.alpha(root.urgent, 0.4)

            ColumnLayout {
              id: confirmColumn
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                text: root.pendingMessage
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)
                Item { Layout.fillWidth: true }
                Button {
                  text: "Cancel"
                  focusable: true
                  bordered: true
                  onClicked: root.cancelPending()
                }
                Button {
                  text: "Confirm"
                  focusable: true
                  bordered: true
                  onClicked: root.confirmPending()
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.busy
            text: root.busyLabel !== "" ? root.busyLabel : "working…"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            Layout.fillWidth: true
            text: "o open · s start/stop · r restart · g logs · u check updates · c copy URL · Esc close"
            color: Util.alpha(root.foreground, 0.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
