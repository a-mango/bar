import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.bar

// The overlay window: overlay layer, no exclusive zone, lying on the bar.
// It is mapped only while it has something to show, and its input mask
// covers only what it draws.
//
// Notes, criticals and (until M5) rich notifications show in NoteView (M4).
// The OSD is still the M1 debug view, plain text over the bar's width,
// until M3 replaces it with OsdView.
//
// `mode` keeps the M0 spike content for tests: "strip" (base0D over the
// whole bar), "part" (the middle third), "handoff" (the idle clock box).
// "off" shows the notifications.
PanelWindow {
    id: win

    required property ShellScreen modelData
    property string mode: "off"
    // The bar of the same output (set in shell.qml): NoteView places the
    // center span from its clock, left section and tray.
    property var bar: null
    // Debug: hold the note view at its first and last frame.
    property bool noteHold: false

    readonly property var osd: Notifs.osd
    // From the first frame of a note's entry to the last frame of its leave.
    readonly property bool noteOpen: noteView.active
    readonly property bool showing: mode !== "off" || osd !== null || noteView.active

    // Spike S3/S4: clicks received by the drawn content.
    property int clicks: 0

    // Test helpers (debug target in shell.qml).
    function noteState(): var {
        return noteView.debugState();
    }
    function releaseNote(): void {
        noteView.release();
    }

    function text(e: var): string {
        if (!e)
            return "";
        Notifs.revision; // re-read after replaces_id updates
        const d = e.n ? {
            app: e.n.appName,
            summary: e.n.summary,
            body: e.n.body,
            value: e.n.hints.value
        } : e.data;
        if (e.cls.kind === "osd")
            return d.summary + (d.value !== undefined && d.value !== null ? "  " + d.value + "%" : "");
        return [d.app, d.summary, d.body].filter(t => t).join("  ·  ").replace(/\n/g, " · ");
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
    mask: Region {
        item: win.mode !== "off" ? spike : win.osd ? osdStrip : noteView.hitArea
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
        hold: win.noteHold
    }

    Rectangle {
        id: osdStrip
        visible: win.mode === "off" && win.osd !== null
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.barHeight
        color: Theme.base00

        BarText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.text(win.osd)
            color: Theme.base05
        }
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

    MouseArea {
        parent: win.mode !== "off" ? spike : win.osd ? osdStrip : noteView.hitArea
        anchors.fill: parent
        onClicked: {
            win.clicks += 1;
            console.info("overlay clicked", win.modelData.name, win.clicks);
        }
    }
}
