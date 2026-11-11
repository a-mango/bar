import QtQuick
import Quickshell
import qs.services

// The clock label. The bar and the overlay both draw it, so that the
// overlay's first frame can reproduce the idle bar center (spike S7).
// M2 adds the seconds toggle, the hover colors and the calendar popup.
Text {
    text: Qt.formatDateTime(clock.date, "yyyy-MM-dd HH:mm")
    color: Theme.base07
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
