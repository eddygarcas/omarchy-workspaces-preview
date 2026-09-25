#!/bin/bash
# Wires SUPER+<number> to this plugin's window picker by appending a marked
# block to ~/.config/hypr/bindings.lua. Run by hand -- Omarchy's plugin
# installer deliberately never runs plugin code or install hooks on
# add/update/enable, so this can't happen automatically. See README.md.
#
# The write is done through the resolved real file rather than the
# pathname: the path is resolved once, must be a regular file, the new
# content goes to a mktemp'd sibling (created O_EXCL, so no pre-existing
# file or symlink at that name is ever followed), and the result is moved
# into place atomically. Nothing here opens a caller-controlled pathname
# for writing.
set -euo pipefail

bindings="$HOME/.config/hypr/bindings.lua"
begin_marker="-- BEGIN eduard.workspaces keybinding (managed by scripts/install-keybinding.sh)"
end_marker="-- END eduard.workspaces keybinding"

real=$(realpath -e -- "$bindings" 2>/dev/null) || { echo "Not found: $bindings" >&2; exit 1; }
[ -f "$real" ] && [ ! -L "$real" ] || { echo "Not a regular file: $real" >&2; exit 1; }

if grep -qF -- "$begin_marker" "$real"; then
  echo "Already installed in $real"
  exit 0
fi

tmp=""
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
trap cleanup EXIT

backup=$(mktemp -- "$real.bak.$(date +%s).XXXXXX")
cat -- "$real" > "$backup"

tmp=$(mktemp -- "$real.tmp.XXXXXX")
{
  cat -- "$real"
  echo ""
  echo "$begin_marker"
  echo 'local workspace_picker = os.getenv("HOME") .. "/.config/omarchy/plugins/eduard.workspaces/scripts/switch-or-preview.sh"'
  echo 'for workspace = 1, 10 do'
  echo '  local key = "code:" .. tostring(workspace + 9)'
  echo '  hl.unbind("SUPER + " .. key)'
  echo '  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, workspace_picker .. " " .. tostring(workspace))'
  echo 'end'
  echo "$end_marker"
} > "$tmp"
chmod --reference="$real" -- "$tmp"
mv -f -- "$tmp" "$real"
tmp=""

echo "Wired SUPER+<number> to the window picker in $real"
echo "(backup saved as $backup; Hyprland picks this up automatically on save)"
