#!/bin/bash
# Prints a line every time the system resumes from suspend. Quickshell's
# cached Hyprland.workspaces/monitors can go stale across a sleep cycle --
# events that happen while the IPC socket is suspended are missed, and
# nothing else pokes Quickshell to refetch afterwards. Workspaces.qml runs
# this and re-syncs on every line it prints.
#
# Wrapped in a restart loop so a dbus-monitor hiccup doesn't silently stop
# future resumes from being reported for the life of this bar instance.
while true; do
  dbus-monitor --system \
    "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null |
    grep --line-buffered 'boolean false' |
    sed -u 's/.*/resume/'
  sleep 1
done
