pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "Rules.js" as Rules

// The notification core (docs/SPEC.md sections 5, 6 and 9): the server,
// classification, the queue, every timer, DND and history.
//
// Every tracked notification must close eventually. The display slots are
// `osd` (one OSD) and `current` (one note, critical or rich), the rest wait
// in `queue` or, when DND hides them, in `hidden`. One timer serves every
// deadline: the visible entries' timeouts, the 30 s queue limit and the
// 5 s DND expiry.
//
// M5 adds the clicks (click()), the hover pause (hover()) and the hold of
// notes while the target output shows a fullscreen window (showNext()).
// M6 places each notification on an output (targetOutput(), osdOn(),
// noteOn()) and moves it off an unplugged one (retarget()).
//
// An entry is a plain object:
//   n          the Notification, null once closed or for a restored history entry
//   data       snapshot {id, app, summary, body, urgency, value, image, icon, time},
//              kept for history and for the views once the object is gone
//   cls        Rules.classify() result
//   tag        x-canonical-private-synchronous hint, or ""
//   restored   true for a reload survivor (the views skip the entry animation)
//   replaced   true when it took the place of a note with the same synchronous tag
//   remaining  display time left in ms (Infinity: never expires)
//   running    whether the display timer runs (false while queued or under an OSD)
//   deadline   absolute ms of the display timeout or DND expiry, or null
//   waitUntil  absolute ms of the queue limit, or null
//   from       for an OSD that replaced another one: the previous value
//   output     the screen it shows on, set when it becomes visible (M6)
Singleton {
    id: root

    readonly property int queueLimit: 30000
    readonly property int historySize: 20

    property bool dnd: StateFile.get("dnd", false)

    property var current: null
    property var osd: null
    property var queue: []
    property var hidden: []
    readonly property int queued: queue.length
    readonly property var history: persist.history
    // Bumped when an entry's snapshot changes, for views that read `data`.
    property int revision: 0
    // Bumped when a display timer starts, pauses or restarts, for the
    // progress line (the entries are plain objects without signals).
    property int timing: 0
    // Bumped when an entry on display moves to another output (hotplug).
    property int placed: 0
    property int received: 0

    // Decision D5: notes whose rule does not show over fullscreen wait in
    // the queue while the target output shows a fullscreen window. The
    // target is the output the next note would show on, the focused one
    // (targetOutput(), SPEC section 11). The first waiting note that may
    // show takes the span once the fullscreen window leaves.
    readonly property bool fullscreen: Sway.isFullscreen(targetOutput())
    onFullscreenChanged: {
        if (!fullscreen && !current)
            showNext();
        reschedule();
    }

    // The note views with the pointer on the note (one key per output).
    // Hovering pauses the note's timer, leaving resumes it (SPEC section 8).
    property var hovering: []
    readonly property bool hovered: hovering.length > 0

    // ---- arrival -------------------------------------------------------

    // A new entry with every field set (see the list above).
    function entry(n: var, data: var, cls: var): var {
        return {
            n: n,
            data: data,
            cls: cls,
            tag: "",
            restored: false,
            replaced: false,
            remaining: cls.timeout > 0 ? cls.timeout : Infinity,
            running: false,
            deadline: null,
            waitUntil: null,
            from: null,
            output: "",
            closed: false
        };
    }

    function accept(n: var): void {
        const e = entry(n, snapshot(n), classify(n, root.dnd));
        e.tag = tagOf(n);
        e.restored = n.lastGeneration;
        n.closed.connect(reason => root.onClosed(e, reason));
        for (const change of [n.summaryChanged, n.bodyChanged, n.expireTimeoutChanged, n.hintsChanged, n.urgencyChanged])
            change.connect(() => root.updated(e));

        if (e.cls.hidden) {
            hide(e);
            return;
        }

        const old = e.tag ? findTag(e.tag) : null;
        const critical = e.cls.kind === "critical";
        if (e.cls.kind === "osd") {
            showOsd(e, old);
        } else if (old && old === current && (critical || old.cls.kind !== "critical")) {
            // Same synchronous tag as the note on display: take its place.
            e.replaced = true;
            show(e, old.output);
            close(old, "expire");
        } else if (old && queue.includes(old) && !critical && old.cls.kind !== "critical") {
            // Same tag as a waiting note: take its place and its queue limit.
            e.waitUntil = old.waitUntil;
            queue = queue.map(q => q === old ? e : q);
            close(old, "expire");
        } else {
            // Everything else goes the normal way, so that a critical takes
            // the span and a note never inherits a critical's unlimited wait.
            if (old)
                close(old, "expire");
            enqueue(e);
        }
        reschedule();
    }

    // A notification nothing else can place: it still has to close. It
    // takes the hidden path (5 s, no history) and reads as little as
    // possible from the object.
    function fallback(n: var, error: var): void {
        console.warn("notifs: could not place notification", n.id, error);
        const e = entry(n, {
            id: n.id,
            app: "",
            summary: "",
            body: "",
            urgency: Rules.NORMAL,
            value: null,
            time: Date.now()
        }, {
            kind: "note",
            timeout: Rules.DND_TIMEOUT,
            hidden: true,
            history: false
        });
        n.closed.connect(reason => root.onClosed(e, reason));
        hide(e);
    }

    function classify(n: var, dnd: bool): var {
        return Rules.classify({
            appName: n.appName,
            urgency: n.urgency,
            expireTimeout: n.expireTimeout,
            transient: n.transient,
            image: n.image,
            appIcon: n.appIcon
        }, {
            dnd: dnd
        });
    }

    function tagOf(n: var): string {
        return String(n.hints["x-canonical-private-synchronous"] ?? "");
    }

    function snapshot(n: var): var {
        return {
            id: n.id,
            app: n.appName,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            value: n.hints.value ?? null,
            image: n.image,
            icon: n.appIcon,
            time: Date.now()
        };
    }

    function findTag(tag: string): var {
        for (const e of [osd, current].concat(queue))
            if (e && e.tag === tag)
                return e;
        return null;
    }

    // ---- display -------------------------------------------------------

    function hide(e: var): void {
        e.deadline = Date.now() + Rules.DND_TIMEOUT;
        hidden = hidden.concat([e]);
        reschedule();
    }

    function showOsd(e: var, old: var): void {
        const previous = osd;
        const same = previous && previous.tag !== "" && previous.tag === e.tag;
        if (same)
            e.from = previous.data.value;
        // Before the slot changes, so that the views never see the entry
        // without its output. Same-tag updates stay where the OSD started.
        e.output = same ? previous.output : targetOutput();
        osd = e;
        run(e);
        syncPause();
        // The replaced OSD (same tag or not) leaves for good.
        if (previous)
            close(previous, "expire");
        if (old && old !== previous)
            close(old, "expire");
    }

    function enqueue(e: var): void {
        if (e.cls.kind === "critical") {
            // A critical takes the span at once. The note or older critical on
            // display goes back to the front of the queue with its time left.
            if (current) {
                const back = current;
                pause(back);
                back.waitUntil = back.cls.kind === "critical" ? null : Date.now() + queueLimit;
                queue = [back].concat(queue);
            }
            show(e, targetOutput());
        } else {
            e.waitUntil = Date.now() + queueLimit;
            queue = queue.concat([e]);
            if (!current)
                showNext();
        }
    }

    // `output` is set before `current` changes, so that the views never see
    // the entry without it.
    function show(e: var, output: string): void {
        e.waitUntil = null;
        e.output = output;
        current = e;
        syncPause();
    }

    // Held while the target output shows a fullscreen window (decision D5).
    function held(e: var): bool {
        return fullscreen && !e.cls.overFullscreen;
    }

    // The first waiting entry that may show. Held notes keep their place
    // (and their queue limit), so a screenshot can pass them.
    function showNext(): void {
        const next = queue.find(e => !held(e));
        if (!next)
            return;
        queue = queue.filter(q => q !== next);
        show(next, targetOutput());
    }

    // The note's timer pauses while an OSD covers it (an OSD on the same
    // output) or the pointer is on it, and runs otherwise.
    function syncPause(): void {
        if (!current)
            return;
        if ((osd && osd.output === current.output) || hovered)
            pause(current);
        else
            run(current);
    }

    // ---- outputs ---------------------------------------------------------

    // The output a notification shows on when it becomes visible: the
    // focused one (docs/SPEC.md section 11). The first screen stands in
    // while sway has not answered yet, or names a screen Quickshell does
    // not know (yet).
    function targetOutput(): string {
        const names = Quickshell.screens.map(s => s.name);
        return names.includes(Sway.focusedOutput) ? Sway.focusedOutput : (names[0] ?? "");
    }

    // The OSD and the note on display on one output, or null. A binding
    // that calls them also depends on `placed`, which changes when an entry
    // on display moves to another output.
    function osdOn(output: string): var {
        return placed >= 0 && osd !== null && osd.output === output ? osd : null;
    }
    function noteOn(output: string): var {
        return placed >= 0 && current !== null && current.output === output ? current : null;
    }

    // Hotplug: an entry on display whose output went away moves to the
    // target output. A critical would otherwise stay out of sight until
    // dismissed. Entries on the remaining outputs stay where they are.
    function retarget(): void {
        const names = Quickshell.screens.map(s => s.name);
        // The note view of a removed output may go before it reports that
        // the pointer left: its hover would hold every note.
        const wasHovered = hovered;
        hovering = hovering.filter(k => names.includes(k));
        let moved = false;
        for (const e of [osd, current]) {
            if (e && !names.includes(e.output)) {
                const to = targetOutput();
                console.info("notifs: output", e.output || "(none)", "is gone, notification", e.data.id, "moves to", to || "(none)");
                e.output = to;
                moved = true;
            }
        }
        if (moved || hovered !== wasHovered) {
            syncPause();
            reschedule();
        }
        if (moved)
            placed += 1;
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            root.retarget();
        }
    }

    function run(e: var): void {
        if (e.running)
            return;
        e.running = true;
        e.deadline = isFinite(e.remaining) ? Date.now() + e.remaining : null;
        timing += 1;
    }

    function pause(e: var): void {
        if (!e.running)
            return;
        e.running = false;
        if (e.deadline !== null)
            e.remaining = Math.max(0, e.deadline - Date.now());
        e.deadline = null;
        timing += 1;
    }

    // ---- updates and closing ------------------------------------------

    // replaces_id update: the server changed the object in place. The entry
    // stays where it is (hidden, waiting or on display) and its time starts
    // again. The rules are read again, since the urgency may have changed.
    function updated(e: var): void {
        if (e.closed || !e.n)
            return;
        e.data = Object.assign(snapshot(e.n), {
            time: e.data.time
        });
        e.tag = tagOf(e.n);
        const was = e.cls.kind;
        const cls = classify(e.n, false);
        // An update does not move an entry between the OSD and the note slot.
        if ((was === "osd") !== (cls.kind === "osd"))
            cls.kind = was;
        if (hidden.includes(e)) {
            // Still never drawn, whatever DND says by now: 5 s from here.
            e.cls = Object.assign(cls, {
                hidden: true,
                timeout: Rules.DND_TIMEOUT
            });
            e.deadline = Date.now() + Rules.DND_TIMEOUT;
        } else {
            e.cls = cls;
            e.remaining = cls.timeout > 0 ? cls.timeout : Infinity;
            if (e.running) {
                e.running = false;
                run(e);
            }
            if (queue.includes(e)) {
                if (cls.kind !== "critical") {
                    // Only a critical waits without a limit.
                    if (e.waitUntil === null)
                        e.waitUntil = Date.now() + queueLimit;
                } else if (was !== "critical") {
                    // A waiting note turned critical takes the span.
                    queue = queue.filter(q => q !== e);
                    enqueue(e);
                }
            }
        }
        revision += 1;
        reschedule();
    }

    // Asks the server to close an entry: "expire" (reason 1) or "dismiss"
    // (reason 2). The closed signal arrives synchronously in onClosed. An
    // entry without a Notification, or one the server does not answer for,
    // is dropped here, so that no entry can stay in a slot for ever.
    function close(e: var, how: string): void {
        if (!e || e.closed)
            return;
        if (e.n) {
            try {
                if (how === "expire")
                    e.n.expire();
                else
                    e.n.dismiss();
            } catch (error) {
                console.warn("notifs: could not close notification", e.data.id, error);
            }
        }
        if (!e.closed)
            onClosed(e, how === "expire" ? NotificationCloseReason.Expired : NotificationCloseReason.Dismissed);
    }

    // The one place an entry leaves: called from the `closed` signal,
    // whoever closed it (a timer, a command, an action, the sender). It
    // runs inside close(), so callers of close() put their own state in
    // order first.
    function onClosed(e: var, reason: var): void {
        if (e.closed)
            return;
        e.closed = true;
        // The server deletes the object when this handler returns.
        e.n = null;
        e.running = false;
        e.deadline = null;
        e.waitUntil = null;
        if (e.cls.history)
            remember(e);
        if (hidden.includes(e))
            hidden = hidden.filter(h => h !== e);
        if (queue.includes(e))
            queue = queue.filter(q => q !== e);
        if (osd === e) {
            osd = null;
            syncPause();
        }
        if (current === e) {
            current = null;
            showNext();
        }
        reschedule();
    }

    function remember(e: var): void {
        persist.history = [{
                app: e.data.app,
                summary: e.data.summary,
                body: e.data.body,
                urgency: e.data.urgency,
                time: e.data.time
            }].concat(persist.history).slice(0, historySize);
    }

    // ---- timers --------------------------------------------------------

    function reschedule(): void {
        let next = Infinity;
        for (const e of [osd, current].concat(hidden))
            if (e && e.deadline !== null)
                next = Math.min(next, e.deadline);
        for (const e of queue)
            if (e.waitUntil !== null)
                next = Math.min(next, e.waitUntil);
        if (next === Infinity) {
            tick.stop();
        } else {
            // QML timers are coarse (Qt allows 5 % error, 250 ms on 5 s).
            // Waking at 90 % of the wait and re-arming brings the last step
            // under 200 ms, so a deadline is met within a few ms.
            const wait = Math.max(1, Math.ceil(next - Date.now()));
            tick.interval = wait <= 200 ? wait : Math.floor(wait * 0.9);
            tick.restart();
        }
    }

    function due(e: var, now: real): bool {
        return (e.deadline !== null && e.deadline <= now) || (e.waitUntil !== null && e.waitUntil <= now);
    }

    function sweep(): void {
        const now = Date.now();
        // Collected first: each close re-enters onClosed and changes the lists.
        const found = [osd, current].concat(hidden, queue).filter(e => e && due(e, now));
        // Checked again: closing the note on display shows the next one, which
        // may be in `found` for its queue limit. It is on display now, so it
        // gets its display time.
        for (const e of found)
            if (due(e, now))
                close(e, "expire");
        reschedule();
    }

    Timer {
        id: tick
        repeat: false
        onTriggered: root.sweep()
    }

    // ---- commands (IPC, sway bindings, later the views) ------------------

    function setDnd(on: bool): void {
        if (dnd !== on) {
            dnd = on;
            StateFile.set("dnd", on);
        }
        if (!on)
            return;
        // Queued notifications that DND hides take the hidden path too. The
        // one on display stays until it leaves.
        const now = Date.now();
        const moving = queue.filter(e => e.n && !e.cls.showInDnd);
        for (const e of moving) {
            e.cls = Object.assign({}, e.cls, {
                hidden: true,
                timeout: Rules.DND_TIMEOUT
            });
            e.waitUntil = null;
            e.deadline = now + Rules.DND_TIMEOUT;
        }
        if (moving.length > 0) {
            queue = queue.filter(e => !moving.includes(e));
            hidden = hidden.concat(moving);
        }
        reschedule();
    }

    // The entry on top: the OSD while one shows, else the note.
    function top(): var {
        return osd ?? current;
    }

    function dismiss(): void {
        close(top(), "dismiss");
    }

    function dismissAll(): void {
        // The queue first: closing the note on display first would show
        // each waiting one for an instant before it is closed too.
        const all = queue.concat([current, osd]);
        for (const e of all)
            close(e, "dismiss");
    }

    // True when the notification on display has that action: it is then
    // invoked once the activation token is out (invokeAction()).
    function invoke(identifier: string): bool {
        for (const e of [current, osd]) {
            if (!e || !e.n)
                continue;
            if (e.n.actions.some(a => a.identifier === identifier)) {
                invokeAction(e, identifier);
                return true;
            }
        }
        console.warn("notifs: no action", identifier, "on the notification on display");
        return false;
    }

    // A click on a notification the views show, per the rules table (SPEC
    // sections 5 and 8). `button` is "left", "right" or "middle". The rule
    // gives "default" (the default action if any, else dismiss), "dismiss"
    // or "action:<id>" (that action, or dismiss if the sender gave none).
    // A middle click dismisses it and the whole queue. An entry that has
    // closed (a click during the leave animation) is left alone.
    function click(e: var, button: string): void {
        if (!e || e.closed || (e !== current && e !== osd))
            return;
        if (button === "middle") {
            dismissAll();
            return;
        }
        const what = String((button === "right" ? e.cls.right : e.cls.left) ?? "dismiss");
        const action = what === "default" ? "default" : what.startsWith("action:") ? what.slice(7) : "";
        const found = action && e.n ? e.n.actions.find(a => a.identifier === action) : null;
        console.info("notifs: click", button, "on", e.data.id, "->", found ? "action " + action : "dismiss");
        if (found)
            invokeAction(e, action);
        else
            close(e, "dismiss");
    }

    // ---- activation token (after M8, SPEC section 5) ----

    // An action goes to the sender after an ActivationToken signal, so that
    // a terminal like kitty can raise its window (sway marks it urgent).
    // helpers/activation-token.py asks the compositor for the token and
    // emits the signal, then bar invokes the action: when the helper has
    // exited, or after 400 ms at most. One invocation at a time: a second
    // click on the same notification meanwhile does nothing, an action of
    // another one while the helper still runs goes out without a token.
    property var invoking: null // {e, id} while the helper runs
    readonly property int tokenWait: 400
    // Debug (`debug tokenHelper <path>`): another helper, "" for the real one.
    property string tokenHelper: ""

    function invokeAction(e: var, identifier: string): void {
        if (invoking && invoking.e === e)
            return;
        // A helper still runs (for another notification, or one that timed
        // out): its exit must not release this action early.
        if (invoking || tokenProc.running) {
            console.info("notifs: activation helper busy, action", identifier, "of", e.data.id, "goes out without a token");
            invokeNow(e, identifier);
            return;
        }
        invoking = {
            e: e,
            id: identifier,
            t: Date.now()
        };
        tokenProc.command = ["python3", "-I", tokenHelper || Quickshell.shellPath("helpers/activation-token.py"), String(e.data.id)];
        tokenProc.running = true;
        tokenTimer.restart();
    }

    // The helper exited or took too long. The entry is held, never e.n:
    // the notification may have closed during the wait.
    function finishInvoke(how: string): void {
        tokenTimer.stop();
        const p = invoking;
        if (!p)
            return;
        invoking = null;
        console.info("notifs: activation token", how, "after", Date.now() - p.t, "ms for", p.e.data.id);
        invokeNow(p.e, p.id);
    }

    function invokeNow(e: var, identifier: string): void {
        const action = e.n && !e.closed ? e.n.actions.find(a => a.identifier === identifier) : null;
        if (!action) {
            console.info("notifs: notification", e.data.id, "closed before its action", identifier);
            return;
        }
        // Emits ActionInvoked, then closes with reason 2 unless the
        // notification is resident (its timer keeps running then).
        action.invoke();
    }

    Process {
        id: tokenProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.info(text.trim());
            }
        }
        onRunningChanged: {
            if (!running)
                root.finishInvoke("sent or failed");
        }
    }

    Timer {
        id: tokenTimer
        interval: root.tokenWait
        onTriggered: root.finishInvoke("timed out")
    }

    // The pointer entered (on) or left the note of the view `key`.
    function hover(key: string, on: bool): void {
        const was = hovered;
        hovering = on ? hovering.filter(k => k !== key).concat([key]) : hovering.filter(k => k !== key);
        if (hovered === was)
            return;
        syncPause();
        reschedule();
    }

    // Shows the newest history entry again as a note without actions. It
    // has no D-Bus object, and goes back to history when it closes.
    function restore(): void {
        if (persist.history.length === 0)
            return;
        const h = persist.history[0];
        persist.history = persist.history.slice(1);
        const e = entry(null, Object.assign({
            id: 0,
            value: null
        }, h), Object.assign(Rules.classify({
            appName: h.app,
            urgency: Rules.NORMAL,
            expireTimeout: -1
        }, {
            dnd: false
        }), {
            kind: "note",
            timeout: 5000,
            history: true,
            // It answers a key press, like its DND exception (Q8).
            overFullscreen: true
        }));
        enqueue(e);
        reschedule();
    }

    function describe(e: var): var {
        if (!e)
            return null;
        return {
            id: e.data.id,
            app: e.data.app,
            summary: e.data.summary,
            kind: e.cls.kind,
            value: e.data.value,
            output: e.output,
            restored: e.restored,
            running: e.running,
            remaining: e.running && e.deadline !== null ? e.deadline - Date.now() : isFinite(e.remaining) ? e.remaining : -1
        };
    }

    function status(): string {
        const t = top();
        return JSON.stringify({
            dnd: dnd,
            visible: t !== null,
            kind: t ? t.cls.kind : "",
            queued: queue.length,
            current: t ? {
                id: t.data.id,
                app: t.data.app,
                summary: t.data.summary
            } : null,
            // Beyond SPEC section 9, for tests:
            note: describe(current),
            osd: describe(osd),
            waiting: queue.map(e => e.data.id),
            held: queue.filter(e => held(e)).map(e => e.data.id),
            fullscreen: fullscreen,
            hovered: hovered,
            hidden: hidden.length,
            history: persist.history.length,
            newest: persist.history.length > 0 ? persist.history[0].summary : "",
            tracked: server.trackedNotifications.values.length
        });
    }

    PersistentProperties {
        id: persist
        reloadableId: "notifs"

        // list<var>, not var: a var array comes back undefined after a reload (spike S8).
        property list<var> history: []
    }

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            // First, or the server closes it as soon as this handler returns.
            n.tracked = true;
            root.received += 1;
            try {
                root.accept(n);
            } catch (error) {
                root.fallback(n, error);
            }
        }
    }

    IpcHandler {
        target: "notify"

        function toggleDnd(): bool {
            root.setDnd(!root.dnd);
            return root.dnd;
        }
        function setDnd(on: bool): void {
            root.setDnd(on);
        }
        function dnd(): bool {
            return root.dnd;
        }
        function dismiss(): void {
            root.dismiss();
        }
        function dismissAll(): void {
            root.dismissAll();
        }
        function restore(): void {
            root.restore();
        }
        function invoke(action: string): void {
            root.invoke(action);
        }
        function status(): string {
            return root.status();
        }
    }
}
