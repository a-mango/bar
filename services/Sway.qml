pragma Singleton

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io

// sway state for the bar: workspaces per output, the focused output, the
// binding mode and the fullscreen state per output (docs/SPEC.md section 11).
Singleton {
    id: root

    property string mode: "default"
    // The output that has the focus, "" until sway has told. Notifications
    // show there (Notifs.targetOutput()).
    readonly property string focusedOutput: I3.focusedMonitor?.name ?? ""

    // The workspaces of one output, sorted by number, then by name.
    function workspacesOn(output: string): var {
        return I3.workspaces.values.filter(w => w.monitor && w.monitor.name === output).sort((a, b) => {
            const na = a.number < 0 ? Infinity : a.number;
            const nb = b.number < 0 ? Infinity : b.number;
            return na !== nb ? na - nb : a.name.localeCompare(b.name);
        });
    }

    I3IpcListener {
        subscriptions: ["mode", "window", "workspace", "output"]
        onIpcEvent: event => {
            // The reply to SUBSCRIBE also arrives here, as type "subscribe".
            if (event.type === "mode")
                root.mode = JSON.parse(event.data).change;
            else if (root.changesTree(event.type, event.data))
                root.readTree();
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

    // ---- fullscreen (M5, decision D5) ----

    // The outputs that show a fullscreen window: a container in fullscreen
    // mode 1 on the output's visible workspace, or any container in global
    // fullscreen (mode 2), which covers every output.
    property list<string> fullscreenOutputs: []
    readonly property bool focusedFullscreen: fullscreenOutputs.includes(focusedOutput)
    // For tests: how many times the tree was read.
    property int treeReads: 0

    function isFullscreen(output: string): bool {
        return fullscreenOutputs.includes(output);
    }

    // Events that can change what is fullscreen. A fullscreen window that
    // closes or moves to another workspace sends no fullscreen_mode event.
    // Title, mark and focus changes of a window cannot change it, and
    // neither can an urgent workspace.
    function changesTree(type: string, data: string): bool {
        if (type === "output")
            return true;
        if (type === "window")
            return ["fullscreen_mode", "close", "move", "floating", "new"].includes(JSON.parse(data).change);
        if (type === "workspace")
            return JSON.parse(data).change !== "urgent";
        return false;
    }

    // Events only say that something changed: read the whole tree again.
    // One swaymsg at a time, and one more run if an event came meanwhile.
    property bool treeDirty: false
    function readTree(): void {
        if (tree.running)
            treeDirty = true;
        else
            tree.running = true;
    }

    // From `swaymsg -t get_tree`. Workspace nodes always report
    // fullscreen_mode 1, so only containers count. The scratchpad output
    // (__i3) never shows.
    function fullscreenIn(node: var): var {
        const found = [];
        let global = false;
        for (const output of node.nodes ?? []) {
            if (output.type !== "output" || output.name === "__i3")
                continue;
            for (const ws of output.nodes ?? []) {
                const modes = containerModes(ws);
                if (modes.includes(2))
                    global = true;
                if (ws.name === output.current_workspace && modes.includes(1))
                    found.push(output.name);
            }
        }
        if (global)
            return (node.nodes ?? []).filter(o => o.type === "output" && o.name !== "__i3").map(o => o.name);
        return found;
    }

    // The fullscreen modes of every container below a workspace.
    function containerModes(node: var): var {
        let modes = [];
        for (const child of (node.nodes ?? []).concat(node.floating_nodes ?? [])) {
            if ((child.type === "con" || child.type === "floating_con") && child.fullscreen_mode > 0)
                modes.push(child.fullscreen_mode);
            modes = modes.concat(containerModes(child));
        }
        return modes;
    }

    Process {
        id: tree
        running: true
        command: ["swaymsg", "-t", "get_tree"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = root.fullscreenIn(JSON.parse(text));
                    if (next.join("\n") !== root.fullscreenOutputs.join("\n")) {
                        root.fullscreenOutputs = next;
                        console.info("sway: fullscreen outputs", JSON.stringify(next));
                    }
                } catch (error) {
                    console.warn("sway: could not read the tree", error);
                }
                root.treeReads += 1;
            }
        }
        // The stream can finish before the process is reaped: run again
        // from here, where `running` is already false.
        onExited: {
            if (root.treeDirty) {
                root.treeDirty = false;
                Qt.callLater(root.readTree);
            }
        }
    }
}
