pragma Singleton

import QtQuick
import Quickshell

// Durations and easing curves. Views take every animation value from here.
// The notification values come from docs/SPEC.md section 7 (M3, M4).
Singleton {
    // Tray NeedsAttention blink: one way of the base08 <-> base00 cycle
    // (waybar's `blink` keyframes, 0.5 s alternate).
    readonly property int blink: 500
    // Hover time before the clock calendar or a tray tooltip shows.
    readonly property int tooltipDelay: 400

    // ---- OSD (overlay/OsdView.qml, SPEC section 7) ----
    // Enter: the strip fades in while the fill grows from 0 to the value.
    // The SPEC gives no curve for the fades: linear.
    readonly property int osdFadeIn: 100
    readonly property int osdFadeEasing: Easing.Linear
    readonly property int osdGrow: 180
    readonly property int osdGrowEasing: Easing.OutCubic
    // Update (same synchronous tag): the fill moves to the new value.
    readonly property int osdUpdate: 120
    readonly property int osdUpdateEasing: Easing.OutQuad
    // Leave: the strip fades out, back to the bar or the open note span.
    readonly property int osdFadeOut: 150

    // ---- notes (docs/SPEC.md section 7, M4) ----

    // Slow motion for frame series (`debug slow <factor>`): every note
    // duration is multiplied by it, the marquee speed divided. 1 in use.
    // The OSD values above ignore it.
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
    // Rich: the card slides up from behind the strip once the wipe (or a
    // roll) ends, and back down before the note leaves or rolls. The SPEC
    // gives the way up: the way down mirrors it, like the retract.
    readonly property int cardRise: 220 * slow
    readonly property int cardRiseEasing: Easing.OutCubic
    readonly property int cardFall: 220 * slow
    readonly property int cardFallEasing: Easing.InCubic
    // Leading edge halo (shaders/wipe.frag): peak opacity next to the
    // 2 px line, and the Gaussian's sigma in logical px.
    readonly property real edgeHalo: 0.55
    readonly property real edgeRadius: 3

    // Critical: the leading-edge glow pulses between two opacities.
    readonly property int pulsePeriod: 1600 * slow
    readonly property real pulseLow: 0.4
    readonly property real pulseHigh: 1.0
    readonly property int pulseEasing: Easing.InOutSine
}
