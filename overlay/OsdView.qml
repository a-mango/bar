import QtQuick
import qs.services
import qs.bar

// The OSD strip (docs/SPEC.md sections 4 and 7): the full width of the
// output, 24 px, a fill from the left edge to the value in the rule's color,
// and the summary drawn twice, split at the fill edge: base05 over the empty
// part, base00 over the fill. It stays readable at 0 % and at 100 %.
//
// The view follows Notifs.osd while that shows on its output (M6), but
// keeps what it draws (label, value, color
// roles) in its own properties. The core drops the entry the moment it
// closes, and the strip still fades out with the last content. `active`
// stays true until that fade ends, so the overlay stays mapped for it.
//
// Rapid presses with the same synchronous tag replace the entry in the core
// without a gap (the new entry is set before the old one closes), so the
// view sees one entry follow another on the same surface: the fill moves to
// the new value and the entry animation never runs again. An OSD that
// arrives during the fade-out is handled the same way: the strip fades back
// in from where it is. Only an OSD that finds the view idle runs the entry.
//
// The entry starts on the window's first frame, about 30 ms after the
// overlay maps. Started at once, the animations ticked irregularly while the
// surface was being set up: the first visible frame came anywhere from 35 to
// 70 ms, and the fade stretched to 150 ms. From the first frame, Qt's ticks
// are regular and the fade ends 100 ms later (docs/PLAN.md section 8, M3).
Item {
    id: root

    // The output of this view's overlay window.
    property string output: ""
    // The entry on display on this output (null once it closed, or while
    // the OSD shows on another output), from the core.
    property var entry: Notifs.osdOn(output)
    // Device pixel ratio of the window: the fill edge snaps to physical pixels.
    property real dpr: 1

    // What the strip draws, latched from the entry and kept for the fade-out.
    // Color roles stay names, so a theme switch mid-fade still applies.
    property string label: ""
    property string fillRole: "base0D"
    property string backgroundRole: "base00"
    // Target and animated fill, both as a fraction of the width.
    property real target: 0
    property real level: 0

    // From the arrival of an OSD to the end of its fade-out.
    property bool shown: false
    // A new entry waits for the next frame of the window before it animates.
    property bool waiting: false
    readonly property bool active: entry !== null || shown
    readonly property real fillWidth: Math.round(width * Math.max(0, Math.min(1, level)) * dpr) / dpr
    readonly property real labelX: Math.round((width - filledLabel.implicitWidth) / 2)

    // For tests (`debug state`): entry animations and updates started.
    property int entries: 0
    property int updates: 0
    property var last: null

    // 0..1 from the `value` hint (0..100). Anything else counts as 0.
    function fraction(value: var): real {
        const v = Number(value);
        return isFinite(v) ? Math.max(0, Math.min(100, v)) / 100 : 0;
    }

    function animate(anim: var, to: real, duration: real, easing: int): void {
        anim.stop();
        anim.to = to;
        anim.duration = Math.max(0, Math.round(duration));
        anim.easing.type = easing;
        anim.start();
    }

    // Called on every change of the entry and of its snapshot (replaces_id
    // updates mutate `data` in place and bump Notifs.revision).
    function sync(): void {
        const e = entry;
        if (e === null) {
            if (shown)
                leave();
            return;
        }
        const d = e.data;
        label = d.summary || d.app || "";
        fillRole = e.cls.fill || "base0D";
        backgroundRole = e.cls.background || "base00";
        const v = fraction(d.value);

        if (!shown) {
            shown = true;
            last = e;
            target = v;
            fade.stop();
            grow.stop();
            if (e.restored) {
                // A reload survivor: back at once, without the entry.
                opacity = 1;
                level = v;
                return;
            }
            entries += 1;
            opacity = 0;
            level = 0;
            waiting = true;
            return;
        }

        // Already on screen, or fading out: the same strip moves on.
        if (e !== last || v !== target) {
            updates += 1;
            last = e;
            target = v;
            if (!waiting)
                animate(grow, v, Motion.osdUpdate, Motion.osdUpdateEasing);
        }
        if (!waiting && opacity < 1 && !(fade.running && fade.to === 1))
            animate(fade, 1, Motion.osdFadeIn * (1 - opacity), Motion.osdFadeEasing);
    }

    // The entry: the strip fades in while the fill grows from 0.
    function enter(): void {
        waiting = false;
        animate(fade, 1, Motion.osdFadeIn, Motion.osdFadeEasing);
        animate(grow, target, Motion.osdGrow, Motion.osdGrowEasing);
    }

    function leave(): void {
        waiting = false;
        const duration = Math.round(Motion.osdFadeOut * opacity);
        if (duration <= 0) {
            fade.stop();
            opacity = 0;
            shown = false;
            last = null;
            return;
        }
        animate(fade, 0, duration, Motion.osdFadeEasing);
    }

    onEntryChanged: sync()
    Component.onCompleted: sync()

    Connections {
        target: Notifs
        function onRevisionChanged(): void {
            if (root.entry !== null)
                root.sync();
        }
    }

    // The frame that put the waiting strip (still at opacity 0) on screen.
    Connections {
        target: root.Window.window
        enabled: root.waiting
        function onFrameSwapped(): void {
            if (root.waiting)
                root.enter();
        }
    }

    height: Theme.barHeight
    visible: active
    opacity: 0
    // Group opacity while fading, so the text does not blend with its own
    // background. Off once the strip is opaque.
    layer.enabled: opacity > 0 && opacity < 1

    NumberAnimation {
        id: fade
        target: root
        property: "opacity"
        onFinished: {
            if (fade.to === 0) {
                root.shown = false;
                root.last = null;
            }
        }
    }

    NumberAnimation {
        id: grow
        target: root
        property: "level"
    }

    // Filled part: the fill color with the base00 copy of the label.
    Rectangle {
        width: root.fillWidth
        height: parent.height
        color: Theme[root.fillRole]
        clip: true

        BarText {
            id: filledLabel
            x: root.labelX
            text: root.label
            color: Theme.base00
        }
    }

    // Empty part: the rule's background with the base05 copy of the label,
    // shifted so that both copies line up on the same pixels.
    Rectangle {
        id: empty
        x: root.fillWidth
        width: root.width - root.fillWidth
        height: parent.height
        color: Theme[root.backgroundRole]
        clip: true

        BarText {
            x: root.labelX - empty.x
            text: root.label
            color: Theme.base05
        }
    }

    // A click on the OSD follows the rules table (SPEC section 8): left and
    // right dismiss it, a middle click also dismisses the whole queue.
    MouseArea {
        anchors.fill: parent
        enabled: root.entry !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => Notifs.click(root.entry, event.button === Qt.RightButton ? "right" : event.button === Qt.MiddleButton ? "middle" : "left")
    }
}
