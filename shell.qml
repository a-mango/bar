//@ pragma UseQApplication
//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING = gray
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

    // M0 spike state. Everything marked "spike" goes away once the real
    // views exist (M1 replaces notify.debugShow, M2 the bar content).
    property string overlayMode: "off"
    property int volatileCounter: 0

    // Singletons load on first use: name the ones that must run from startup.
    readonly property list<QtObject> services: [Notifs, Sway]

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

    // Spike S8: plain objects survive a reload in a `list<var>` property.
    // A `property var` holding a JS array or object comes back undefined.
    PersistentProperties {
        id: persist
        reloadableId: "spike"

        property list<var> items: []
    }

    IpcHandler {
        target: "notify"

        // Temporary: shows the solid base0D strip in the overlay.
        function debugShow(on: bool): void {
            root.overlayMode = on ? "strip" : "off";
        }
    }

    // Spike helpers.
    IpcHandler {
        target: "debug"

        function overlay(mode: string): void {
            root.overlayMode = mode;
        }

        // Adds one plain object to the persisted array and bumps a counter
        // that a reload resets.
        function push(text: string): void {
            root.volatileCounter += 1;
            persist.items = persist.items.concat([{
                    text: text,
                    n: persist.items.length + 1
                }]);
        }

        function watchFiles(on: bool): void {
            Quickshell.watchFiles = on;
        }

        function trayMenu(index: int, open: bool): void {
            const cell = bars.instances[0].tray.cell(index);
            if (open)
                cell.openMenu();
            else
                cell.closeMenu();
        }

        function barFocus(mode: string): void {
            for (const bar of bars.instances)
                bar.focusMode = mode;
        }

        function trayActivate(index: int): void {
            SystemTray.items.values[index].activate();
        }

        function state(): string {
            return JSON.stringify({
                overlay: root.overlayMode,
                volatileCounter: root.volatileCounter,
                persisted: persist.items,
                watchFiles: Quickshell.watchFiles,
                received: Notifs.received,
                mode: Sway.mode,
                events: Sway.events,
                bars: bars.instances.map(b => ({
                            screen: b.screen.name,
                            clicks: b.clicks,
                            focusMode: b.focusMode
                        })),
                overlays: overlays.instances.map(o => ({
                            screen: o.screen.name,
                            clicks: o.clicks,
                            visible: o.visible
                        })),
                tray: SystemTray.items.values.map((item, index) => ({
                            id: item.id,
                            title: item.title,
                            status: item.status,
                            hasMenu: item.hasMenu,
                            onlyMenu: item.onlyMenu,
                            menuOpen: bars.instances[0].tray.cell(index)?.menuOpen ?? false
                        }))
            });
        }
    }
}
