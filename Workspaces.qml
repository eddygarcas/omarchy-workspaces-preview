import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "IconRules.js" as IconRules

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // --- settings, read from this widget's shell.json layout entry ------------
  // Draw a Nerd Font glyph per open window beside the workspace number.
  readonly property bool showIcons: root.setting("showIcons", true)
  // 0 = an icon for every window; otherwise the overflow collapses to "+N".
  readonly property int maxIcons: root.setting("maxIcons", 0)
  // Keep 1-5 pinned on the bar whether or not they hold windows (the old
  // behaviour). Off by default: only occupied and on-screen workspaces show.
  readonly property bool showEmpty: root.setting("showEmpty", false)
  // A pill for Hyprland's special workspace while something is stashed in
  // it (SUPER+ALT+S parks a window there, SUPER+S brings it back). It shows
  // on every bar, since the stash is one global thing rather than something
  // a monitor owns; it lights up on the monitor currently displaying it.
  readonly property bool showScratchpad: root.setting("showScratchpad", true)
  readonly property string scratchpadName: root.setting("scratchpadName", "special:scratchpad")
  readonly property string scratchpadLabel: root.setting("scratchpadLabel", "S")

  // --- keeping Hyprland's view fresh ---------------------------------------
  // Quickshell does not refetch toplevels or workspaces on its own, so window
  // and workspace events have to poke it or occupancy (and the icons, which
  // also key off window titles) go stale. `revision` is bumped alongside so
  // the bindings below re-evaluate even on events that change nothing
  // Quickshell exposes as a property.
  property int revision: 0

  readonly property var windowEvents: ["openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2", "activewindow", "activewindowv2", "urgent"]
  readonly property var workspaceEvents: ["workspace", "workspacev2", "createworkspace", "createworkspacev2", "destroyworkspace", "destroyworkspacev2", "moveworkspace", "moveworkspacev2", "focusedmon", "configreloaded"]
  // Toggling the scratchpad open or shut changes which monitor is showing
  // it, which only the monitors payload carries.
  readonly property var specialEvents: ["activespecial", "activespecialv2"]

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (root.windowEvents.indexOf(name) !== -1) {
        Hyprland.refreshToplevels()
        root.revision++
      } else if (root.workspaceEvents.indexOf(name) !== -1) {
        Hyprland.refreshWorkspaces()
        root.revision++
      } else if (root.specialEvents.indexOf(name) !== -1) {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshMonitors()
        root.revision++
      }
    }
  }

  // --- scratchpad -----------------------------------------------------------
  // One bar surface exists per monitor, so the widget reads its own screen
  // off the window it was instantiated into to tell whether the stash is
  // open *here*.
  readonly property var barWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property string screenName: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""

  // Hyprland keeps the special workspace in the list for as long as it
  // holds windows, whether or not it is currently toggled open.
  readonly property var scratchpadWorkspace: {
    var _ = root.revision
    if (!root.showScratchpad) return null
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name || "") === root.scratchpadName) return values[i]
    }
    return null
  }

  readonly property bool scratchpadVisible: root.showScratchpad && root.hasWindows(root.scratchpadWorkspace)

  readonly property bool scratchpadOpen: {
    var _ = root.revision
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (String(mons[i].name) !== root.screenName) continue
      var ipc = mons[i].lastIpcObject
      var special = ipc ? ipc.specialWorkspace : null
      return !!special && String(special.name || "") === root.scratchpadName
    }
    return false
  }

  function toggleScratchpad() {
    if (!root.bar) return
    var name = root.scratchpadName.indexOf("special:") === 0 ? root.scratchpadName.slice(8) : root.scratchpadName
    root.bar.run("hyprctl dispatch " + Util.shellQuote('hl.dsp.workspace.toggle_special("' + name + '")'))
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Which workspaces get a pill. By default only the ones that hold windows,
  // plus whatever is currently on screen on any monitor (so stepping onto a
  // fresh workspace never leaves the bar with nothing to point at, and a
  // linked pair's empty partner still renders while it's shown). With
  // `showEmpty` on, 1-5 stay pinned as well.
  function workspaceIds() {
    var _ = root.revision
    var ids = root.showEmpty ? [1, 2, 3, 4, 5] : []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      var id = ws.id
      if (id <= 0 || id > 10 || ids.indexOf(id) !== -1) continue
      if (root.showEmpty || root.hasWindows(ws) || root.isWorkspaceShown(id)) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function hasWindows(ws) {
    if (!ws) return false
    var tops = ws.toplevels ? ws.toplevels.values : null
    return !!tops && tops.length > 0
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

  // --- icons ---------------------------------------------------------------
  // One Nerd Font glyph per window, resolved from the window's class and
  // title via IconRules.js (title first, so a GitHub tab beats the browser).
  function windowClass(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    if (ipc && ipc.class) return ipc.class
    if (toplevel && toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId
    return ""
  }

  function windowTitle(toplevel) {
    if (toplevel && toplevel.title) return toplevel.title
    var ipc = toplevel ? toplevel.lastIpcObject : null
    if (ipc && ipc.title) return ipc.title
    return ""
  }

  function iconFor(toplevel) {
    var cls = root.windowClass(toplevel).toLowerCase()
    var title = root.windowTitle(toplevel).toLowerCase()
    if (!cls && !title) return IconRules.fallback
    return IconRules.resolve(cls, title)
  }

  function iconsFor(ws) {
    var _ = root.revision
    if (!root.showIcons || !ws) return ""
    var tops = ws.toplevels ? ws.toplevels.values : null
    if (!tops || tops.length === 0) return ""

    var shown = root.maxIcons > 0 ? Math.min(tops.length, root.maxIcons) : tops.length
    var icons = []
    for (var i = 0; i < shown; i++) icons.push(root.iconFor(tops[i]))
    if (tops.length > shown) icons.push("+" + (tops.length - shown))
    return icons.join(" ")
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
    columns: root.vertical ? 1 : root.workspaceGroups().length + (root.scratchpadVisible ? 1 : 0)
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

              readonly property string label: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
              // Icons only fit beside the number on a horizontal bar; a
              // vertical bar keeps the bare number in its fixed-width slot.
              readonly property string icons: root.vertical ? "" : root.iconsFor(workspace)

              bar: root.bar
              text: icons !== "" ? label + " " + icons : label
              opacity: occupied || focused || shown ? 1 : 0.5
              horizontalMargin: 6
              verticalPadding: 6
              fixedWidth: root.vertical ? root.barSize : (icons !== "" ? -1 : Style.space(20))
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
            }
          }
        }
      }
    }

    // The scratchpad sits after the numbers, as the place windows go when
    // they are not on any of them. Click toggles the stash on this monitor.
    WidgetButton {
      id: scratchpadButton
      visible: root.scratchpadVisible
      readonly property string icons: root.vertical ? "" : root.iconsFor(root.scratchpadWorkspace)

      bar: root.bar
      text: icons !== "" ? (root.scratchpadLabel !== "" ? root.scratchpadLabel + " " + icons : icons) : root.scratchpadLabel
      opacity: root.scratchpadOpen ? 1 : 0.5
      horizontalMargin: 6
      verticalPadding: 6
      fixedWidth: root.vertical ? root.barSize : -1
      fixedHeight: root.barSize
      tooltipText: "Scratchpad"
      onPressed: function() { root.toggleScratchpad() }
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
