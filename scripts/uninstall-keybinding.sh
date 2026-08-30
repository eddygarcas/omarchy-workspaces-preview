#!/bin/bash
# Reverts install-keybinding.sh: removes the marked block from
# ~/.config/hypr/bindings.lua, restoring Hyprland's default SUPER+<number>
# behavior. Run by hand, same reasoning as install-keybinding.sh.
set -euo pipefail

bindings="$HOME/.config/hypr/bindings.lua"
begin_marker="-- BEGIN eduard.workspaces keybinding (managed by scripts/install-keybinding.sh)"
end_marker="-- END eduard.workspaces keybinding"

[ -f "$bindings" ] || { echo "Not found: $bindings" >&2; exit 1; }

if ! grep -qF -- "$begin_marker" "$bindings"; then
  echo "Not installed in $bindings"
  exit 0
fi

cp "$bindings" "$bindings.bak.$(date +%s)"

awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { skipping = 1; next }
  $0 == end { skipping = 0; next }
  !skipping { print }
' "$bindings" > "$bindings.tmp"
mv "$bindings.tmp" "$bindings"

echo "Removed the keybinding block from $bindings"
