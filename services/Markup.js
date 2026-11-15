// Text of the note line (docs/SPEC.md section 4). Pure JS with no QML
// imports and no `.pragma`/`.import` lines, so that node can load it:
// tests/markup.test.mjs evaluates this file and reads its top-level names.
// overlay/NoteView.qml imports it with `import "../services/Markup.js" as Markup`.

// What the note line puts between body lines.
var LINE_BREAK = " · ";

// The markup subset the body keeps. Every other tag is stripped, its text
// stays. <img> in particular: StyledText would load the image.
var KEPT_TAGS = { b: true, i: true, u: true };

var TAG = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b[^<>]*?(\/?)>/g;
var ENTITY = /&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g;

// Escapes the characters StyledText would read as markup.
function escapeText(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Escapes a run of text between tags, keeping well-formed entities.
function escapeRun(run) {
    var out = "";
    var last = 0;
    var m;
    ENTITY.lastIndex = 0;
    while ((m = ENTITY.exec(run)) !== null) {
        out += escapeText(run.slice(last, m.index)) + m[0];
        last = m.index + m[0].length;
    }
    return out + escapeText(run.slice(last));
}

// Line breaks (newlines and <br>) of a body become one LINE_BREAK each run,
// and the ones at either end go.
function joinLines(text) {
    return text.replace(/^[ \t]*(\n[ \t]*)+/, "").replace(/([ \t]*\n)+[ \t]*$/, "")
        .replace(/[ \t]*(\n[ \t]*)+/g, LINE_BREAK);
}

// The body as StyledText: <b>, <i> and <u> kept without attributes, other
// tags stripped, entities kept, stray `<`, `>` and `&` escaped, line
// breaks turned into LINE_BREAK.
function body(text) {
    if (text === undefined || text === null)
        return "";
    var src = String(text).replace(/\r\n?/g, "\n");
    var out = "";
    var last = 0;
    var m;
    TAG.lastIndex = 0;
    while ((m = TAG.exec(src)) !== null) {
        out += escapeRun(src.slice(last, m.index));
        last = m.index + m[0].length;
        var name = m[2].toLowerCase();
        if (name === "br")
            out += "\n";
        else if (KEPT_TAGS[name] && m[3] !== "/")
            out += "<" + m[1] + name + ">";
    }
    out += escapeRun(src.slice(last));
    return joinLines(out);
}

// A plain-text field (app name, summary) on one line.
function line(text) {
    if (text === undefined || text === null)
        return "";
    return joinLines(String(text).replace(/\r\n?/g, "\n"));
}
