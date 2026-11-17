//@ pragma UseQApplication
//@ pragma NativeTextRendering
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.services
import qs.bar
import qs.overlay

ShellRoot {
    id: root

    // Spike modes of the overlay (debug.overlay), "off" for the normal
    // notification display (OsdView and NoteView).
    property string overlayMode: "off"
    // Test helper (debug.noteHold): the note view waits at its first and
    // last frame until debug.noteRelease, for the handoff check.
    property bool noteHold: false

    // Singletons load on first use: name the ones that must run from startup.
    readonly property list<QtObject> services: [Notifs, Sway, Theme]

    // For tests: every bar window gets a serial number when it is created,
    // so that `debug state` shows whether a bar was replaced.
    property int barsCreated: 0

    // The live copy (`make install`, docs/PLAN.md section 6) holds a `live`
    // file with the tag it was installed from. It never reloads on a file
    // change: a reload would drop the bar's exclusive zone and re-tile every
    // window. The tree itself has no such file and keeps hot reloading.
    property string live: ""

    FileView {
        id: liveMarker
        path: Quickshell.shellPath("live")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        root.live = liveMarker.text().trim();
        if (root.live !== "") {
            Quickshell.watchFiles = false;
            console.info("bar: live copy", root.live + ", file watching off");
        }
    }

    // One bar and one overlay per screen (docs/SPEC.md section 11). Variants
    // keeps the instances of the screens that stay when one comes or goes.
    Variants {
        id: bars
        model: Quickshell.screens

        Bar {
            id: bar
            // The mode name elides while this output's overlay shows a note.
            noteOpen: overlays.instances.find(o => o.modelData === bar.modelData)?.noteOpen ?? false
            Component.onCompleted: {
                root.barsCreated += 1;
                serial = root.barsCreated;
            }
        }
    }

    Variants {
        id: overlays
        model: Quickshell.screens

        Overlay {
            id: overlay
            mode: root.overlayMode
            bar: bars.instances.find(b => b.modelData === overlay.modelData) ?? null
            noteHold: root.noteHold
        }
    }

    // Test helpers for the matrix and the remaining overlay spikes.
    IpcHandler {
        target: "debug"

        function overlay(mode: string): void {
            root.overlayMode = mode;
        }

        // Slow motion for frame series: note durations times `factor`.
        function slow(factor: real): void {
            Motion.slow = factor > 0 ? factor : 1;
        }

        function noteHold(on: bool): void {
            root.noteHold = on;
        }

        function noteRelease(): void {
            for (const o of overlays.instances)
                o.releaseNote();
        }

        function trayMenu(index: int, open: bool): void {
            const cell = (bars.instances.find(b => b.output === Sway.focusedOutput) ?? bars.instances[0]).tray.cell(index);
            if (open)
                cell.openMenu();
            else
                cell.closeMenu();
        }

        function state(): string {
            return JSON.stringify({
                live: root.live,
                watchFiles: Quickshell.watchFiles,
                overlay: root.overlayMode,
                theme: Theme.mode,
                mode: Sway.mode,
                focusedOutput: Sway.focusedOutput,
                screens: Quickshell.screens.map(s => s.name),
                sway: {
                    focused: Sway.focusedOutput,
                    fullscreen: Sway.fullscreenOutputs,
                    focusedFullscreen: Sway.focusedFullscreen,
                    treeReads: Sway.treeReads
                },
                received: Notifs.received,
                notifs: JSON.parse(Notifs.status()),
                bars: bars.instances.map(b => ({
                            screen: b.output,
                            serial: b.serial,
                            connects: b.connects,
                            hides: b.hides,
                            height: b.height,
                            workspaces: Sway.workspacesOn(b.output).map(w => w.name),
                            clock: {
                                width: b.clock.width,
                                seconds: b.clock.showSeconds,
                                calendar: b.clock.calendarShown
                            },
                            leftEnd: b.leftEnd,
                            trayStart: b.trayStart,
                            mode: {
                                x: b.mode.x,
                                width: b.mode.width,
                                full: b.mode.fullWidth,
                                elided: b.mode.elided,
                                visible: b.mode.visible
                            },
                            tray: b.tray.count
                        })),
                overlays: overlays.instances.map(o => ({
                            screen: o.output,
                            clicks: o.clicks,
                            visible: o.visible,
                            maps: o.maps,
                            osd: {
                                active: o.osdView.active,
                                entries: o.osdView.entries,
                                updates: o.osdView.updates,
                                level: o.osdView.level,
                                opacity: o.osdView.opacity,
                                label: o.osdView.label
                            },
                            note: o.noteState()
                        })),
                tray: SystemTray.items.values.map((item, index) => ({
                            id: item.id,
                            status: item.status,
                            // On any bar: the menu opens on the bar that was clicked.
                            menuOpen: bars.instances.some(b => b.tray.cell(index)?.menuOpen ?? false)
                        }))
            });
        }
    }
}
