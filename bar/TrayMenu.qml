pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// A tray item's menu drawn in QML (M7, the look half of Q2 in
// docs/PLAN.md section 8): the entries of QsMenuOpener in Theme colors, so
// that menus follow the palette and darkman like the rest of the bar.
//
// The popup grabs the pointer (grabFocus): a click on another client's
// surface closes the whole chain of menus. Clicks on bar's own surfaces do
// not, so Tray and Bar close menus themselves. The grab leaves the
// keyboard with the focused window, as QMenu did (spike in M7): the
// keyboard half of Q2 stays open, and the menu reacts to the pointer only.
//
// The anchor is set by the user: a tray cell for the top level, the entry
// row for a submenu, which opens left and up, away from the output's right
// and bottom edges (sway does not slide layer-surface popups back).
PopupWindow {
    id: root

    // The menu: a tray item's menu, or an entry with children.
    property QsMenuHandle handle: null
    // An entry ran: every menu of the chain closes.
    signal triggered

    // The open submenu, and the row it opens from.
    property QsMenuEntry subEntry: null
    property Item subFrom: null

    readonly property var entries: opener.children ? opener.children.values : []
    readonly property bool hasMarks: entries.some(e => e.buttonType !== QsMenuButtonType.None)
    readonly property bool hasIcons: entries.some(e => e.icon !== "")
    readonly property bool hasSubs: entries.some(e => e.hasChildren)
    readonly property real widest: {
        let w = 120;
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row)
                w = Math.max(w, row.implicitWidth);
        }
        return w;
    }

    function openSub(entry: QsMenuEntry, from: Item): void {
        if (subEntry === entry)
            return;
        subEntry = null;
        subFrom = from;
        subEntry = entry;
    }

    visible: false
    grabFocus: true
    color: "transparent"
    implicitWidth: frame.width
    implicitHeight: frame.height
    onVisibleChanged: {
        if (!visible)
            subEntry = null;
    }

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    Rectangle {
        id: frame
        width: list.width + 2
        height: list.height + 2
        color: Theme.base00
        border.width: 1
        border.color: Theme.base03

        Column {
            id: list
            x: 1
            y: 1
            topPadding: 3
            bottomPadding: 3

            Repeater {
                id: rows
                model: opener.children

                delegate: Item {
                    id: row

                    required property QsMenuEntry modelData
                    readonly property bool separator: modelData.isSeparator
                    readonly property bool usable: !separator && modelData.enabled
                    readonly property bool lit: usable && (mouse.containsMouse || root.subEntry === modelData)
                    readonly property int marks: root.hasMarks ? 24 : 0
                    readonly property int icons: root.hasIcons ? 24 : 0

                    implicitWidth: separator ? 0 : 8 + marks + icons + label.implicitWidth + (root.hasSubs ? 24 : 0) + 8
                    width: root.widest
                    height: separator ? 9 : Theme.barHeight

                    Rectangle {
                        visible: row.separator
                        x: 8
                        y: 4
                        width: row.width - 16
                        height: 1
                        color: Theme.base03
                    }

                    // Hover, and the row whose submenu is open.
                    Rectangle {
                        anchors.fill: parent
                        visible: row.lit
                        color: Theme.base02
                    }

                    BarText {
                        visible: !row.separator && row.modelData.buttonType !== QsMenuButtonType.None
                        x: 8
                        text: {
                            const e = row.modelData;
                            if (e.buttonType === QsMenuButtonType.RadioButton)
                                return e.checkState === Qt.Checked ? "●" : "○";
                            return e.checkState === Qt.Checked ? "✓" : e.checkState === Qt.PartiallyChecked ? "–" : "";
                        }
                        color: label.color
                    }

                    IconImage {
                        visible: !row.separator && row.modelData.icon !== ""
                        x: 8 + row.marks
                        y: (Theme.barHeight - 16) / 2
                        implicitSize: 16
                        source: row.separator ? "" : row.modelData.icon
                        opacity: row.usable ? 1 : 0.5
                    }

                    BarText {
                        id: label
                        visible: !row.separator
                        x: 8 + row.marks + row.icons
                        text: row.separator ? "" : row.modelData.text
                        // Disabled: base04, readable in both modes (9.0:1 dark,
                        // 6.7:1 light; base03 gave 2.6 and 1.9:1).
                        color: !row.usable ? Theme.base04 : row.lit ? Theme.base07 : Theme.base05
                    }

                    // The submenu opens to the left: the chevron points there.
                    BarText {
                        visible: !row.separator && row.modelData.hasChildren
                        x: row.width - 8 - implicitWidth
                        text: "‹"
                        color: label.color
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.usable
                        onClicked: {
                            if (row.modelData.hasChildren) {
                                root.openSub(row.modelData, row);
                                return;
                            }
                            root.subEntry = null;
                            row.modelData.triggered();
                            root.triggered();
                        }
                    }
                }
            }
        }
    }

    // Submenus: this file again, through a Loader (a component cannot
    // instantiate itself directly).
    Loader {
        id: sub
        active: root.subEntry !== null && root.visible
        source: "TrayMenu.qml"
        onLoaded: {
            item.handle = root.subEntry;
            item.anchor.item = root.subFrom;
            item.anchor.edges = Edges.Left | Edges.Bottom;
            item.anchor.gravity = Edges.Left | Edges.Top;
            item.visible = true;
        }
    }

    Connections {
        target: sub.item
        ignoreUnknownSignals: true
        function onTriggered(): void {
            root.triggered();
        }
        function onVisibleChanged(): void {
            if (sub.item && !sub.item.visible)
                root.subEntry = null;
        }
    }

    onTriggered: visible = false
}
