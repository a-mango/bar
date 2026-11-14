pragma Singleton

import QtQuick
import Quickshell

// Durations and easing curves. Views take every animation value from here.
// M3 and M4 add the notification values from docs/SPEC.md section 7.
Singleton {
    // Tray NeedsAttention blink: one way of the base08 <-> base00 cycle
    // (waybar's `blink` keyframes, 0.5 s alternate).
    readonly property int blink: 500
    // Hover time before the clock calendar or a tray tooltip shows.
    readonly property int tooltipDelay: 400

    // ---- notes (docs/SPEC.md section 7, M4) ----

    // Slow motion for frame series (`debug slow <factor>`): every note
    // duration is multiplied by it, the marquee speed divided. 1 in use.
    property real slow: 1

    // Enter: the clock compacts and slides to the span's left edge, then
    // the note wipes in from the separator.
    readonly property int clockCompact: 240 * slow
    readonly property int clockCompactEasing: Easing.OutCubic
    readonly property int noteWipe: 320 * slow
    readonly property int noteWipeEasing: Easing.OutCubic
    // Leave: the note retracts into the separator, then the clock slides
    // back to the center and expands.
    readonly property int noteRetract: 240 * slow
    readonly property int noteRetractEasing: Easing.InCubic
    readonly property int clockExpand: 240 * slow
    readonly property int clockExpandEasing: Easing.OutCubic
    // Next in queue: the old line leaves upwards, the new one comes from below.
    readonly property int noteRoll: 200 * slow
    readonly property int noteRollEasing: Easing.OutQuad
    // Marquee of a line wider than its space: hold, scroll, hold, fade back.
    readonly property int marqueeHold: 1200 * slow
    readonly property real marqueeSpeed: 60 / slow // px per second
    readonly property int marqueeEndHold: 1000 * slow
    readonly property int marqueeReturn: 150 * slow
    // Critical: the leading-edge glow pulses between two opacities.
    readonly property int pulsePeriod: 1600 * slow
    readonly property real pulseLow: 0.4
    readonly property real pulseHigh: 1.0
    readonly property int pulseEasing: Easing.InOutSine
}
