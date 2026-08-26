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

# Ceiling on the compositor's workspace JSON, applied before any of it
# reaches jq. Workspace state is normally under 2 KiB even with a dozen
# workspaces open (`lastwindowtitle` is the only unbounded-looking field,
# and even that's rarely more than a line), but that title text is
# client-controlled -- a misbehaving or adversarial window could set an
# arbitrarily large one, and this script runs on every workspace keybind.
# `head -c` bounds how much is ever read into the shell, not just how much
# jq is asked to parse.
max_bytes=262144

focus() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$id\" })" >/dev/null 2>&1
}

workspaces_json=$(hyprctl workspaces -j 2>/dev/null | head -c "$((max_bytes + 1))")
byte_len=$(LC_ALL=C printf '%s' "$workspaces_json" | wc -c)

if [ "$byte_len" -gt "$max_bytes" ]; then
  # Reject an over-limit document outright rather than handing jq a
  # truncated fragment (which could parse "successfully" into a wrong
  # count) -- degrade to a plain switch, the same fallback already used
  # when the widget itself can't be reached.
  focus
  exit 0
fi

count=$(printf '%s' "$workspaces_json" | jq -r --arg id "$id" '([.[] | select(.id == ($id | tonumber)) | .windows][0]) // 0')

if [ "${count:-0}" -le 1 ]; then
  focus
  exit 0
fi

result=$(omarchy-shell eduard.workspaces preview "$id" 2>/dev/null || true)
if [ "$result" != "ok" ]; then
  focus
fi
