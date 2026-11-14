import QtQuick
import Quickshell
import qs.services

// The clock box (docs/SPEC.md section 3): "yyyy-MM-dd HH:mm" with waybar's
// 7 px padding. A click toggles "HH:mm:ss", hovering shows the calendar.
// The overlay draws the same box with `interactive: false` for the
// handoff (spike S7), so both must stay pixel-identical when idle.
Item {
    id: root

    property bool interactive: true
    property bool showSeconds: false
    readonly property bool hovered: interactive && mouse.containsMouse
    property bool calendarShown: false

    onHoveredChanged: {
        calendarShown = false;
        if (hovered)
            delay.restart();
        else
            delay.stop();
    }

    implicitWidth: label.implicitWidth + 14
    implicitHeight: Theme.barHeight

    SystemClock {
        id: clock
        // Ticks every second only while the seconds show.
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: root.hovered ? Theme.base07 : Theme.base00
    }

    BarText {
        id: label
        x: 7
        text: Qt.formatDateTime(clock.date, root.showSeconds ? "HH:mm:ss" : "yyyy-MM-dd HH:mm")
        color: root.hovered ? Theme.base00 : Theme.base07
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        onClicked: root.showSeconds = !root.showSeconds
    }

    Timer {
        id: delay
        interval: Motion.tooltipDelay
        onTriggered: root.calendarShown = true
    }

    PopupWindow {
        visible: root.calendarShown
        anchor.item: root
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: frame.width
        implicitHeight: frame.height
        color: "transparent"

        Rectangle {
            id: frame
            width: calendar.width
            height: calendar.height
            color: Theme.base00
            border.width: 1
            border.color: Theme.base03

            Calendar {
                id: calendar
                today: clock.date
            }
        }
    }
}
