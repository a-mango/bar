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
    // The rich card above the note span (SPEC section 4, decision D1).
    readonly property int cardHeight: 72

    readonly property var palettes: ({
            dark: parse(darkFile.text()),
            light: parse(lightFile.text())
        })
    readonly property var palette: palettes[mode] ?? palettes.dark

    property color base00: palette.base00
    Behavior on base00 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base01: palette.base01
    Behavior on base01 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base02: palette.base02
    Behavior on base02 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base03: palette.base03
    Behavior on base03 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base04: palette.base04
    Behavior on base04 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base05: palette.base05
    Behavior on base05 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base06: palette.base06
    Behavior on base06 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base07: palette.base07
    Behavior on base07 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base08: palette.base08
    Behavior on base08 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base09: palette.base09
    Behavior on base09 { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0A: palette.base0A
    Behavior on base0A { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0B: palette.base0B
    Behavior on base0B { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0C: palette.base0C
    Behavior on base0C { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0D: palette.base0D
    Behavior on base0D { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0E: palette.base0E
    Behavior on base0E { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }
    property color base0F: palette.base0F
    Behavior on base0F { enabled: Motion.themeFade > 0; ColorAnimation { duration: Motion.themeFade; easing.type: Motion.themeFadeEasing } }

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
