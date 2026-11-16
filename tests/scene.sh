#!/usr/bin/env bash
# Puts a nested session into a known state, so that the bar and the waybar
# reference can be screenshotted in the same situation (make compare,
# matrix cases B1 to B5). NESTED_DIR selects the session (default .test).
#
#   tests/scene.sh setup            workspaces 1, 2, 3 and 4:demo with a client
#                                   each, 3 urgent, focus on 2, two tray items
#                                   (once per session: it leaves scene-ready)
#   tests/scene.sh mode <name>      enter a sway mode ("default" leaves it)
#   tests/scene.sh present          enter the long cheat-sheet mode
#   tests/scene.sh long             enter the longer one (no room for a note)
#   tests/scene.sh focus-other      add a second output if needed, put it right of
#                                   HEADLESS-1 (1920x1080, scale 1) and focus it
#   tests/scene.sh focus-main       focus HEADLESS-1 again
#   tests/scene.sh plug             like focus-other, but the focus stays where it is
#   tests/scene.sh other            print the second output's name ("" if none)
#   tests/scene.sh unplug           remove the second output, focus HEADLESS-1
#   tests/scene.sh hover <x> <y>    move the pointer (logical coordinates)
#   tests/scene.sh tray <n> <status>  set tray item n (1 or 2) to Active,
#                                   Passive or NeedsAttention
#   tests/scene.sh tray-add <n>     start fake tray item n
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=${NESTED_DIR:-$REPO/.test}
export NESTED_DIR=$T

PRESENT="present: n next · p previous · b blank · z zoom · Escape leave the fictional cheat sheet"
# Longer than the room a 600 px note leaves (matrix case NW). Both names
# are modes of tests/sway-nested.conf.
LONG="present: n next · p previous · b blank · z zoom · f freeze · r reload · s swap screens · t timer · h hide notes · Escape leave the fictional cheat sheet that runs on past the clock"

n() { "$REPO/tests/nested.sh" run "$@"; }
msg() { n swaymsg -q -- "$@"; }

# Polls a command until it succeeds (5 s).
wait_for() {
    local what=$1; shift
    for _ in $(seq 50); do "$@" > /dev/null 2>&1 && return 0; sleep 0.1; done
    echo "scene: timed out waiting for $what" >&2; return 1
}

has_title() { n swaymsg -t get_tree | grep -q "\"name\": \"$1\""; }
item_count() {
    n busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems | awk '{print $2}'
}

client() { # workspace title
    msg workspace "$1"
    if ! has_title "$2"; then
        "$REPO/tests/nested.sh" run env CLIENT_TITLE="$2" quickshell -p "$REPO/tests/client" \
            > "$T/logs/$2.log" 2>&1 < /dev/null &
        wait_for "window $2" has_title "$2"
    fi
}

more_items() { [ "$(item_count)" -gt "$1" ]; }

# The output that is not HEADLESS-1. sway numbers headless outputs on
# from the last one created, so after an unplug the next is HEADLESS-3.
other() {
    n swaymsg -t get_outputs | python3 -c 'import json,sys; print(next((o["name"] for o in json.load(sys.stdin) if o["name"] != "HEADLESS-1"), ""))'
}

tray_add() {
    local before; before=$(item_count)
    "$REPO/tests/nested.sh" run env FAKE_SNI_PIDFILE="$T/fake-sni-$1.pid" FAKE_SNI_STATUS="${2:-Active}" \
        "$REPO/tests/fake-sni.py" > "$T/logs/fake-sni-$1.out" 2>&1 < /dev/null &
    wait_for "tray item $1" more_items "$before"
}

tray() { # n status
    local pid; pid=$(cat "$T/fake-sni-$1.pid")
    case $2 in
        Active) kill -USR2 "$pid" ;;
        Passive) kill -HUP "$pid" ;;
        NeedsAttention) kill -USR1 "$pid" ;;
        *) echo "scene: unknown status $2" >&2; exit 2 ;;
    esac
}

case ${1:-} in
    setup)
        client 1 client-1
        client 2 client-2
        client 3 client-3
        client 4:demo client-4
        msg workspace 2
        msg '[title="client-3"] urgent enable'
        tray_add 1
        tray_add 2
        msg seat seat0 cursor set 960 600
        touch "$T/scene-ready"
        ;;
    # swaymsg joins its arguments into one command: names with spaces need quotes.
    mode) msg mode "\"$2\"" ;;
    present) msg mode "\"$PRESENT\"" ;;
    long) msg mode "\"$LONG\"" ;;
    focus-other | plug)
        name=$(other)
        if [ -z "$name" ]; then
            msg create_output
            name=$(other)
        fi
        # sway may place a new output first: put both back where tests expect them.
        msg output HEADLESS-1 position 0 0
        msg output "$name" mode --custom 1920x1080 position 1920 0 scale 1
        [ "$1" = plug ] || msg focus output "$name"
        ;;
    focus-main) msg focus output HEADLESS-1 ;;
    other) other ;;
    unplug)
        name=$(other)
        [ -z "$name" ] || msg output "$name" unplug
        msg output HEADLESS-1 position 0 0
        msg focus output HEADLESS-1
        ;;
    hover) msg seat seat0 cursor set "$2" "$3" ;;
    tray) tray "$2" "$3" ;;
    tray-add) tray_add "$2" "${3:-Active}" ;;
    *) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2; exit 2 ;;
esac
