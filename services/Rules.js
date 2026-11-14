// Notification rules (docs/SPEC.md section 5). Pure JS with no QML imports
// and no `.pragma`/`.import` lines, so that node can load it:
// tests/rules.test.mjs evaluates this file and reads its top-level names.
// M1 adds the rules table and the real classify().

var RULES = [];

function classify(notification, state) {
    return { kind: "note" };
}
