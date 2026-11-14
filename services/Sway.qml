pragma Singleton

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io

// sway state for the bar: workspaces per output and the binding mode.
// M5 adds the fullscreen state per output (docs/SPEC.md section 11).
Singleton {
    id: root

    property string mode: "default"

    // The workspaces of one output, sorted by number, then by name.
    function workspacesOn(output: string): var {
        return I3.workspaces.values.filter(w => w.monitor && w.monitor.name === output).sort((a, b) => {
            const na = a.number < 0 ? Infinity : a.number;
            const nb = b.number < 0 ? Infinity : b.number;
            return na !== nb ? na - nb : a.name.localeCompare(b.name);
        });
    }

    I3IpcListener {
        subscriptions: ["mode"]
        onIpcEvent: event => {
            // The reply to SUBSCRIBE also arrives here, as type "subscribe".
            if (event.type === "mode")
                root.mode = JSON.parse(event.data).change;
        }
    }

    // The mode in force at startup: no event announces it.
    Process {
        running: true
        command: ["swaymsg", "-t", "get_binding_state"]
        stdout: StdioCollector {
            onStreamFinished: root.mode = JSON.parse(text).name
        }
    }
}
