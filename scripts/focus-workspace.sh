#!/bin/bash
# Focuses workspace $1 (and, if $2 is given, a specific window address on
# it -- see below). On an exactly-two-monitor setup, links odd/even
# workspace pairs (1,2 / 3,4 / ...): switching to either member puts the
# odd id on the leftmost monitor (by x position) and the even id on the
# other, so both are visible at once instead of the switch displacing
# whatever the other monitor was showing. Single- and 3+-monitor setups
# fall back to a plain switch, unchanged from prior behavior.
#
# Called from ./switch-or-preview.sh (SUPER+<number>) and from
# Workspaces.qml's focusWorkspace()/focusWindow() (bar clicks), so both
# switch paths get the same linking. $2, when given, is a toplevel
# address (as Hyprland reports it, "0x..."); it's used instead of the
# final focusmonitor step so picking a window from the multi-window
# preview list ends with real input focus on that exact window rather
# than just on its monitor.
set -euo pipefail

id=$1
window_addr=${2:-}

case "$id" in
  ''|*[!0-9]*) exit 1 ;;
esac

case "$window_addr" in
  ''|0x[0-9a-fA-F]*) ;;
  *) window_addr="" ;;
esac

focus_window_or_workspace() {
  if [ -n "$window_addr" ]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$window_addr\" })" >/dev/null 2>&1
  else
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$id\" })" >/dev/null 2>&1
  fi
}

# Same defensive ceiling as switch-or-preview.sh: bound what reaches jq
# before parsing, since this runs on every workspace keybind/click.
max_bytes=262144

monitors_json=$(hyprctl monitors -j 2>/dev/null | head -c "$((max_bytes + 1))") || true
byte_len=$(LC_ALL=C printf '%s' "$monitors_json" | wc -c)

if [ -z "$monitors_json" ] || [ "$byte_len" -gt "$max_bytes" ]; then
  focus_window_or_workspace
  exit 0
fi

count=$(printf '%s' "$monitors_json" | jq -r 'length' 2>/dev/null) || count=0

if [ "${count:-0}" -ne 2 ]; then
  focus_window_or_workspace
  exit 0
fi

names=$(printf '%s' "$monitors_json" | jq -r 'sort_by(.x) | "\(.[0].name)\n\(.[1].name)"' 2>/dev/null) || names=""
left_name=$(printf '%s\n' "$names" | sed -n 1p)
right_name=$(printf '%s\n' "$names" | sed -n 2p)

if [ -z "$left_name" ] || [ -z "$right_name" ]; then
  focus_window_or_workspace
  exit 0
fi

pair_index=$(( (id + 1) / 2 ))
left_id=$(( pair_index * 2 - 1 ))
right_id=$(( pair_index * 2 ))

# hyprctl dispatch on this build parses its whole argument as Lua (it
# wraps it as `hl.dispatch(<arg>)`), so every dispatch has to go through
# the hl.dsp.* call syntax -- a plain "focusmonitor NAME" string errors as
# invalid Lua. hl.dsp.focus({workspace=...}) lands the workspace on
# whichever monitor hl.dsp.focus({monitor=...}) focused most recently
# (verified empirically), which is what lets each half of the pair be set
# independently below.
focus_monitor() {
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null 2>&1
}

focus_monitor "$left_name"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$left_id\" })" >/dev/null 2>&1
focus_monitor "$right_name"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$right_id\" })" >/dev/null 2>&1

if [ -n "$window_addr" ]; then
  focus_window_or_workspace
elif [ $(( id % 2 )) -eq 1 ]; then
  focus_monitor "$left_name"
else
  focus_monitor "$right_name"
fi
