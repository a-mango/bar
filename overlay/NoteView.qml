pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.bar
import "../services/Markup.js" as Markup

// The note view (docs/SPEC.md sections 2, 4 and 7): the 24 px strip of the
// overlay where a note, a critical or a rich notification shows. A rich
// notification adds the card above the span (RichView, M5).
//
// While a note is visible, the overlay draws its own clock and the whole
// center span, and the bar's clock never moves. The first frame draws the
// bar's idle clock box at the bar's position, the clock then compacts to
// "HH:mm" while sliding to the span's left edge, the separator appears and
// the note wipes in. Leaving runs the same steps backwards, and the overlay
// unmaps once its last frame, the idle clock box again, is on screen.
//
// Two values drive the layout: `c` (0 the bar's clock box, 1 the compact
// clock at the span's left edge) and `w` (0 retracted into the separator,
// 1 the note across the span). A third, `r`, drives the rich card (0 behind
// the strip, 1 up): it rises once the wipe or a roll has ended, and falls
// before the line changes or the note leaves. The view draws from
// snapshots only: the leave animation and the roll run after the
// notification has closed.
//
// Input (SPEC section 8, M5): clicks on the span or the card go to
// Notifs.click(), which applies the rules table. The pointer on the span or
// the card pauses the note's timer (Notifs.hover()) and its marquee.
Item {
    id: root

    // The bar of the same output: its clock box, the end of its left
    // section and the start of its tray place the span.
    property var bar: null
    // The output's name: this view's key for the hover pause.
    property string output: ""
    // Device pixel ratio of the window, for the card's thumbnail.
    property real dpr: 1
    // Debug (`debug noteHold`): wait at the first and at the last frame.
    property bool hold: false
    // The pointer is on the span or the card. Never while idle, so that a
    // stale hover cannot hold a note on display.
    readonly property bool hovered: active && (noteMouse.containsMouse || card.hovered)
    // Pauses the marquee.
    readonly property bool paused: hovered
    // Every click on the drawn content (the overlay counts them for tests).
    signal clicked

    // "idle" (unmapped), "first" (mapped, the first frame shows the bar's
    // clock box), "opening", "open", "closing", "last" (the last frame shows
    // the bar's clock box, then unmap).
    property string phase: "idle"
    readonly property bool active: phase !== "idle"
    // The entry on display. It stays while the note leaves, after it closed.
    property var entry: null

    property real c: 0
    property real w: 0
    property real r: 0

    // The line on display and the one that rolls out (or in, during a roll).
    property Line front: lineA
    property Line back: lineB
    readonly property bool critical: front.snap !== null && front.snap.critical
    readonly property string background: front.snap ? front.snap.background : "base01"
    property string oldBackground: "base01"

    // The progress line: share of the timeout left, and whether there is one.
    property real progress: 1
    property bool timed: false
    // Opacity of the leading-edge glow (pulses on critical).
    property real glow: Motion.pulseHigh

    // ---- geometry (logical px, window coordinates) ----

    readonly property real fullX: bar ? bar.clock.x : 0
    readonly property real fullW: bar ? bar.clock.width : 0
    readonly property bool seconds: bar ? bar.clock.showSeconds : false
    readonly property real compactW: compactProbe.implicitWidth + 14
    readonly property real spanX: bar ? Math.round(bar.leftEnd + 8) : 0
    readonly property real spanEnd: bar ? Math.round(bar.trayStart - 8) : width
    readonly property real sepW: separator.implicitWidth
    // The note region at its final place, right of the separator.
    readonly property real regionX: spanX + compactW + sepW
    readonly property real regionW: Math.max(0, spanEnd - regionX)

    // What the overlay's input mask covers: everything drawn in the strip,
    // and the card above it (an empty item while the card is down).
    readonly property Item hitArea: hit
    readonly property Item cardHitArea: card.hitArea

    // The line on display has a card: a rich notification with a picture.
    readonly property bool cardWanted: front.snap !== null && front.snap.rich && front.snap.picture !== ""
    // The card is on its way down (sync() waits for it).
    readonly property bool lowering: cardAnim.running && cardAnim.to === 0

    height: Theme.barHeight

    // ---- state machine ----

    function sync(): void {
        // The card falls first, then this runs again (lowerCard).
        if (lowering)
            return;
        const next = Notifs.current;
        if (next === entry) {
            if (next && (phase === "closing" || phase === "last"))
                open();
            return;
        }
        // The line changes or the note leaves: the card goes down first. A
        // rich note replaced through the synchronous tag keeps it up.
        if (r > 0 && !(next && next.replaced && snapOf(next).rich)) {
            lowerCard();
            return;
        }
        if (!next) {
            close();
            return;
        }
        entry = next;
        if (phase === "idle") {
            show(front, snapOf(next));
            back.snap = null;
            if (next.restored) {
                // A reload survivor comes back without the entry animation.
                c = 1;
                w = 1;
                phase = "open";
                raiseCard(true);
            } else {
                c = 0;
                w = 0;
                phase = "first";
                afterFrame(() => {
                    if (!root.hold)
                        root.open();
                });
            }
        } else {
            if (w > 0 && !next.replaced) {
                roll(snapOf(next));
            } else {
                show(front, snapOf(next));
                // In place: the card shows the new picture, or rises now.
                if (r > 0)
                    card.snap = front.snap;
                else
                    raiseCard();
            }
            if (phase === "closing" || phase === "last")
                open();
        }
        prefetchCard();
        syncProgress();
    }

    // The card's picture loads in the background while the span opens or
    // the line rolls in, so that the card can rise as soon as they end.
    // Decoding a screenshot takes 150 to 350 ms (M5 findings).
    function prefetchCard(): void {
        if (r === 0 && !lowering)
            card.snap = cardWanted ? front.snap : null;
    }

    function open(): void {
        closeAnim.stop();
        phase = "opening";
        openC.from = c;
        openC.duration = Motion.clockCompact * (1 - c);
        openW.from = w;
        openW.duration = Motion.noteWipe * (1 - w);
        openAnim.restart();
    }

    function close(): void {
        if (phase === "idle" || phase === "closing" || phase === "last")
            return;
        openAnim.stop();
        // Closing before the roll completes, so that its end does not
        // raise the card again.
        phase = "closing";
        if (rollAnim.running)
            rollAnim.complete();
        closeW.from = w;
        closeW.duration = Motion.noteRetract * w;
        closeC.from = c;
        closeC.duration = Motion.clockExpand * c;
        closeAnim.restart();
    }

    function closed(): void {
        phase = "last";
        afterFrame(() => {
            if (!root.hold)
                root.finish();
        });
    }

    function finish(): void {
        phase = "idle";
        entry = null;
        progressAnim.stop();
        cardAnim.stop();
        r = 0;
        card.snap = null;
        lineA.snap = null;
        lineB.snap = null;
        front = lineA;
        back = lineB;
    }

    // ---- the rich card ----

    // Once the span is open and no roll runs: the card of the line on
    // display slides up from behind the strip (`instant` for a reload
    // survivor). It waits for its picture to load.
    function raiseCard(instant: bool): void {
        if (phase !== "open" || rollAnim.running || lowering || !cardWanted)
            return;
        card.snap = front.snap;
        if (!card.ready || r >= 1)
            return;
        cardAnim.stop();
        if (instant) {
            r = 1;
            return;
        }
        cardAnim.to = 1;
        cardAnim.duration = Motion.cardRise * (1 - r);
        cardAnim.easing.type = Motion.cardRiseEasing;
        cardAnim.start();
    }

    // The card slides back behind the strip, then sync() runs again for
    // whatever changed meanwhile.
    function lowerCard(): void {
        if (lowering)
            return;
        cardAnim.stop();
        cardAnim.to = 0;
        cardAnim.duration = Motion.cardFall * r;
        cardAnim.easing.type = Motion.cardFallEasing;
        cardAnim.start();
    }

    // ---- input ----

    function click(button: int): void {
        root.clicked();
        Notifs.click(entry, button === Qt.RightButton ? "right" : button === Qt.MiddleButton ? "middle" : "left");
    }

    // Settled once per event loop turn: moving from the span to the card
    // leaves one and enters the other in the same turn.
    onHoveredChanged: Qt.callLater(root.reportHover)
    function reportHover(): void {
        Notifs.hover(output, hovered);
    }
    Component.onDestruction: Notifs.hover(output, false)

    // Debug: continue after a hold at the first or the last frame.
    function release(): void {
        if (phase === "first")
            open();
        else if (phase === "last")
            finish();
    }

    // Runs `then` once a frame of the current phase is on screen, so that
    // the first and the last frame are the bar's clock box (the handoff).
    property var frameThen: null
    property string framePhase: ""
    // Debug: how the last wait ended, "frame" or "timeout".
    property string frameVia: ""
    function afterFrame(then: var): void {
        frameThen = then;
        framePhase = phase;
        frameFallback.restart();
        if (root.Window.window)
            root.Window.window.update();
    }
    function frameDone(via: string): void {
        const then = frameThen;
        if (!then)
            return;
        frameThen = null;
        frameVia = via;
        frameFallback.stop();
        if (framePhase === phase)
            then();
    }

    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onFrameSwapped(): void {
            if (root.frameThen)
                Qt.callLater(root.frameDone, "frame");
        }
    }

    // In case no frame comes (a hidden view, a window still configuring).
    Timer {
        id: frameFallback
        interval: 250
        onTriggered: root.frameDone("timeout")
    }

    // ---- lines ----

    function iconOf(d: var): string {
        if (d.image)
            return d.image;
        const icon = d.icon || "";
        if (icon.startsWith("file://"))
            return icon;
        if (icon.startsWith("/"))
            return "file://" + icon;
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    // The card's picture at full size: `notify-send -i <file>` arrives as
    // image://icon/<path>, which is loaded from the file itself. Other
    // images (image-data) keep their URL. An absolute appIcon path is the
    // other source rich mode accepts (Rules.hasImage).
    function pictureOf(d: var): string {
        const image = d.image || "";
        const file = path => "file://" + path.split("/").map(encodeURIComponent).join("/");
        if (image.startsWith("image://icon//"))
            return file(image.slice("image://icon/".length));
        if (image)
            return image;
        const icon = d.icon || "";
        if (icon.startsWith("file://"))
            return icon;
        return icon.startsWith("/") ? file(icon) : "";
    }

    function snapOf(e: var): var {
        const d = e.data;
        const rich = e.cls.kind === "rich";
        return {
            id: d.id,
            icon: iconOf(d),
            app: Markup.line(d.app),
            summary: Markup.line(d.summary),
            body: Markup.body(d.body),
            critical: e.cls.kind === "critical",
            background: e.cls.background || "base01",
            rich: rich,
            picture: rich ? pictureOf(d) : ""
        };
    }

    function show(line: Line, snap: var): void {
        line.snap = snap;
        line.y = 0;
    }

    // Next in queue: the old line leaves upwards, the new one comes from
    // below, the background color crossfades. The clock stays compact.
    function roll(snap: var): void {
        if (rollAnim.running)
            rollAnim.complete();
        oldBackground = background;
        const out = front;
        front = back;
        back = out;
        front.snap = snap;
        rollOut.target = back;
        rollIn.target = front;
        rollAnim.restart();
    }

    // replaces_id update: the text changes in place. Updates of other
    // entries leave the line (and its marquee) alone.
    function refresh(): void {
        if (entry && !entry.closed) {
            const snap = snapOf(entry);
            if (JSON.stringify(snap) !== JSON.stringify(front.snap)) {
                front.snap = snap;
                // The card follows: new picture, down without one, up with one.
                if (r > 0 && cardWanted)
                    card.snap = snap;
                else if (r > 0)
                    lowerCard();
                else
                    raiseCard();
            }
        }
        syncProgress();
    }

    function syncProgress(): void {
        const e = entry;
        progressAnim.stop();
        // A closed entry keeps the line where it stopped while it leaves.
        if (!e || e.closed)
            return;
        const total = e.cls.timeout;
        timed = total > 0 && isFinite(e.remaining);
        if (!timed)
            return;
        if (e.running && e.deadline !== null) {
            const left = Math.max(0, e.deadline - Date.now());
            progress = Math.min(1, left / total);
            progressAnim.from = progress;
            progressAnim.duration = left;
            progressAnim.start();
        } else {
            progress = Math.min(1, e.remaining / total);
        }
    }

    Connections {
        target: Notifs
        // `current` passes through null when the next note in the queue
        // takes the span: read it once the change is complete.
        function onCurrentChanged(): void {
            Qt.callLater(root.sync);
        }
        function onRevisionChanged(): void {
            Qt.callLater(root.refresh);
        }
        function onTimingChanged(): void {
            Qt.callLater(root.syncProgress);
        }
    }

    // A running animation keeps the durations it started with: restart the
    // looping ones when the slow-motion factor changes (frame series).
    Connections {
        target: Motion
        function onSlowChanged(): void {
            if (pulseAnim.running)
                pulseAnim.restart();
            root.front.restartMarquee();
        }
    }

    Component.onCompleted: sync()

    // ---- animations ----

    SequentialAnimation {
        id: openAnim
        NumberAnimation {
            id: openC
            target: root
            property: "c"
            to: 1
            easing.type: Motion.clockCompactEasing
        }
        NumberAnimation {
            id: openW
            target: root
            property: "w"
            to: 1
            easing.type: Motion.noteWipeEasing
        }
        ScriptAction {
            script: {
                root.phase = "open";
                root.raiseCard();
            }
        }
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            id: closeW
            target: root
            property: "w"
            to: 0
            easing.type: Motion.noteRetractEasing
        }
        NumberAnimation {
            id: closeC
            target: root
            property: "c"
            to: 0
            easing.type: Motion.clockExpandEasing
        }
        ScriptAction {
            script: root.closed()
        }
    }

    ParallelAnimation {
        id: rollAnim
        // The card of the new line rises once it is in place.
        onFinished: root.raiseCard()
        NumberAnimation {
            id: rollOut
            property: "y"
            from: 0
            to: -Theme.barHeight
            duration: Motion.noteRoll
            easing.type: Motion.noteRollEasing
        }
        NumberAnimation {
            id: rollIn
            property: "y"
            from: Theme.barHeight
            to: 0
            duration: Motion.noteRoll
            easing.type: Motion.noteRollEasing
        }
        NumberAnimation {
            target: oldFill
            property: "opacity"
            from: 1
            to: 0
            duration: Motion.noteRoll
            easing.type: Motion.noteRollEasing
        }
    }

    NumberAnimation {
        id: progressAnim
        target: root
        property: "progress"
        to: 0
    }

    // The card, up or down (raiseCard, lowerCard).
    NumberAnimation {
        id: cardAnim
        target: root
        property: "r"
        onFinished: {
            if (cardAnim.to === 0)
                root.sync();
        }
    }

    // Critical: the glow pulses while the note shows.
    SequentialAnimation {
        id: pulseAnim
        running: root.critical && root.active && root.w > 0
        loops: Animation.Infinite
        onRunningChanged: {
            if (!running)
                root.glow = Motion.pulseHigh;
        }
        NumberAnimation {
            target: root
            property: "glow"
            to: Motion.pulseLow
            duration: Motion.pulsePeriod / 2
            easing.type: Motion.pulseEasing
        }
        NumberAnimation {
            target: root
            property: "glow"
            to: Motion.pulseHigh
            duration: Motion.pulsePeriod / 2
            easing.type: Motion.pulseEasing
        }
    }

    // ---- drawing ----

    SystemClock {
        id: clock
        enabled: root.active
        precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Measures the compact clock text.
    BarText {
        id: compactProbe
        visible: false
        text: root.seconds ? "HH:mm:ss" : "HH:mm"
    }

    // Hides the bar's own clock box while the overlay moves its copy.
    Rectangle {
        visible: root.active
        x: root.fullX
        width: root.fullW
        height: Theme.barHeight
        color: Theme.base00
    }

    // The clock: the bar's clock text, right-aligned in a box that shrinks
    // from the bar's clock box to the compact one, so the date leaves on
    // the left and "HH:mm" stays.
    Item {
        id: clockBox
        visible: root.active
        x: root.fullX + (root.spanX - root.fullX) * root.c
        width: root.fullW + (root.compactW - root.fullW) * root.c
        height: Theme.barHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.base00
        }

        BarText {
            x: clockBox.width - 7 - implicitWidth
            text: Qt.formatDateTime(clock.date, root.seconds ? "HH:mm:ss" : "yyyy-MM-dd HH:mm")
            color: Theme.base07
        }
    }

    BarText {
        id: separator
        visible: root.active
        x: clockBox.x + clockBox.width
        text: "│"
        color: Theme.base03
        opacity: root.c
    }

    // The note region: grows from the separator with the wipe. The content
    // sits at its final place and the clip reveals it.
    Item {
        id: region
        visible: root.active && width > 0
        x: separator.x + root.sepW
        width: root.w * root.regionW
        height: Theme.barHeight
        clip: true

        Rectangle {
            width: root.regionW
            height: Theme.barHeight
            color: Theme[root.background]
        }

        // The previous background, fading out during a roll.
        Rectangle {
            id: oldFill
            width: root.regionW
            height: Theme.barHeight
            color: Theme[root.oldBackground]
            opacity: 0
        }

        // Progress: 2 px on the top edge, shrinking to zero over the timeout.
        Rectangle {
            visible: root.timed
            width: root.regionW * root.progress
            height: 2
            color: root.critical ? Theme.base07 : Theme.base03
        }

        Item {
            id: viewport
            x: 7
            width: Math.max(0, root.regionW - 14 - (counter.visible ? counter.implicitWidth + 8 : 0))
            height: Theme.barHeight
            clip: true

            Line {
                id: lineA
                width: viewport.width
                scrolling: root.front === lineA && root.phase === "open" && !rollAnim.running
                paused: root.paused
            }
            Line {
                id: lineB
                width: viewport.width
                scrolling: root.front === lineB && root.phase === "open" && !rollAnim.running
                paused: root.paused
            }
        }

        // While others wait: +N at the right end of the span.
        BarText {
            id: counter
            visible: Notifs.queued > 0
            x: root.regionW - 7 - implicitWidth
            text: "+" + Notifs.queued
            color: root.critical ? Theme.base07 : Theme.base04
        }
    }

    // The leading edge: a 2 px line with a soft glow, kept inside the bar's
    // height and short of the tray.
    Item {
        visible: region.visible
        x: root.spanX
        width: Math.max(0, root.spanEnd + 7 - root.spanX)
        height: Theme.barHeight
        clip: true

        Rectangle {
            id: edge
            x: region.x + region.width - 2 - root.spanX
            width: 2
            height: Theme.barHeight
            color: Theme.base0D
            visible: false
        }

        MultiEffect {
            source: edge
            anchors.fill: edge
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: Theme.base0D
            shadowBlur: 1.0
            blurMax: 12
            shadowOpacity: root.glow
        }
    }

    // The rich card, in the overlay's upper 72 px, at the note region's
    // left edge. It belongs to the note: same clicks, same hover.
    RichView {
        id: card
        visible: root.active
        x: root.regionX
        y: -Theme.cardHeight
        up: root.r
        dpr: root.dpr
        maxWidth: root.regionW
        onClicked: button => root.click(button)
        // A picture that loads after the wipe ended (a reload survivor's
        // card comes back without the animation).
        onReadyChanged: {
            if (ready)
                root.raiseCard(root.entry !== null && root.entry.restored);
        }
    }

    // Everything drawn: the cover over the bar's clock, the clock and the
    // region up to its current edge. It takes the clicks and the hover.
    Item {
        id: hit
        readonly property real x0: Math.min(root.fullX, clockBox.x)
        readonly property real x1: Math.max(root.fullX + root.fullW, region.x + region.width)
        x: x0
        width: root.active ? x1 - x0 : 0
        height: Theme.barHeight

        MouseArea {
            id: noteMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: event => root.click(event.button)
        }
    }

    // ---- debug ----

    function debugState(): var {
        const s = front.snap;
        return {
            phase: phase,
            hold: hold,
            frameVia: frameVia,
            c: c,
            w: w,
            entry: entry ? entry.data.id : null,
            span: {
                x: spanX,
                end: spanEnd,
                width: spanEnd - spanX
            },
            clock: {
                x: clockBox.x,
                width: clockBox.width
            },
            region: {
                x: region.x,
                width: region.width,
                full: regionW
            },
            hit: {
                x: hit.x,
                width: hit.width
            },
            line: s ? {
                id: s.id,
                icon: s.icon,
                app: s.app,
                summary: s.summary,
                body: s.body
            } : null,
            marquee: {
                overflow: front.overflow,
                offset: front.offset,
                running: front.marqueeRunning
            },
            rolling: rollAnim.running,
            counter: counter.visible ? counter.text : "",
            timed: timed,
            progress: progress,
            critical: critical,
            pulse: pulseAnim.running,
            glow: glow,
            hovered: hovered,
            // The card in window coordinates (the strip starts at y 72).
            card: {
                r: r,
                wanted: cardWanted,
                ready: card.ready,
                lowering: lowering,
                picture: card.snap ? card.snap.picture : "",
                x: card.x,
                y: card.card.y,
                width: card.card.width,
                height: card.height - card.card.y,
                hit: card.hitArea.width
            }
        };
    }

    // One note line: icon, app name, summary, body. A line wider than its
    // space scrolls (the marquee) while `scrolling` is set.
    component Line: Item {
        id: line

        property var snap: null
        property bool scrolling: false
        property bool paused: false
        property real offset: 0
        readonly property real overflow: snap ? Math.max(0, Math.ceil(row.implicitWidth - width)) : 0
        readonly property bool marqueeRunning: marquee.running

        height: Theme.barHeight
        visible: snap !== null

        function restartMarquee(): void {
            offset = 0;
            row.opacity = 1;
            if (marquee.running)
                marquee.restart();
        }

        // New text: back to the start, and the hold starts again.
        onSnapChanged: restartMarquee()

        Row {
            id: row
            x: -line.offset
            spacing: 8

            IconImage {
                y: (Theme.barHeight - 16) / 2
                implicitSize: 16
                // A screenshot file decodes in full before it is scaled:
                // off the GUI thread, so that a roll does not stall. The
                // 16 px stay reserved while it loads.
                asynchronous: true
                visible: source.toString() !== "" && status !== Image.Error
                source: line.snap ? line.snap.icon : ""
            }
            BarText {
                visible: text !== ""
                text: line.snap ? line.snap.app : ""
                color: line.snap && line.snap.critical ? Theme.base07 : Theme.base04
            }
            BarText {
                visible: text !== ""
                text: line.snap ? line.snap.summary : ""
                color: Theme.base07
            }
            BarText {
                visible: text !== ""
                textFormat: Text.StyledText
                text: line.snap ? line.snap.body : ""
                color: line.snap && line.snap.critical ? Theme.base07 : Theme.base05
            }
        }

        // Hold, scroll left, hold at the end, fade back to the start.
        SequentialAnimation {
            id: marquee
            running: line.scrolling && line.overflow > 0
            paused: running && line.paused
            loops: Animation.Infinite
            PropertyAction {
                target: line
                property: "offset"
                value: 0
            }
            PropertyAction {
                target: row
                property: "opacity"
                value: 1
            }
            PauseAnimation {
                duration: Motion.marqueeHold
            }
            NumberAnimation {
                target: line
                property: "offset"
                from: 0
                to: line.overflow
                duration: line.overflow / Motion.marqueeSpeed * 1000
            }
            PauseAnimation {
                duration: Motion.marqueeEndHold
            }
            NumberAnimation {
                target: row
                property: "opacity"
                to: 0
                duration: Motion.marqueeReturn / 2
            }
            PropertyAction {
                target: line
                property: "offset"
                value: 0
            }
            NumberAnimation {
                target: row
                property: "opacity"
                to: 1
                duration: Motion.marqueeReturn / 2
            }
        }
    }
}
