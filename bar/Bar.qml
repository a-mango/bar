import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The bar window: bottom layer, 24 px exclusive zone, never unmapped.
// M0 version: a static label, the clock and the tray. M2 adds the
// workspaces and the sway mode.
PanelWindow {
    id: win

    required property ShellScreen modelData

    // Spike S3/S4: clicks received by the label.
    property int clicks: 0
    readonly property alias tray: tray

    // Spike S9: "none", "ondemand" (always), "menu" (OnDemand while a tray menu
    // is open) or "hover" (OnDemand while the pointer is on the tray or a menu is open).
    property string focusMode: "none"

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
    WlrLayershell.keyboardFocus: focusMode === "ondemand" || (focusMode === "menu" && tray.menuOpen) || (focusMode === "hover" && (tray.hovered || tray.menuOpen)) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    MouseArea {
        id: label
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: labelText.implicitWidth + 10
        onClicked: {
            win.clicks += 1;
            console.info("bar label clicked", win.modelData.name, win.clicks);
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.base02
        }
        Text {
            id: labelText
            anchors.centerIn: parent
            text: "bar " + win.modelData.name
            color: Theme.base07
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    Text {
        anchors.left: label.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: Sway.mode !== "default"
        text: Sway.mode
        color: Theme.base00
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.italic: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            z: -1
            color: Theme.base04
        }
    }

    Clock {
        anchors.centerIn: parent
    }

    Tray {
        id: tray
        window: win
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
    }
}
