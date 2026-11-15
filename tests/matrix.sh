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
# presses) and ON (an OSD over a note). The B cases and the OSD cases set
# up tests/scene.sh once per session.
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

# The OSD part of B7 (M3): a fullscreen client covers the bar, a volume OSD
# draws above it. The screenshot note and the held plain note come with M5
# (decision D5).
case_B7() {
    local f=0 s client="#8b008b" # the test client's darkmagenta
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
    n swaymsg -q '[title="client-2"] fullscreen disable'
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
overlay_mapped() { state "d['overlays'][0]['visible']"; }
# Every case starts and ends with nothing on display and DND off. The
# overlays unmap only once their fade-out has ended.
reset_notifs() {
    ipc notify dismissAll
    ipc notify setDnd false
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
# The overlay of HEADLESS-1 in a state `d`. Until M6 the overlay maps on
# every output, so surfaces and entries are counted on HEADLESS-1 only.
H1="[o for o in d['overlays'] if o['screen'] == 'HEADLESS-1'][0]"
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
mapped_h1() { state "$H1['visible']"; }
wait_unmapped() {
    for _ in $(seq 30); do
        [ "$(mapped_h1)" = False ] && return 0
        sleep 0.1
    done
    return 1
}
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
    check "note span drawn again (base01)" "$(px "$s" color 960 $TOP)" "$(palette base01)" || f=1
    click 65 $MID
    sleep 0.3
    check "mask back on the note span: a click on workspace 3 reaches the bar" "$(focused_ws)" 3 || f=1
    n swaymsg -q workspace 2
    c2=$(osd_counts)
    counts_check "OSD over the note, whole case" "$c0" "$c2" 0 1 0 || f=1
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
