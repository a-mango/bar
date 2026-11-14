import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.bar

// The overlay window: overlay layer, no exclusive zone, lying on the bar.
// It is mapped only while it has something to show, and its input mask
// covers only what it draws.
// M0 version: debug content for the spikes. `mode` is one of
//   off      unmapped
//   strip    solid base0D strip over the whole bar (S2, S6)
//   part     the same strip over the middle third only (S3)
//   handoff  the idle bar center, redrawn by the overlay (S7)
PanelWindow {
    id: win

    required property ShellScreen modelData
    property string mode: "off"

    // Spike S3/S4: clicks received by the drawn content.
    property int clicks: 0

    screen: modelData
    anchors {
        left: true
        right: true
        bottom: true
    }
    implicitHeight: 96
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: mode !== "off"
    mask: Region {
        item: content
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bar-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: content

        anchors.bottom: parent.bottom
        height: Theme.barHeight
        // In handoff mode the box sits exactly where the bar draws its clock.
        x: win.mode === "part" ? Math.round(parent.width / 3) : win.mode === "handoff" ? Math.round((parent.width - width) / 2) : 0
        width: win.mode === "part" ? Math.round(parent.width / 3) : win.mode === "handoff" ? clock.implicitWidth : parent.width
        color: win.mode === "handoff" ? Theme.base00 : Theme.base0D

        Clock {
            id: clock
            interactive: false
            visible: win.mode === "handoff"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                win.clicks += 1;
                console.info("overlay clicked", win.modelData.name, win.clicks);
            }
        }
    }
}
