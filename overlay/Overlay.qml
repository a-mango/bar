import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.bar

// The overlay window: overlay layer, no exclusive zone, lying on the bar.
// It is mapped only while it has something to show, and its input mask
// covers only what it draws.
//
// The OSD is OsdView (M3). Notes, criticals and rich notifications show in
// NoteView (M4), the rich card above the span in RichView (M5).
//
// `mode` keeps the M0 spike content for tests: "strip" (base0D over the
// whole bar), "part" (the middle third), "handoff" (the idle clock box).
// "off" shows the notifications.
PanelWindow {
    id: win

    required property ShellScreen modelData
    // The output's name. modelData turns null while the window is torn down
    // after an unplug.
    readonly property string output: modelData?.name ?? ""
    property string mode: "off"
    // The bar of the same output (set in shell.qml): NoteView places the
    // center span from its clock, left section and tray.
    property var bar: null
    // Debug: hold the note view at its first and last frame.
    property bool noteHold: false

    // Both views stay active until their leave animation ends: the OSD
    // until its fade-out, the note from the first frame of its entry to
    // the last frame of its leave.
    readonly property bool noteOpen: noteView.active
    readonly property bool showing: mode !== "off" || osdView.active || noteView.active
    readonly property alias osdView: osdView

    // Spike S3/S4: clicks received by the drawn content.
    property int clicks: 0
    // For tests: how many times the window was mapped (one layer surface each).
    property int maps: 0
    onVisibleChanged: {
        if (visible)
            maps += 1;
    }

    // Test helpers (debug target in shell.qml).
    function noteState(): var {
        return noteView.debugState();
    }
    function releaseNote(): void {
        noteView.release();
    }

    screen: modelData
    anchors {
        left: true
        right: true
        bottom: true
    }
    implicitHeight: 96
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: showing
    // Only what takes clicks: the OSD while it has an entry, else the note
    // span (empty while no note shows). A fading OSD takes no clicks. The
    // rich card adds its part above the strip (empty while it is down);
    // the rest of the upper 72 px never takes clicks.
    mask: Region {
        item: win.mode !== "off" ? spike : osdView.entry !== null ? osdView : noteView.hitArea

        Region {
            item: noteView.cardHitArea
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bar-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---- notifications ----

    NoteView {
        id: noteView
        visible: win.mode === "off"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        bar: win.bar
        output: win.output
        hold: win.noteHold
        dpr: win.devicePixelRatio
        onClicked: {
            win.clicks += 1;
            console.info("overlay clicked", win.output, win.clicks);
        }
    }

    // Above the note span: an OSD covers the whole bar.
    OsdView {
        id: osdView
        visible: win.mode === "off" && active
        anchors.bottom: parent.bottom
        width: parent.width
        output: win.output
        dpr: win.devicePixelRatio
    }

    // ---- M0 spike content ----

    Rectangle {
        id: spike

        visible: win.mode !== "off"
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
    }

    // Spike S3/S4 only: the note view takes its own clicks.
    MouseArea {
        anchors.fill: spike
        enabled: win.mode !== "off"
        onClicked: {
            win.clicks += 1;
            console.info("overlay clicked", win.output, win.clicks);
        }
    }
}
