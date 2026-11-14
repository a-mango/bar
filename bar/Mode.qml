import QtQuick
import qs.services

// The sway binding mode, hidden in "default" (docs/SPEC.md section 3).
// The name always shows in full: M4 adds the eliding needed while a note
// takes the center span.
Rectangle {
    visible: Sway.mode !== "default"
    color: Theme.base04
    implicitWidth: Math.max(20, label.implicitWidth + 14)
    implicitHeight: Theme.barHeight

    BarText {
        id: label
        x: 7
        text: Sway.mode
        color: Theme.base07
        font.italic: true
    }
}
