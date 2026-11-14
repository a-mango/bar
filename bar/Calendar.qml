pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Month calendar for the clock popup: "yyyy MMMM", the weekday names, then
// the weeks, with today in bold and underlined (waybar's default format).
// The first day of the week follows the locale.
Column {
    id: root

    required property date today

    readonly property var locale: Qt.locale()
    readonly property int firstDay: locale.firstDayOfWeek
    readonly property date first: new Date(today.getFullYear(), today.getMonth(), 1)
    readonly property int offset: (first.getDay() - firstDay + 7) % 7
    readonly property int days: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()

    padding: 8
    spacing: 4

    BarText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(root.today, "yyyy MMMM")
        color: Theme.base07
        font.bold: true
    }

    Grid {
        columns: 7
        columnSpacing: 8

        Repeater {
            model: 7
            delegate: BarText {
                required property int index
                width: 16
                horizontalAlignment: Text.AlignRight
                text: root.locale.dayName((root.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
                color: Theme.base04
            }
        }

        Repeater {
            model: Math.ceil((root.offset + root.days) / 7) * 7
            delegate: BarText {
                required property int index
                readonly property int day: index - root.offset + 1
                readonly property bool isToday: day === root.today.getDate()
                width: 16
                horizontalAlignment: Text.AlignRight
                text: day >= 1 && day <= root.days ? day : ""
                color: isToday ? Theme.base07 : Theme.base05
                font.bold: isToday
                font.underline: isToday
            }
        }
    }
}
