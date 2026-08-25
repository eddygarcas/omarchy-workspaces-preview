# Workspaces Preview

An [Omarchy](https://omarchy.org/) shell plugin that replaces the built-in
workspace indicator with one that lets you preview and pick a window before
switching, instead of jumping blind into a busy workspace.

![Workspaces Preview popup](screenshot.png)

## Why

Omarchy's built-in `omarchy.workspaces` widget switches straight to a
workspace on click. That's fine when a workspace has one window, but on a
busy workspace you land wherever the compositor last left focus, then have
to hunt for the window you actually wanted. This plugin adds a picker: click
(or press `SUPER+<number>`) on a workspace with more than one window and a
popup lists its windows so you can jump straight to the right one.

## Install

```
omarchy plugin add https://github.com/eddygarcas/omarchy-workspaces-preview.git --enable
```

Or manually:

```
git clone https://github.com/eddygarcas/omarchy-workspaces-preview.git \
  ~/.config/omarchy/plugins/eduard.workspaces
omarchy-shell shell rescanPlugins
omarchy plugin enable eduard.workspaces
```

Installing switches the bar to this widget in place of the built-in
`omarchy.workspaces`.

### Optional: wire up SUPER+<number>

By default `SUPER+<number>` still runs Hyprland's plain
`hl.dsp.focus` and switches immediately. To make it defer to this widget's
picker on busy workspaces, add to `~/.config/hypr/bindings.lua`:

```lua
local workspace_picker = os.getenv("HOME") .. "/.config/omarchy/plugins/eduard.workspaces/scripts/switch-or-preview.sh"
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + " .. key)
  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, workspace_picker .. " " .. tostring(workspace))
end
```

This is a Hyprland keybinding change, not something the plugin installs on
its own, so it's opt-in and won't touch your existing bindings otherwise.

## What it does

- **Click a workspace** — switches directly if it has 0-1 windows. If it has
  more, opens a popup listing its windows instead of switching blind.
- **Pick a window from the popup** — arrow keys (or mouse hover) to move the
  selection, `Enter`/click to jump to it. The popup auto-dismisses after 2
  seconds of inactivity, or on `Esc`.
- **`SUPER+<number>`** (once wired up per above) — same behavior as a click,
  via `scripts/switch-or-preview.sh` and an `IpcHandler` (`eduard.workspaces
  preview <id>`) that relays the request to whichever monitor is currently
  focused.
- Workspace `10` displays as `0`, matching the built-in widget.

## Known limitations

The `SUPER+<number>` integration requires manually editing
`~/.config/hypr/bindings.lua` (see above) — a plugin can't safely rewrite
another config file's keybindings for you, so this step isn't automated by
install/enable.

## Permissions & dependencies

- No external packages or network access required.
- Reads workspace/window state via Quickshell's `Hyprland` integration and
  dispatches `hyprctl dispatch hl.dsp.focus(...)` to switch.
- `scripts/switch-or-preview.sh` (only used if you wire up the optional
  keybinding) calls `hyprctl workspaces -j`, `jq`, and `omarchy-shell`.
- Like every Quickshell plugin, this code runs unsandboxed inside the shared
  `omarchy-shell` process — review `Workspaces.qml` before installing.

## Files

| File                            | Purpose                                             |
|----------------------------------|------------------------------------------------------|
| `manifest.json`                  | Plugin manifest (`bar-widget`)                        |
| `Workspaces.qml`                 | Bar widget, popup UI, and IPC handler                 |
| `scripts/switch-or-preview.sh`   | Optional `SUPER+<number>` keybinding helper           |

## Remove

```
omarchy plugin remove eduard.workspaces
```

This deletes `~/.config/omarchy/plugins/eduard.workspaces/` and restores the
built-in `omarchy.workspaces` widget on the bar. If you wired up the optional
keybinding, revert that block in `~/.config/hypr/bindings.lua` by hand.

## License

MIT — see [LICENSE](LICENSE).
