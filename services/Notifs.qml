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
// An entry is a plain object:
//   n          the Notification, null once closed or for a restored history entry
//   data       snapshot {id, app, summary, body, urgency, value, time}, kept for history
//   cls        Rules.classify() result
//   tag        x-canonical-private-synchronous hint, or ""
//   restored   true for a reload survivor (the views skip the entry animation)
//   replaced   true when it took the place of a note with the same synchronous tag
//   remaining  display time left in ms (Infinity: never expires)
//   running    whether the display timer runs (false while queued or under an OSD)
//   deadline   absolute ms of the display timeout or DND expiry, or null
//   waitUntil  absolute ms of the queue limit, or null
//   from       for an OSD that replaced another one: the previous value
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
    property int received: 0

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
            show(e);
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
        if (previous && previous.tag !== "" && previous.tag === e.tag)
            e.from = previous.data.value;
        osd = e;
        run(e);
        if (current)
            pause(current);
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
            show(e);
        } else {
            e.waitUntil = Date.now() + queueLimit;
            queue = queue.concat([e]);
            if (!current)
                showNext();
        }
    }

    function show(e: var): void {
        e.waitUntil = null;
        current = e;
        if (!osd)
            run(e);
    }

    function showNext(): void {
        if (queue.length === 0)
            return;
        const next = queue[0];
        queue = queue.slice(1);
        show(next);
    }

    function run(e: var): void {
        if (e.running)
            return;
        e.running = true;
        e.deadline = isFinite(e.remaining) ? Date.now() + e.remaining : null;
    }

    function pause(e: var): void {
        if (!e.running)
            return;
        e.running = false;
        if (e.deadline !== null)
            e.remaining = Math.max(0, e.deadline - Date.now());
        e.deadline = null;
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
            if (current)
                run(current);
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

    function invoke(identifier: string): bool {
        for (const e of [current, osd]) {
            if (!e || !e.n)
                continue;
            const action = e.n.actions.find(a => a.identifier === identifier);
            if (action) {
                // Emits ActionInvoked, then closes with reason 2 unless the
                // notification is resident (its timer keeps running then).
                action.invoke();
                return true;
            }
        }
        console.warn("notifs: no action", identifier, "on the notification on display");
        return false;
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
            history: true
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
            hidden: hidden.length,
            history: persist.history.length,
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
