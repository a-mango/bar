// Unit tests for services/Rules.js (make test).
// Rules.js is a plain script shared with QML, not a module: it is evaluated
// here and its top-level names are read from the context.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../services/Rules.js", import.meta.url), "utf8");

function load() {
    const context = vm.createContext({});
    vm.runInContext(source, context, { filename: "services/Rules.js" });
    return context;
}

test("Rules.js is pure JS: no QML pragma or import lines", () => {
    assert.doesNotMatch(source, /^\s*\.(pragma|import)\b/m);
});

test("Rules.js loads in node and exposes RULES and classify()", () => {
    const rules = load();
    assert.ok(Array.isArray(rules.RULES));
    assert.equal(typeof rules.classify, "function");
});

// M1: one test per row of the rules table (docs/SPEC.md section 5), the
// timeout resolution and the DND exceptions.
