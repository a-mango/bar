// Unit tests for services/Rules.js (make test).
// Rules.js is a plain script shared with QML, not a module: it is evaluated
// here and its top-level names are read from the context.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../services/Rules.js", import.meta.url), "utf8");
const R = vm.createContext({});
vm.runInContext(source, R, { filename: "services/Rules.js" });

// A notification as Notifs.qml passes it, with defaults for a plain note.
function n(fields = {}) {
    return { appName: "demo-app", urgency: R.NORMAL, expireTimeout: -1, transient: false, image: "", appIcon: "", ...fields };
}
const plain = (obj) => JSON.parse(JSON.stringify(obj));
const off = { dnd: false };
const on = { dnd: true };

test("Rules.js is pure JS: no QML pragma or import lines", () => {
    assert.doesNotMatch(source, /^\s*\.(pragma|import)\b/m);
});

describe("rules table (SPEC section 5), one test per row", () => {
    test("default: note, 5000 ms, hidden in DND and over fullscreen, history, default action / dismiss, base01", () => {
        assert.deepEqual(plain(R.classify(n(), off)), {
            rule: "default", kind: "note", timeout: 5000, hidden: false, showInDnd: false, overFullscreen: false,
            history: true, left: "default", right: "dismiss", background: "base01", fill: null,
        });
    });

    for (const [app, fill] of [["volume", "base0D"], ["brightness", "base0A"], ["microphone", "base0E"]]) {
        test(`app ${app}: OSD, 2000 ms, shown in DND and over fullscreen, no history, dismiss / dismiss, fill ${fill}`, () => {
            assert.deepEqual(plain(R.classify(n({ appName: app }), off)), {
                rule: app, kind: "osd", timeout: 2000, hidden: false, showInDnd: true, overFullscreen: true,
                history: false, left: "dismiss", right: "dismiss", background: "base00", fill,
            });
        });
    }

    test("app screenshot with an image: rich, 10000 ms, shown in DND and over fullscreen, history, dismiss / action discard", () => {
        assert.deepEqual(plain(R.classify(n({ appName: "screenshot", image: "image://icon//tmp/shot.png" }), off)), {
            rule: "screenshot", kind: "rich", timeout: 10000, hidden: false, showInDnd: true, overFullscreen: true,
            history: true, left: "dismiss", right: "action:discard", background: "base01", fill: null,
        });
    });

    test("app screenshot without an image: note, same rule otherwise", () => {
        const c = R.classify(n({ appName: "screenshot" }), off);
        assert.equal(c.kind, "note");
        assert.equal(c.rule, "screenshot");
        assert.equal(c.right, "action:discard");
    });

    test("critical from battery-appindicator: critical, no timeout, shown in DND and over fullscreen, history", () => {
        assert.deepEqual(plain(R.classify(n({ appName: "battery-appindicator", urgency: R.CRITICAL }), off)), {
            rule: "battery-critical", kind: "critical", timeout: 0, hidden: false, showInDnd: true, overFullscreen: true,
            history: true, left: "default", right: "dismiss", background: "base08", fill: null,
        });
    });

    test("critical from any other app: critical, no timeout, hidden in DND, shown over fullscreen, history", () => {
        assert.deepEqual(plain(R.classify(n({ urgency: R.CRITICAL }), off)), {
            rule: "critical", kind: "critical", timeout: 0, hidden: false, showInDnd: false, overFullscreen: true,
            history: true, left: "default", right: "dismiss", background: "base08", fill: null,
        });
    });

    test("battery-appindicator at normal urgency falls to the default rule", () => {
        assert.equal(R.classify(n({ appName: "battery-appindicator" }), off).rule, "default");
    });

    test("low urgency is a plain note", () => {
        assert.equal(R.classify(n({ urgency: R.LOW }), off).rule, "default");
    });

    test("an OSD app wins over critical urgency (first match)", () => {
        assert.equal(R.classify(n({ appName: "volume", urgency: R.CRITICAL }), off).kind, "osd");
    });

    test("an unlisted app with a value hint stays a note (the table decides)", () => {
        assert.equal(R.classify(n({ appName: "demo-app", hints: { value: 40 } }), off).kind, "note");
    });

    test("urgency given as a name is accepted", () => {
        assert.equal(R.classify(n({ urgency: "critical" }), off).kind, "critical");
    });
});

describe("timeout resolution", () => {
    test("a positive sender timeout wins (the OSD senders pass 800)", () => {
        assert.equal(R.classify(n({ appName: "volume", expireTimeout: 800 }), off).timeout, 800);
        assert.equal(R.classify(n({ expireTimeout: 12000 }), off).timeout, 12000);
        assert.equal(R.classify(n({ urgency: R.CRITICAL, expireTimeout: 3000 }), off).timeout, 3000);
    });

    test("-1 takes the rule's value", () => {
        assert.equal(R.classify(n({ expireTimeout: -1 }), off).timeout, 5000);
        assert.equal(R.classify(n({ appName: "screenshot", expireTimeout: -1 }), off).timeout, 10000);
    });

    test("-1 on a rule without timeout never expires (0)", () => {
        assert.equal(R.classify(n({ urgency: R.CRITICAL, expireTimeout: -1 }), off).timeout, 0);
    });

    test("0 never expires", () => {
        assert.equal(R.classify(n({ expireTimeout: 0 }), off).timeout, 0);
        assert.equal(R.classify(n({ appName: "volume", expireTimeout: 0 }), off).timeout, 0);
    });

    test("a missing expireTimeout counts as -1", () => {
        const fields = n();
        delete fields.expireTimeout;
        assert.equal(R.classify(fields, off).timeout, 5000);
    });
});

describe("DND", () => {
    test("a plain note is hidden and expires after 5000 ms", () => {
        const c = R.classify(n(), on);
        assert.equal(c.hidden, true);
        assert.equal(c.timeout, R.DND_TIMEOUT);
        assert.equal(c.history, true);
    });

    test("the hidden 5000 ms overrides a sender timeout and 0", () => {
        assert.equal(R.classify(n({ expireTimeout: 60000 }), on).timeout, 5000);
        assert.equal(R.classify(n({ expireTimeout: 0 }), on).timeout, 5000);
    });

    test("a critical from another app is hidden and expires after 5000 ms instead of never", () => {
        const c = R.classify(n({ urgency: R.CRITICAL }), on);
        assert.equal(c.hidden, true);
        assert.equal(c.timeout, 5000);
    });

    test("exceptions: OSDs, screenshots and battery-appindicator criticals stay visible", () => {
        for (const fields of [{ appName: "volume" }, { appName: "brightness" }, { appName: "microphone" },
                              { appName: "screenshot", image: "image://icon//tmp/a.png" },
                              { appName: "battery-appindicator", urgency: R.CRITICAL }]) {
            const c = R.classify(n(fields), on);
            assert.equal(c.hidden, false, JSON.stringify(fields));
        }
        assert.equal(R.classify(n({ appName: "battery-appindicator", urgency: R.CRITICAL }), on).timeout, 0);
        assert.equal(R.classify(n({ appName: "volume", expireTimeout: 800 }), on).timeout, 800);
    });

    test("a missing state counts as DND off", () => {
        assert.equal(R.classify(n()).hidden, false);
    });
});

describe("history and images", () => {
    test("transient notifications never go to history", () => {
        assert.equal(R.classify(n({ transient: true }), off).history, false);
        assert.equal(R.classify(n({ urgency: R.CRITICAL, transient: true }), off).history, false);
    });

    test("rich mode accepts an absolute image path in appIcon", () => {
        assert.equal(R.classify(n({ appName: "screenshot", appIcon: "/tmp/shot.png" }), off).kind, "rich");
        assert.equal(R.classify(n({ appName: "screenshot", appIcon: "file:///tmp/shot.jpg" }), off).kind, "rich");
    });

    test("rich mode ignores icon names and relative paths", () => {
        assert.equal(R.classify(n({ appName: "screenshot", appIcon: "camera-photo" }), off).kind, "note");
        assert.equal(R.classify(n({ appName: "screenshot", appIcon: "shots/a.png" }), off).kind, "note");
        assert.equal(R.classify(n({ appName: "screenshot", appIcon: "/usr/bin/demo" }), off).kind, "note");
    });
});
