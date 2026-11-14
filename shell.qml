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

    // Debug state of the overlay until the real views exist (M1 replaces
    // notify.debugShow, M3 and M4 the overlay content).
    property string overlayMode: "off"

    // Singletons load on first use: name the ones that must run from startup.
    readonly property list<QtObject> services: [Notifs, Sway, Theme]

    Variants {
        id: bars
        model: Quickshell.screens

        Bar {
        }
    }

    Variants {
        id: overlays
        model: Quickshell.screens

        Overlay {
            mode: root.overlayMode
        }
    }

    IpcHandler {
        target: "notify"

        // Temporary: shows the solid base0D strip in the overlay.
        function debugShow(on: bool): void {
            root.overlayMode = on ? "strip" : "off";
        }
    }

    // Test helpers for the matrix and the remaining overlay spikes.
    IpcHandler {
        target: "debug"

        function overlay(mode: string): void {
            root.overlayMode = mode;
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
                bars: bars.instances.map(b => ({
                            screen: b.screen.name,
                            workspaces: Sway.workspacesOn(b.screen.name).map(w => w.name),
                            clock: {
                                width: b.clock.width,
                                seconds: b.clock.showSeconds,
                                calendar: b.clock.calendarShown
                            },
                            tray: b.tray.count
                        })),
                overlays: overlays.instances.map(o => ({
                            screen: o.screen.name,
                            clicks: o.clicks,
                            visible: o.visible
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
