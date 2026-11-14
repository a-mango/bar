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

"$REPO/tests/nested.sh" status || { echo "matrix: no nested session, run: make nested" >&2; exit 1; }

cases=$(declare -F | sed -n 's/^declare -f case_//p')
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
