// Notification rules (docs/SPEC.md section 5) and classify(). Pure JS with
// no QML imports and no `.pragma`/`.import` lines, so that node can load it:
// tests/rules.test.mjs evaluates this file and reads its top-level names.
// services/Notifs.qml imports it with `import "Rules.js" as Rules`.

// NotificationUrgency values as Quickshell delivers them.
var LOW = 0;
var NORMAL = 1;
var CRITICAL = 2;

// A notification that DND hides always expires after this time, because
// nobody can click a notification that is never drawn.
var DND_TIMEOUT = 5000;

// First match wins. `timeout` applies when the sender passes -1, in ms;
// null means none. `left` and `right` are the click actions: "default"
// (default action if any, else dismiss), "dismiss" or "action:<id>".
var RULES = [
    { name: "volume", app: "volume", kind: "osd", timeout: 2000, dnd: true, fullscreen: true, history: false,
      left: "dismiss", right: "dismiss", background: "base00", fill: "base0D" },
    { name: "brightness", app: "brightness", kind: "osd", timeout: 2000, dnd: true, fullscreen: true, history: false,
      left: "dismiss", right: "dismiss", background: "base00", fill: "base0A" },
    { name: "microphone", app: "microphone", kind: "osd", timeout: 2000, dnd: true, fullscreen: true, history: false,
      left: "dismiss", right: "dismiss", background: "base00", fill: "base0E" },
    { name: "screenshot", app: "screenshot", kind: "rich", timeout: 10000, dnd: true, fullscreen: true, history: true,
      left: "dismiss", right: "action:discard", background: "base01", fill: null },
    { name: "battery-critical", app: "battery-appindicator", urgency: CRITICAL, kind: "critical", timeout: null,
      dnd: true, fullscreen: true, history: true, left: "default", right: "dismiss", background: "base08", fill: null },
    { name: "critical", urgency: CRITICAL, kind: "critical", timeout: null, dnd: false, fullscreen: true, history: true,
      left: "default", right: "dismiss", background: "base08", fill: null },
    { name: "default", kind: "note", timeout: 5000, dnd: false, fullscreen: false, history: true,
      left: "default", right: "dismiss", background: "base01", fill: null }
];

var IMAGE_FILE = /\.(png|jpe?g|gif|bmp|svg|webp|tiff?|xpm)$/i;

function urgencyOf(value) {
    if (value === "low") return LOW;
    if (value === "critical") return CRITICAL;
    if (value === "normal" || value === undefined || value === null) return NORMAL;
    return value;
}

function matches(rule, n) {
    if (rule.app !== undefined && rule.app !== n.appName) return false;
    if (rule.urgency !== undefined && rule.urgency !== urgencyOf(n.urgency)) return false;
    return true;
}

function ruleFor(n) {
    for (var i = 0; i < RULES.length; i++)
        if (matches(RULES[i], n)) return RULES[i];
    return RULES[RULES.length - 1];
}

// An image for rich mode: `image` is set, or `appIcon` is an absolute path
// (or file:// URL) to an image file.
function hasImage(n) {
    if (n.image) return true;
    var icon = n.appIcon || "";
    if (icon.indexOf("file://") === 0) icon = icon.slice(7);
    return icon.charAt(0) === "/" && IMAGE_FILE.test(icon);
}

// Timeout in ms, 0 for none. A positive sender value wins, -1 takes the
// rule's value, 0 never expires. DND-hidden notifications override all three.
function resolveTimeout(sender, ruleTimeout, hidden) {
    if (hidden) return DND_TIMEOUT;
    if (sender > 0) return sender;
    if (sender === 0) return 0;
    return ruleTimeout === null ? 0 : ruleTimeout;
}

// n: {appName, urgency, expireTimeout, transient, image, appIcon}
// state: {dnd}
function classify(n, state) {
    var rule = ruleFor(n);
    var hidden = !!(state && state.dnd) && !rule.dnd;
    var kind = rule.kind;
    if (kind === "rich" && !hasImage(n)) kind = "note";
    return {
        rule: rule.name,
        kind: kind,
        timeout: resolveTimeout(n.expireTimeout === undefined ? -1 : n.expireTimeout, rule.timeout, hidden),
        hidden: hidden,
        showInDnd: rule.dnd,
        overFullscreen: rule.fullscreen,
        history: rule.history && !n.transient,
        left: rule.left,
        right: rule.right,
        background: rule.background,
        fill: rule.fill
    };
}
