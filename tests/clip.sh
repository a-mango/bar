#!/usr/bin/env bash
# Review clips (M7): records the notification animations of the nested
# session with wf-recorder, one clip per scene, plus all scenes in one file.
#
#   tests/clip.sh <round> [scene...]     default: every scene
#
# Writes .test/clips/<round>/<scene>.mp4 and all.mp4 (HEADLESS-1, bottom
# 96 logical px: the strip and the rich card's room, 3840x192 physical).
# SLOW=<factor> records under `debug slow <factor>` (notes only, the OSD
# ignores it) and resets it to 1 afterwards.
#
# wf-recorder uses wlr-screencopy's region capture, so it does not stall
# the compositor the way grim does (frames arrive every 16-17 ms during a
# wipe). -D asks for frames continuously: on damage only, wf-recorder exits
# after the next damaged frame, up to a minute later on an idle bar. It
# runs inside the nested session only, through tests/nested.sh run. The
# clips are lossless RGB (libx264rgb, crf 0): 4:2:0 turns the 2 px edge
# gray, and yuv444p still shifts the colors through the range conversion.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=$REPO/.test
round=${1:?usage: tests/clip.sh <round> [scene...]}
shift
SCENES=(note roll marquee critical osd rich light theme)
[ $# -gt 0 ] && SCENES=("$@")
OUT=$T/clips/$round
mkdir -p "$OUT"

n() { "$REPO/tests/nested.sh" run "$@"; }
ipc() { n quickshell ipc -p "$REPO" call "$@"; }
osd() { n notify-send -a "$1" -t "${3:-800}" -e -h "int:value:$2" -h "string:x-canonical-private-synchronous:$1" "${1^}: $2%"; }

png=$T/demo-screenshot.png
[ -e "$png" ] || n magick -size 1920x1200 gradient:steelblue-plum -fill white -pointsize 160 -gravity center -annotate 0 demo "$png"

reset() {
    ipc notify dismissAll > /dev/null
    ipc theme set dark > /dev/null
    "$REPO/tests/scene.sh" hover 960 600 > /dev/null
    sleep 1.2
}

# rec <scene> <seconds after the scene's commands>: records while the
# scene function runs, then for the given time.
rec() {
    local scene=$1 tail=$2 pid
    reset
    # Not through n(): a backgrounded function is a subshell, and $! must be
    # wf-recorder itself (nested.sh and env exec into it).
    "$REPO/tests/nested.sh" run wf-recorder -D -o HEADLESS-1 -g "0,1104 1920x96" -c libx264rgb -x bgr0 -p crf=0 -p preset=ultrafast \
        -y -f "$OUT/$scene.mp4" > "$OUT/$scene.log" 2>&1 &
    pid=$!
    sleep 0.8
    "scene_$scene"
    sleep "$tail"
    kill -INT "$pid"
    wait "$pid" || true
    echo "clip: $OUT/$scene.mp4" >&2
}

scene_note() { n notify-send -a demo-app -t 3000 "Orchard report" "The pears are ripe on the north rows"; }
scene_roll() {
    n notify-send -a demo-app -t 2000 "Orchard report" "The pears are ripe on the north rows"
    sleep 0.3
    n notify-send -a demo-mail -t 2000 "Letter from the mill" "Flour delivery moves to Thursday"
}
scene_marquee() {
    n notify-send -a demo-app -t 9000 "Release notes" "$(printf 'Lantern 4.2 adds tide tables, a quieter fan curve, moon phases in the calendar, %.0s' 1 2 3)"
}
scene_critical() {
    n notify-send -a demo-battery -u critical "Battery low" "5% remaining"
    sleep 5
    ipc notify dismiss > /dev/null
}
scene_osd() {
    osd volume 30; sleep 0.3
    osd volume 45; sleep 0.3
    osd volume 60; sleep 1.5
    osd brightness 40
}
scene_rich() { n notify-send -a screenshot -i "$png" -t 4000 "Screenshot saved" "demo-screenshot.png. Right click to discard"; }
scene_light() {
    ipc theme set light > /dev/null
    sleep 0.5
    n notify-send -a demo-app -t 2500 "Orchard report" "The pears are ripe on the north rows"
    sleep 3.5
    osd volume 55
}

# A theme switch while a note shows, and back.
scene_theme() {
    n notify-send -a demo-app -t 6000 "Orchard report" "The pears are ripe on the north rows"
    sleep 2
    ipc theme set light > /dev/null
    sleep 2
    ipc theme set dark > /dev/null
}

if [ -n "${SLOW:-}" ]; then
    ipc debug slow "$SLOW" > /dev/null
    trap 'ipc debug slow 1 > /dev/null' EXIT
fi

for s in "${SCENES[@]}"; do
    case $s in
        note) rec note 4 ;;
        roll) rec roll 5 ;;
        marquee) rec marquee 10 ;;
        critical) rec critical 1.5 ;;
        osd) rec osd 2 ;;
        rich) rec rich 6 ;;
        light) rec light 2 ;;
        theme) rec theme 2 ;;
        *) echo "clip: unknown scene $s" >&2; exit 2 ;;
    esac
done
reset

# All recorded scenes in one file, in the default order.
list=$OUT/all.txt
: > "$list"
for s in note roll marquee critical osd rich light theme; do
    [ -e "$OUT/$s.mp4" ] && echo "file '$OUT/$s.mp4'" >> "$list"
done
ffmpeg -v error -y -f concat -safe 0 -i "$list" -c copy "$OUT/all.mp4"
echo "clip: $OUT/all.mp4" >&2
