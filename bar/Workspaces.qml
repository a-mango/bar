pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The workspaces of one output (docs/SPEC.md section 3). A left click
// activates one, the wheel steps to the previous or next one on this
// output, wrapping around (after the M8 cutover, the owner; waybar's
// scroll without disable-scroll).
Row {
    id: root

    required property string output

    // Wheel travel not yet turned into a step, in angleDelta units: a
    // wheel notch is 120. Touchpad and TrackPoint scrolling come with pixel
    // deltas, and 60 px count as one notch: their angleDelta is 12 per px,
    // which would step through several workspaces in one short swipe. What
    // is left over after a pause is dropped.
    property real wheelRest: 0
    property real wheelAt: 0

    function wheel(event: var): void {
        const px = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.pixelDelta.x;
        const angle = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
        const delta = px !== 0 ? px * 2 : angle;
        if (delta === 0)
            return;
        const now = Date.now();
        // A pause or a change of direction starts over.
        if (now - wheelAt > 400 || Math.sign(delta) !== Math.sign(wheelRest))
            wheelRest = 0;
        wheelAt = now;
        wheelRest += delta;
        let steps = 0;
        while (Math.abs(wheelRest) >= 120) {
            // Up (or left) is the previous workspace.
            steps += wheelRest > 0 ? -1 : 1;
            wheelRest -= Math.sign(wheelRest) * 120;
        }
        if (steps !== 0)
            step(steps);
    }

    // The workspace the last step asked for. sway reports the switch a few
    // ms later: a step that follows within 300 ms goes on from there, so
    // fast scrolling does not lose steps.
    property var stepTarget: null
    property real stepAt: 0

    function step(steps: int): void {
        const list = Sway.workspacesOn(output);
        if (list.length < 2)
            return;
        const now = Date.now();
        let from = now - stepAt < 300 ? list.indexOf(stepTarget) : -1;
        // Else from the workspace shown on this output.
        if (from < 0)
            from = Math.max(0, list.findIndex(w => w.monitor?.activeWorkspace === w));
        const to = ((from + steps) % list.length + list.length) % list.length;
        stepTarget = list[to];
        stepAt = now;
        stepTarget.activate();
    }

    Repeater {
        model: ScriptModel {
            values: Sway.workspacesOn(root.output)
        }

        delegate: MouseArea {
            id: button

            required property var modelData
            readonly property bool focusedHere: modelData.focused
            readonly property bool shownHere: modelData.monitor?.activeWorkspace === modelData

            // waybar: 5 px padding on both sides of a content box of at least 16 px.
            width: Math.max(16, label.implicitWidth) + 10
            height: Theme.barHeight
            hoverEnabled: true
            onClicked: modelData.activate()
            onWheel: event => root.wheel(event)

            Rectangle {
                anchors.fill: parent
                // Same precedence as style.css: urgent, focused, visible, hover.
                color: button.modelData.urgent ? Theme.base08 : button.focusedHere ? Theme.base07 : button.shownHere ? Theme.base02 : button.containsMouse ? Theme.base03 : Theme.base00
            }

            BarText {
                id: label
                x: 5 + (Math.max(16, implicitWidth) - implicitWidth) / 2
                text: button.modelData.name
                // On the urgent base08, Theme.onCritical (M7): waybar's base05
                // gave 4.0:1 in dark mode and 2.1:1 in light mode.
                color: button.modelData.urgent ? Theme.onCritical : button.focusedHere ? Theme.base00 : button.shownHere ? Theme.base07 : Theme.base05
                // waybar's workspaces are GTK buttons, which the GTK theme draws bold.
                font.bold: true
            }
        }
    }
}
