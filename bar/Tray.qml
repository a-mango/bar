pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// System tray. M0 version for spike S9: icons, activate on left click and
// the menu on right click. M2 adds status styling, tooltips, middle click
// and scroll.
Row {
    id: root

    // The bar window: the menus open as its popups.
    required property var window

    readonly property int count: items.count
    property int openMenus: 0
    readonly property bool menuOpen: openMenus > 0
    readonly property bool hovered: hover.hovered

    spacing: 14

    function cell(index: int): var {
        return items.itemAt(index);
    }

    HoverHandler {
        id: hover
    }

    Repeater {
        id: items
        model: SystemTray.items

        delegate: MouseArea {
            id: cell

            required property SystemTrayItem modelData
            readonly property bool menuOpen: menu.visible

            function openMenu(): void {
                menu.open();
            }
            function closeMenu(): void {
                menu.close();
            }

            width: 16
            height: 16
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => {
                if (event.button === Qt.RightButton || modelData.onlyMenu)
                    menu.open();
                else
                    modelData.activate();
            }

            IconImage {
                anchors.fill: parent
                source: cell.modelData.icon
            }

            QsMenuAnchor {
                id: menu
                menu: cell.modelData.menu
                anchor.item: cell
                anchor.edges: Edges.Top
                anchor.gravity: Edges.Top
                onOpened: {
                    root.openMenus += 1;
                    console.info("tray menu opened", cell.modelData.id);
                }
                onClosed: {
                    root.openMenus -= 1;
                    console.info("tray menu closed", cell.modelData.id);
                }
            }
        }
    }
}
