#!/bin/bash
# Reverts install-keybinding.sh: removes the marked block from
# ~/.config/hypr/bindings.lua, restoring Hyprland's default SUPER+<number>
# behavior. Run by hand, same reasoning -- and same resolved-path,
# mktemp-then-rename write discipline -- as install-keybinding.sh.
set -euo pipefail

bindings="$HOME/.config/hypr/bindings.lua"
begin_marker="-- BEGIN eduard.workspaces keybinding (managed by scripts/install-keybinding.sh)"
end_marker="-- END eduard.workspaces keybinding"

real=$(realpath -e -- "$bindings" 2>/dev/null) || { echo "Not found: $bindings" >&2; exit 1; }
[ -f "$real" ] && [ ! -L "$real" ] || { echo "Not a regular file: $real" >&2; exit 1; }

if ! grep -qF -- "$begin_marker" "$real"; then
  echo "Not installed in $real"
  exit 0
fi

tmp=""
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
trap cleanup EXIT

backup=$(mktemp -- "$real.bak.$(date +%s).XXXXXX")
cat -- "$real" > "$backup"

tmp=$(mktemp -- "$real.tmp.XXXXXX")
awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { skipping = 1; next }
  $0 == end { skipping = 0; next }
  !skipping { print }
' "$real" > "$tmp"
chmod --reference="$real" -- "$tmp"
mv -f -- "$tmp" "$real"
tmp=""

echo "Removed the keybinding block from $real (backup saved as $backup)"
