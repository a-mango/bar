#!/bin/sh
# darkman hook. Installed at cutover (M8) as ~/.local/share/darkman/bar.sh
# with the executable bit set. darkman calls it with "dark" or "light".
# darkman may run without WAYLAND_DISPLAY, hence --any-display. The call
# fails quietly when bar is not running.
quickshell ipc --any-display -p "$HOME/.local/share/bar" call theme set "$1" > /dev/null 2>&1 || true
