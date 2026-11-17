pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services

// System tray (docs/SPEC.md section 3). Icons 16 px, 14 px apart.
// Left click: activate, or the menu for menu-only items. Middle click:
// secondary activate. Right click: the menu. Wheel: scroll.
// Menus are drawn in QML (TrayMenu, M7: the look half of Q2) with the
// bar's keyboard focus at None (spike S9). The keyboard half of Q2 in
// docs/PLAN.md section 8 is open, so menus react to the pointer only.
Row {
    id: root

    readonly property int count: items.count
    readonly property bool menuOpen: {
        for (let i = 0; i < items.count; i++)
            if (items.itemAt(i)?.menuOpen)
                return true;
        return false;
    }

    spacing: 14

    function cell(index: int): var {
        return items.itemAt(index);
    }

    // The menu grab ignores clicks on bar's own surfaces (M7 spike), so
    // the bar closes menus on a press outside the tray, and a cell closes
    // the others before it opens its own.
    function closeMenus(): void {
        for (let i = 0; i < items.count; i++)
            items.itemAt(i)?.closeMenu();
    }

    Repeater {
        id: items
        model: SystemTray.items

        delegate: MouseArea {
            id: cell

            required property SystemTrayItem modelData
            readonly property bool attention: modelData.status === Status.NeedsAttention
            readonly property bool menuOpen: menu.visible
            property bool tooltipShown: false

            function openMenu(): void {
                root.closeMenus();
                menu.visible = true;
            }
            function closeMenu(): void {
                menu.visible = false;
            }

            width: 16
            height: Theme.barHeight
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            hoverEnabled: true

            onClicked: event => {
                tooltipShown = false;
                if (event.button === Qt.MiddleButton)
                    modelData.secondaryActivate();
                else if (event.button === Qt.RightButton || modelData.onlyMenu)
                    menuOpen ? closeMenu() : openMenu();
                else
                    modelData.activate();
            }
            // As waybar: one step per notch, -1 for up or left.
            onWheel: event => {
                if (event.angleDelta.y !== 0)
                    modelData.scroll(event.angleDelta.y > 0 ? -1 : 1, false);
                if (event.angleDelta.x !== 0)
                    modelData.scroll(event.angleDelta.x > 0 ? -1 : 1, true);
            }
            onContainsMouseChanged: {
                tooltipShown = false;
                if (containsMouse)
                    tooltipDelay.restart();
                else
                    tooltipDelay.stop();
            }

            // NeedsAttention: the cell fades between base08 and base00 like
            // waybar's `blink` keyframes. The animation runs only meanwhile.
            Rectangle {
                id: blink
                y: 1
                width: parent.width
                height: parent.height - 1.5
                visible: cell.attention
                color: Theme.base08

                SequentialAnimation on color {
                    running: cell.attention
                    loops: Animation.Infinite
                    ColorAnimation {
                        to: Theme.base00
                        duration: Motion.blink
                    }
                    ColorAnimation {
                        to: Theme.base08
                        duration: Motion.blink
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: cell.modelData.icon
                opacity: cell.modelData.status === Status.Passive ? 0.5 : 1
            }

            // Grows up and to the left from the icon's top right corner,
            // like the tooltip, so it stays on the output.
            TrayMenu {
                id: menu
                handle: cell.modelData.menu
                anchor.item: cell
                anchor.edges: Edges.Top | Edges.Right
                anchor.gravity: Edges.Top | Edges.Left
            }

            Timer {
                id: tooltipDelay
                interval: Motion.tooltipDelay
                onTriggered: cell.tooltipShown = true
            }

            PopupWindow {
                visible: cell.tooltipShown && !cell.menuOpen && (cell.modelData.tooltipTitle !== "" || cell.modelData.tooltipDescription !== "")
                // Grows up and to the left from the icon's top right corner, so
                // it stays on the output (sway does not slide these popups).
                anchor.item: cell
                anchor.edges: Edges.Top | Edges.Right
                anchor.gravity: Edges.Top | Edges.Left
                implicitWidth: tip.width
                implicitHeight: tip.height
                color: "transparent"

                Rectangle {
                    id: tip
                    width: lines.width
                    height: lines.height
                    color: Theme.base00
                    border.width: 1
                    border.color: Theme.base03

                    Column {
                        id: lines
                        padding: 8

                        BarText {
                            visible: text !== ""
                            text: cell.modelData.tooltipTitle
                            color: Theme.base07
                        }
                        BarText {
                            visible: text !== ""
                            text: cell.modelData.tooltipDescription
                            textFormat: Text.StyledText
                            color: Theme.base05
                        }
                    }
                }
            }
        }
    }
}
