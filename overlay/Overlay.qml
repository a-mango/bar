import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.bar

// The overlay window: overlay layer, no exclusive zone, lying on the bar.
// It is mapped only while it has something to show, and its input mask
// covers only what it draws.
//
// The OSD is OsdView (M3). Notes still use the M1 debug view, plain text
// in the middle half without animation, until NoteView (M4).
//
// `mode` keeps the M0 spike content for tests: "strip" (base0D over the
// whole bar), "part" (the middle third), "handoff" (the idle clock box).
// "off" shows the notifications.
PanelWindow {
    id: win

    required property ShellScreen modelData
    property string mode: "off"

    readonly property var note: Notifs.current
    // The OSD view stays active until its fade-out ends.
    readonly property bool showing: mode !== "off" || osdView.active || note !== null
    readonly property alias osdView: osdView

    // Spike S3/S4: clicks received by the drawn content.
    property int clicks: 0
    // For tests: how many times the window was mapped (one layer surface each).
    property int maps: 0
    onVisibleChanged: {
        if (visible)
            maps += 1;
    }

    function text(e: var): string {
        if (!e)
            return "";
        Notifs.revision; // re-read after replaces_id updates
        const d = e.n ? {
            app: e.n.appName,
            summary: e.n.summary,
            body: e.n.body
        } : e.data;
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
    // Only what takes clicks: nothing while the OSD fades out over the bar.
    mask: Region {
        item: win.mode !== "off" ? spike : osdView.entry !== null ? osdView : win.note !== null ? noteSpan : null
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bar-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---- notifications (M1 debug view) ----

    Rectangle {
        id: noteSpan
        visible: win.mode === "off" && win.note !== null
        anchors.bottom: parent.bottom
        x: Math.round(parent.width / 4)
        width: Math.round(parent.width / 2)
        height: Theme.barHeight
        color: win.note ? Theme[win.note.cls.background] : "transparent"

        BarText {
            x: 8
            width: parent.width - 16 - (queued.visible ? queued.width + 8 : 0)
            elide: Text.ElideRight
            text: win.text(win.note)
            color: win.note && win.note.cls.kind === "critical" ? Theme.base07 : Theme.base05
        }
        BarText {
            id: queued
            anchors.right: parent.right
            anchors.rightMargin: 8
            visible: Notifs.queued > 0
            text: "+" + Notifs.queued
            color: Theme.base04
        }
    }

    // Above the note span: an OSD covers the whole bar.
    OsdView {
        id: osdView
        visible: win.mode === "off" && active
        anchors.bottom: parent.bottom
        width: parent.width
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

    MouseArea {
        parent: win.mode !== "off" ? spike : noteSpan
        anchors.fill: parent
        onClicked: {
            win.clicks += 1;
            console.info("overlay clicked", win.modelData.name, win.clicks);
        }
    }
}
