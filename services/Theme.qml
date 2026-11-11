pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Palettes and fonts. Views take every color from here.
// M0 version: loads the palette for `mode` from themes/. M2 adds the darkman
// startup mode, the state fallback and the `theme` IPC handler.
Singleton {
    id: root

    property string mode: "dark"

    readonly property string fontFamily: "IosevkaTerm Nerd Font"
    readonly property int fontSize: 15
    readonly property int barHeight: 24

    readonly property var palette: parse(file.text())

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

    FileView {
        id: file
        path: Quickshell.shellPath("themes/base16-default-" + root.mode + ".css")
        blockLoading: true
    }
}
