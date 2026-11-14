import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The bar window of one output: bottom layer, 24 px exclusive zone, never
// unmapped (docs/SPEC.md sections 2 and 3). Workspaces and mode on the
// left, the clock centered on the output, the tray on the right.
PanelWindow {
    id: win

    required property ShellScreen modelData
    readonly property alias tray: tray
    readonly property alias clock: clock

    screen: modelData
    anchors {
        left: true
        right: true
        bottom: true
    }
    implicitHeight: Theme.barHeight
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.barHeight
    color: Theme.base00

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Workspaces {
        id: workspaces
        output: win.modelData.name
    }

    // waybar: 4 px margin after the workspaces, 2 px between modules.
    Mode {
        x: workspaces.width + 6
    }

    Clock {
        id: clock
        x: Math.round((win.width - width) / 2)
    }

    // waybar: the tray box has 7 px padding on both sides.
    Tray {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: 7
    }
}
