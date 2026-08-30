#!/bin/bash
# Wires SUPER+<number> to this plugin's window picker by appending a marked
# block to ~/.config/hypr/bindings.lua. Run by hand -- Omarchy's plugin
# installer deliberately never runs plugin code or install hooks on
# add/update/enable, so this can't happen automatically. See README.md.
set -euo pipefail

bindings="$HOME/.config/hypr/bindings.lua"
begin_marker="-- BEGIN eduard.workspaces keybinding (managed by scripts/install-keybinding.sh)"
end_marker="-- END eduard.workspaces keybinding"

[ -f "$bindings" ] || { echo "Not found: $bindings" >&2; exit 1; }

if grep -qF -- "$begin_marker" "$bindings"; then
  echo "Already installed in $bindings"
  exit 0
fi

cp "$bindings" "$bindings.bak.$(date +%s)"

{
  echo ""
  echo "$begin_marker"
  echo 'local workspace_picker = os.getenv("HOME") .. "/.config/omarchy/plugins/eduard.workspaces/scripts/switch-or-preview.sh"'
  echo 'for workspace = 1, 10 do'
  echo '  local key = "code:" .. tostring(workspace + 9)'
  echo '  hl.unbind("SUPER + " .. key)'
  echo '  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, workspace_picker .. " " .. tostring(workspace))'
  echo 'end'
  echo "$end_marker"
} >> "$bindings"

echo "Wired SUPER+<number> to the window picker in $bindings"
echo "(backup saved alongside it; Hyprland picks this up automatically on save)"
