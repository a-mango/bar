#!/usr/bin/env bash
# The docs/SPEC.md test matrix, run against the nested session (make nested).
#
#   tests/matrix.sh          run every case
#   tests/matrix.sh N5       run one case
#
# Each case is a shell function named case_<ID>. It saves screenshots to
# .test/shots/<ID>/ and returns non-zero on failure. M2 added B1 to B6,
# M1 the N cases, NX (paths outside the SPEC matrix), SC and END. M3 adds
# the OSD frame series (N5, N6, tests/frames.py), B7 for the OSD, RP (rapid
# presses) and ON (an OSD over a note). M4 adds N2, N4, N15, N16, the frame
# series of N1 to N4 and N15 (tests/strip-frames.py), HO (handoff), NW (note
# width beside a long mode name) and CPU (idle cost). M5 adds N7 (rich card
# and the screenshot.sh outcomes through real clicks), N17 (notes held
# during fullscreen), the screenshot and plain-note parts of B7, HV (hover
# pause) and CL (clicks per the rules table). Clicks leave the pointer
# where they landed, so reset_notifs parks it away from the bar. M6 adds
# N12 (focused output), HP (hotplug) and TH (theme switches during an OSD
# and a note).
# The B cases, the OSD cases and the note view cases set up tests/scene.sh
# once per session. N16 and END run last, in that order. N16 compares with a
# screenshot taken before the first case.
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=$REPO/.test

n() { "$REPO/tests/nested.sh" run "$@"; }             # a command inside the session
ipc() { n quickshell ipc -p "$REPO" call "$@"; }      # an IPC call to bar
scene() { "$REPO/tests/scene.sh" "$@"; }
click() { "$REPO/tests/nested.sh" click "$@"; }
# The pointer away from the bar: on a note it pauses the timer (M5).
park() { scene hover 960 600; }
px() { "$REPO/tests/pixel.py" "$@"; }

# Screenshot of HEADLESS-1 into .test/shots/<case>/<name>.png; prints the path.
shot() {
    mkdir -p "$T/shots/$1"
    n grim -o HEADLESS-1 "$T/shots/$1/$2.png"
    echo "$T/shots/$1/$2.png"
}

# palette <name> [dark|light]: a palette color by name, from themes/.
palette() { sed -n "s/^@define-color $1 \(#[0-9a-f]*\);/\1/p" "$REPO/themes/base16-default-${2:-dark}.css"; }

# check <what> <actual> <expected>: prints the result, fails on a mismatch.
check() {
    if [ "$2" = "$3" ]; then
        echo "  ok    $1: $2"
    else
        echo "  FAIL  $1: got '$2', expected '$3'"
        return 1
    fi
}
# more <what> <actual> <minimum>: fails unless actual >= minimum.
more() {
    if [ "$2" -ge "$3" ]; then
        echo "  ok    $1: $2 (>= $3)"
    else
        echo "  FAIL  $1: got $2, expected at least $3"
        return 1
    fi
}

# One field of `call debug state`, as a Python expression on `d`.
state() { ipc debug state | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
bar1() { echo "[b for b in d['bars'] if b['screen'] == 'HEADLESS-1'][0]"; }
focused_ws() { n swaymsg -t get_workspaces | python3 -c 'import json,sys; print([w["name"] for w in json.load(sys.stdin) if w["focused"]][0])'; }

# Logical geometry of the bar on HEADLESS-1 (1920x1200): row 1176.5 is the
# second physical row of the bar, above any text.
TOP=1176.5
MID=1188

# The test client's darkmagenta, as grim sees it.
CLIENT="#8b008b"
# A 1920x1200 picture for screenshot notes, made once per session.
shot_png() {
    local png=$T/demo-screenshot.png
    [ -e "$png" ] || n magick -size 1920x1200 gradient:steelblue-plum -fill white -pointsize 160 -gravity center -annotate 0 demo "$png"
    echo "$png"
}

# Center of tray icon <index> of <count>: icons 16 px, 14 px apart, 7 px
# from the right edge.
tray_x() { echo $((1920 - 7 - 8 - (${2} - 1 - ${1}) * 30)); }

prepare() {
    [ -e "$T/scene-ready" ] || scene setup
    ipc theme set dark
    scene focus-main
    scene mode default
    n swaymsg -q workspace 2
    scene hover 960 600
    sleep 0.3
}

case_B1() {
    local f=0 s
    prepare
    s=$(shot B1 focused)
    check "workspace 1 background" "$(px "$s" color 13 $TOP)" "$(palette base00)" || f=1
    check "workspace 2 background (focused)" "$(px "$s" color 39 $TOP)" "$(palette base07)" || f=1
    check "workspace 1 button" "$(px "$s" run 13 $TOP)" "0 26" || f=1
    check "workspace 2 button" "$(px "$s" run 39 $TOP)" "26 52" || f=1
    more "workspace 1 label (colors in the button)" "$(px "$s" ink 0 1177 26 1199)" 3 || f=1
    scene hover 13 $MID; sleep 0.3
    s=$(shot B1 hover)
    check "workspace 1 background (hover)" "$(px "$s" color 13 $TOP)" "$(palette base03)" || f=1
    scene hover 960 600
    scene focus-other; sleep 0.5
    s=$(shot B1 visible)
    check "workspace 2 background (visible, focus on HEADLESS-2)" "$(px "$s" color 39 $TOP)" "$(palette base02)" || f=1
    scene focus-main; sleep 0.3
    click 65 $MID; sleep 0.3
    check "focused workspace after a click on 3" "$(focused_ws)" 3 || f=1
    n swaymsg -q workspace 2
    # The wheel steps through this output's workspaces and wraps around
    # (after M8). Up first, so that the urgent 3 is never focused.
    echo "  wheel and touchpad over the workspaces (tests/wheel.py)"
    scene hover 13 $MID; sleep 0.2
    n "$REPO/tests/wheel.py" notch -1; sleep 0.3
    check "one notch up from 2" "$(focused_ws)" 1 || f=1
    n "$REPO/tests/wheel.py" notch 1; sleep 0.3
    check "one notch down, back" "$(focused_ws)" 2 || f=1
    n "$REPO/tests/wheel.py" notch -2; sleep 0.3
    check "two quick notches up from 2: 1, then wraps to the last" "$(focused_ws)" 4:demo || f=1
    n "$REPO/tests/wheel.py" notch 2; sleep 0.3
    check "two notches down: wraps to 1, then 2" "$(focused_ws)" 2 || f=1
    n "$REPO/tests/wheel.py" finger -4 10; sleep 0.5
    check "a 40 px touchpad swipe: no step" "$(focused_ws)" 2 || f=1
    n "$REPO/tests/wheel.py" finger -6 10; sleep 0.3
    check "a 60 px touchpad swipe up: one step" "$(focused_ws)" 1 || f=1
    n swaymsg -q workspace 2
    scene hover 960 600
    return $f
}

case_B2() {
    local f=0 s
    prepare
    n swaymsg -q '[title="client-3"] urgent enable'; sleep 0.3
    s=$(shot B2 urgent)
    check "workspace 3 background (urgent, hidden)" "$(px "$s" color 65 $TOP)" "$(palette base08)" || f=1
    return $f
}

case_B3() {
    local f=0 s name width
    prepare
    scene mode resize; sleep 0.3
    s=$(shot B3 resize)
    check "mode label background" "$(px "$s" color 150 $TOP)" "$(palette base04)" || f=1
    check "mode label box (after workspaces 0..136, 4 + 2 px gap)" "$(px "$s" run 150 $TOP)" "142 204" || f=1
    more "mode label text (colors in the box)" "$(px "$s" ink 142 1177 204 1199)" 3 || f=1
    scene present; sleep 0.3
    name=$(n swaymsg -t get_binding_state | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
    width=$(python3 -c 'import sys; print(len(sys.argv[1]) * 8 + 14)' "$name")
    s=$(shot B3 present)
    check "long mode label box ($(printf %s "$name" | wc -m) characters, 8 px each + 14)" "$(px "$s" run 150 $TOP)" "142 $((142 + width))" || f=1
    scene mode default; sleep 0.3
    s=$(shot B3 default)
    check "mode label hidden in default" "$(px "$s" color 150 $TOP)" "$(palette base00)" || f=1
    return $f
}

case_B4() {
    local f=0 a b c idle
    prepare
    [ "$(state "$(bar1)['clock']['seconds']")" = True ] && { click 960 $MID; sleep 1.2; }
    idle=$(shot B4 idle)
    click 960 $MID; sleep 1.2
    scene hover 960 600; sleep 0.3
    a=$(shot B4 seconds-1); sleep 1.0
    b=$(shot B4 seconds-2)
    check "seconds shown after a click" "$(state "$(bar1)['clock']['seconds']")" True || f=1
    more "clock text changes within one second" "$(px "$a" diff "$b" 900 1177 1020 1199)" 1 || f=1
    check "clock box with seconds (8 characters + 14 px)" "$(state "$(bar1)['clock']['width']")" 78 || f=1
    click 960 $MID; sleep 1.2
    check "seconds hidden after a second click" "$(state "$(bar1)['clock']['seconds']")" False || f=1
    scene hover 960 600; sleep 0.3
    scene hover 960 $MID; sleep 1.0
    c=$(shot B4 calendar)
    check "calendar shown on hover" "$(state "$(bar1)['clock']['calendar']")" True || f=1
    check "clock background on hover" "$(px "$c" color 890 $TOP)" "$(palette base07)" || f=1
    check "clock box (centered, text + 14 px)" "$(px "$c" run 890 $TOP)" "889 1031" || f=1
    more "calendar drawn above the clock" "$(px "$c" diff "$idle" 860 1000 1060 1170)" 1000 || f=1
    scene hover 960 600; sleep 0.5
    check "calendar hidden after leaving" "$(state "$(bar1)['clock']['calendar']")" False || f=1
    return $f
}

case_B5() {
    local f=0 pid count index x a b c before menu box mark log
    prepare
    pid=$(cat "$T/fake-sni-1.pid")
    log=$T/logs/fake-sni.log
    count=$(state "len(d['tray'])")
    check "tray items (two fake items from the scene)" "$count" 2 || f=1
    a=$(shot B5 idle)
    for i in $(seq 0 $((count - 1))); do
        more "icon $i drawn at x $(tray_x "$i" "$count")" "$(px "$a" ink $(($(tray_x "$i" "$count") - 8)) 1180 $(($(tray_x "$i" "$count") + 8)) 1196)" 2 || f=1
    done
    scene tray 1 NeedsAttention; sleep 0.3
    index=$(state "[i for i, t in enumerate(d['tray']) if t['status'] == 2][0]")
    x=$(tray_x "$index" "$count")
    # The blink is a fade with a 1 s period, and a full-output shot takes
    # about half a second: two shots can land one period apart (seen in the
    # M5 run). Three shots with unequal gaps cannot all match.
    a=$(shot B5 attention-1); sleep 0.3
    b=$(shot B5 attention-2); sleep 0.55
    c=$(shot B5 attention-3)
    more "NeedsAttention: the background above icon $index changes" "$(python3 -c "print(max($(px "$a" diff "$b" $((x - 8)) 1177 $((x + 8)) 1179), $(px "$b" diff "$c" $((x - 8)) 1177 $((x + 8)) 1179)))")" 1 || f=1
    # Passive items are hidden, as waybar hides them (M8): the right-aligned
    # Row closes up, so the leftmost slot empties and the tray starts 30 px
    # further right.
    b=$(state "$(bar1)['trayStart']")
    scene tray 1 Passive; sleep 0.3
    a=$(shot B5 passive)
    check "Passive: icons drawn" "$(state "$(bar1)['trayShown']")" $((count - 1)) || f=1
    check "Passive: leftmost slot empty (one color)" "$(px "$a" ink $(($(tray_x 0 "$count") - 8)) 1180 $(($(tray_x 0 "$count") + 8)) 1196)" 1 || f=1
    check "Passive: tray start moves right" "$(python3 -c "print(round($(state "$(bar1)['trayStart']") - $b))")" 30 || f=1
    scene tray 1 Active; sleep 0.3
    check "Active again: icons drawn" "$(state "$(bar1)['trayShown']")" "$count" || f=1
    mark=$(wc -l < "$log")
    click "$x" $MID; sleep 0.3
    click "$x" $MID button2; sleep 0.3
    n swaymsg -q seat seat0 cursor press button4; sleep 0.3
    check "left click" "$(tail -n +$((mark + 1)) "$log" | grep -c "\[$pid\] Activate ")" 1 || f=1
    check "middle click" "$(tail -n +$((mark + 1)) "$log" | grep -c "\[$pid\] SecondaryActivate ")" 1 || f=1
    check "wheel up" "$(tail -n +$((mark + 1)) "$log" | grep -o "\[$pid\] Scroll .*")" "[$pid] Scroll -1 vertical" || f=1
    scene hover 960 600; sleep 0.5
    before=$(shot B5 before-menu)
    click "$x" $MID button3; sleep 0.8
    menu=$(shot B5 menu)
    check "menu open after a right click" "$(state "d['tray'][$index]['menuOpen']")" True || f=1
    box=$(px "$menu" bbox "$before")
    echo "  menu box (logical): $box"
    mark=$(wc -l < "$log")
    # The menu drawn in QML (TrayMenu, M7): 1 px frame and 3 px padding,
    # rows of 24 px, the separator 9 px. "Sync demo data" is the second
    # row, its middle 40 px below the menu's top.
    read -r x0 y0 x1 _ <<< "$box"
    check "menu height: seven rows and a separator (185 px)" "$(python3 -c "print(int(${box##* } - $y0))")" 185 || f=1
    click "$(python3 -c "print(int(($x0 + $x1) / 2))")" "$(python3 -c "print(int($y0 + 40))")"; sleep 0.5
    check "click on an entry reaches the item" "$(tail -n +$((mark + 1)) "$log" | grep -o "\[$pid\] Event 2 clicked .*")" "[$pid] Event 2 clicked 'Sync demo data'" || f=1
    check "menu closed after the click" "$(state "d['tray'][$index]['menuOpen']")" False || f=1

    echo "  submenu: 'Demo layouts', then 'Layout north'"
    click "$x" $MID button3; sleep 0.8
    mark=$(wc -l < "$log")
    # "Demo layouts" is the eighth row, 157 to 181 px below the top. Its
    # submenu (two rows, 56 px) opens left of it, bottom on the row's bottom.
    click "$(python3 -c "print(int(($x0 + $x1) / 2))")" "$(python3 -c "print(int($y0 + 169))")"; sleep 0.6
    check "submenu opened" "$(tail -n +$((mark + 1)) "$log" | grep -c "\[$pid\] Event 8 opened ")" 1 || f=1
    click "$(python3 -c "print(int($x0 - 30))")" "$(python3 -c "print(int($y0 + 181 - 56 + 16))")"; sleep 0.6
    check "click in the submenu reaches the item" "$(tail -n +$((mark + 1)) "$log" | grep -o "\[$pid\] Event 9 clicked .*")" "[$pid] Event 9 clicked 'Layout north'" || f=1
    check "both menus closed" "$(state "d['tray'][$index]['menuOpen']")" False || f=1

    echo "  the grab ignores bar's own surfaces: the bar closes the menu"
    click "$x" $MID button3; sleep 0.6
    click "$x" $MID button3; sleep 0.6
    check "a second right click closes it" "$(state "d['tray'][$index]['menuOpen']")" False || f=1
    click "$x" $MID button3; sleep 0.6
    click 600 $MID; sleep 0.6
    check "a press on the bar outside the tray closes it" "$(state "d['tray'][$index]['menuOpen']")" False || f=1
    scene hover 960 600
    return $f
}

case_B6() {
    local out
    out=$(n env SNI_WAIT_TIMEOUT=10 /usr/libexec/sway-systemd/wait-sni-ready 2>&1)
    echo "  $out"
    check "wait-sni-ready (the script exits 0 on failure too)" "$(grep -c 'Successfully waited for org.kde.StatusNotifierHost' <<< "$out")" 1
}

# B7: a fullscreen client covers the bar. A volume OSD (M3) and a
# screenshot note with its card draw above it, a plain note waits in the
# queue until fullscreen ends (M5, decision D5).
case_B7() {
    local f=0 s client=$CLIENT out p plain x
    prepare
    reset_notifs
    n swaymsg -q '[title="client-2"] fullscreen enable'
    sleep 0.5
    s=$(shot B7 fullscreen)
    check "bar covered by the fullscreen client" "$(px "$s" color 39 $TOP)" "$client" || f=1
    send -a volume -t 3000 -e -h int:value:60 -h string:x-canonical-private-synchronous:volume "Volume: 60%" > /dev/null
    sleep 0.5
    s=$(shot B7 osd)
    check "OSD fill above the client" "$(px "$s" color 2 $TOP)" "$(palette base0D)" || f=1
    check "OSD fill at 60 % of 1920 px" "$(px "$s" run 2 $TOP)" "0 1152" || f=1
    check "OSD empty part above the client" "$(px "$s" color 1900 $TOP)" "$(palette base00)" || f=1
    more "OSD label above the client (base00 over the fill)" "$(px "$s" count "$(palette base00)" 900 1177 1020 1199)" 50 || f=1
    check "client still shown above the bar rows" "$(px "$s" color 960 1170)" "$client" || f=1
    ipc notify dismiss
    wait_unmapped

    echo "  a screenshot note, then a plain note, over the fullscreen client"
    out=$T/logs/B7-screenshot.out
    n "$REPO/tests/fake-screenshot.sh" "$(shot_png)" > "$out" 2>&1 &
    p=$!
    sleep 1.3
    plain=$(send "Held note" "fictional note behind a fullscreen client")
    sleep 0.3
    s=$(shot B7 screenshot)
    check "screenshot note on display over fullscreen" "$(notif "(d['current']['app'], d['kind'], d['fullscreen'])")" "('screenshot', 'rich', True)" || f=1
    check "screenshot note line above the client (base01)" "$(px "$s" color 1000 1179)" "$(palette base01)" || f=1
    x=$(view "round(v['card']['x'])")
    check "card above the client (base01 frame)" "$(px "$s" color $((x + 1)) 1105)" "$(palette base01)" || f=1
    more "card thumbnail above the client" "$(px "$s" ink $((x + 4)) 1108 $((x + 90)) 1172)" 50 || f=1
    check "plain note held in the queue" "$(notif "d['held']")" "[$plain]" || f=1
    check "counter for the held note" "$(view "v['counter']")" "+1" || f=1
    # A left click dismisses the screenshot note: notify-send prints nothing.
    click 1000 $MID
    park
    wait "$p" || true
    check "screenshot dismissed by a left click, nothing printed" "$(wc -c < "$out")" 0 || f=1
    wait_unmapped
    s=$(shot B7 held)
    check "plain note still held, nothing on display" "$(notif "(d['note'], d['held'])")" "(None, [$plain])" || f=1
    check "overlay unmapped while the note is held" "$(mapped_h1)" False || f=1
    check "bar rows still show the client" "$(px "$s" color 1000 1179)" "$client" || f=1
    n swaymsg -q '[title="client-2"] fullscreen disable'
    sleep 1
    s=$(shot B7 after-fullscreen)
    check "plain note on display once fullscreen ends" "$(notif "d['current']['summary']")" "Held note" || f=1
    check "plain note drawn (base01)" "$(px "$s" color 1000 1179)" "$(palette base01)" || f=1
    reset_notifs
    return $f
}

# ---- notifications (M1) ----------------------------------------------

# Bus log of the case: every Notify, CloseNotification, NotificationClosed
# and ActionInvoked on the private bus, with dbus-monitor's timestamps.
bus_start() {
    BUSLOG=$T/logs/bus-$1.log
    "$REPO/tests/nested.sh" run dbus-monitor --session "interface='org.freedesktop.Notifications'" > "$BUSLOG" 2>&1 &
    BUSPID=$!
    sleep 0.5
}
bus_stop() {
    sleep 0.2
    kill "$BUSPID" 2>/dev/null || true
    wait "$BUSPID" 2>/dev/null || true
}
# closed <id> <summary>: "<reason> <seconds since the Notify with that summary>"
closed() { "$REPO/tests/buslog.py" "$BUSLOG" closed "$1" "$2"; }
# within <what> <actual> <expected> [tolerance]: seconds within tolerance (0.3 s).
within() {
    if python3 -c 'import sys; sys.exit(0 if abs(float(sys.argv[1]) - float(sys.argv[2])) <= float(sys.argv[3]) else 1)' "${2:-nan}" "$3" "${4:-0.3}" 2> /dev/null; then
        echo "  ok    $1: $2 s (expected $3 ± ${4:-0.3})"
    else
        echo "  FAIL  $1: '$2' s, expected $3 ± ${4:-0.3}"
        return 1
    fi
}
# One field of `call notify status`, as a Python expression on `d`.
notif() { ipc notify status | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
send() { n notify-send -p "$@"; }
# The overlay of HEADLESS-1 in a state `d`. Since M6 a notification maps
# the overlay of one output only (the focused one), and the cases that do
# not move the focus run on HEADLESS-1 (reset_notifs focuses it).
H1="[o for o in d['overlays'] if o['screen'] == 'HEADLESS-1'][0]"
mapped_h1() { state "$H1['visible']"; }
overlay_mapped() { mapped_h1; }
# Waits for the overlay of HEADLESS-1 to unmap: the note view's leave and the
# OSD's fade-out run after the notification closed (up to about 0.5 s).
wait_unmapped() {
    for _ in $(seq 40); do
        [ "$(mapped_h1)" = False ] && return 0
        sleep 0.1
    done
    return 1
}
# focus_main and focus_other move the focus and wait until bar has seen it
# (Sway.focusedOutput), so that the next notification goes there.
focus_wait() {
    for _ in $(seq 30); do
        [ "$(state "d['focusedOutput']")" = "$1" ] && return 0
        sleep 0.1
    done
    echo "  note: bar still sees the focus on $(state "d['focusedOutput']"), not $1"
    return 1
}
focus_main() { scene focus-main; focus_wait HEADLESS-1; }
focus_other() { scene focus-other; OTHER=$(scene other); focus_wait "$OTHER"; }
# Every case starts and ends with nothing on display, DND off and the focus
# on HEADLESS-1. The overlays unmap only once their leave animations have
# ended.
reset_notifs() {
    # The pointer left on the span by a click would pause the next note (M5).
    park
    focus_main
    ipc notify dismissAll
    ipc notify setDnd false
    ipc debug slow 1
    for _ in $(seq 70); do
        [ "$(notif "d['tracked']")" = 0 ] && [ "$(state "any(o['visible'] for o in d['overlays'])")" = False ] && return 0
        sleep 0.1
    done
    echo "  note: $(notif "d['tracked']") notification(s) still tracked or an overlay still mapped after the reset"
}
# closed_check <what> <id> <summary> <reason> <seconds> [tolerance]
closed_check() {
    local r t
    read -r r t <<< "$(closed "$2" "$3")"
    check "$1: NotificationClosed reason" "$r" "$4" && within "$1: closed after" "$t" "$5" "${6:-0.3}"
}

case_N1() {
    local f=0 id s left tray
    prepare
    reset_notifs
    bus_start N1
    id=$(send "Build finished" "demo-app compiled in 42 s")
    sleep 1.4
    s=$(shot N1 visible)
    check "on display" "$(notif "d['current']['summary']")" "Build finished" || f=1
    check "kind" "$(notif "d['kind']")" note || f=1
    check "overlay mapped" "$(overlay_mapped)" True || f=1
    check "note view open" "$(view "v['phase']")" open || f=1
    left=$(state "$(bar1)['leftEnd']")
    tray=$(state "$(bar1)['trayStart']")
    check "span from the left section + 8 (scene: workspaces end at 136)" "$(view "v['span']['x']")" "$(python3 -c "print(round($left + 8))")" || f=1
    check "span to the tray - 8 (scene: tray starts at 1867)" "$(view "v['span']['end']")" "$(python3 -c "print(round($tray - 8))")" || f=1
    check "compact clock at the span's left edge, 'HH:mm' + 14 px" "$(view "(v['clock']['x'], v['clock']['width'])")" "(144, 54)" || f=1
    more "compact clock text drawn" "$(px "$s" ink 144 1180 198 1198)" 3 || f=1
    check "note background (base01) from the separator on" "$(px "$s" run 1000 1179 | cut -d' ' -f1)" 206 || f=1
    check "note background over the bar's clock box" "$(px "$s" color 960 1179)" "$(palette base01)" || f=1
    check "progress line on the top edge (base03)" "$(px "$s" color 220 1176)" "$(palette base03)" || f=1
    sleep 4.5
    bus_stop
    closed_check "note" "$id" "Build finished" 1 5.0 || f=1
    wait_unmapped
    check "overlay unmapped after the leave animation" "$(overlay_mapped)" False || f=1

    echo "  frame series (slow motion x10): enter, then leave after a dismiss"
    ipc debug slow 10
    strip_frames N1 enter 10 0 80 160 240 320 400 480 560 640 720 800 900 1050 -- notify-send -t 30000 "Build finished" "demo-app compiled in 42 s"
    strip_frames N1 leave 10 0 100 200 300 400 500 600 700 800 900 -- quickshell ipc -p "$REPO" call notify dismiss
    ipc debug slow 1
    wait_unmapped
    reset_notifs
    return $f
}

case_N3() {
    local f=0 a b c ta s1 s3
    prepare
    reset_notifs
    bus_start N3
    a=$(send "Note one" "first of three"); ta=$(date +%s.%N); sleep 0.1
    b=$(send "Note two" "second of three"); sleep 0.1
    c=$(send "Note three" "third of three")
    sleep 0.8
    s1=$(shot N3 first)
    check "first on display" "$(notif "d['current']['summary']")" "Note one" || f=1
    check "waiting (+2)" "$(notif "d['queued']")" 2 || f=1
    check "counter" "$(view "v['counter']")" "+2" || f=1
    # The roll starts when note one times out, 5 s after it arrived. Slow
    # motion x10 for that roll only.
    until_t "$ta" 4.5
    ipc debug slow 10
    echo "  frame series of the roll (slow motion x10)"
    FRAMES_T0=$(python3 -c "print($ta + 5.0)") strip_frames N3 roll 10 0 25 50 75 100 150 200 300 400
    check "second on display after the first leaves" "$(notif "d['current']['summary']")" "Note two" || f=1
    check "waiting (+1)" "$(notif "d['queued']")" 1 || f=1
    check "counter after the roll" "$(view "v['counter']")" "+1" || f=1
    check "no second wipe: the span stayed open" "$(view "(v['phase'], v['w'], v['clock']['width'])")" "('open', 1, 54)" || f=1
    ipc debug slow 1
    until_t "$ta" 10.6
    s3=$(shot N3 third)
    check "third on display" "$(notif "d['current']['summary']")" "Note three" || f=1
    check "no counter with nothing waiting" "$(view "v['counter']")" "" || f=1
    more "counter drawn at the span's right end (+2 against none)" "$(px "$s1" diff "$s3" 1828 1180 1856 1198)" 10 || f=1
    until_t "$ta" 15.6
    bus_stop
    closed_check "first, from its arrival" "$a" "Note one" 1 5.0 || f=1
    closed_check "second, from the first arrival" "$b" "Note one" 1 10.0 || f=1
    closed_check "third, from the first arrival" "$c" "Note one" 1 15.0 || f=1
    reset_notifs
    return $f
}

# ---- OSD frame series (M3) --------------------------------------------

# frames <dir> <event>...: a frame series (tests/frames.py) into
# .test/shots/<dir>/. Events: "<ms> shot", "<ms> run <command>".
frames() {
    local dir=$T/shots/$1
    shift
    rm -rf "$dir"
    n "$REPO/tests/frames.py" "$dir" "$@" > /dev/null
    FJ=$dir/frames.json
    FD=$dir
}
# fj <expression>: a field of the last frames.json (`d`).
fj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$FJ"; }
# fstate <expression>: a field of the `debug state` run in the last series (`d`).
fstate() {
    python3 -c "import json,sys; d=json.loads([r for r in json.load(open(sys.argv[1]))['runs'] if 'debug state' in r['cmd']][0]['stdout']); print($1)" "$FJ"
}
# "<maps> <entries> <updates>" of the HEADLESS-1 overlay and its OSD view.
osd_counts() { state "(lambda o: '%d %d %d' % (o['maps'], o['osd']['entries'], o['osd']['updates']))($H1)"; }
# counts_check <what> <before> <after> <maps> <entries> <updates>: deltas.
counts_check() {
    local m0 e0 u0 m1 e1 u1 f=0
    read -r m0 e0 u0 <<< "$2"
    read -r m1 e1 u1 <<< "$3"
    check "$1: overlay maps (one layer surface each)" $((m1 - m0)) "$4" || f=1
    check "$1: entry animations" $((e1 - e0)) "$5" || f=1
    check "$1: updates of the same strip" $((u1 - u0)) "$6" || f=1
    return $f
}
# osd_cmd <app> <value> [timeout] [summary]: an OSD sender's notify-send, as
# ~/bin/volume-helper sends it (transient, synchronous tag = app name).
osd_cmd() {
    echo "notify-send -p -a $1 -t ${3:-800} -e -h int:value:$2 -h string:x-canonical-private-synchronous:$1 '${4:-${1^}: $2%}'"
}
# Rows in a frame of the default region (the overlay window, y 1104 to
# 1200): CTOP is TOP, the bar's text box spans 73 to 95.
CTOP=72.5
# frame_times: "<requested> -> <frame time>" for every shot of the last series.
frame_times() { fj "', '.join('%d -> %.1f' % (s['at'], s['frame_ms']) for s in d['shots'])"; }

case_N5() {
    local f=0 v ev=() ids=() c0 c1 x300 x900
    prepare
    reset_notifs
    c0=$(osd_counts)
    bus_start N5
    for v in 10 20 30 40 50; do
        ev+=("$(((v / 10 - 1) * 100)) run $(osd_cmd volume $v)")
    done
    # The last OSD lives 800 ms from about 420 ms: the state at 500 ms.
    frames N5 "${ev[@]}" "0 shot" "60 shot" "120 shot" "300 shot" "900 shot" \
        "500 run quickshell ipc -p $REPO call debug state"
    mapfile -t ids < <(fj "'\n'.join(r['stdout'] for r in d['runs'] if r['cmd'].startswith('notify-send'))")
    echo "  frames (requested -> frame time, ms): $(frame_times); $FD/sheet.png"
    check "kind on display" "$(fstate "d['notifs']['kind']")" osd || f=1
    check "OSD value" "$(fstate "d['notifs']['osd']['value']")" 50 || f=1
    check "OSD id (the last one)" "$(fstate "d['notifs']['osd']['id']")" "${ids[4]}" || f=1
    check "nothing queued, no note" "$(fstate "(d['notifs']['queued'], d['notifs']['note'])")" "(0, None)" || f=1
    check "overlay mapped on HEADLESS-1" "$(fstate "$H1['visible']")" True || f=1
    check "0 ms: idle bar (focused workspace button, no strip)" "$(px "$FD/t0000.png" color 39 $CTOP)" "$(palette base07)" || f=1
    if [ "$(px "$FD/t0060.png" color 2 $CTOP)" != "$(palette base0D)" ]; then
        echo "  ok    60 ms: entry not finished (no opaque fill yet)"
    else
        echo "  FAIL  60 ms: the strip is already opaque"
        f=1
    fi
    check "300 ms: opaque fill" "$(px "$FD/t0300.png" color 2 $CTOP)" "$(palette base0D)" || f=1
    x300=$(px "$FD/t0300.png" run 2 $CTOP | cut -d' ' -f2)
    x900=$(px "$FD/t0900.png" run 2 $CTOP | cut -d' ' -f2)
    if python3 -c 'import sys; a, b = map(float, sys.argv[1:]); sys.exit(0 if 0 < a <= b else 1)' "$x300" "$x900"; then
        echo "  ok    fill grows through the values: $x300 px at 300 ms, $x900 px at 900 ms"
    else
        echo "  FAIL  fill does not grow: $x300 px at 300 ms, $x900 px at 900 ms"
        f=1
    fi
    check "900 ms: fill at 50 % of 1920 px" "$x900" 960 || f=1
    check "900 ms: empty part" "$(px "$FD/t0900.png" color 1900 $CTOP)" "$(palette base00)" || f=1
    more "900 ms: label over the fill, in base00" "$(px "$FD/t0900.png" count "$(palette base00)" 900 73 960 95)" 50 || f=1
    more "900 ms: label over the empty part, in base05" "$(px "$FD/t0900.png" count "$(palette base05)" 960 73 1020 95)" 50 || f=1
    check "900 ms: no base05 over the fill" "$(px "$FD/t0900.png" count "$(palette base05)" 900 73 960 95)" 0 || f=1
    sleep 0.6
    bus_stop
    for v in 0 1 2 3; do
        closed_check "OSD $((v + 1)) replaced by the next" "${ids[$v]}" "Volume: $((v * 10 + 20))%" 1 0.0 0.2 || f=1
    done
    closed_check "last OSD (sender timeout 800 ms)" "${ids[4]}" "Volume: 50%" 1 0.8 || f=1
    wait_unmapped || true
    check "overlay unmapped after the fade-out" "$(mapped_h1)" False || f=1
    c1=$(osd_counts)
    counts_check "five presses" "$c0" "$c1" 1 1 4 || f=1
    reset_notifs
    return $f
}

# Brightness and microphone at value 0: the label stays readable over the
# empty strip. Then the same and full fills in both themes (palette sheets
# for the owner), and a click on the strip.
case_N6() {
    local f=0 app summary s mode c0 c1 id
    prepare
    for app in brightness microphone; do
        reset_notifs
        summary="${app^}: 0%"
        [ "$app" = microphone ] && summary="Microphone: muted"
        c0=$(osd_counts)
        frames "N6/$app" "0 run $(osd_cmd "$app" 0 800 "$summary")" "0 shot" "60 shot" "120 shot" "300 shot" "900 shot"
        echo "  $app frames (requested -> frame time, ms): $(frame_times); $FD/sheet.png"
        s=$FD/t0300.png
        check "$app: strip over the bar (focused workspace button covered)" "$(px "$s" color 39 $CTOP)" "$(palette base00)" || f=1
        check "$app: no fill at value 0 (one color over the whole row)" "$(px "$s" run 2 $CTOP)" "0 1920" || f=1
        more "$app: label pixels in base05" "$(px "$s" count "$(palette base05)" 860 73 1060 95)" 150 || f=1
        check "$app: clock hidden under the strip (no base07)" "$(px "$s" count "$(palette base07)" 860 73 1060 95)" 0 || f=1
        wait_unmapped || true
        c1=$(osd_counts)
        counts_check "$app" "$c0" "$c1" 1 1 0 || f=1
    done

    # Palette sheets: value 0 and 100 per app, dark then light.
    for mode in dark light; do
        reset_notifs
        ipc theme set "$mode"
        sleep 0.3
        frames "N6/palette-$mode" "0 run $(osd_cmd brightness 0 5000)" "300 shot" \
            "400 run $(osd_cmd brightness 100 5000)" "700 shot" \
            "800 run $(osd_cmd microphone 0 5000 "Microphone: muted")" "1100 shot" \
            "1200 run $(osd_cmd microphone 100 5000 "Microphone: on")" "1500 shot" \
            "1600 run $(osd_cmd volume 0 5000)" "1900 shot" \
            "2000 run $(osd_cmd volume 100 5000)" "2300 shot"
        echo "  palette ($mode): $FD/sheet.png"
    done
    reset_notifs
    ipc theme set dark
    sleep 0.3

    # A click on the strip dismisses it (reason 2) and stays out of the bar.
    bus_start N6
    id=$(send -a brightness -t 5000 -e -h int:value:40 -h string:x-canonical-private-synchronous:brightness "Brightness: 40%")
    sleep 0.4
    click 960 $MID
    sleep 0.3
    bus_stop
    check "click on the OSD: NotificationClosed reason" "$(closed "$id" "Brightness: 40%" | cut -d' ' -f1)" 2 || f=1
    check "the click did not reach the clock below" "$(state "$(bar1)['clock']['seconds']")" False || f=1
    reset_notifs
    return $f
}

case_N8() {
    local f=0 id h0
    reset_notifs
    ipc notify setDnd true
    h0=$(notif "d['history']")
    bus_start N8
    id=$(send "Quiet note" "sent during DND")
    sleep 0.5
    shot N8 dnd > /dev/null
    check "nothing on display" "$(notif "d['visible']")" False || f=1
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    check "hidden" "$(notif "d['hidden']")" 1 || f=1
    sleep 5
    bus_stop
    closed_check "hidden note" "$id" "Quiet note" 1 5.0 || f=1
    # The list keeps the last 20: a full matrix run fills it before N8.
    check "history grew by one, up to 20" "$(notif "d['history']")" $((h0 < 20 ? h0 + 1 : 20)) || f=1
    check "newest history entry" "$(notif "d['newest']")" "Quiet note" || f=1
    reset_notifs
    return $f
}

case_N9() {
    local f=0 id
    reset_notifs
    bus_start N9
    id=$(send "Closing early" "the sender closes it")
    sleep 1
    n gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification "$id" > /dev/null
    sleep 0.5
    bus_stop
    closed_check "CloseNotification" "$id" "Closing early" 3 1.0 0.4 || f=1
    check "nothing on display" "$(notif "d['visible']")" False || f=1
    reset_notifs
    return $f
}

case_N10() {
    local f=0 id id2
    reset_notifs
    bus_start N10
    id=$(send "First text" "before the update")
    sleep 2
    id2=$(send -r "$id" "Second text" "after the update")
    sleep 0.3
    shot N10 updated > /dev/null
    check "same id after notify-send -r" "$id2" "$id" || f=1
    check "text changed in place" "$(notif "(d['current']['id'], d['current']['summary'])")" "($id, 'Second text')" || f=1
    sleep 5.5
    bus_stop
    closed_check "timer restarted by the update" "$id" "Second text" 1 5.0 || f=1
    check "closed once" "$("$REPO/tests/buslog.py" "$BUSLOG" count "$id")" 1 || f=1
    reset_notifs
    return $f
}

case_N11() {
    local f=0 id
    reset_notifs
    bus_start N11
    id=$(send "Survivor" "kept across a reload")
    sleep 1
    touch "$REPO/shell.qml"
    sleep 2
    shot N11 after-reload > /dev/null
    check "still on display after the reload" "$(notif "d['current']['id']")" "$id" || f=1
    check "marked as a survivor (no second entry animation)" "$(notif "d['note']['restored']")" True || f=1
    check "note view back open without the entry animation" "$(view "(v['phase'], v['c'], v['w'])")" "('open', 1, 1)" || f=1
    sleep 5
    bus_stop
    # Timer restarted at the reload: about 1 s + reload + 5 s, not 5 s.
    closed_check "survivor" "$id" "Survivor" 1 6.4 0.9 || f=1
    wait_unmapped

    echo "  a screenshot note survives with its card up (M5)"
    screenshot_start N11-rich
    touch "$REPO/shell.qml"
    sleep 2
    check "screenshot note still on display, a survivor" "$(notif "(d['current']['id'], d['note']['restored'])")" "($SHOT_ID, True)" || f=1
    check "card back up, span open" "$(view "(v['phase'], v['w'], v['card']['r'], v['card']['ready'])")" "('open', 1, 1, True)" || f=1
    shot N11 rich-after-reload > /dev/null
    ipc notify dismiss
    check "screenshot run exited" "$(screenshot_wait)" exited || f=1
    reset_notifs
    return $f
}

case_N13() {
    local f=0 cid out apid aid
    reset_notifs
    bus_start N13
    cid=$(send -u critical -a demo-app "Disk check" "fictional critical, stays")
    sleep 0.5
    out=$T/logs/N13-notify-send.out
    n notify-send -p -A discard=Discard -a demo-app "Queued action" "waits behind the critical" > "$out" 2>&1 &
    apid=$!
    sleep 0.5
    shot N13 queued > /dev/null
    check "critical on display" "$(notif "d['current']['summary']")" "Disk check" || f=1
    check "action note waiting" "$(notif "d['queued']")" 1 || f=1
    for _ in $(seq 320); do kill -0 "$apid" 2> /dev/null || break; sleep 0.1; done
    if kill -0 "$apid" 2> /dev/null; then
        echo "  FAIL  notify-send -A still running after 32 s"; f=1; kill "$apid"
    else
        echo "  ok    notify-send -A exited"
    fi
    wait "$apid" 2> /dev/null || true
    aid=$(head -n 1 "$out")
    check "notify-send printed no action (only its id)" "$(wc -l < "$out")" 1 || f=1
    check "critical still on display" "$(notif "d['current']['id']")" "$cid" || f=1
    bus_stop
    closed_check "queued note (30 s limit)" "$aid" "Queued action" 1 30.0 0.5 || f=1
    reset_notifs
    return $f
}

case_N14() {
    local f=0 id
    reset_notifs
    ipc notify setDnd true
    bus_start N14
    id=$(send -u critical -a demo-app "Disk almost full" "fictional test")
    sleep 0.5
    check "nothing on display" "$(notif "d['visible']")" False || f=1
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    sleep 5
    bus_stop
    closed_check "hidden critical" "$id" "Disk almost full" 1 5.0 || f=1
    reset_notifs
    return $f
}

case_N18() {
    local f=0 a b
    reset_notifs
    bus_start N18
    a=$(send -u critical -a battery-appindicator "Battery low" "20% remaining")
    sleep 1
    b=$(send -u critical -a battery-appindicator "Battery very low" "5% remaining")
    echo "  waiting 60 s"
    sleep 60
    shot N18 after-60s > /dev/null
    check "both still tracked" "$(notif "d['tracked']")" 2 || f=1
    check "newer on display" "$(notif "d['current']['summary']")" "Battery very low" || f=1
    check "older waiting (+1)" "$(notif "d['queued']")" 1 || f=1
    check "no NotificationClosed yet" "$("$REPO/tests/buslog.py" "$BUSLOG" count "$a")$("$REPO/tests/buslog.py" "$BUSLOG" count "$b")" 00 || f=1
    ipc notify dismiss
    sleep 0.3
    check "older on display after dismissing the newer" "$(notif "d['current']['summary']")" "Battery low" || f=1
    ipc notify dismiss
    bus_stop
    check "newer closed as dismissed" "$(closed "$b" "Battery very low" | cut -d' ' -f1)" 2 || f=1
    check "older closed as dismissed" "$(closed "$a" "Battery low" | cut -d' ' -f1)" 2 || f=1
    reset_notifs
    return $f
}

# ---- note view (M4) -----------------------------------------------------

# One field of the note view on HEADLESS-1, as a Python expression on `v`.
view() {
    ipc debug state | python3 -c "import json,sys; d=json.load(sys.stdin); v=[o['note'] for o in d['overlays'] if o['screen'] == 'HEADLESS-1'][0]; print($1)"
}
# strip_frames <case> <label> <slow> <ms...> [-- command]: a frame series of
# the bar strip into .test/shots/<case>/ (tests/strip-frames.py); prints the
# sheet.
strip_frames() {
    local c=$1; shift
    echo "  frames: $("$REPO/tests/strip-frames.py" "$T/shots/$c" "$@" | tail -n 1)"
}
# until_t <epoch> <seconds>: sleeps until <seconds> after <epoch>.
until_t() {
    local wait
    wait=$(python3 -c "import time; print(max(0, $1 + $2 - time.time()))")
    sleep "$wait"
}
# The clock box of the idle bar, in physical pixels, for comparisons that
# span a minute change.
CLOCK_BOX=284x48+1778+2352
# pixdiff <a> <b> [args]: the comparison line of tests/pixdiff.py.
pixdiff() { "$REPO/tests/pixdiff.py" "$@" || true; }
# Workspace 3 urgent again (a click on 3 clears it), as tests/scene.sh setup leaves it.
urgent_again() { n swaymsg -q '[title="client-3"] urgent enable'; }

case_N2() {
    local f=0 body id o1 o2 a b fp
    prepare
    reset_notifs
    body=$(python3 -c 'import sys; s = "Fictional release notes for demo-app: the parser reads longer lines, the cache keeps fewer copies, the demo theme gains two colors. "; print((s * 4)[:400])')
    bus_start N2
    echo "  frame series at normal speed: hold for 1200 ms once the wipe ends, then the scroll"
    "$REPO/tests/strip-frames.py" "$T/shots/N2" marquee 1 300 800 1300 1800 2100 2500 3000 3500 4000 4500 -- notify-send -p "Release notes" "$body" > "$T/logs/N2-frames.out" &
    fp=$!
    sleep 1.25
    id=$(notif "d['current']['id']")
    read -r o1 <<< "$(view "v['marquee']['offset']")"
    check "body length" "$(view "len(v['line']['body'])")" 400 || f=1
    more "line wider than its space (overflow px)" "$(view "int(v['marquee']['overflow'])")" 1 || f=1
    check "1.25 s after arrival: holding at the start (compact 432 + wipe 576 ms, then hold 1200 ms)" "$o1" 0 || f=1
    sleep 1.75
    # Speed: two reads 1 s apart, each timed around its IPC call.
    read -r o1 t1 <<< "$(view "f\"{v['marquee']['offset']} {__import__('time').time()}\"")"
    sleep 1
    read -r o2 t2 <<< "$(view "f\"{v['marquee']['offset']} {__import__('time').time()}\"")"
    more "3 s after arrival: scrolled left (px)" "${o1%.*}" 20 || f=1
    within "scroll speed (px/s)" "$(python3 -c "print(f'{($o2 - $o1) / ($t2 - $t1):.1f}')")" 60 8 || f=1
    wait "$fp" || true
    echo "  frames: $(tail -n 1 "$T/logs/N2-frames.out")"
    a=$T/shots/N2/marquee-01300.png
    b=$T/shots/N2/marquee-01800.png
    check "frames 1300 and 1800 ms: the text stands still (below the progress line)" "$(px "$a" diff "$b" 206 3 1840 23)" 0 || f=1
    more "frames 2500 and 3000 ms: the text moves" "$(px "$T/shots/N2/marquee-02500.png" diff "$T/shots/N2/marquee-03000.png" 206 3 1840 23)" 100 || f=1
    sleep 2.2
    bus_stop
    closed_check "long note" "$id" "Release notes" 1 5.0 || f=1
    wait_unmapped

    echo "  a line that fits: no marquee"
    id=$(send "Short note" "fits in the span")
    sleep 2
    a=$(shot N2 fits-2s)
    sleep 1.5
    b=$(shot N2 fits-3.5s)
    check "fits: no overflow, no marquee, no offset" "$(view "(v['marquee']['overflow'], v['marquee']['running'], v['marquee']['offset'])")" "(0, False, 0)" || f=1
    check "fits: the text stands still from 2 to 3.5 s" "$(px "$a" diff "$b" 206 1179 1840 1199)" 0 || f=1
    reset_notifs
    return $f
}

case_N4() {
    local f=0 id s glows lo hi
    prepare
    reset_notifs
    ipc notify setDnd true
    bus_start N4
    ipc debug slow 10
    echo "  frame series of the entry (slow motion x10)"
    strip_frames N4 enter 10 0 160 320 480 640 800 900 1050 -- notify-send -u critical -a battery-appindicator "Battery low" "5% remaining"
    ipc debug slow 1
    id=$(notif "d['current']['id']")
    s=$(shot N4 visible)
    check "DND on" "$(notif "d['dnd']")" True || f=1
    check "critical on display in DND" "$(notif "(d['kind'], d['current']['summary'])")" "('critical', 'Battery low')" || f=1
    check "red span (base08)" "$(px "$s" color 1000 1179)" "$(palette base08)" || f=1
    check "no progress line without a timeout" "$(view "v['timed']")" False || f=1
    check "glow pulse running" "$(view "v['pulse']")" True || f=1
    echo "  frame series of the pulse (normal speed, 1600 ms period)"
    strip_frames N4 pulse 1 0 200 400 600 800 1000 1200 1400 1600
    glows=$(for _ in $(seq 12); do view "v['glow']"; sleep 0.1; done | tr '\n' ' ')
    echo "  glow opacity samples: $glows"
    read -r lo hi <<< "$(python3 -c "import sys; v = [float(x) for x in sys.argv[1].split()]; print(min(v), max(v))" "$glows")"
    check "glow pulses down to about 0.4" "$(python3 -c "print($lo < 0.6)")" True || f=1
    check "glow pulses up to about 1.0" "$(python3 -c "print($hi > 0.85)")" True || f=1
    more "pulse visible near the leading edge (frames 0 and 800 ms)" "$(px "$T/shots/N4/pulse-00000.png" diff "$T/shots/N4/pulse-00800.png" 1830 0 1866 24)" 10 || f=1
    sleep 6
    check "still on display after 10 s (stays until clicked)" "$(notif "(d['current']['id'], d['kind'])")" "($id, 'critical')" || f=1
    # No default action: a left click dismisses it (M5).
    click 1000 $MID
    park
    wait_unmapped
    bus_stop
    check "dismissed: NotificationClosed reason" "$(closed "$id" "Battery low" | cut -d' ' -f1)" 2 || f=1
    reset_notifs
    return $f
}

case_N15() {
    local f=0 id c0 fp
    prepare
    reset_notifs
    id=$(send -t 30000 "Mask check" "clicks beside the note reach the bar")
    sleep 1
    c0=$(state "$H1['clicks']")
    echo "  frame series around a click on workspace 3 (normal speed)"
    "$REPO/tests/strip-frames.py" "$T/shots/N15" click 1 0 200 400 700 > "$T/logs/N15-frames.out" &
    fp=$!
    sleep 0.1
    click 65 $MID
    wait "$fp" || true
    echo "  frames: $(tail -n 1 "$T/logs/N15-frames.out")"
    sleep 0.2
    shot N15 after-click > /dev/null
    check "workspace 3 focused after a click beside the note" "$(focused_ws)" 3 || f=1
    check "note still on display" "$(notif "d['current']['id']")" "$id" || f=1
    check "the overlay did not get that click" "$(state "$H1['clicks']")" "$c0" || f=1
    # The upper 72 px of the overlay take no clicks without a card (M5).
    click 700 1150; park; sleep 0.3
    check "a click above the span reaches the window, not the overlay" "$(state "$H1['clicks']") $(notif "d['current']['id']")" "$c0 $id" || f=1
    click 960 $MID; sleep 0.3
    check "a click on the span reaches the overlay" "$(state "$H1['clicks']")" $((c0 + 1)) || f=1
    check "and not the bar's clock under it (no seconds)" "$(state "$(bar1)['clock']['seconds']")" False || f=1
    check "the left click dismissed the note (no default action, M5)" "$(notif "d['note']")" None || f=1
    n swaymsg -q workspace 2
    urgent_again
    reset_notifs
    return $f
}

# Handoff (SPEC section 2, spike S7 method): the first and the last overlay
# frames are the idle bar, pixel for pixel. The view holds at both frames.
# The note's timeout runs while the view holds at the first frame, and the
# full-output shot of that frame takes about 0.9 s. With 1.5 s the note could
# expire before the first release, which then ended the hold at the last
# frame: 3 s keeps the release inside the timeout.
case_HO() {
    local f=0 attempt m0 m1 phase1 mapped idle first last after id
    prepare
    reset_notifs
    for attempt in 1 2 3; do
        m0=$(date +%H:%M)
        ipc debug noteHold true
        idle=$(shot HO idle)
        id=$(send -t 3000 "Handoff check" "first and last frame")
        sleep 0.6
        phase1=$(view "(v['phase'], v['c'], v['w'], $H1['visible'])")
        first=$(shot HO first)
        ipc debug noteRelease
        for _ in $(seq 40); do [ "$(view "v['phase']")" = last ] && break; sleep 0.1; done
        mapped=$(view "(v['phase'], v['c'], v['w'], $H1['visible'])")
        last=$(shot HO last)
        ipc debug noteRelease
        wait_unmapped
        after=$(shot HO after)
        ipc debug noteHold false
        m1=$(date +%H:%M)
        [ "$m0" = "$m1" ] && break
        echo "  note: the minute changed during attempt $attempt, again"
    done
    check "held at the first frame, overlay mapped" "$phase1" "('first', 0, 0, True)" || f=1
    check "first overlay frame against the idle bar" "$(pixdiff "$idle" "$first")" "identical: 0 of 9216000 pixels differ" || f=1
    check "held at the last frame, overlay still mapped" "$mapped" "('last', 0, 0, True)" || f=1
    check "last overlay frame against the idle bar" "$(pixdiff "$idle" "$last")" "identical: 0 of 9216000 pixels differ" || f=1
    check "after the unmap against the idle bar" "$(pixdiff "$idle" "$after")" "identical: 0 of 9216000 pixels differ" || f=1
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    reset_notifs
    return $f
}

# Note width (SPEC section 3): the mode name shows in full unless a note
# would get less than 600 px, then it elides, and it comes back in full.
case_NW() {
    local f=0 s x w full span
    prepare
    reset_notifs
    scene present; sleep 0.3
    send -t 30000 "Width check" "beside the present mode" > /dev/null
    sleep 1
    s=$(shot NW present)
    read -r x w full <<< "$(state "' '.join(str(round($(bar1)['mode'][k])) for k in ('x', 'width', 'full'))")"
    check "present mode: not elided" "$(state "$(bar1)['mode']['elided']")" False || f=1
    check "present mode: label at full width" "$w" "$full" || f=1
    check "present mode: span starts 8 px after the label" "$(view "v['span']['x']")" $((x + w + 8)) || f=1
    more "present mode: span width" "$(view "int(v['span']['width'])")" 600 || f=1
    reset_notifs
    scene long; sleep 0.3
    full=$(state "round($(bar1)['mode']['full'])")
    more "long mode: full label wider than the room left for a 600 px note" "$((142 + full + 8 + 600 + 8))" 1868 || f=1
    shot NW long-idle > /dev/null
    send -t 30000 "Width check" "beside a mode name that has to elide" > /dev/null
    sleep 1
    s=$(shot NW long)
    read -r x w <<< "$(state "' '.join(str(round($(bar1)['mode'][k])) for k in ('x', 'width'))")"
    span=$(view "int(v['span']['width'])")
    check "long mode: elided" "$(state "$(bar1)['mode']['elided']")" True || f=1
    more "long mode: span width" "$span" 600 || f=1
    check "long mode: span starts 8 px after the elided label" "$(view "v['span']['x']")" $((x + w + 8)) || f=1
    # The bar's clock box covers the label from 889 to 1031, as when idle.
    check "long mode: label box on screen ends at the elided width" "$(px "$s" run 1100 $TOP | cut -d' ' -f2)" $((x + w)) || f=1
    check "long mode: note background up to the span's end" "$(px "$s" color 1750 1179)" "$(palette base01)" || f=1
    reset_notifs
    sleep 0.2
    check "long mode: back in full after the note" "$(state "(round($(bar1)['mode']['width']), $(bar1)['mode']['elided'])")" "($full, False)" || f=1
    scene mode default
    return $f
}

# Idle cost (docs/PLAN.md M4): the bar's Quickshell process near 0 % CPU.
# It runs every note animation first (marquee, progress line, critical
# pulse, roll), so that one left running after use would show here.
case_CPU() {
    local f=0 pid log samples avg body
    prepare
    reset_notifs
    scene tray 1 Active
    scene tray 2 Active
    [ "$(state "$(bar1)['clock']['seconds']")" = True ] && { click 960 $MID; scene hover 960 600; }
    body=$(python3 -c 'print(("Fictional idle check with a body long enough to scroll across the span. " * 8)[:400])')
    send "Idle check" "$body" > /dev/null
    sleep 2.5
    check "marquee ran" "$(view "v['marquee']['running']")" True || f=1
    send -u critical -a demo-app "Idle check" "critical, pulsing" > /dev/null
    sleep 1
    check "pulse ran" "$(view "v['pulse']")" True || f=1
    ipc notify dismiss
    sleep 0.5
    reset_notifs
    check "afterwards: view idle, no pulse, no marquee, no roll" "$(view "(v['phase'], v['pulse'], v['marquee']['running'], v['rolling'])")" "('idle', False, False, False)" || f=1
    sleep 2
    pid=$(ps -eo pid=,args= | awk -v want="quickshell -p $REPO" '{ p = $1; $1 = ""; sub(/^ /, ""); if ($0 == want) print p }')
    check "one bar process" "$(wc -w <<< "$pid")" 1 || return 1
    mkdir -p "$T/logs/m4"
    log=$T/logs/m4/cpu-idle.log
    top -b -n 5 -d 1 -p "$pid" > "$log"
    # The first sample counts from the process start: the last four count.
    samples=$(awk -v pid="$pid" '$1 == pid { print $9 }' "$log" | tail -n 4 | tr '\n' ' ')
    avg=$(python3 -c "import sys; v = [float(x.replace(',', '.')) for x in sys.argv[1].split()]; print(f'{sum(v) / len(v):.2f}')" "$samples")
    echo "  top samples (% CPU, pid $pid): $samples-> average $avg (log: $log)"
    check "idle CPU near 0 % (average under 1 %)" "$(python3 -c "print($avg < 1.0)")" True || f=1
    return $f
}

# ---- outputs and theme switches (M6) ------------------------------------

# The overlay of the second output in a state `d` (OTHER holds its name).
H2() { echo "[o for o in d['overlays'] if o['screen'] == '$OTHER'][0]"; }
# Screens of the bar and overlay windows, sorted: "([bars], [overlays])".
windows() { state "(sorted(b['screen'] for b in d['bars']), sorted(o['screen'] for o in d['overlays']))"; }
# The bar window of HEADLESS-1 as "<serial> <connects> <hides>": a bar that
# is replaced gets a new serial, a backing window that is created again
# counts a connect, and one that stops being visible counts a hide.
bar_life() { state "(lambda b: '%d %d %d' % (b['serial'], b['connects'], b['hides']))($(bar1))"; }
# Height of the visible workspace on HEADLESS-1: 1176 with the bar's
# exclusive zone, 1200 without it.
ws_height() {
    n swaymsg -t get_workspaces | python3 -c 'import json,sys; print([w["rect"]["height"] for w in json.load(sys.stdin) if w["output"] == "HEADLESS-1" and w["visible"]][0])'
}
# bar_kept <what> <life before> <height before>: the bar of HEADLESS-1 was
# never replaced or unmapped, and its exclusive zone holds.
bar_kept() {
    local f=0
    check "$1: HEADLESS-1 bar kept (serial, connects, hides)" "$(bar_life)" "$2" || f=1
    check "$1: workspace height on HEADLESS-1 (exclusive zone)" "$(ws_height)" "$3" || f=1
    return $f
}
# The Quickshell log: log_mark gives the line count, log_clean fails on any
# WARN, ERROR or FATAL line after the mark.
log_mark() { wc -l < "$T/logs/quickshell.log"; }
log_clean() {
    local lines
    lines=$(tail -n "+$(($2 + 1))" "$T/logs/quickshell.log" | grep -E 'WARN|ERROR|CRIT|FATAL' || true)
    if [ -z "$lines" ]; then
        echo "  ok    $1: no warning or error in the Quickshell log"
    else
        echo "  FAIL  $1: the Quickshell log has:"
        sed 's/^/          /' <<< "$lines"
        return 1
    fi
}
osd_on() { send -a volume -t "${2:-3000}" -e -h int:value:"$1" -h string:x-canonical-private-synchronous:volume "Volume: $1%"; }

# N12: a note shows on the output that has the focus when it becomes
# visible, and stays there until it leaves. An OSD on another output does
# not pause it, and same-tag OSD updates stay where the OSD started.
case_N12() {
    local f=0 a b ta s e0 e1
    prepare
    reset_notifs
    focus_other
    echo "  second output: $OTHER (1920x1080, scale 1, right of HEADLESS-1), focused"
    e0=$(state "$(H2)['osd']['entries']")
    bus_start N12
    # 9 s, so that the second note is queued while the first still shows.
    a=$(send -t 9000 "Second screen" "fictional note on the focused output"); ta=$(date +%s.%N)
    sleep 1
    check "note placed on the focused output" "$(notif "d['note']['output']")" "$OTHER" || f=1
    check "overlay of $OTHER mapped, note open" "$(state "($(H2)['visible'], $(H2)['note']['phase'])")" "(True, 'open')" || f=1
    check "overlay of HEADLESS-1 not mapped" "$(mapped_h1)" False || f=1
    mkdir -p "$T/shots/N12"
    n grim -o "$OTHER" "$T/shots/N12/other-note.png"
    check "note background on $OTHER" "$(PX_SCALE=1 px "$T/shots/N12/other-note.png" color 960 1060)" "$(palette base01)" || f=1
    more "compact clock drawn on $OTHER" "$(PX_SCALE=1 px "$T/shots/N12/other-note.png" ink 30 1058 120 1078)" 3 || f=1
    s=$(shot N12 main-idle)
    check "HEADLESS-1 keeps its idle clock box" "$(px "$s" color 960 $TOP)" "$(palette base00)" || f=1

    echo "  the focus moves back: the note stays on $OTHER"
    focus_main
    sleep 0.3
    check "note still on $OTHER" "$(notif "d['note']['output']")" "$OTHER" || f=1
    check "overlays ($OTHER, HEADLESS-1) mapped" "$(state "($(H2)['visible'], $H1['visible'])")" "(True, False)" || f=1

    echo "  an OSD on HEADLESS-1 leaves the note on $OTHER running"
    # 3 s: the same-tag update below has to find this OSD still up.
    osd_on 30 3000 > /dev/null
    sleep 0.3
    check "OSD on the focused output" "$(notif "d['osd']['output']")" HEADLESS-1 || f=1
    check "note on $OTHER keeps running" "$(notif "d['note']['running']")" True || f=1
    focus_other
    osd_on 40 3000 > /dev/null
    sleep 0.3
    check "same-tag update stays where the OSD started" "$(notif "(d['osd']['output'], d['osd']['value'])")" "('HEADLESS-1', 40)" || f=1
    e1=$(state "$(H2)['osd']['entries']")
    check "no OSD drawn on $OTHER" "$(state "$(H2)['osd']['active']") $((e1 - e0))" "False 0" || f=1
    focus_main

    echo "  the next note shows on the output focused when it becomes visible"
    b=$(send "Main screen" "fictional note, queued behind the first")
    sleep 0.3
    check "second note waits ($(python3 -c "import time; print('%.1f' % (time.time() - $ta))") s after the first)" "$(notif "d['waiting']")" "[$b]" || f=1
    until_t "$ta" 9.6
    check "second note on display, on HEADLESS-1" "$(notif "(d['note']['id'], d['note']['output'])")" "($b, 'HEADLESS-1')" || f=1
    sleep 0.5
    check "overlays (HEADLESS-1, $OTHER) mapped after the first note's leave" "$(state "($H1['visible'], $(H2)['visible'])")" "(True, False)" || f=1
    s=$(shot N12 main-note)
    check "note background on HEADLESS-1" "$(px "$s" color 960 1179)" "$(palette base01)" || f=1
    n grim -o "$OTHER" "$T/shots/N12/other-idle.png"
    check "$OTHER back to its idle clock box" "$(PX_SCALE=1 px "$T/shots/N12/other-idle.png" color 960 1057)" "$(palette base00)" || f=1
    ipc notify dismiss
    bus_stop
    closed_check "first note, not paused by the OSD on HEADLESS-1" "$a" "Second screen" 1 9.0 || f=1
    reset_notifs
    return $f
}

# HP: outputs come and go while notifications show. The bar of HEADLESS-1
# is never replaced or unmapped and keeps its exclusive zone, a new output's
# overlay stays unmapped, and a notification whose output goes away moves
# to the focused one. Nothing may reach the Quickshell log.
case_HP() {
    local f=0 mark life h m0 s
    prepare
    reset_notifs
    scene unplug
    sleep 0.5
    life=$(bar_life)
    h=$(ws_height)
    echo "  HEADLESS-1 bar (serial, connects, hides): $life, workspace height $h"
    mark=$(log_mark)

    echo "  1. create_output while a note shows on HEADLESS-1"
    send -t 30000 "Dock check" "fictional note during a hotplug" > /dev/null
    sleep 1
    m0=$(state "$H1['maps']")
    scene plug
    OTHER=$(scene other)
    sleep 1
    check "one bar and one overlay per output" "$(windows)" "(['HEADLESS-1', '$OTHER'], ['HEADLESS-1', '$OTHER'])" || f=1
    check "overlay of $OTHER never mapped (maps, visible, note)" "$(state "($(H2)['maps'], $(H2)['visible'], $(H2)['note']['phase'])")" "(0, False, 'idle')" || f=1
    check "note still on HEADLESS-1, same surface (output, visible, new maps, phase)" "$(state "(d['notifs']['note']['output'], $H1['visible'], $H1['maps'] - $m0, $H1['note']['phase'])")" "('HEADLESS-1', True, 0, 'open')" || f=1
    check "bar of $OTHER shows the workspaces of $OTHER" "$(state "[b['workspaces'] for b in d['bars'] if b['screen'] == '$OTHER'][0]")" \
        "$(n swaymsg -t get_workspaces | python3 -c "import json,sys; print([w['name'] for w in json.load(sys.stdin) if w['output'] == '$OTHER'])")" || f=1
    bar_kept "after create_output" "$life" "$h" || f=1

    echo "  2. unplug $OTHER while the note shows on HEADLESS-1"
    scene unplug
    sleep 1
    check "windows of HEADLESS-1 only" "$(windows)" "(['HEADLESS-1'], ['HEADLESS-1'])" || f=1
    check "note still on HEADLESS-1, same surface (output, visible, new maps, phase)" "$(state "(d['notifs']['note']['output'], $H1['visible'], $H1['maps'] - $m0, $H1['note']['phase'])")" "('HEADLESS-1', True, 0, 'open')" || f=1
    s=$(shot HP after-unplug)
    check "note drawn on HEADLESS-1" "$(px "$s" color 960 1179)" "$(palette base01)" || f=1
    bar_kept "after the unplug" "$life" "$h" || f=1
    ipc notify dismiss
    wait_unmapped || true

    echo "  3. unplug the output that shows a critical and an OSD"
    focus_other
    send -u critical -a demo-app "Dock check" "fictional critical on the second output" > /dev/null
    osd_on 70 5000 > /dev/null
    sleep 0.6
    check "critical and OSD on $OTHER" "$(notif "(d['note']['output'], d['osd']['output'])")" "('$OTHER', '$OTHER')" || f=1
    check "critical paused under the OSD" "$(notif "d['note']['running']")" False || f=1
    m0=$(state "$H1['maps']")
    scene unplug
    sleep 1
    check "both moved to HEADLESS-1" "$(notif "(d['note']['output'], d['osd']['output'])")" "('HEADLESS-1', 'HEADLESS-1')" || f=1
    check "overlay of HEADLESS-1: mapped once, OSD shown, note open below it" "$(state "($H1['visible'], $H1['maps'] - $m0, $H1['osd']['active'], $H1['note']['phase'])")" "(True, 1, True, 'open')" || f=1
    check "critical still paused under the OSD" "$(notif "d['note']['running']")" False || f=1
    s=$(shot HP moved-osd)
    check "OSD fill on HEADLESS-1" "$(px "$s" color 2 $TOP)" "$(palette base0D)" || f=1
    ipc notify dismiss # the OSD while one shows (Q7)
    sleep 0.5
    s=$(shot HP moved-critical)
    check "critical drawn on HEADLESS-1 (base08)" "$(px "$s" color 960 1179)" "$(palette base08)" || f=1
    check "critical runs again (it has no timeout, so it stays)" "$(notif "(d['note']['kind'], d['note']['running'])")" "('critical', True)" || f=1
    check "windows of HEADLESS-1 only" "$(windows)" "(['HEADLESS-1'], ['HEADLESS-1'])" || f=1
    bar_kept "after the unplug of the critical's output" "$life" "$h" || f=1
    log_clean "create_output and two unplugs" "$mark" || f=1
    reset_notifs
    return $f
}

# theme_frames <dir> <x> <y> <name> <x> <y> <name>...: for each shot of
# the last frame series, which palette each probe matches ("dark", "light"
# or the color itself; THEME_RAW=1 prints the color always). Prints one
# line per shot.
theme_frames() {
    python3 - "$FJ" "$REPO" "$@" <<'PY'
import json, re, subprocess, sys
import os
fj, repo, probes = sys.argv[1], sys.argv[2], sys.argv[3:]
raw = os.environ.get("THEME_RAW") == "1"
pal = {}
for mode in ("dark", "light"):
    css = open(f"{repo}/themes/base16-default-{mode}.css").read()
    pal[mode] = dict(re.findall(r"@define-color (base0[0-9A-F]) (#[0-9a-f]{6});", css))
d = json.load(open(fj))
for s in d["shots"]:
    out = []
    for i in range(0, len(probes), 3):
        x, y, role = probes[i:i + 3]
        c = subprocess.run([f"{repo}/tests/pixel.py", s["file"], "color", x, y], capture_output=True, text=True).stdout.strip()
        names = [m for m in ("dark", "light") if pal[m][role] == c]
        out.append(c if raw else "both" if len(names) == 2 else names[0] if names else c)
    print("%d %.1f %s" % (s["at"], s["frame_ms"], " ".join(out)))
PY
}

# fade_check <role> <probe>...: reads `theme_frames` rows (THEME_RAW=1)
# on stdin and checks the crossfade (Q26) of each probe of the given role:
# dark frames, then in-between colors, then light frames, never back. With
# two probes, also the largest channel difference between them per frame
# (the bar and the overlay in step). Prints "ok <summary>" or "bad <why>".
fade_check() {
    # The heredoc is python's stdin, so the rows go through the environment.
    FADE_ROWS=$(cat) python3 - "$REPO" "$@" <<'PY'
import os, re, sys
repo, role, n = sys.argv[1], sys.argv[2], len(sys.argv) - 3
pal = {}
for mode in ("dark", "light"):
    css = open(f"{repo}/themes/base16-default-{mode}.css").read()
    pal[mode] = dict(re.findall(r"@define-color (base0[0-9A-F]) (#[0-9a-f]{6});", css))[role]
rows = [l.split() for l in os.environ["FADE_ROWS"].splitlines() if l.strip()]
out, bad = [], []
for k in range(n):
    seq = ["dark" if r[2 + k] == pal["dark"] else "light" if r[2 + k] == pal["light"] else "mid" for r in rows]
    order = {"dark": 0, "mid": 1, "light": 2}
    if any(order[b] < order[a] for a, b in zip(seq, seq[1:])):
        bad.append(f"probe {k + 1} goes back: {' '.join(seq)}")
    if seq[-1] != "light":
        bad.append(f"probe {k + 1} not light at the end")
    mids = sorted({float(r[1]) for r, q in zip(rows, seq) if q == "mid"})
    lights = [float(r[1]) for r, q in zip(rows, seq) if q == "light"]
    darks = [float(r[1]) for r, q in zip(rows, seq) if q == "dark"]
    # Distinct frames. The capture misses frames while the `quickshell ipc`
    # client starts (gaps up to about 120 ms), so this only shows that a
    # fade ran: a wf-recorder clip shows a new value every 16.4 ms.
    if len(mids) < 2:
        bad.append(f"probe {k + 1}: {len(mids)} in-between frames")
    else:
        span = lights[0] - darks[-1] if darks and lights else 0
        if not 200 <= span <= 600:
            bad.append(f"probe {k + 1}: fade over {span:.0f} ms")
        out.append(f"probe {k + 1}: {len(mids)} in-between frames, last dark at {darks[-1] if darks else 0:.0f} ms, first light at {lights[0] if lights else 0:.0f} ms")
if n == 2:
    hexes = lambda c: [int(c[i:i + 2], 16) for i in (1, 3, 5)]
    diff = max(max(abs(a - b) for a, b in zip(hexes(r[2]), hexes(r[3]))) for r in rows)
    # At most one frame apart: one 16.7 ms frame of the 300 ms InOutQuad
    # fade from #181818 to #f8f8f8 is up to 25 at its middle. The two
    # windows commit separately, and one run saw them a frame apart (19).
    if diff > 26:
        bad.append(f"probes apart by {diff} in one frame")
    out.append(f"largest difference between the probes in one frame: {diff}")
print(("bad " + "; ".join(bad)) if bad else ("ok " + "; ".join(out)))
PY
}

# TH: `theme set light` while an OSD and while a note shows. Colors change
# in place: no map, no entry, the bar is neither replaced nor unmapped and
# keeps its exclusive zone. The frame series show the 300 ms crossfade
# (M7, Q26), with the bar and the overlay in step.
case_TH() {
    local f=0 life h mark c0 c1 m0 s rows bad mixed sched
    prepare
    reset_notifs
    life=$(bar_life)
    h=$(ws_height)
    mark=$(log_mark)
    sched=()
    for c0 in $(seq 0 33 726); do sched+=("$c0 shot"); done

    echo "  during an OSD"
    # 15 s, so that the OSD is still up for every check below.
    osd_on 60 15000 > /dev/null
    sleep 0.5
    c0=$(osd_counts)
    m0=$(state "$H1['maps']")
    frames TH/osd "10 run quickshell ipc -p $REPO call theme set light" "${sched[@]}"
    c1=$(osd_counts)
    check "OSD still shown, opaque (visible, new maps, active, opacity)" "$(state "($H1['visible'], $H1['maps'] - $m0, $H1['osd']['active'], $H1['osd']['opacity'])")" "(True, 0, True, 1)" || f=1
    counts_check "theme switch during the OSD" "$c0" "$c1" 0 0 0 || f=1
    s=$(shot TH osd-light)
    check "OSD fill (base0D in both palettes)" "$(px "$s" run 2 $TOP)" "0 1152" || f=1
    check "OSD empty part in light base00" "$(px "$s" color 1900 $TOP)" "$(palette base00 light)" || f=1
    more "OSD label over the fill in light base07 (Theme.onFill, Q10)" "$(px "$s" count "$(palette base07 light)" 900 1177 1020 1199)" 50 || f=1
    check "no light base00 in the label over the fill" "$(px "$s" count "$(palette base00 light)" 900 1177 1020 1199)" 0 || f=1
    echo "  frames (requested -> frame time, ms): $(frame_times); $FD/sheet.png"
    # Per frame: the fill (base0D, the same in both palettes) and the empty part.
    rows=$(THEME_RAW=1 theme_frames 2 $CTOP base0D 1900 $CTOP base00)
    echo "  per frame (ms, frame ms, fill, empty part):"
    sed 's/^/          /' <<< "$rows"
    check "the fill stays base0D in every frame" "$(awk '{print $3}' <<< "$rows" | sort -u)" "$(palette base0D)" || f=1
    c0=$(awk '{print $1, $2, $4}' <<< "$rows" | fade_check base00 1)
    echo "  info  $c0"
    check "the empty part crossfades to light (Q26)" "${c0%% *}" ok || f=1
    bar_kept "after theme set light during the OSD" "$life" "$h" || f=1
    ipc notify dismiss
    wait_unmapped || true

    echo "  during a note"
    ipc theme set dark
    sleep 0.6 # past the 300 ms crossfade
    # 30 s: the per-frame analysis below takes seconds, and the note must
    # still show for the switch back to dark.
    send -t 30000 "Theme check" "fictional note across a theme switch" > /dev/null
    sleep 1
    m0=$(state "$H1['maps']")
    frames TH/note "10 run quickshell ipc -p $REPO call theme set light" "${sched[@]}"
    check "note still open on the same surface (new maps, phase, c, w)" "$(state "($H1['maps'] - $m0, $H1['note']['phase'], $H1['note']['c'], $H1['note']['w'])")" "(0, 'open', 1, 1)" || f=1
    # The shot and its checks first: the per-frame analysis takes seconds.
    s=$(shot TH note-light)
    check "note span in light base01" "$(px "$s" color 960 1179)" "$(palette base01 light)" || f=1
    check "focused workspace in light base07" "$(px "$s" color 39 $TOP)" "$(palette base07 light)" || f=1
    echo "  frames (requested -> frame time, ms): $(frame_times); $FD/sheet.png"
    # Per frame: the bar (workspace 1, base00), the note span (base01) and
    # the compact clock (base00, both drawn by the overlay; 4 px down, off
    # the progress line).
    rows=$(THEME_RAW=1 theme_frames 13 $CTOP base00 960 75 base01 150 76.5 base00)
    echo "  per frame (ms, frame ms, bar, note span, compact clock):"
    sed 's/^/          /' <<< "$rows"
    c0=$(awk '{print $1, $2, $3, $5}' <<< "$rows" | fade_check base00 1 2)
    echo "  info  bar and compact clock: $c0"
    check "bar and overlay crossfade in step (Q26)" "${c0%% *}" ok || f=1
    c0=$(awk '{print $1, $2, $4}' <<< "$rows" | fade_check base01 1)
    echo "  info  note span: $c0"
    check "the note span crossfades to light" "${c0%% *}" ok || f=1
    bar_kept "after theme set light during the note" "$life" "$h" || f=1
    ipc theme set dark
    sleep 0.6 # past the 300 ms crossfade
    s=$(shot TH note-dark-again)
    check "back in dark: note span base01" "$(px "$s" color 960 1179)" "$(palette base01)" || f=1
    bar_kept "after theme set dark" "$life" "$h" || f=1
    log_clean "three theme switches" "$mark" || f=1
    reset_notifs
    return $f
}

# N16: idle after all cases. The screenshot before the first case is taken
# by the loop at the bottom. A few notes run first, so the case means
# something on its own too. The clock digits are left out: the minute
# changes during a full run.
case_N16() {
    local f=0 before after
    prepare
    reset_notifs
    before=$T/shots/N16/before.png
    [ -e "$before" ] || before_shot
    send -t 800 "Idle check" "one" > /dev/null
    send -t 800 "Idle check" "two" > /dev/null
    send -u critical -a demo-app "Idle check" "critical" > /dev/null
    sleep 1.5
    ipc notify dismiss
    sleep 3
    reset_notifs
    urgent_again
    sleep 0.3
    after=$(shot N16 after)
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    check "idle bar against the one before the cases (clock digits left out)" "$(pixdiff "$before" "$after" --ignore $CLOCK_BOX)" "identical: 0 of 9216000 pixels differ" || f=1
    check "clock box unchanged" "$(px "$after" run 890 $TOP)" "$(px "$before" run 890 $TOP)" || f=1
    return $f
}

before_shot() {
    prepare
    reset_notifs
    urgent_again
    sleep 0.3
    shot N16 before > /dev/null
}

# Paths outside the SPEC matrix where a notification could get stuck or
# lose its place: resident actions, updates of waiting and hidden
# notifications, and dismissAll.
case_NX() {
    local f=0 r a b c x y z h order log ta tb
    reset_notifs
    bus_start NX

    echo "  resident: the action does not close it, its timer does"
    # Through gdbus: notify-send closes its notification once an action came.
    r=$(n gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify demo-app 0 "" "Resident note" "stays after its action" \
        "['open', 'Open']" "{'resident': <true>}" 3000 | sed 's/.*uint32 \([0-9]*\).*/\1/')
    sleep 1
    ipc notify invoke open
    sleep 0.5
    check "still on display after its action" "$(notif "d['current']['id']")" "$r" || f=1
    sleep 2

    echo "  replaces_id on a waiting note: new timeout, then critical"
    a=$(send "Front note" "on display first")
    b=$(send "Waiting note" "second in line")
    c=$(send "Last note" "third in line")
    send -r "$b" -t 1500 "Waiting note, updated" "shorter timeout" > /dev/null
    sleep 0.3
    check "still waiting after the update" "$(notif "(d['current']['id'], d['waiting'])")" "($a, [$b, $c])" || f=1
    send -r "$c" -u critical "Last note, now critical" "takes the span" > /dev/null
    sleep 0.3
    check "the critical one takes the span, the front note waits again" "$(notif "(d['current']['id'], d['kind'], d['waiting'])")" "($c, 'critical', [$a, $b])" || f=1
    ipc notify dismiss
    sleep 0.3
    check "front note back on display" "$(notif "d['current']['id']")" "$a" || f=1
    sleep 6.5

    echo "  dismissAll: the queue first, then the note on display"
    x=$(send "Dismiss one" "on display")
    y=$(send "Dismiss two" "waiting")
    z=$(send "Dismiss three" "waiting")
    sleep 0.3
    ipc notify dismissAll
    sleep 0.3
    check "nothing left" "$(notif "(d['visible'], d['queued'], d['tracked'])")" "(False, 0, 0)" || f=1

    echo "  replaces_id on a hidden critical after DND went off"
    ipc notify setDnd true
    h=$(send -u critical -a demo-app "Hidden critical" "sent during DND")
    sleep 1
    ipc notify setDnd false
    send -r "$h" -u critical -a demo-app "Hidden critical, updated" "after DND" > /dev/null
    sleep 0.5
    check "still hidden after the update" "$(notif "(d['visible'], d['hidden'])")" "(False, 1)" || f=1
    sleep 5
    bus_stop

    log=$("$REPO/tests/buslog.py" "$BUSLOG")
    check "resident: ActionInvoked open" "$(grep -c "id=$r key='open'" <<< "$log")" 1 || f=1
    closed_check "resident note (sender timeout 3 s)" "$r" "Resident note" 1 3.0 || f=1
    check "critical dismissed" "$(closed "$c" "Front note" | cut -d' ' -f1)" 2 || f=1
    read -r _ ta <<< "$(closed "$a" "Front note")"
    read -r _ tb <<< "$(closed "$b" "Front note")"
    check "updated waiting note: NotificationClosed reason" "$(closed "$b" "Front note" | cut -d' ' -f1)" 1 || f=1
    within "updated waiting note: on display for its new timeout" "$(python3 -c "print(f'{$tb - $ta:.2f}')")" 1.5 || f=1
    order=$(grep '^closed' <<< "$log" | grep -E "id=($x|$y|$z) " | sed 's/.*id=\([0-9]*\) reason=\([0-9]\)/\1:\2/' | tr '\n' ' ')
    check "dismissAll order and reasons" "$order" "$y:2 $z:2 $x:2 " || f=1
    closed_check "hidden critical, from its update" "$h" "Hidden critical, updated" 1 5.0 || f=1
    reset_notifs
    return $f
}

# Rapid presses (docs/PLAN.md M3): never a second surface, never a second
# entry animation. Three paths: key repeat on a volume key (a press every
# 40 ms for 1.2 s), a press during the fade-out, and a reload while an OSD
# shows. The counters come from the views; the frames back them with pixels.
case_RP() {
    local f=0 ev=() i t c0 c1 bad=0 total=0 file
    prepare
    reset_notifs
    c0=$(osd_counts)
    for i in $(seq 0 29); do
        ev+=("$((i * 40)) run $(osd_cmd volume $((60 + i % 4 * 5)))")
    done
    for t in $(seq 300 50 1400); do ev+=("$t shot"); done
    frames RP/repeat --region "0,1176 1920x24" "${ev[@]}"
    echo "  frames: $FD/sheet.png"
    for file in "$FD"/t*.png; do
        total=$((total + 1))
        # Every value is at least 60 %: x 2 and x 960 are on an opaque fill.
        [ "$(px "$file" color 2 0.5)$(px "$file" color 960 0.5)" = "$(palette base0D)$(palette base0D)" ] || {
            bad=$((bad + 1))
            echo "  frame $(basename "$file"): $(px "$file" color 2 0.5) at x 2, $(px "$file" color 960 0.5) at x 960"
        }
    done
    check "key repeat: frames from 300 to 1400 ms with an opaque fill past 50 % (of $total)" "$((total - bad))" "$total" || f=1
    sleep 1.2
    wait_unmapped || true
    c1=$(osd_counts)
    counts_check "key repeat, 30 presses" "$c0" "$c1" 1 1 29 || f=1

    # The first OSD closes at about 320 ms and fades out until about 470 ms.
    # The second arrives at about 380 ms, during the fade.
    reset_notifs
    c0=$(osd_counts)
    frames RP/fade "0 run $(osd_cmd volume 40 300)" "360 run $(osd_cmd volume 70 800)" \
        "280 shot" "330 shot" "380 shot" "420 shot" "460 shot" "600 shot"
    echo "  frames (requested -> frame time, ms): $(frame_times); $FD/sheet.png"
    # The counters alone would also pass for a press before the close: one
    # frame between the close and the second press must show a fading strip
    # (x 2 is over workspace 1, base00 in the bar).
    local fading=0
    for t in 0330 0380; do
        case $(px "$FD/t$t.png" color 2 $CTOP) in
            "$(palette base0D)" | "$(palette base00)") ;;
            *) fading=$((fading + 1)) ;;
        esac
    done
    more "press during the fade-out: frames at 330 and 380 ms with a fading strip" "$fading" 1 || f=1
    sleep 1.2
    wait_unmapped || true
    c1=$(osd_counts)
    counts_check "press during the fade-out" "$c0" "$c1" 1 1 1 || f=1

    # A reload brings the OSD back at once, without the entry.
    reset_notifs
    send -a volume -t 4000 -e -h int:value:30 -h string:x-canonical-private-synchronous:volume "Volume: 30%" > /dev/null
    sleep 0.5
    touch "$REPO/shell.qml"
    sleep 2
    shot RP after-reload > /dev/null
    check "reload: OSD back as a survivor" "$(notif "d['osd']['restored']")" True || f=1
    check "reload: no entry animation in the new view" "$(state "$H1['osd']['entries']")" 0 || f=1
    check "reload: strip opaque, fill at the value" "$(state "($H1['osd']['opacity'], $H1['osd']['level'])")" "(1, 0.3)" || f=1
    reset_notifs
    return $f
}

# An OSD over an open note (SPEC section 6, item 7): the overlay is already
# mapped, so the entry runs without a new surface, and it still has to start
# (it waits for the next frame of the window). The note pauses under the
# strip and is back, with its timer and its input mask, once the OSD leaves.
case_ON() {
    local f=0 c0 c1 c2 s
    prepare
    reset_notifs
    send "Sync finished" "fictional test note" > /dev/null
    sleep 0.5
    c0=$(osd_counts)
    # A long timeout, so that the checks below see the OSD; dismissed after.
    send -a volume -t 3000 -e -h int:value:40 -h string:x-canonical-private-synchronous:volume "Volume: 40%" > /dev/null
    sleep 0.35
    s=$(shot ON osd-over-note)
    c1=$(osd_counts)
    counts_check "OSD over the note" "$c0" "$c1" 0 1 0 || f=1
    check "OSD opaque, fill at the value" "$(state "($H1['osd']['opacity'], $H1['osd']['level'])")" "(1, 0.4)" || f=1
    check "OSD fill drawn over the note" "$(px "$s" color 2 $TOP)" "$(palette base0D)" || f=1
    check "note still current, timer paused" "$(notif "(d['note']['summary'], d['note']['running'])")" "('Sync finished', False)" || f=1
    ipc notify dismiss # the OSD while one shows (Q7)
    sleep 0.4
    s=$(shot ON note-after-osd)
    check "OSD gone, overlay still mapped for the note" "$(state "($H1['osd']['active'], $H1['visible'])")" "(False, True)" || f=1
    check "note on display again, timer running" "$(notif "(d['note']['summary'], d['note']['running'])")" "('Sync finished', True)" || f=1
    check "note span drawn again (base01, below the progress line)" "$(px "$s" color 960 1179)" "$(palette base01)" || f=1
    click 65 $MID
    sleep 0.3
    check "mask back on the note span: a click on workspace 3 reaches the bar" "$(focused_ws)" 3 || f=1
    n swaymsg -q workspace 2
    c2=$(osd_counts)
    counts_check "OSD over the note, whole case" "$c0" "$c2" 0 1 0 || f=1
    reset_notifs
    return $f
}

# ---- rich mode and input (M5) -------------------------------------------

# One run of tests/fake-screenshot.sh in the background: SHOT_OUT is its
# output file, SHOT_PID its process, SHOT_ID the notification on display.
screenshot_start() {
    SHOT_OUT=$T/logs/$1.out
    n "$REPO/tests/fake-screenshot.sh" "$(shot_png)" > "$SHOT_OUT" 2>&1 &
    SHOT_PID=$!
    sleep 1.3
    SHOT_ID=$(notif "d['current']['id'] if d['current'] else 0")
}
# Waits (12 s at most) for the run to exit: "exited" or "running".
screenshot_wait() {
    for _ in $(seq 120); do kill -0 "$SHOT_PID" 2> /dev/null || break; sleep 0.1; done
    kill -0 "$SHOT_PID" 2> /dev/null && echo running || { wait "$SHOT_PID" 2> /dev/null || true; echo exited; }
}
reason() { closed "$1" "$2" | cut -d' ' -f1; }

# N7 (SPEC section 12, decision D1): the screenshot note with its card, and
# the three outcomes of screenshot.sh through real clicks: a right click
# prints discard, a left click and the 10 s timeout print nothing.
case_N7() {
    local f=0 s x y w h png c0
    prepare
    reset_notifs
    png=$(shot_png)
    bus_start N7

    echo "  right click on the card: prints discard"
    screenshot_start N7-right
    check "screenshot note on display" "$(notif "(d['current']['app'], d['kind'])")" "('screenshot', 'rich')" || f=1
    check "card up, picture loaded" "$(view "(v['card']['r'], v['card']['ready'])")" "(1, True)" || f=1
    read -r x y w h <<< "$(view "' '.join(str(round(v['card'][k])) for k in ('x', 'y', 'width', 'height'))")"
    check "card at the note region's left edge, the 72 px above the strip" "$x $y $h" "$(view "round(v['region']['x'])") 0 72" || f=1
    check "card width: a 64 px high 16:10 thumbnail + 2 x 4 px (110 +- 1)" "$(python3 -c "print(abs($w - 110.4) <= 1)")" True || f=1
    s=$(shot N7 card)
    check "card frame (base01) above the strip" "$(px "$s" color $((x + 1)) 1105)" "$(palette base01)" || f=1
    more "thumbnail drawn in the card" "$(px "$s" ink $((x + 4)) 1108 $((x + w - 4)) 1172)" 50 || f=1
    check "beside the card: the window" "$(px "$s" color $((x + w + 20)) 1140)" "$CLIENT" || f=1
    check "note line below the card (base01)" "$(px "$s" color 1000 1179)" "$(palette base01)" || f=1
    # With the card up, the rest of the upper 72 px still lets clicks through.
    c0=$(state "$H1['clicks']")
    click $((x + w + 40)) 1140
    park
    sleep 0.3
    check "a click beside the card reaches the window, not the overlay" "$(state "$H1['clicks']") $(notif "d['current']['id']")" "$c0 $SHOT_ID" || f=1
    click $((x + w / 2)) 1140 button3
    park
    check "right click: notify-send exited" "$(screenshot_wait)" exited || f=1
    check "right click: printed" "$(cat "$SHOT_OUT")" discard || f=1
    check "right click: NotificationClosed reason" "$(reason "$SHOT_ID" "Screenshot saved")" 2 || f=1
    wait_unmapped

    echo "  left click on the note line: prints nothing"
    screenshot_start N7-left
    click 1000 $MID
    park
    check "left click: notify-send exited" "$(screenshot_wait)" exited || f=1
    check "left click: printed nothing" "$(wc -c < "$SHOT_OUT")" 0 || f=1
    check "left click: NotificationClosed reason" "$(reason "$SHOT_ID" "Screenshot saved")" 2 || f=1
    wait_unmapped

    echo "  no click: the 10 s timeout prints nothing"
    screenshot_start N7-timeout
    check "timeout: notify-send exited" "$(screenshot_wait)" exited || f=1
    check "timeout: printed nothing" "$(wc -c < "$SHOT_OUT")" 0 || f=1
    bus_stop
    closed_check "timeout" "$SHOT_ID" "Screenshot saved" 1 10.0 || f=1
    check "one ActionInvoked on the bus, discard" "$("$REPO/tests/buslog.py" "$BUSLOG" | grep -c "action")" 1 || f=1
    wait_unmapped

    echo "  frame series: the card rises after the wipe, falls before the leave"
    frames N7/card "0 run notify-send -a screenshot -i $png -t 10000 'Screenshot saved' 'demo-screenshot.png. Right click to discard'" \
        "0 shot" "640 shot" "900 shot" "1300 shot" "1700 shot" "2100 run quickshell ipc -p $REPO call notify dismiss" \
        "2100 shot" "2400 shot" "2700 shot" "3000 shot" "3400 shot" "3900 shot"
    echo "  frames: $FD/sheet.png ($(frame_times))"
    check "900 ms: wipe still running, no card" "$(px "$FD/t0900.png" color $((x + 50)) 36)" "$CLIENT" || f=1
    check "1700 ms: card up" "$(px "$FD/t1700.png" color $((x + 1)) 1)" "$(palette base01)" || f=1
    check "2100 ms: card still up" "$(px "$FD/t2100.png" color $((x + 1)) 1)" "$(palette base01)" || f=1
    check "2700 ms: card down" "$(px "$FD/t2700.png" color $((x + 50)) 10)" "$CLIENT" || f=1
    check "2700 ms: the note still open while the card is down" "$(px "$FD/t2700.png" color 1300 84)" "$(palette base01)" || f=1
    wait_unmapped
    reset_notifs
    return $f
}

# N17 (decision D5): a plain note sent during fullscreen waits in the queue.
# Fullscreen off after 10 s: it shows then. Off after 35 s: it expired into
# history at 30 s and nothing appears.
case_N17() {
    local f=0 id ta toff s h0
    prepare
    reset_notifs
    bus_start N17
    echo "  fullscreen off after 10 s"
    n swaymsg -q '[title="client-2"] fullscreen enable'
    sleep 0.5
    ta=$(date +%s.%N)
    id=$(send "Held note" "fictional note during a film")
    sleep 1
    check "fullscreen on the focused output" "$(notif "d['fullscreen']")" True || f=1
    check "held in the queue, nothing on display" "$(notif "(d['note'], d['held'])")" "(None, [$id])" || f=1
    check "overlay unmapped" "$(mapped_h1)" False || f=1
    s=$(shot N17 held)
    check "bar rows show the client" "$(px "$s" color 1000 1179)" "$CLIENT" || f=1
    until_t "$ta" 10
    toff=$(date +%s.%N)
    n swaymsg -q '[title="client-2"] fullscreen disable'
    sleep 1
    check "on display after fullscreen ends" "$(notif "d['current']['summary']")" "Held note" || f=1
    s=$(shot N17 shown)
    check "note drawn (base01)" "$(px "$s" color 1000 1179)" "$(palette base01)" || f=1
    until_t "$toff" 5.5
    closed_check "5 s after it showed" "$id" "Held note" 1 "$(python3 -c "print(f'{$toff - $ta + 5.0:.2f}')")" 0.4 || f=1
    wait_unmapped

    echo "  fullscreen off after 35 s"
    h0=$(notif "d['history']")
    n swaymsg -q '[title="client-2"] fullscreen enable'
    sleep 0.5
    ta=$(date +%s.%N)
    id=$(send "Held too long" "fictional note during a long film")
    until_t "$ta" 29
    check "29 s: still held" "$(notif "(d['note'], d['held'])")" "(None, [$id])" || f=1
    until_t "$ta" 31
    check "31 s: gone from the queue" "$(notif "(d['note'], d['waiting'])")" "(None, [])" || f=1
    check "31 s: newest history entry" "$(notif "(d['history'], d['newest'])")" "($((h0 < 20 ? h0 + 1 : 20)), 'Held too long')" || f=1
    until_t "$ta" 35
    n swaymsg -q '[title="client-2"] fullscreen disable'
    sleep 1
    check "nothing appears after fullscreen ends" "$(notif "d['visible']") $(mapped_h1)" "False False" || f=1
    bus_stop
    closed_check "queue limit" "$id" "Held too long" 1 30.0 || f=1
    reset_notifs
    return $f
}

# Hover pause (SPEC section 8): the pointer on the note pauses its timer
# and its marquee, leaving resumes both. The card counts as the note.
case_HV() {
    local f=0 id body o1 o2 o3 o4
    prepare
    reset_notifs
    bus_start HV
    echo "  frame series: the pointer moves onto a 3 s note at 1 s, away at 4 s"
    frames HV/pause --region "0,1176 1920x24" \
        "0 run notify-send -p -t 3000 'Hover check' 'the timer pauses under the pointer'" \
        "1000 run swaymsg -q seat seat0 cursor set 1000 1188" \
        "4000 run swaymsg -q seat seat0 cursor set 960 600" \
        "500 shot" "900 shot" "1500 shot" "2500 shot" "3500 shot" "4500 shot" "5500 shot" "6800 shot"
    echo "  frames: $FD/sheet.png ($(frame_times))"
    id=$(fj "[r for r in d['runs'] if 'Hover check' in r['cmd']][0]['stdout'].strip()")
    more "500 to 900 ms: the progress line shrinks" "$(px "$FD/t0500.png" diff "$FD/t0900.png" 206 0 1860 2)" 10 || f=1
    check "1500 to 3500 ms: frozen under the pointer" "$(px "$FD/t1500.png" diff "$FD/t3500.png" 206 0 1860 24)" 0 || f=1
    check "3500 ms: on display past its 3 s" "$(px "$FD/t3500.png" color 1300 12)" "$(palette base01)" || f=1
    more "4500 to 5500 ms: shrinks again once the pointer left" "$(px "$FD/t4500.png" diff "$FD/t5500.png" 206 0 1860 2)" 10 || f=1
    check "5500 ms: still on display" "$(px "$FD/t5500.png" color 1300 12)" "$(palette base01)" || f=1
    check "6800 ms: gone" "$(px "$FD/t6800.png" color 1300 12)" "$(palette base00)" || f=1
    bus_stop
    closed_check "3 s plus the 3 s under the pointer" "$id" "Hover check" 1 6.0 || f=1
    wait_unmapped

    echo "  the marquee stands still under the pointer"
    body=$(python3 -c 'print(("Fictional hover check with a body long enough to scroll across the span. " * 8)[:400])')
    send -t 30000 "Hover marquee" "$body" > /dev/null
    sleep 2.6
    more "scrolling before the hover (offset px)" "$(view "int(v['marquee']['offset'])")" 10 || f=1
    scene hover 1000 $MID
    sleep 0.2
    o1=$(view "v['marquee']['offset']")
    sleep 1
    o2=$(view "v['marquee']['offset']")
    check "offset unchanged for 1 s under the pointer" "$o2" "$o1" || f=1
    check "timer paused, hover reported" "$(notif "(d['note']['running'], d['hovered'])")" "(False, True)" || f=1
    park
    sleep 0.6
    o3=$(view "v['marquee']['offset']")
    more "scrolls again once the pointer left (px in 0.6 s)" "$(python3 -c "print(int($o3 - $o2))")" 15 || f=1
    check "timer running again" "$(notif "(d['note']['running'], d['hovered'])")" "(True, False)" || f=1
    reset_notifs

    echo "  the card counts as the note"
    screenshot_start HV-card
    read -r o1 o2 <<< "$(view "f\"{round(v['card']['x'] + v['card']['width'] / 2)} {round(1104 + v['card']['y'] + 30)}\"")"
    scene hover "$o1" "$o2"
    sleep 0.3
    check "pointer on the card: paused" "$(notif "(d['note']['running'], d['hovered'])")" "(False, True)" || f=1
    scene hover 1000 $MID
    sleep 0.3
    check "card to note line: still paused" "$(notif "(d['note']['running'], d['hovered'])")" "(False, True)" || f=1
    park
    sleep 0.3
    check "away: running" "$(notif "(d['note']['running'], d['hovered'])")" "(True, False)" || f=1
    ipc notify dismiss
    check "screenshot run exited" "$(screenshot_wait)" exited || f=1
    wait_unmapped

    echo "  no hover left behind when the note leaves under the pointer"
    send -t 30000 "Hover check" "dismissed under the pointer" > /dev/null
    sleep 1
    scene hover 1000 $MID
    sleep 0.3
    check "on the note: paused" "$(notif "d['hovered']")" True || f=1
    ipc notify dismiss
    wait_unmapped
    check "after the unmap: no hover" "$(notif "d['hovered']")" False || f=1
    park
    send -t 30000 "Hover check" "the next one runs" > /dev/null
    sleep 1
    check "next note: timer running" "$(notif "(d['note']['running'], d['hovered'])")" "(True, False)" || f=1
    reset_notifs

    # Q21 (M7): the overlay gets no pointer enter until the pointer moves,
    # so the view asks the bar, which still holds the pointer.
    echo "  a note that opens under a resting pointer pauses at once"
    scene hover 1000 $MID
    sleep 0.3
    send -t 3000 "Hover check" "opens under the resting pointer" > /dev/null
    sleep 1
    check "resting pointer: paused" "$(notif "(d['note']['running'], d['hovered'])")" "(False, True)" || f=1
    check "reported by the bar, not the overlay" "$(view "v['resting']")" True || f=1
    park
    sleep 0.3
    check "pointer moved away: running" "$(notif "(d['note']['running'], d['hovered'])")" "(True, False)" || f=1
    reset_notifs
    return $f
}

# Clicks per the rules table (SPEC sections 5 and 8): left runs the default
# action or dismisses, right dismisses, middle dismisses everything.
case_CL() {
    local f=0 out p id a b c v
    prepare
    reset_notifs
    bus_start CL
    echo "  left click on a note with a default action"
    out=$T/logs/CL-default.out
    n notify-send -p -A default=Open -A later=Later "Click check" "left click runs the default action" > "$out" 2>&1 &
    p=$!
    sleep 1
    id=$(notif "d['current']['id']")
    click 1000 $MID
    park
    wait "$p" || true
    check "notify-send printed the default action" "$(sed -n 2p "$out")" default || f=1
    check "closed with reason 2" "$(reason "$id" "Click check")" 2 || f=1
    wait_unmapped

    echo "  right click on a note with a default action"
    out=$T/logs/CL-right.out
    n notify-send -p -A default=Open "Click right" "right click only dismisses" > "$out" 2>&1 &
    p=$!
    sleep 1
    id=$(notif "d['current']['id']")
    click 1000 $MID button3
    park
    wait "$p" || true
    check "no action printed" "$(sed -n 2p "$out")" "" || f=1
    check "closed with reason 2" "$(reason "$id" "Click right")" 2 || f=1
    wait_unmapped

    echo "  left click on a critical without actions"
    id=$(send -u critical -a demo-app "Click critical" "left click dismisses")
    sleep 1
    click 1000 $MID
    park
    sleep 0.3
    check "critical closed with reason 2" "$(reason "$id" "Click critical")" 2 || f=1
    wait_unmapped

    echo "  middle click: the note and the whole queue"
    a=$(send "Click middle" "first of three")
    b=$(send "Click middle" "second of three")
    c=$(send "Click middle" "third of three")
    sleep 1
    check "two waiting" "$(notif "d['queued']")" 2 || f=1
    click 1000 $MID button2
    park
    sleep 0.3
    for v in "$a" "$b" "$c"; do
        check "note $v closed with reason 2" "$(reason "$v" "Click middle")" 2 || f=1
    done
    check "nothing left" "$(notif "d['tracked']")" 0 || f=1
    wait_unmapped

    echo "  middle click on an OSD over a note"
    a=$(send "Click under" "note under the OSD")
    sleep 0.6
    b=$(send -a volume -t 3000 -e -h int:value:50 -h string:x-canonical-private-synchronous:volume "Volume: 50%")
    sleep 0.4
    click 1000 $MID button2
    park
    sleep 0.3
    bus_stop
    check "OSD closed with reason 2" "$(reason "$b" "Volume: 50%")" 2 || f=1
    check "note under it closed with reason 2" "$(reason "$a" "Click under")" 2 || f=1
    reset_notifs
    return $f
}

# The screenshot.sh contract (docs/PLAN.md M1): discard through IPC, then a
# run that times out.
case_SC() {
    local f=0 out1 out2 p1 p2 id
    reset_notifs
    check "GetCapabilities (SPEC section 12)" "$(n gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetCapabilities)" \
        "(['body', 'body-markup', 'actions', 'icon-static'],)" || f=1
    bus_start SC
    out1=$T/logs/SC-discard.out
    n "$REPO/tests/fake-screenshot.sh" > "$out1" 2>&1 &
    p1=$!
    sleep 1
    check "screenshot note on display" "$(notif "(d['current']['app'], d['kind'])")" "('screenshot', 'rich')" || f=1
    ipc notify invoke discard
    for _ in $(seq 30); do kill -0 "$p1" 2> /dev/null || break; sleep 0.1; done
    check "first run exited after invoke" "$(kill -0 "$p1" 2> /dev/null && echo running || echo exited)" exited || f=1
    check "first run printed" "$(cat "$out1")" discard || f=1
    out2=$T/logs/SC-timeout.out
    n "$REPO/tests/fake-screenshot.sh" > "$out2" 2>&1 &
    p2=$!
    sleep 1
    id=$(notif "d['current']['id']")
    for _ in $(seq 120); do kill -0 "$p2" 2> /dev/null || break; sleep 0.1; done
    check "second run exited on its own" "$(kill -0 "$p2" 2> /dev/null && echo running || echo exited)" exited || f=1
    check "second run printed nothing" "$(wc -c < "$out2")" 0 || f=1
    bus_stop
    check "ActionInvoked discard on the bus" "$("$REPO/tests/buslog.py" "$BUSLOG" | grep -c "key='discard'")" 1 || f=1
    closed_check "timed-out screenshot note" "$id" "Screenshot saved" 1 10.0 || f=1
    reset_notifs
    return $f
}

# Runs last when the whole matrix runs: nothing may stay tracked.
case_END() {
    local f=0
    reset_notifs
    check "tracked notifications after dismissAll" "$(notif "d['tracked']")" 0 || f=1
    wait_unmapped
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    return $f
}

"$REPO/tests/nested.sh" status || { echo "matrix: no nested session, run: make nested" >&2; exit 1; }

cases="$(declare -F | sed -n 's/^declare -f case_//p' | grep -vx -e END -e N16 | sort -V) N16 END"
[ $# -gt 0 ] && wanted=$* || wanted=$cases
[ -n "$wanted" ] || { echo "matrix: no case implemented yet" >&2; exit 1; }

# N16 compares the idle bar after the cases with this one.
rm -f "$T/shots/N16/before.png"
if grep -qw N16 <<< "$wanted"; then
    before_shot
fi

failed=0
for id in $wanted; do
    if ! declare -F "case_$id" > /dev/null; then
        echo "FAIL $id (not implemented)"; failed=1; continue
    fi
    if "case_$id"; then echo "PASS $id"; else echo "FAIL $id"; failed=1; fi
done
exit $failed
