// Unit tests for services/Markup.js (make test), the text of the note line.
// Markup.js is a plain script shared with QML, not a module: it is evaluated
// here and its top-level names are read from the context.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../services/Markup.js", import.meta.url), "utf8");
const M = vm.createContext({});
vm.runInContext(source, M, { filename: "services/Markup.js" });

test("Markup.js is pure JS: no QML pragma or import lines", () => {
    assert.doesNotMatch(source, /^\s*\.(pragma|import)\b/m);
});

describe("body(): the StyledText subset of SPEC section 4", () => {
    test("plain text passes unchanged", () => {
        assert.equal(M.body("demo-app compiled in 42 s"), "demo-app compiled in 42 s");
    });

    test("<b>, <i> and <u> stay, attributes go", () => {
        assert.equal(M.body("<b>bold</b> <i>it</i> <U class='x'>under</U>"), "<b>bold</b> <i>it</i> <u>under</u>");
    });

    test("other tags are stripped and keep their text", () => {
        assert.equal(M.body('see <a href="https://example.invalid">the demo page</a>'), "see the demo page");
        assert.equal(M.body("<span foreground='red'>red</span> text"), "red text");
        assert.equal(M.body("<font color=red>x</font>"), "x");
    });

    test("<img> is stripped, with its attributes", () => {
        assert.equal(M.body('before <img src="/tmp/demo.png" alt="demo"/> after'), "before  after");
        assert.equal(M.body("<img src='file:///tmp/demo.png'>"), "");
    });

    test("entities stay, stray markup characters are escaped", () => {
        assert.equal(M.body("Tom &amp; Jerry &#8212; &lt;tag&gt;"), "Tom &amp; Jerry &#8212; &lt;tag&gt;");
        assert.equal(M.body("a < b && c > d"), "a &lt; b &amp;&amp; c &gt; d");
        assert.equal(M.body("100% & more"), "100% &amp; more");
    });

    test("newlines and <br> become one separator per run, none at the ends", () => {
        assert.equal(M.body("first line\nsecond line"), "first line · second line");
        assert.equal(M.body("one\r\n\r\ntwo\rthree"), "one · two · three");
        assert.equal(M.body("a<br>b<br/>c<BR />d"), "a · b · c · d");
        assert.equal(M.body("\n  leading and trailing  \n\n"), "leading and trailing");
        assert.equal(M.body("x  \n   y"), "x · y");
    });

    test("self-closing kept tags are dropped", () => {
        assert.equal(M.body("a<b/>b"), "ab");
    });

    test("empty and missing bodies", () => {
        assert.equal(M.body(""), "");
        assert.equal(M.body(undefined), "");
        assert.equal(M.body(null), "");
    });
});

describe("line(): plain fields on one line", () => {
    test("newlines become separators, markup characters stay as typed", () => {
        assert.equal(M.line("Build\nfinished <b>"), "Build · finished <b>");
        assert.equal(M.line("demo-app"), "demo-app");
        assert.equal(M.line(undefined), "");
    });
});
