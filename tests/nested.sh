#!/usr/bin/env bash
# Isolated test desktop: a headless sway on a private D-Bus session bus,
# running quickshell on this tree. Nothing here talks to the live session:
# the session starts under `env -i` with its own SWAYSOCK and bus address.
#
#   tests/nested.sh start [bar|bare|waybar]   start in the background, return when ready
#   tests/nested.sh stop                      end the session and clean up
#   tests/nested.sh fg [bar|bare|waybar]      run until interrupted, then clean up
#   tests/nested.sh status                    exit 0 if the session is up
#   tests/nested.sh run <command...>          run a command inside the session
#   tests/nested.sh shot [name]               screenshot HEADLESS-1 into .test/shots/
#   tests/nested.sh click <x> <y> [button]    click at logical output coordinates
#   tests/nested.sh reference                 waybar session, bar screenshot, stop
#
# Variants: `bar` runs quickshell on this tree (default), `bare` runs nothing
# (spike S5), `waybar` runs waybar with docs/reference/waybar (the visual
# target). NESTED_DIR selects the runtime directory (default .test), so the
# reference session can run next to the main one.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=${NESTED_DIR:-$REPO/.test}
case $T in /*) ;; *) echo "nested: NESTED_DIR must be absolute" >&2; exit 2 ;; esac
START_TIMEOUT=${NESTED_TIMEOUT:-20}

log() { echo "nested: $*" >&2; }

# The environment of everything inside the session. Every path is absolute.
session_env() {
    printf '%s\n' \
        "HOME=$HOME" \
        "PATH=$REPO/tests/bin:$PATH" \
        "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
        "DBUS_SESSION_BUS_ADDRESS=$1" \
        "SWAYSOCK=$T/sway.sock" \
        "XDG_STATE_HOME=$T/state" \
        "XDG_CACHE_HOME=$T/cache" \
        "BAR_REPO=$REPO" \
        "BAR_TEST_DIR=$T" \
        "NESTED_DIR=$T"
}

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
session_pid() { cat "$T/session.pid" 2>/dev/null || true; }

# Runs a command with the environment of the running session and nothing else.
run_in() {
    [ -r "$T/env" ] || { log "no session in $T (start it with: make nested)"; exit 1; }
    local vars=()
    while IFS= read -r line; do
        vars+=("${line#export }")
    done < <(sed -e "s/^export \([A-Z0-9_]*\)='\(.*\)'\$/\1=\2/" "$T/env")
    exec env -i "${vars[@]}" "$@"
}

# Step 1 (inside dbus-run-session): drop the caller's environment, start sway.
cmd_session() {
    local variant=$1 vars=()
    mapfile -t vars < <(session_env "$DBUS_SESSION_BUS_ADDRESS")
    exec env -i "${vars[@]}" \
        WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
        BAR_VARIANT="$variant" \
        sway -c "$REPO/tests/sway-nested.conf"
}

# Step 2 (exec'd by sway): publish the session environment, start the client.
cmd_inside() {
    {
        session_env "$DBUS_SESSION_BUS_ADDRESS" | sed -e "s/^\([A-Z0-9_]*\)=\(.*\)\$/export \1='\2'/"
        echo "export WAYLAND_DISPLAY='$WAYLAND_DISPLAY'"
        echo "export I3SOCK='$T/sway.sock'"
    } > "$T/env.tmp"
    mv "$T/env.tmp" "$T/env"
    # A headless seat has no pointer: without this device, the
    # `seat seat0 cursor` commands reach no client (spike S4).
    "$REPO/tests/vpointer.py" > "$T/logs/vpointer.log" 2>&1 &
    case ${BAR_VARIANT:-bar} in
        bar)
            exec quickshell -p "$REPO" > "$T/logs/quickshell.log" 2>&1 ;;
        waybar)
            mkdir -p "$T/waybar"
            cp "$REPO/docs/reference/waybar/config.jsonc" "$REPO/docs/reference/waybar/style.css" "$T/waybar/"
            cp "$REPO/docs/reference/waybar/base16-default-dark.css" "$T/waybar/base16-theme.css"
            exec waybar -c "$T/waybar/config.jsonc" -s "$T/waybar/style.css" > "$T/logs/waybar.log" 2>&1 ;;
        bare) ;;
    esac
}

bus_has() {
    ( run_in gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetNameOwner "$1" ) > /dev/null 2>&1
}

ready() {
    [ -r "$T/env" ] || return 1
    case $1 in
        bar) bus_has org.freedesktop.Notifications ;;
        waybar) bus_has org.kde.StatusNotifierWatcher ;;
        bare) ( run_in swaymsg -t get_version ) > /dev/null 2>&1 ;;
    esac && grep -q created "$T/logs/vpointer.log" 2>/dev/null
}

# A left click (or another button) at logical output coordinates.
cmd_click() {
    local x=$1 y=$2 button=${3:-button1}
    ( run_in swaymsg -q seat seat0 cursor set "$x" "$y" )
    ( run_in swaymsg -q seat seat0 cursor press "$button" )
    ( run_in swaymsg -q seat seat0 cursor release "$button" )
}

cmd_stop() {
    local pid; pid=$(session_pid)
    if alive "$pid"; then
        if [ -S "$T/sway.sock" ]; then
            swaymsg -s "$T/sway.sock" exit > /dev/null 2>&1 || true
        fi
        for _ in $(seq 50); do alive "$pid" || break; sleep 0.1; done
        if alive "$pid"; then
            log "session $pid did not exit, sending SIGTERM to its process group"
            kill -TERM -- "-$pid" 2>/dev/null || true
            for _ in $(seq 30); do alive "$pid" || break; sleep 0.1; done
            alive "$pid" && kill -KILL -- "-$pid" 2>/dev/null || true
        fi
        log "stopped (session $pid)"
    else
        log "not running"
    fi
    rm -f "$T/session.pid" "$T/env" "$T/env.tmp" "$T/sway.sock"
}

cmd_start() {
    local variant=${1:-bar}
    case $variant in bar|bare|waybar) ;; *) log "unknown variant: $variant"; exit 2 ;; esac
    if alive "$(session_pid)"; then
        log "already running (session $(session_pid)), stop it first"; exit 1
    fi
    mkdir -p "$T/logs" "$T/shots" "$T/state" "$T/cache"
    rm -f "$T/env" "$T/sway.sock" "$T/logs/vpointer.log" "$T/scene-ready" "$T"/fake-sni-*.pid

    # Clean up if the start is interrupted or fails half-way.
    trap 'trap - EXIT INT TERM; log "start aborted"; cmd_stop; exit 1' EXIT INT TERM
    setsid dbus-run-session --config-file="$REPO/tests/session.conf" -- \
        "$REPO/tests/nested.sh" _session "$variant" > "$T/logs/sway.log" 2>&1 < /dev/null &
    echo $! > "$T/session.pid"

    local deadline=$((SECONDS + START_TIMEOUT))
    until ready "$variant"; do
        if ! alive "$(session_pid)"; then log "session died, see $T/logs/sway.log"; exit 1; fi
        if [ "$SECONDS" -ge "$deadline" ]; then log "not ready after ${START_TIMEOUT}s, see $T/logs/"; exit 1; fi
        sleep 0.1
    done
    trap - EXIT INT TERM
    log "up: variant=$variant session=$(session_pid) $(grep -o "WAYLAND_DISPLAY='[^']*'" "$T/env") dir=$T"
}

cmd_fg() {
    cmd_start "${1:-bar}"
    trap 'trap - EXIT INT TERM; cmd_stop' EXIT INT TERM
    log "running in the foreground, Ctrl-C to stop"
    tail --pid="$(session_pid)" -f /dev/null
}

cmd_shot() {
    local out="$T/shots/${1:-$(date +%Y%m%d-%H%M%S)}.png"
    mkdir -p "$(dirname "$out")"
    ( run_in grim -o HEADLESS-1 "$out" )
    echo "$out"
}

# Visual target for M2: waybar with the reference config in its own session.
cmd_reference() {
    mkdir -p "$REPO/.test/shots"
    export NESTED_DIR="$REPO/.test/reference"
    T=$NESTED_DIR
    cmd_start waybar
    trap 'trap - EXIT INT TERM; cmd_stop' EXIT INT TERM
    sleep 1 # waybar draws its first frame after it owns the watcher name
    ( run_in grim -o HEADLESS-1 "$REPO/.test/shots/reference-full.png" )
    magick "$REPO/.test/shots/reference-full.png" -gravity South -crop 3840x48+0+0 +repage \
        "$REPO/.test/shots/reference-bar.png"
    log "reference bar: $REPO/.test/shots/reference-bar.png"
}

case ${1:-} in
    start) shift; cmd_start "$@" ;;
    stop) cmd_stop ;;
    fg) shift; cmd_fg "$@" ;;
    status) alive "$(session_pid)" && [ -r "$T/env" ] ;;
    run) shift; run_in "$@" ;;
    shot) shift; cmd_shot "$@" ;;
    click) shift; cmd_click "$@" ;;
    reference) cmd_reference ;;
    _session) shift; cmd_session "$@" ;;
    _inside) cmd_inside ;;
    *) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2; exit 2 ;;
esac
