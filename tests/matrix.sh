#!/usr/bin/env bash
# The docs/SPEC.md test matrix, run against the nested session (make nested).
#
#   tests/matrix.sh          run every case
#   tests/matrix.sh N5       run one case
#
# Each case is a shell function named case_<ID>. It saves screenshots to
# .test/shots/<ID>/ and returns non-zero on failure. M2 added B1 to B6,
# M1 adds the N cases. The B cases set up tests/scene.sh once per session.
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=$REPO/.test

n() { "$REPO/tests/nested.sh" run "$@"; }             # a command inside the session
ipc() { n quickshell ipc -p "$REPO" call "$@"; }      # an IPC call to bar
scene() { "$REPO/tests/scene.sh" "$@"; }
click() { "$REPO/tests/nested.sh" click "$@"; }
px() { "$REPO/tests/pixel.py" "$@"; }

# Screenshot of HEADLESS-1 into .test/shots/<case>/<name>.png; prints the path.
shot() {
    mkdir -p "$T/shots/$1"
    n grim -o HEADLESS-1 "$T/shots/$1/$2.png"
    echo "$T/shots/$1/$2.png"
}

# A dark palette color by name, from themes/.
palette() { sed -n "s/^@define-color $1 \(#[0-9a-f]*\);/\1/p" "$REPO/themes/base16-default-dark.css"; }

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
    local f=0 pid count index x a b before menu box mark log
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
    a=$(shot B5 attention-1); sleep 0.5
    b=$(shot B5 attention-2)
    more "NeedsAttention: the background above icon $index changes" "$(px "$a" diff "$b" $((x - 8)) 1177 $((x + 8)) 1179)" 1 || f=1
    scene tray 1 Passive; sleep 0.3
    a=$(shot B5 passive)
    check "Passive: no blink background" "$(px "$a" color $x $TOP)" "$(palette base00)" || f=1
    scene tray 1 Active; sleep 0.3
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
    # The second entry, "Sync demo data", sits 35 px below the menu's top.
    read -r x0 y0 x1 _ <<< "$box"
    click "$(python3 -c "print(int(($x0 + $x1) / 2))")" "$(python3 -c "print(int($y0 + 35))")"; sleep 0.5
    check "click on an entry reaches the item" "$(tail -n +$((mark + 1)) "$log" | grep -o "\[$pid\] Event 2 clicked .*")" "[$pid] Event 2 clicked 'Sync demo data'" || f=1
    check "menu closed after the click" "$(state "d['tray'][$index]['menuOpen']")" False || f=1
    return $f
}

case_B6() {
    local out
    out=$(n env SNI_WAIT_TIMEOUT=10 /usr/libexec/sway-systemd/wait-sni-ready 2>&1)
    echo "  $out"
    check "wait-sni-ready (the script exits 0 on failure too)" "$(grep -c 'Successfully waited for org.kde.StatusNotifierHost' <<< "$out")" 1
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
overlay_mapped() { state "d['overlays'][0]['visible']"; }
# Every case starts and ends with nothing on display and DND off.
reset_notifs() {
    ipc notify dismissAll
    ipc notify setDnd false
    for _ in $(seq 70); do
        [ "$(notif "d['tracked']")" = 0 ] && return 0
        sleep 0.1
    done
    echo "  note: $(notif "d['tracked']") notification(s) still tracked after the reset"
}
# closed_check <what> <id> <summary> <reason> <seconds> [tolerance]
closed_check() {
    local r t
    read -r r t <<< "$(closed "$2" "$3")"
    check "$1: NotificationClosed reason" "$r" "$4" && within "$1: closed after" "$t" "$5" "${6:-0.3}"
}

case_N1() {
    local f=0 id
    reset_notifs
    bus_start N1
    id=$(send "Build finished" "demo-app compiled in 42 s")
    sleep 0.5
    shot N1 visible > /dev/null
    check "on display" "$(notif "d['current']['summary']")" "Build finished" || f=1
    check "kind" "$(notif "d['kind']")" note || f=1
    check "overlay mapped" "$(overlay_mapped)" True || f=1
    sleep 5
    bus_stop
    closed_check "note" "$id" "Build finished" 1 5.0 || f=1
    check "overlay unmapped afterwards" "$(overlay_mapped)" False || f=1
    reset_notifs
    return $f
}

case_N3() {
    local f=0 a b c
    reset_notifs
    bus_start N3
    a=$(send "Note one" "first of three"); sleep 0.1
    b=$(send "Note two" "second of three"); sleep 0.1
    c=$(send "Note three" "third of three")
    sleep 0.4
    shot N3 first > /dev/null
    check "first on display" "$(notif "d['current']['summary']")" "Note one" || f=1
    check "waiting (+2)" "$(notif "d['queued']")" 2 || f=1
    sleep 5
    shot N3 second > /dev/null
    check "second on display after the first leaves" "$(notif "d['current']['summary']")" "Note two" || f=1
    check "waiting (+1)" "$(notif "d['queued']")" 1 || f=1
    sleep 10.5
    bus_stop
    closed_check "first, from its arrival" "$a" "Note one" 1 5.0 || f=1
    closed_check "second, from the first arrival" "$b" "Note one" 1 10.0 || f=1
    closed_check "third, from the first arrival" "$c" "Note one" 1 15.0 || f=1
    reset_notifs
    return $f
}

case_N5() {
    local f=0 v ids=()
    reset_notifs
    bus_start N5
    for v in 10 20 30 40 50; do
        ids+=("$(send -a volume -t 800 -e -h int:value:$v -h string:x-canonical-private-synchronous:volume "Volume: $v%")")
        [ "$v" = 50 ] || sleep 0.1
    done
    # The last OSD lives 800 ms: read everything at once, right away.
    local st
    st=$(ipc debug state)
    py() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($1)" "$st"; }
    shot N5 osd > /dev/null
    check "kind on display" "$(py "d['notifs']['kind']")" osd || f=1
    check "OSD value" "$(py "d['notifs']['osd']['value']")" 50 || f=1
    check "OSD id (the last one)" "$(py "d['notifs']['osd']['id']")" "${ids[4]}" || f=1
    check "nothing queued, no note" "$(py "(d['notifs']['queued'], d['notifs']['note'])")" "(0, None)" || f=1
    check "one overlay mapped" "$(py "sum(1 for o in d['overlays'] if o['visible'])")" 1 || f=1
    sleep 1.2
    bus_stop
    for v in 0 1 2 3; do
        closed_check "OSD $((v + 1)) replaced by the next" "${ids[$v]}" "Volume: $((v * 10 + 20))%" 1 0.0 0.2 || f=1
    done
    closed_check "last OSD (sender timeout 800 ms)" "${ids[4]}" "Volume: 50%" 1 0.8 || f=1
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
    check "history grew by one" "$(notif "d['history']")" $((h0 + 1)) || f=1
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
    sleep 5
    bus_stop
    # Timer restarted at the reload: about 1 s + reload + 5 s, not 5 s.
    closed_check "survivor" "$id" "Survivor" 1 6.4 0.9 || f=1
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

# The screenshot.sh contract (docs/PLAN.md M1): discard through IPC, then a
# run that times out.
case_SC() {
    local f=0 out1 out2 p1 p2 id
    reset_notifs
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
    check "overlay unmapped" "$(overlay_mapped)" False || f=1
    return $f
}

"$REPO/tests/nested.sh" status || { echo "matrix: no nested session, run: make nested" >&2; exit 1; }

cases="$(declare -F | sed -n 's/^declare -f case_//p' | grep -vx END | sort -V) END"
[ $# -gt 0 ] && wanted=$* || wanted=$cases
[ -n "$wanted" ] || { echo "matrix: no case implemented yet" >&2; exit 1; }

failed=0
for id in $wanted; do
    if ! declare -F "case_$id" > /dev/null; then
        echo "FAIL $id (not implemented)"; failed=1; continue
    fi
    if "case_$id"; then echo "PASS $id"; else echo "FAIL $id"; failed=1; fi
done
exit $failed
