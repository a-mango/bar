pragma Singleton

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io

// sway state that the I3 singleton does not expose. M0 version: the binding
// mode and a log of raw events (spike S10). M2 adds workspaces per output,
// M5 the fullscreen state per output.
Singleton {
    id: root

    property string mode: "default"

    // Spike S10: the last events seen, newest last, as {type, change, fullscreen_mode}.
    property var events: []

    function record(type: string, data: var): void {
        const entry = { type: type, change: data.change };
        if (data.container)
            entry.fullscreen_mode = data.container.fullscreen_mode;
        events = events.concat([entry]).slice(-20);
    }

    I3IpcListener {
        subscriptions: ["mode", "window"]
        onIpcEvent: event => {
            const data = JSON.parse(event.data);
            console.info("sway event", event.type, event.data.length, "bytes");
            if (event.type === "mode")
                root.mode = data.change;
            root.record(event.type, data);
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
