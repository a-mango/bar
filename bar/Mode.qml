import QtQuick
import qs.services

// The sway binding mode, hidden in "default" (docs/SPEC.md section 3).
// The name shows in full, except while a note would otherwise get less
// than 600 px of the center span: the bar then sets `maxWidth` and the
// name elides on the right.
Rectangle {
    id: root

    // Width limit in px, negative for none.
    property real maxWidth: -1
    readonly property real fullWidth: Math.max(20, label.implicitWidth + 14)
    readonly property bool elided: label.truncated

    visible: Sway.mode !== "default"
    color: Theme.base04
    implicitWidth: maxWidth < 0 ? fullWidth : Math.max(20, Math.min(fullWidth, Math.floor(maxWidth)))
    implicitHeight: Theme.barHeight

    BarText {
        id: label
        x: 7
        width: root.width - 14
        text: Sway.mode
        color: Theme.base07
        font.italic: true
        elide: Text.ElideRight
    }
}
