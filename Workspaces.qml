import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function focusWindow(address) {
    if (!root.bar || !address) return
    var addr = "0x" + String(address).replace(/^0x/i, "")
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:" + addr + "\" })"))
    root.selectedWorkspaceId = -1
  }

  // Shows the running-apps list for `id` without switching to it. Picking a
  // window from the list (or dismissing it) is what decides whether any
  // switch actually happens.
  function startPreview(id) {
    root.selectedWorkspaceId = id
  }

  // Clicking a workspace: if it's already focused, just toggles the list.
  // Otherwise, a workspace with one window (or none) is switched to
  // directly -- there's nothing to pick between. A busier workspace is only
  // previewed; the switch happens once a window is picked, same as the
  // SUPER+<number> keybinds (see ~/.config/hypr/bindings.lua, which calls
  // scripts/switch-or-preview.sh).
  function selectWorkspace(id) {
    if (Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === id) {
      root.selectedWorkspaceId = root.selectedWorkspaceId === id ? -1 : id
      return
    }
    var ws = root.workspaceById(id)
    var windowCount = ws ? ws.toplevels.values.length : 0
    if (windowCount > 1) root.startPreview(id)
    else root.focusWorkspace(id)
  }

  property int selectedWorkspaceId: -1
  readonly property var selectedWorkspace: root.workspaceById(root.selectedWorkspaceId)
  readonly property var selectedWindows: selectedWorkspace ? selectedWorkspace.toplevels.values : []
  // A single window is never worth popping a list up for -- switching (or
  // focusWindow, which switches too) already lands on it directly.
  readonly property bool popupVisible: root.selectedWorkspaceId !== -1 && root.selectedWindows.length > 1

  onSelectedWorkspaceIdChanged: {
    var opening = root.popupVisible
    windowList.currentIndex = opening ? 0 : -1
    if (opening) {
      autoDismissTimer.restart()
      // Safety net: re-assert keyboard focus slightly after opening, in case
      // anything else grabs it in the same moment as our own focus grab.
      refocusTimer.restart()
    } else {
      autoDismissTimer.stop()
    }
  }

  // Idle auto-dismiss: fades out (via KeyboardPanel's own opacity animation)
  // if nothing is done with the list for a bit. Any navigation restarts it.
  Timer {
    id: autoDismissTimer
    interval: 2000
    onTriggered: root.selectedWorkspaceId = -1
  }

  Timer {
    id: refocusTimer
    interval: 120
    onTriggered: if (root.selectedWorkspaceId !== -1) keyCatcher.forceActiveFocus()
  }

  // Reached by scripts/switch-or-preview.sh (bound to SUPER+<number> in
  // ~/.config/hypr/bindings.lua) so a keybind can ask for a preview instead
  // of dispatching a real workspace switch. Only one of this widget's
  // per-monitor instances ever wins this IPC target, so it relays to
  // whichever sibling instance is on the currently-focused monitor --
  // that's the one whose bar the user is actually looking at.
  IpcHandler {
    target: "eduard.workspaces"

    function preview(workspaceId: string): string {
      var id = parseInt(workspaceId, 10)
      if (isNaN(id)) return "bad-id"
      if (!root.bar || typeof root.bar.moduleWidgets !== "function") return "no-bar"
      if (!Hyprland.focusedMonitor) return "no-focused-monitor"

      var targetName = Hyprland.focusedMonitor.name
      var instances = root.bar.moduleWidgets(root.moduleName)
      for (var i = 0; i < instances.length; i++) {
        var instance = instances[i]
        var win = instance && instance.QsWindow ? instance.QsWindow.window : null
        var screenName = win && win.screen ? win.screen.name : ""
        if (screenName === targetName) {
          instance.startPreview(id)
          return "ok"
        }
      }
      return "no-match"
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: wsButton
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property int windowCount: workspace !== null ? workspace.toplevels.values.length : 0
        readonly property bool occupied: windowCount > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.selectWorkspace(modelData) }

        // Window-count badge: only earns its place once there's a real pick
        // to make between windows (i.e. exactly when selectWorkspace() would
        // preview instead of switching directly).
        BorderSurface {
          id: countBadge
          visible: wsButton.windowCount > 1
          width: Math.max(Style.space(11), badgeText.implicitWidth + Style.space(4))
          height: Style.space(11)
          radius: height / 2
          color: Color.accent
          borderSpec: Border.flat(Color.popups.background, 1)
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: -2
          anchors.rightMargin: -2

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: String(wsButton.windowCount)
            color: Color.background
            font.family: root.bar.fontFamily
            font.pixelSize: Style.space(7)
            font.bold: true
          }
        }
      }
    }
  }

  // Keyboard-driven popup: KeyboardPanel is a PanelWindow that primes real
  // Wayland keyboard focus on open (unlike PopupCard/PopupWindow, whose
  // xdg-popup only ever receives pointer input via HyprlandFocusGrab), so
  // PanelKeyCatcher's arrow keys actually reach this list.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupVisible
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    function close() { root.selectedWorkspaceId = -1 }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        autoDismissTimer.restart()
        if (dy > 0) windowList.currentIndex = Math.min(root.selectedWindows.length - 1, windowList.currentIndex + 1)
        else if (dy < 0) windowList.currentIndex = Math.max(0, windowList.currentIndex - 1)
      }
      onActivateRequested: windowList.selectCurrent()
      onCloseRequested: root.selectedWorkspaceId = -1

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(6)
        scale: root.selectedWorkspaceId !== -1 ? 1.0 : 0.96
        transformOrigin: Item.Top

        Behavior on scale {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
          spacing: Style.space(6)

          Text {
            text: "󱓻"
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "Workspace " + (root.selectedWorkspaceId === 10 ? "0" : String(root.selectedWorkspaceId))
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        ListView {
          id: windowList
          width: parent.width
          height: Math.min(contentHeight, Style.space(240))
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          model: root.selectedWindows
          currentIndex: -1
          keyNavigationEnabled: false
          highlightFollowsCurrentItem: true

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.selectedWindows.length) return
            root.focusWindow(root.selectedWindows[currentIndex].address)
          }

          delegate: Rectangle {
            id: windowRow
            required property var modelData
            required property int index

            readonly property var win: modelData
            readonly property string appId: win && win.wayland ? win.wayland.appId : ""

            width: windowList.width
            height: Style.space(32)
            radius: Style.spacing.labelGap
            color: index === windowList.currentIndex
              ? Style.hoverFillFor(root.bar.foreground, Color.accent)
              : "transparent"

            Behavior on color {
              ColorAnimation { duration: 100 }
            }

            Rectangle {
              visible: index === windowList.currentIndex
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.leftMargin: 2
              anchors.topMargin: 4
              anchors.bottomMargin: 4
              width: 3
              radius: 1.5
              color: Color.accent
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Image {
                width: Style.space(20)
                height: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
                source: windowRow.appId ? Quickshell.iconPath(windowRow.appId, true) : ""
                visible: source !== ""
              }

              Text {
                width: parent.width - Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                text: windowRow.win ? (windowRow.win.title || windowRow.appId || "Window") : ""
                color: index === windowList.currentIndex
                  ? Style.hoverStateColor(root.bar.foreground, Color.accent)
                  : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: windowRow.win ? windowRow.win.activated : false
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: { windowList.currentIndex = windowRow.index; autoDismissTimer.restart() }
              onClicked: windowList.selectCurrent()
            }
          }
        }
      }
    }
  }
}
