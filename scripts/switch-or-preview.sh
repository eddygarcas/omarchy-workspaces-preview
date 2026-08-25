#!/bin/bash
# Called from ~/.config/hypr/bindings.lua for SUPER+<workspace number>.
#
# Switches straight to the workspace if it has 0-1 windows (nothing to pick
# between). If it has more, asks the eduard.workspaces bar widget to show its
# selector instead of switching -- picking a window there is what actually
# performs the switch. Falls back to a plain switch if the widget can't be
# reached (not loaded, disabled, etc.) so the key never does nothing.
set -euo pipefail

id=$1

focus() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$id\" })" >/dev/null 2>&1
}

count=$(hyprctl workspaces -j 2>/dev/null | jq -r --arg id "$id" '([.[] | select(.id == ($id | tonumber)) | .windows][0]) // 0')

if [ "${count:-0}" -le 1 ]; then
  focus
  exit 0
fi

result=$(omarchy-shell eduard.workspaces preview "$id" 2>/dev/null || true)
if [ "$result" != "ok" ]; then
  focus
fi
