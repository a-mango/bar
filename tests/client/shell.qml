import QtQuick
import Quickshell

// Test client: a normal toplevel that swaymsg can make urgent or
// fullscreen (matrix cases B2 and B7, spikes S6 and S10).
// It logs the keys it receives, which shows where the keyboard focus is.
// Run it inside the nested session only:
//   tests/nested.sh run quickshell -p tests/client
ShellRoot {
    FloatingWindow {
        title: "bar-test-client"
        color: "darkmagenta"
        implicitWidth: 640
        implicitHeight: 400

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => console.info("client key", event.text)
        }

        Text {
            anchors.centerIn: parent
            text: "test client"
            color: "white"
            font.pixelSize: 24
        }
    }
}
