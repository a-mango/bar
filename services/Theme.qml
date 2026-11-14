pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Palettes, fonts and the theme mode. Views take every color from here.
// A mode change only swaps the bound colors: it never reloads the shell,
// which would unmap the bar (docs/SPEC.md section 10).
Singleton {
    id: root

    // "dark" or "light". Startup: `darkman get`, else the mode stored in
    // state.json, else dark.
    property string mode: StateFile.get("themeMode", "dark")

    readonly property string fontFamily: "IosevkaTerm Nerd Font"
    readonly property int fontSize: 15
    // waybar (Pango) rounds the font's 7.5 px advance to 8 px, Qt keeps
    // 7.5. Every text adds this spacing to match the reference widths.
    readonly property real letterSpacing: 0.5
    readonly property int barHeight: 24

    readonly property var palettes: ({
            dark: parse(darkFile.text()),
            light: parse(lightFile.text())
        })
    readonly property var palette: palettes[mode] ?? palettes.dark

    readonly property color base00: palette.base00
    readonly property color base01: palette.base01
    readonly property color base02: palette.base02
    readonly property color base03: palette.base03
    readonly property color base04: palette.base04
    readonly property color base05: palette.base05
    readonly property color base06: palette.base06
    readonly property color base07: palette.base07
    readonly property color base08: palette.base08
    readonly property color base09: palette.base09
    readonly property color base0A: palette.base0A
    readonly property color base0B: palette.base0B
    readonly property color base0C: palette.base0C
    readonly property color base0D: palette.base0D
    readonly property color base0E: palette.base0E
    readonly property color base0F: palette.base0F

    // Reads the 16 `@define-color baseXX #rrggbb;` lines of a base16 CSS file.
    function parse(css: string): var {
        const out = {};
        const re = /@define-color\s+(base0[0-9A-F])\s+(#[0-9a-fA-F]{6})\s*;/g;
        let m;
        while ((m = re.exec(css)) !== null)
            out[m[1]] = m[2];
        return out;
    }

    function setMode(next: string): bool {
        if (next !== "dark" && next !== "light") {
            console.warn("theme: unknown mode", next);
            return false;
        }
        if (mode !== next)
            mode = next;
        if (StateFile.get("themeMode", "") !== next)
            StateFile.set("themeMode", next);
        return true;
    }

    FileView {
        id: darkFile
        path: Quickshell.shellPath("themes/base16-default-dark.css")
        blockLoading: true
    }

    FileView {
        id: lightFile
        path: Quickshell.shellPath("themes/base16-default-light.css")
        blockLoading: true
    }

    Process {
        running: true
        command: ["darkman", "get"]
        stdout: StdioCollector {
            id: darkman
        }
        onExited: code => {
            const answer = darkman.text.trim();
            if (code === 0 && (answer === "dark" || answer === "light"))
                root.setMode(answer);
            else
                console.info("theme: darkman get failed (exit " + code + "), keeping", root.mode);
        }
    }

    IpcHandler {
        target: "theme"

        function set(mode: string): void {
            root.setMode(mode);
        }

        function mode(): string {
            return root.mode;
        }
    }
}
