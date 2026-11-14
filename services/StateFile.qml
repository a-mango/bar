pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// state.json under Quickshell.stateDir: small values that survive a restart
// (the last theme mode, the DND flag). Each service reads and writes its
// own key only. bar is the only writer, so the file is read once at startup
// and the in-memory copy is the reference afterwards.
Singleton {
    id: root

    readonly property string path: Quickshell.statePath("state.json")
    property var data: load()

    function load(): var {
        try {
            return JSON.parse(file.text() || "{}");
        } catch (e) {
            console.warn("state: ignoring unreadable", root.path, e);
            return {};
        }
    }

    function get(key: string, fallback: var): var {
        return key in data ? data[key] : fallback;
    }

    function set(key: string, value: var): void {
        const next = Object.assign({}, data);
        next[key] = value;
        data = next;
        file.setText(JSON.stringify(data, null, 2) + "\n");
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
}
