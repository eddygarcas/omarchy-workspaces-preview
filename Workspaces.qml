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

  // Workspace linking only applies with exactly two monitors -- see
  // focus-workspace.sh, which this mirrors so the bar's grouping always
  // matches what a switch actually does.
  function isLinkedSetup() {
    return Hyprland.monitors.values.length === 2
  }

  function isWorkspaceShown(id) {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].activeWorkspace && mons[i].activeWorkspace.id === id) return true
    }
    return false
  }

  // WCAG relative-luminance contrast (same formula used elsewhere in the
  // shell, e.g. the agents plugin's icon-variant picker). Badges sit on
  // Color.accent, which some themes make bright and others make a
  // saturated-but-dark color, so a hardcoded badge-text color can't stay
  // legible across themes -- pick whichever of foreground/background
  // actually contrasts against the real badge background.
  function luminanceChannel(value) {
    var c = Number(value)
    if (!isFinite(c)) return 0
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }

  function relativeLuminance(color) {
    return 0.2126 * root.luminanceChannel(color.r)
      + 0.7152 * root.luminanceChannel(color.g)
      + 0.0722 * root.luminanceChannel(color.b)
  }

  function contrastingTextColor(bg) {
    var bgLum = root.relativeLuminance(bg)
    var contrastVsForeground = Math.abs(root.relativeLuminance(Color.foreground) - bgLum)
    var contrastVsBackground = Math.abs(root.relativeLuminance(Color.background) - bgLum)
    return contrastVsForeground >= contrastVsBackground ? Color.foreground : Color.background
  }

  // Pairs up adjacent odd/even workspace ids (1,2 / 3,4 / ...) when linked.
  // A workspace whose pair partner isn't in workspaceIds() yet (no windows,
  // never switched to) renders alone rather than groomed in with a
  // placeholder for a workspace that doesn't exist.
  function workspaceGroups() {
    var ids = root.workspaceIds()

    if (!root.isLinkedSetup()) {
      var solo = []
      for (var i = 0; i < ids.length; i++) solo.push({ ids: [ids[i]], linked: false })
      return solo
    }

    var idSet = {}
    for (var i = 0; i < ids.length; i++) idSet[ids[i]] = true

    var groups = []
    var handled = {}
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (handled[id]) continue

      var isOdd = id % 2 === 1
      var partner = isOdd ? id + 1 : id - 1
      if (idSet[partner]) {
        var left = isOdd ? id : partner
        var right = isOdd ? partner : id
        groups.push({ ids: [left, right], linked: true })
        handled[left] = true
        handled[right] = true
      } else {
        groups.push({ ids: [id], linked: false })
        handled[id] = true
      }
    }
    return groups
  }

  // Same script the SUPER+<number> keybind runs (scripts/switch-or-preview.sh
  // -> focus-workspace.sh), so bar clicks and keybinds link odd/even
  // workspace pairs across monitors identically -- see focus-workspace.sh
  // for the linking rules.
  readonly property string linkScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/eduard.workspaces/scripts/focus-workspace.sh"

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run(Util.shellQuote(root.linkScript) + " " + Util.shellQuote(String(id)))
  }

  function focusWindow(address) {
    if (!root.bar || !address) return
    var addr = "0x" + String(address).replace(/^0x/i, "")
    root.bar.run(Util.shellQuote(root.linkScript) + " " + Util.shellQuote(String(root.selectedWorkspaceId)) + " " + Util.shellQuote(addr))
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
    columns: root.vertical ? 1 : root.workspaceGroups().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceGroups()

      Item {
        id: cell
        required property var modelData
        readonly property var groupIds: modelData.ids
        readonly property bool linked: modelData.linked === true

        implicitWidth: flow.implicitWidth
        implicitHeight: flow.implicitHeight

        Flow {
          id: flow
          anchors.centerIn: parent
          flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
          // Linked pairs get extra room so the dotted connector (drawn as
          // an overlay off the first button, below) has space to sit
          // between the two buttons instead of overlapping either one.
          spacing: cell.linked ? Style.space(11) : Style.space(2)

          Repeater {
            model: cell.groupIds

            WidgetButton {
              id: wsButton
              required property int modelData
              required property int index

              readonly property var workspace: root.workspaceById(modelData)
              readonly property int windowCount: workspace !== null ? workspace.toplevels.values.length : 0
              readonly property bool occupied: windowCount > 0
              readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
              // True while linked and shown on some monitor even if input
              // focus is on its pair partner -- it's still on-screen, so it
              // shouldn't read as dim/unoccupied.
              readonly property bool shown: cell.linked && root.isWorkspaceShown(modelData)

              bar: root.bar
              text: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
              opacity: occupied || focused || shown ? 1 : 0.5
              horizontalMargin: 6
              verticalPadding: 6
              fixedWidth: root.vertical ? root.barSize : Style.space(20)
              fixedHeight: root.barSize
              onPressed: function() { root.selectWorkspace(modelData) }

              // Dotted link line to the paired workspace -- drawn as an
              // overlay reaching from the pair's first (odd) button into
              // the gap toward its second (even) button, rather than a
              // pill wrapping both, so switching to either one reads as
              // "these two are connected" instead of "these two are boxed
              // together". Overflows this button's own bounds on purpose
              // (WidgetButton doesn't clip), landing in the flow.spacing
              // gap reserved for it above.
              Flow {
                id: linkDots
                visible: cell.linked && wsButton.index === 0
                flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                spacing: Style.space(1)
                anchors.left: root.vertical ? undefined : parent.right
                anchors.leftMargin: root.vertical ? 0 : Style.space(2)
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? parent.bottom : undefined
                anchors.topMargin: root.vertical ? Style.space(2) : 0
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                Repeater {
                  model: 3
                  Rectangle {
                    width: Style.space(2)
                    height: width
                    radius: width / 2
                    color: Color.accent
                  }
                }
              }

              // Window-count badge: only earns its place once there's a real
              // pick to make between windows (i.e. exactly when
              // selectWorkspace() would preview instead of switching
              // directly).
              BorderSurface {
                id: countBadge
                visible: wsButton.windowCount > 1
                width: Math.max(Style.space(14), badgeText.implicitWidth + Style.space(5))
                height: Style.space(14)
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
                  color: root.contrastingTextColor(countBadge.color)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.space(9)
                  font.bold: true
                }
              }
            }
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
                textFormat: Text.PlainText
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
