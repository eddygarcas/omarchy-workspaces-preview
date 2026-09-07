#!/bin/bash
# Focuses workspace $1 (and, if $2 is given, a specific window address on
# it -- see below). On an exactly-two-monitor setup, links odd/even
# workspace pairs (1,2 / 3,4 / ...): switching to either member puts the
# odd id on the leftmost monitor (by x position) and the even id on the
# other, so both are visible at once instead of the switch displacing
# whatever the other monitor was showing, even if one half of the pair was
# last shown pinned to the other monitor (see place_workspace() below).
# Single- and 3+-monitor setups fall back to a plain switch, unchanged
# from prior behavior.
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
# whichever monitor hl.dsp.focus({monitor=...}) focused most recently --
# but only when that workspace isn't already active on some monitor. If it
# is (e.g. it was last shown solo on the "wrong" side of a pair -- reached
# through SUPER+TAB/scroll, which bypass this script, or briefly displayed
# alone while down to one monitor), the dispatch just redirects focus to
# wherever it already lives instead of moving it, leaving the intended
# monitor showing stale content. place_workspace() below detects that and
# forces it over with hl.dsp.workspace.move(), which does relocate a
# pinned workspace (verified empirically).
focus_monitor() {
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null 2>&1
}

focus_workspace() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null 2>&1
}

# Which of the two monitors is currently showing workspace $1, if either.
# Prints nothing if it's not active on either one right now. Re-fetches
# fresh JSON (through the same byte ceiling as the initial fetch above)
# since this runs after dispatches that may have changed monitor state.
active_monitor_for() {
  local ws="$1" json byte_len
  json=$(hyprctl monitors -j 2>/dev/null | head -c "$((max_bytes + 1))") || true
  byte_len=$(LC_ALL=C printf '%s' "$json" | wc -c)
  if [ -z "$json" ] || [ "$byte_len" -gt "$max_bytes" ]; then
    return 0
  fi
  printf '%s' "$json" | jq -r --arg id "$ws" '.[] | select(.activeWorkspace.id == ($id | tonumber)) | .name' 2>/dev/null || true
}

place_workspace() {
  local ws="$1" target="$2"

  focus_monitor "$target"
  focus_workspace "$ws"

  [ "$(active_monitor_for "$ws")" = "$target" ] && return 0

  # Pinned on the other monitor -- focus_workspace above already redirected
  # focus there, so force the rest of the way across.
  local direction
  [ "$target" = "$left_name" ] && direction="l" || direction="r"
  hyprctl dispatch "hl.dsp.workspace.move({ monitor = \"$direction\" })" >/dev/null 2>&1
}

place_workspace "$left_id" "$left_name"
place_workspace "$right_id" "$right_name"

if [ -n "$window_addr" ]; then
  focus_window_or_workspace
elif [ $(( id % 2 )) -eq 1 ]; then
  focus_monitor "$left_name"
else
  focus_monitor "$right_name"
fi
