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
}
