pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The workspaces of one output (docs/SPEC.md section 3). A left click
// activates one, the wheel does nothing (waybar's disable-scroll).
Row {
    id: root

    required property string output

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
