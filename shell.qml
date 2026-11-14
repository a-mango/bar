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
    // notification display. M3 and M4 replace the overlay content.
    property string overlayMode: "off"
    // Test helper (debug.noteHold): the note view waits at its first and
    // last frame until debug.noteRelease, for the handoff check.
    property bool noteHold: false

    // Singletons load on first use: name the ones that must run from startup.
    readonly property list<QtObject> services: [Notifs, Sway, Theme]

    Variants {
        id: bars
        model: Quickshell.screens

        Bar {
            id: bar
            // The mode name elides while this output's overlay shows a note.
            noteOpen: overlays.instances.find(o => o.modelData === bar.modelData)?.noteOpen ?? false
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
            const cell = bars.instances[0].tray.cell(index);
            if (open)
                cell.openMenu();
            else
                cell.closeMenu();
        }

        function state(): string {
            return JSON.stringify({
                overlay: root.overlayMode,
                theme: Theme.mode,
                mode: Sway.mode,
                received: Notifs.received,
                notifs: JSON.parse(Notifs.status()),
                bars: bars.instances.map(b => ({
                            screen: b.screen.name,
                            workspaces: Sway.workspacesOn(b.screen.name).map(w => w.name),
                            clock: {
                                width: b.clock.width,
                                seconds: b.clock.showSeconds,
                                calendar: b.clock.calendarShown
                            },
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
                            screen: o.screen.name,
                            clicks: o.clicks,
                            visible: o.visible,
                            note: o.noteState()
                        })),
                tray: SystemTray.items.values.map((item, index) => ({
                            id: item.id,
                            status: item.status,
                            menuOpen: bars.instances[0].tray.cell(index)?.menuOpen ?? false
                        }))
            });
        }
    }
}
