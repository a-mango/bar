#!/usr/bin/env bash
# The notification part of ~/Documents/scripts/screenshot.sh, without
# grimshot or `gio trash`. Like the real script, notify-send blocks until
# the notification closes and prints the action that was invoked, if any.
# This script prints that action ("discard") or nothing (matrix case N7).
#
#   tests/nested.sh run tests/fake-screenshot.sh [image.png]
set -euo pipefail
[ -n "${BAR_TEST_DIR:-}" ] || { echo "fake-screenshot: run me inside the nested session" >&2; exit 2; }

file=${1:-$BAR_TEST_DIR/demo-shot.png}
[ -e "$file" ] || magick -size 320x200 gradient: "$file"

action=$(notify-send -a screenshot -i "$file" -A discard=Discard \
    "Screenshot saved" \
    "$(basename "$file"). Right click to discard")
if [ "$action" = discard ]; then
    echo discard
fi
