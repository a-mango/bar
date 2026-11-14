import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.bar

// The overlay window: overlay layer, no exclusive zone, lying on the bar.
// It is mapped only while it has something to show, and its input mask
// covers only what it draws.
//
// M1 version: a debug view of the notification core, plain text without
// animation. An OSD fills the bar's width, a note the middle half. M3 and
// M4 replace it with OsdView and NoteView.
//
// `mode` keeps the M0 spike content for tests: "strip" (base0D over the
// whole bar), "part" (the middle third), "handoff" (the idle clock box).
// "off" shows the notifications.
PanelWindow {
    id: win

    required property ShellScreen modelData
    property string mode: "off"

    readonly property var osd: Notifs.osd
    readonly property var note: Notifs.current
    readonly property bool showing: mode !== "off" || osd !== null || note !== null

    // Spike S3/S4: clicks received by the drawn content.
    property int clicks: 0

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
        item: win.mode !== "off" ? spike : win.osd ? osdStrip : noteSpan
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
        parent: win.mode !== "off" ? spike : win.osd ? osdStrip : noteSpan
        anchors.fill: parent
        onClicked: {
            win.clicks += 1;
            console.info("overlay clicked", win.modelData.name, win.clicks);
        }
    }
}
