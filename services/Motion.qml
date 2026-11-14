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
}
