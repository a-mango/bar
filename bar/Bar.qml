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
    // The output's name. modelData turns null while the window is torn down
    // after an unplug.
    readonly property string output: modelData?.name ?? ""
    readonly property alias tray: tray
    readonly property alias clock: clock
    readonly property alias mode: mode

    // True while the overlay of this output shows a note (set in shell.qml).
    // The mode name then elides if the note would get less than noteMinimum.
    property bool noteOpen: false
    readonly property int noteMinimum: 600
    // The bounds of the note's center span (docs/SPEC.md section 4): the
    // end of the left section and the start of the tray, 8 px gap each.
    readonly property real leftEnd: mode.visible ? mode.x + mode.width : workspaces.width
    readonly property real trayStart: tray.x

    // For tests (`debug state`): the serial number given at creation (in
    // shell.qml), how often a backing window was connected, and how often
    // it stopped being visible. The bar is never unmapped, so the last two
    // stay at 1 and 0 for the life of the bar.
    property int serial: 0
    property int connects: 0
    property int hides: 0
    onWindowConnected: connects += 1
    onBackingWindowVisibleChanged: {
        if (!backingWindowVisible)
            hides += 1;
    }

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
        output: win.output
    }

    // waybar: 4 px margin after the workspaces, 2 px between modules.
    Mode {
        id: mode
        x: workspaces.width + 6
        // Depends on the tray and its own x only, never on its width.
        maxWidth: win.noteOpen ? tray.x - 8 - win.noteMinimum - 8 - x : -1
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
