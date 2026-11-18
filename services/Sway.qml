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

    // ---- workspaces ----

    // From `swaymsg -t get_workspaces`, read again on every workspace and
    // output event: plain objects {name, num, focused, visible, urgent,
    // output}. Not Quickshell's I3.workspaces: its workspace objects keep a
    // pointer to the I3Monitor of an output that went away, and the next
    // workspace event reads it. Disabling and enabling the only output (a
    // lid close, a suspend) crashed or hung the live bar six times on
    // 2026-11-18 (PLAN.md section 8, M8 findings). The I3IpcListener alone
    // is safe.
    property var workspaces: []
    // The output that has the focus, "" until sway has told. Notifications
    // show there (Notifs.targetOutput()).
    readonly property string focusedOutput: workspaces.find(w => w.focused)?.output ?? ""

    // The workspaces of one output, sorted by number, then by name.
    function workspacesOn(output: string): var {
        return workspaces.filter(w => w.output === output).sort((a, b) => {
            const na = a.num < 0 ? Infinity : a.num;
            const nb = b.num < 0 ? Infinity : b.num;
            return na !== nb ? na - nb : a.name.localeCompare(b.name);
        });
    }

    // `swaymsg` joins its arguments into one command: quote the name.
    function activate(name: string): void {
        Quickshell.execDetached(["swaymsg", "workspace \"" + name.replace(/["\\]/g, "\\$&") + "\""]);
    }

    // One swaymsg at a time, and one more run if an event came meanwhile.
    property bool workspacesDirty: false
    function readWorkspaces(): void {
        if (workspaceList.running)
            workspacesDirty = true;
        else
            workspaceList.running = true;
    }

    Process {
        id: workspaceList
        running: true
        command: ["swaymsg", "-t", "get_workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(text).map(w => ({
                                name: w.name,
                                num: w.num,
                                focused: w.focused,
                                visible: w.visible,
                                urgent: w.urgent,
                                output: w.output
                            }));
                    // New objects rebuild the buttons: only when something changed.
                    if (JSON.stringify(next) !== JSON.stringify(root.workspaces))
                        root.workspaces = next;
                } catch (error) {
                    console.warn("sway: could not read the workspaces", error);
                }
            }
        }
        onRunningChanged: {
            if (!running && root.workspacesDirty) {
                root.workspacesDirty = false;
                Qt.callLater(root.readWorkspaces);
            }
        }
    }

    I3IpcListener {
        subscriptions: ["mode", "window", "workspace", "output"]
        onIpcEvent: event => {
            // The reply to SUBSCRIBE also arrives here, as type "subscribe".
            if (event.type === "mode")
                root.mode = JSON.parse(event.data).change;
            if (event.type === "workspace" || event.type === "output")
                root.readWorkspaces();
            if (root.changesTree(event.type, event.data))
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
