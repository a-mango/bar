import QtQuick
import Quickshell

// Test client: a normal toplevel that swaymsg can make urgent or
// fullscreen (matrix cases B2 and B7, spikes S6 and S10).
// It logs the keys it receives, which shows where the keyboard focus is.
// CLIENT_TITLE sets the window title, so that scenes can target one client.
// Run it inside the nested session only:
//   tests/nested.sh run env CLIENT_TITLE=client-1 quickshell -p tests/client
ShellRoot {
    FloatingWindow {
        title: Quickshell.env("CLIENT_TITLE") || "bar-test-client"
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
