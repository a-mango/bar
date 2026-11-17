# bar: behavior specification

**bar** is the status bar and notification daemon of the owner's sway desktop. It is a single Quickshell (Qt 6, Qt Modeling Language (QML)) process. On every output it draws a 24 px bar with the workspaces and the sway mode on the left, the clock in the center and the system tray on the right. The same process owns `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher` on the session bus, so notification senders and tray applets talk to it directly. A notification grows out of the clock and fills the center of the bar. Volume, brightness and microphone On-Screen Displays (OSDs) take the full width for a moment. When nothing is happening, the bar looks like the current waybar.

bar replaces waybar and mako. Neither runs after the cutover, and mako is uninstalled (see `PLAN.md`, M8). Do Not Disturb (DND), screenshot notifications and critical notifications are implemented in bar itself.

This document describes what bar does. `PLAN.md` describes the order in which it gets built and how each part is verified. The configurations bar replaces are kept in `docs/reference/` (waybar's `config.jsonc`, `style.css` and base16 palettes, and mako's `config`).

## Contents

1. Scope
2. Windows and layers
3. Bar
4. Notification display
5. Notification rules
6. Lifecycle
7. Animation
8. Input
9. Inter-Process Communication (IPC)
10. Theme
11. Outputs
12. Compatibility contract
13. Test matrix

## 1. Scope

In scope:

- The bar: workspaces, sway mode, clock with a calendar popup, system tray.
- The notification server (D-Bus `org.freedesktop.Notifications`, spec version 1.2) with DND, history, screenshot and critical handling.
- The tray watcher and host (StatusNotifierItem (SNI) protocol).
- An IPC interface for sway bindings and the darkman hook.

Out of scope for this plan: a notification center panel, inline replies, sounds, extra bar modules (battery, network, audio). They can come later in the same configuration.

## 2. Windows and layers

Each output gets two layer-shell windows:

| Window | Layer | Exclusion | Size (logical px) | Mapped | Content |
|---|---|---|---|---|---|
| Bar | `WlrLayer.Bottom` | `ExclusionMode.Normal`, 24 px exclusive zone | full width × 24 | always | workspaces, mode, clock, tray |
| Overlay | `WlrLayer.Overlay` | `ExclusionMode.Ignore`, so it sits on the bar | full width × 96 | only while transient content shows | OSD, notes, critical, rich card |

Reasons for the split:

- On the bottom layer, a fullscreen window covers the bar, as it covers waybar today. A volume OSD during a fullscreen video, or a battery alert during a fullscreen game, must still show, so all transient content goes on the overlay layer. mako placed its OSDs and critical notifications on the overlay layer for the same reason.
- The bar window is never hidden or unmapped. Unmapping it drops its exclusive zone and re-tiles every window on the output twice. That is the flash documented in `~/.local/share/darkman/sway.sh`.

Overlay rules:

- Its input `mask` covers only what it draws, so the workspaces and the tray stay clickable while a note fills the center.
- Its bottom edge is the output's bottom edge, so the 24 px strip lies exactly on the bar (spike S2).
- The upper 72 px exist only for the rich card. They are transparent, and outside the mask except where the card shows.
- Namespaces: `bar` and `bar-overlay`. Keyboard focus: `WlrKeyboardFocus.None` for both.

Handoff rule: while a note is visible, the overlay draws its own compact clock and the whole center span. The bar's clock never animates. The overlay's first and last frames reproduce the bar's idle center pixel for pixel (same font, position and colors), so the switch between the two windows cannot be seen (spike S7).

Font: `IosevkaTerm Nerd Font` at 15 px, as in waybar's `style.css`. Every bar text adds 0.5 px letter spacing: Pango (waybar) rounds the font's 7.5 px advance to 8 px, Qt does not.

Text rendering: Qt's native (FreeType) renderer, set for the whole process with `//@ pragma NativeTextRendering` in `shell.qml` (decision D7). It hints glyphs like waybar's Pango, draws them with grayscale antialiasing, and keeps the handoff pixel-exact (spike S7: 0 differing pixels). Qt's default distance-field renderer uses subpixel antialiasing, which leaves pixels off by 1/255 between the two windows.

## 3. Bar

The bar reproduces `docs/reference/waybar/config.jsonc` and `style.css`. The `make reference` screenshot of waybar in the nested session is the visual target.

### Left: workspaces and mode

- Only the workspaces of this output, sorted by number, labelled with their name. Source: the `I3` singleton (`workspaces`, filtered on `monitor.name`).
- Colors from `style.css`:
  - Default: `base00` background, `base05` text.
  - Visible on this output but not focused: `base02` background, `base07` text.
  - Focused: `base07` background, `base00` text.
  - Urgent: `base08` background.
  - Hover: `base03` background.
- Buttons have 5 px horizontal padding around a content box of at least 16 px, and no rounded corners. Labels are bold, as the GTK theme draws waybar's buttons. A left click activates the workspace (`I3Workspace.activate()`). Scrolling does nothing (waybar's `disable-scroll`).
- The sway mode follows the workspaces with a 6 px gap (waybar's 4 px margin plus 2 px module spacing). It is hidden in `default`. Other modes show their name in italics, `base07` on `base04`, with 7 px padding. Source: an `I3IpcListener` subscribed to `mode` events, with the initial mode from `swaymsg -t get_binding_state` (spike S10).
- The mode name always shows in full while no note is visible. The `present:` mode doubles as a cheat sheet (`~/.config/sway/config.d/60-bindings-present.conf`), and waybar cuts it short today. The text only elides on the right if a note would otherwise get less than 600 px. The 600 px are the whole center span of section 4 (M4 choice, question Q14 in `PLAN.md` section 8). The label elides from the first frame of the note's entry to the last frame of its leave. A name that already runs under the clock when idle keeps the bar's clock box over it, empty while the note shows (question Q13).

### Center: clock

- Format `yyyy-MM-dd HH:mm` in a box with 7 px padding, centered on the output whatever the width of the left and right sections (waybar's `fixed-center`).
- A left click toggles `HH:mm:ss`, which updates every second only while it is shown.
- Hovering for 400 ms shows a month calendar in a `PopupWindow` above the clock (waybar's `{calendar}` tooltip): `yyyy MMMM`, the weekday names from the locale, then the weeks, with today in bold and underlined as in waybar's default format. The popup is `base00` with a 1 px `base03` border and 8 px padding.
- Hover colors: `base07` background, `base00` text.

### Right: tray

- `SystemTray.items`, icons 16 px, 14 px apart.
- `Passive` items are dimmed (opacity 0.5). `NeedsAttention` items blink on `base08`, alternating every 0.5 s like the `blink` keyframes in `style.css`.
- Left click: `activate()`, or open the menu if `onlyMenu` is true. Middle click: `secondaryActivate()`. Right click: open the menu through `QsMenuAnchor`. Scroll: `scroll(delta, horizontal)`.
- `QsMenuAnchor` needs `//@ pragma UseQApplication` in `shell.qml`. Its menu is a QtWidgets menu that does not use `Theme` (spike S9, question Q2 in `PLAN.md` section 8).
- Tooltip after 400 ms of hover: `tooltipTitle` (`base07`) over `tooltipDescription` (`base05`, simple markup allowed), in the same frame as the calendar. It grows up and to the left from the icon's top right corner, because sway does not slide popups of layer surfaces back onto the output.
- The tray box has 7 px padding on both sides, so the last icon ends 7 px from the right edge.
- The watcher and the host run inside bar. Quickshell registers `org.kde.StatusNotifierWatcher` and retries when the current owner leaves. At login, `/usr/libexec/sway-systemd/wait-sni-ready` waits up to 25 s for a watcher with a registered host before it starts the XDG autostart applets.

## 4. Notification display

| Kind | Trigger | Where | Height |
|---|---|---|---|
| OSD | `hints.value` is set | overlay, full width (covers the workspaces and the tray) | 24 |
| Note | default | overlay, center span | 24 |
| Critical | urgency `Critical` | like a note, on `base08` | 24 |
| Rich | the rule enables rich mode (only `screenshot` by default) and an image is present: `image` is set, or `appIcon` is an absolute path to an image file | note line plus a 72 px card above the center span | 96 |

The rule in section 5 decides the kind: only the apps `volume`, `brightness` and `microphone` are OSDs. Another app that sends a `value` hint stays a note (M1 choice, question Q3 in `PLAN.md` section 8).

Rich card (decision D1): it sits in the overlay's upper 72 px, at the note region's left edge (right of the separator). It is a `base01` card, 72 px high, with a 4 px frame around a thumbnail 64 px high at the picture's aspect ratio, no wider than the note region (M5 choice, Q17). `notify-send -i <file>` arrives as `image://icon/<path>`, and the card loads the file itself at the physical size it draws. The picture loads in the background from the moment the line shows, since decoding a screenshot on the GUI thread blocks for 150 to 350 ms (`PLAN.md` section 8, M5 findings). A picture that does not load gives no card.

Center span: while a note is visible, it runs from the end of the left section (plus 8 px) to the start of the tray (minus 8 px). From left to right, it holds the compact clock `HH:mm`, a `│` separator in `base03`, then the note line.

- The compact clock is the bar's clock box made narrow: `base07` on `base00` with 7 px padding (54 px). With seconds shown in the bar, it is `HH:mm` too: the full text is then left-aligned, so the seconds leave on the right (M7, Q15).
- The separator takes one character cell (8 px) on the bar's background.
- The note region runs from the separator to the span's end: `base01` (`base08` on critical), 7 px padding on both sides, the parts of the line 8 px apart.

Note line, left to right:

- Icon (16 px), from `image` or `appIcon` through `Quickshell.iconPath()`. Browsers and chat apps often send `image-data` (avatars, site icons). Outside rich mode, that image only fills this icon. An icon that does not load takes no room.
- App name in `base04`, summary in `base07`, body in `base05`. On a critical, all three are `base07`, the app name at 70 % and the body at 85 % opacity over `base08`, so the summary stays brightest in both modes (M7, Q15).
- Newlines in the body become ` · `. The body advertises and renders a safe markup subset (`<b>`, `<i>`, `<u>`), and other tags are stripped. `services/Markup.js` does this, pure JS with unit tests: `<br>` counts as a newline, entities stay, a stray `<`, `>` or `&` is escaped, `<img>` goes with its attributes (StyledText would load it). App name and summary are plain text on one line.
- While others wait, a counter `+N` sits at the right end of the span, `base04` (`base07` on critical).

## 5. Notification rules

`services/Rules.js` holds the rules as data, plus a pure `classify(notification, state)` function with no QML imports, so `node --test` can check it. The rules reproduce the behavior of the retired mako configuration (`docs/reference/mako/config`, as of 2026-11-03), except for the changes listed after the table.

| Criteria | Kind | Timeout when sender passes -1 | Shown in DND | Shown over fullscreen | History | Left click | Right click | Colors |
|---|---|---|---|---|---|---|---|---|
| default | note | 5000 ms | no | no (held) | yes | default action if any, else dismiss | dismiss | `base01` background, text as in section 4 |
| app `volume` | OSD | 2000 ms | yes | yes | no | dismiss | dismiss | fill `base0D` |
| app `brightness` | OSD | 2000 ms | yes | yes | no | dismiss | dismiss | fill `base0A` |
| app `microphone` | OSD | 2000 ms | yes | yes | no | dismiss | dismiss | fill `base0E` |
| app `screenshot` | rich (note if no image) | 10000 ms | yes | yes | yes | dismiss | invoke action `discard` | as default |
| urgency critical, app `battery-appindicator` | critical | none | yes | yes | yes | default action if any, else dismiss | dismiss | `base08` background, `base07` text |
| urgency critical, any other app | critical | none | no | yes | yes | default action if any, else dismiss | dismiss | as above |

Timeout resolution: a positive `expireTimeout` from the sender wins (the OSD senders pass 800 ms). `-1` takes the rule's value. `0` never expires. Quickshell delivers `expireTimeout` in milliseconds, as sent. One exception overrides all three: a notification that DND hides always expires after 5000 ms, because nobody can click a notification that is never drawn.

Fullscreen (decision D5): a notification whose rule does not show over fullscreen waits in the queue while its target output shows a fullscreen window. This matches what the owner sees today, since mako's normal notifications were on the top layer, under fullscreen windows. OSDs, screenshots and critical notifications still show over the fullscreen window. Screenshots get the same reasoning as their DND exception in the mako config: they answer a key press, and without them a successful shot looks like nothing happened. A note restored from history (`restore()`) shows over fullscreen for the same reason (M5 choice, Q19). A note already on display when fullscreen starts stays until it leaves, as with DND (M5 choice, Q16).

Changes from the mako behavior:

- Critical notifications stay until clicked or closed by the sender. mako applied `default-timeout=5000` to them (decision D2).
- Notes held during fullscreen show once it ends, if they have waited less than 30 s. mako dropped them out of sight under the fullscreen window.
- DND starts off (decision D6). mako was in DND mode when this was written.
- Timers start when a notification becomes visible, not when it arrives, because the bar shows one notification at a time.
- Hovering a note pauses its timer.
- mako's `[urgency=high]` section is dropped: it matched nothing, since urgencies are low, normal and critical.

## 6. Lifecycle

1. **Arrival.** The `NotificationServer.notification(n)` handler sets `n.tracked = true` before anything else. An untracked notification is closed and deleted as soon as the handler returns.
2. **Reload survivors.** With `keepOnReload: true`, a Quickshell reload re-emits every tracked notification with `n.lastGeneration` set. The handler tracks it again and puts it back without the arrival animation.
3. **Classification.** `Rules.classify()` returns the kind, timeout, DND visibility, history flag, click actions and color roles.
4. **DND.** A notification hidden by DND stays tracked, and a 5000 ms timer starts at once, whatever its rule's timeout (a hidden critical with timeout "none" would otherwise never close). It expires silently (`NotificationClosed` reason 1) and goes to history. When DND is switched on, the waiting notifications that DND hides take the same path. The one on display stays until it leaves (M1 choice, Q4).
5. **Synchronous tag.** If `hints["x-canonical-private-synchronous"]` matches a tracked notification, the old one is closed with `expire()`. The OSD keeps its surface and animates from the old value to the new one, and the timer restarts. The OSD senders never pass `replaces_id`, so this is the only replacement path they use. A note with the tag of the note on display takes its place at once, and one with the tag of a waiting note takes its place in the queue, with its queue limit. There is one OSD at a time: an OSD with another tag also expires the visible one (M1 choice, Q5).
6. **`replaces_id` updates.** The server updates the existing object and emits no new `notification` signal. Views bind to the properties (`summary`, `body`, `hints`, `urgency`, `image`). The core listens to `expireTimeoutChanged`, `hintsChanged`, `summaryChanged`, `bodyChanged` and `urgencyChanged`. It reads the rules again and restarts the time, and the notification stays where it is: one on display starts its timeout again, a waiting one shows later with the new timeout and keeps its queue limit, and one hidden by DND starts its 5000 ms again. A waiting note that turns critical takes the span, and an update never turns a note into an OSD, or an OSD into a note (M1 choice, Q9). A `notify-send -r` update that repeats the same text restarts the time as well (measured: closed 5.0 s after the update, `.test/logs/m1/bus-same-update.log`).
7. **Queue.** One note is visible at a time:
   - Order: critical notifications first (newest first), then the others in arrival order (oldest first).
   - An OSD draws above the current note. The note's timer pauses and resumes once the OSD leaves. With several outputs, this holds when both show on the same output: a note on another output keeps running (M6 choice, Q22 in `PLAN.md` section 8).
   - A critical notification pushes the current note back to the front of the queue with its remaining time. The note's 30 s queue limit starts again at that moment (M1 choice, Q6). A newer critical also takes the span from an older one, which goes back to the front of the queue. `battery-appindicator` sends 20 %, 5 % and suspend warnings in a row, and the latest one must be the one on screen.
   - While the target output shows a fullscreen window, notes whose rule does not show over fullscreen stay in the queue (decision D5). They keep their place and their queue limit, and the first entry that may show takes the span, so a screenshot passes the held notes. The first held note appears when the fullscreen window leaves. The target output is the one the next note would show on, the focused one (section 11).
   - The pointer on the note (or its card) pauses its timer, like an OSD over it. The timer runs only while neither holds it.
   - A notification that has waited 30 s in the queue without being shown expires into history (reason 1). This includes notes held during fullscreen, so most notes that arrive during a film end up in history. Critical notifications are exempt: they stay until clicked (decision D2), so they wait in the queue as long as needed. Blocking senders such as `screenshot.sh` would otherwise wait for as long as the queue lasts.
8. **Timers.** The server has no expiry timer, so all timers live in QML. Expiry calls `n.expire()` (reason 1). A dismiss click calls `n.dismiss()` (reason 2). An action click calls `action.invoke()`, which emits `ActionInvoked` and then closes with reason 2 unless the notification is `resident`. A sender's `CloseNotification` closes with reason 3, and the views react to the `closed` signal. A `resident` notification keeps its timer after an action and expires as usual. One scheduler `Timer` in `services/Notifs.qml` serves every deadline. QML timers are coarse (Qt allows 5 % error), so it wakes at 90 % of the wait and arms again, and a close lands within about 10 ms of its time. Every tracked notification must close eventually.
9. **History.** The last 20 closed notifications whose rule keeps history and that are not `transient`. Entries are plain objects (app, summary, body, urgency, time), not `Notification` objects, kept across reloads in a `property list<var>` of a `PersistentProperties`. A `property var` holding a JS array comes back `undefined` after a reload (spike S8). `restore()` takes the newest entry off the list and shows it again as a plain note without actions, for 5000 ms. It queues like any other note and goes back to history when it closes (M1 choice, Q8). It has no D-Bus object, so a reload while it shows loses it.
10. **State.** `state.json` under `Quickshell.stateDir` stores the DND flag and the last theme mode. With no state file, DND starts off (decision D6).

## 7. Animation

Durations and easing curves live in one `Motion.qml` singleton. M7 tuned them with the owner: every note transition is 1.2 times its starting value (the values below), and the OSD, marquee and pulse kept theirs.

Note:

- **Enter.** The overlay maps showing exactly the bar's idle center: a `base00` box over the bar's clock box, and the overlay's own clock in it. Nothing moves until that first frame is on screen (the window's `frameSwapped`, with a 250 ms fallback), because a layer surface is configured before it draws. The clock compacts from `yyyy-MM-dd HH:mm` to `HH:mm` while sliding to the left edge of the span (288 ms, `Easing.OutCubic`): the full text stays right-aligned in a box that narrows, so the date leaves on the left. The separator fades in with the slide, then the note wipes in from the separator to the right end of the span (384 ms, `Easing.OutCubic`). The span background (`base01`) grows with the wipe. The leading edge is a 2 px `base0D` line with a soft halo: `shaders/wipe.frag`, a horizontal Gaussian (sigma 3 px, peak opacity 0.55) the same over the whole bar height, drawn under the line (M7, chosen over a `MultiEffect` shadow and over a trail behind the moving edge). It stays at the span's end while the note shows. The text sits at its final position and is revealed by the clip, so it does not move. The `base00` box over the bar's clock stays until the overlay unmaps, so the bar's clock never shows through.
- **Stay.** A line wider than the space it has holds for 1200 ms, then scrolls left at 60 px/s. It holds for 1000 ms at the end, then fades back to the start in 150 ms, and the cycle repeats. The hold starts when the wipe (or a roll) ends. A 2 px progress line on the top edge of the whole span (compact clock, separator and note region, M7, Q15) shrinks to zero over the timeout (`base03`, `base07` on critical). It stops while the timer pauses (under an OSD), and a notification without a timeout has none.
- **Leave.** The note retracts into the separator (288 ms, `Easing.InCubic`). Then the clock slides back to the center and expands to the full format (288 ms, `Easing.OutCubic`). The overlay unmaps once the frame that matches the bar's idle center is on screen. The leave runs after the notification closed, so the view draws from the entry's snapshot. A note that arrives during the leave opens the span again from where it is.
- **Next in queue.** While the span is open, the old line moves up out of the strip and the new one comes in from below, 240 ms (`Easing.OutQuad`). The background crossfades over the same time when the colors differ. The clock stays compact, and there is no second wipe. A note that replaces the one on display through the synchronous tag changes the text in place, like a `replaces_id` update.
- **Reload survivor.** It comes back with the span already open, without the entry animation.

OSD (full width):

- **Enter.** The strip fades in over 100 ms (linear) while the fill grows from 0 to the value in 180 ms (`Easing.OutCubic`). Both start on the overlay's first frame, about 30 ms after it maps: started earlier, they ticked irregularly while the surface was set up (`PLAN.md` section 8, M3 findings).
- **Update** (same synchronous tag): the fill width animates to the new value in 120 ms (`Easing.OutQuad`).
- **Rapid presses.** A new OSD that finds the strip shown or fading out keeps the same surface: the fill moves to the new value as in an update, and a fading strip fades back in from where it is. The entry runs only when the overlay was idle. An OSD of another app takes the strip the same way, and its fill color changes at once (M3 choice, question Q11).
- **Leave.** Fade out over 150 ms (linear), back to the bar (or to the open note span). The strip keeps its last label and value while it fades, and the overlay unmaps when the fade ends.
- The label (the summary, for example `Brightness: 40%`) is centered on the output (M3 choice, Q12). It is drawn twice and split at the fill edge with clipping: `base05` over the empty part, `Theme.onFill` over the filled part: `base00`, and `base07` in light mode (M7, Q10). Both are `#181818`. It stays readable at 0 % and at 100 %, which matters for the muted microphone (value 0). The fill edge snaps to physical pixels, so both copies line up. In light mode that gives 11.7:1 on brightness, 7.5:1 on volume and 6.1:1 on microphone.

Critical: the leading-edge glow pulses between 0.4 and 1.0 opacity with a 1600 ms period while shown.

Rich: the card slides up from behind the strip in 264 ms (`Easing.OutCubic`) after the note's wipe, and slides back down before the note leaves (264 ms, `Easing.InCubic`, M5 choice, Q18). It is clipped at the strip's top edge, so it comes out from behind it. Before a roll it slides down first, and the card of a rich line rises once the roll ends. A rich note replaced through the synchronous tag keeps its card up and changes the picture in place. A reload survivor comes back with its card up.

Cost: no animation runs while idle. The overlay is unmapped, the bar redraws only when its content changes, and the marquee, pulse and blink timers stop when nothing uses them.

## 8. Input

- Overlay clicks land only on drawn content. Everything else reaches the bar, or the window above the bar for the transparent upper 72 px. The input mask combines the strip's content with the visible part of the rich card.
- Note clicks follow the rules table: "default action if any" means the action with the identifier `default`, and `invoke action discard` falls back to a dismiss when the sender gave no such action. The rich card takes the same clicks as its note. A middle click dismisses the current notification and the whole queue. A click during the leave animation (after the notification closed) does nothing.
- Hovering a note (the span or its card) pauses its timer and its marquee. Leaving resumes both. A note that opens under a pointer resting on the bar pauses at once (M7, Q21). The overlay gets no pointer enter until the pointer moves, so the view asks the bar, whose `HoverHandler` still holds the pointer, whether it lies inside the drawn span. Once the pointer moves, the bar gets the leave and the overlay the enter. A pointer parked on the center therefore holds every new note. A view that unmaps under the pointer leaves no hover behind.
- An OSD covers the whole bar for up to 2 s. A click on it dismisses it (left or right button, as in the rules table). A middle click also dismisses the queue, as on a note (M5 choice, Q20). While it fades out, its input mask is empty, so clicks reach the bar (M3 choice).
- Tray menus open as popups of the bar window. They are the only part of bar that may need keyboard input. Spike S9 showed that they get none while the bar's keyboard focus is `None`: arrow keys and Escape go to the focused window, and the menu only reacts to the pointer. Switching to `WlrKeyboardFocus.OnDemand` once a menu is open does not help, because sway gives the focus on a click and that click has already happened. What works is `OnDemand` while the pointer is on the tray or a menu is open: the opening click then focuses the bar, and the focus returns to the window when the menu closes. `OnDemand` at all times is ruled out, since the bar would keep the keyboard after any click on it. Whether menus get keyboard input at all is question Q2 in `PLAN.md` section 8. Until it is answered, the bar stays at `None`.

## 9. Inter-Process Communication (IPC)

Calls use `quickshell ipc -p <config dir> call <target> <function> [args]`. Typed arguments follow what `IpcHandler` supports in this snapshot (check with `quickshell ipc --help`).

`notify` target:

| Function | Effect |
|---|---|
| `toggleDnd(): bool` | flips DND and returns the new state |
| `setDnd(on: bool)` | sets DND |
| `dnd(): bool` | returns the DND state |
| `dismiss()` | dismisses the OSD while one shows, else the current notification (M1 choice, Q7) |
| `dismissAll()` | dismisses the queue, the current notification and the OSD. Notifications hidden by DND are left to their 5 s |
| `restore()` | shows the newest history entry again (section 6, item 9) |
| `invoke(action: string)` | invokes the named action on the current notification |
| `status(): string` | JSON `{dnd, visible, kind, queued, current: {id, app, summary}}`, for tests and scripts. `current` is the OSD while one shows. The matrix reads more fields: `note`, `osd`, `waiting`, `held` (waiting notes held by fullscreen), `fullscreen`, `hovered`, `hidden`, `history`, `newest` (summary of the newest history entry), `tracked` |

`theme` target: `set(mode: string)` with `dark` or `light`, and `mode(): string`.

`debug` target, for tests only: `state(): string` (the focused output and the screens, bars with a serial number and counters of backing-window connects and hides, overlays, the note view's geometry and animation state), `overlay(mode)` (the M0 spike content), `trayMenu(index, open)`, `slow(factor: real)` (note durations times `factor`, for frame series), `noteHold(on: bool)` and `noteRelease()` (the note view waits at its first and last frame, for the handoff check).

Sway bindings (decision D3), installed at cutover from `packaging/sway-bindings.conf`. Each one runs `quickshell ipc -p ~/.local/share/bar call notify <function>`:

| Keys | Function |
|---|---|
| `$mod+n` | `dismiss()` |
| `$mod+Shift+n` | `dismissAll()` |
| `$mod+Ctrl+n` | `restore()` |
| `$mod+Shift+d` | `toggleDnd()` |

`$mod+m` (`bar hidden_state toggle`) is removed at cutover (decision D4). The bar has no hide function.

## 10. Theme

- The repository ships the two palettes as `themes/base16-default-dark.css` and `themes/base16-default-light.css` (copies of `docs/reference/waybar/`). `services/Theme.qml` parses their 16 `@define-color baseXX #rrggbb;` lines.
- Every color in the views comes from the theme service, and no view contains a raw hex value.
- Startup mode: the output of `darkman get` (through `Process`). darkman may not be up yet at login, so if that fails, the last mode stored in `state.json` (key `themeMode`) applies, then `dark`. Every applied mode is written back to that key.
- Transitions: a new darkman hook, `~/.local/share/darkman/bar.sh`, calls `quickshell ipc --any-display -p ~/.local/share/bar call theme set "$1"`. darkman is a systemd user service and may lack `WAYLAND_DISPLAY` when it starts at login, and `quickshell ipc` only sees instances on the caller's display without `--any-display`. The `-p` path already selects the live instance only. The hook exits quietly when bar is not running.
- A theme change only changes the bound color properties. It never calls `Quickshell.reload()`, which would unmap the bar. During an OSD or a note it maps nothing and runs no entry (matrix case TH). Every color crossfades over 300 ms (`Motion.themeFade`, `Easing.InOutQuad`, M7, Q26), the bar and the overlay in step, since both bind to the same animated theme colors. The answer of `darkman get` at startup swaps at once, so a login shows no fade.

## 11. Outputs

- One bar window and one overlay window per screen, through `Variants { model: Quickshell.screens }`.
- Each bar shows the workspaces of its own output. The clock and tray appear on every bar.
- Fullscreen state per output comes from sway IPC: `swaymsg -t get_tree` at startup, then `window` events (`fullscreen_mode` changes) and `workspace` events through an `I3IpcListener`. An output counts as fullscreen when its visible workspace holds a fullscreen container, or when a global fullscreen window exists. Events only say that something changed: every `window` event that can change the answer (`fullscreen_mode`, `close`, `move`, `floating`, `new`), every `workspace` event but `urgent` and every `output` event reads the tree again, one `swaymsg` at a time. In the tree, workspace nodes always report `fullscreen_mode: 1`, so only `con` and `floating_con` nodes count, and the scratchpad output `__i3` never does (`PLAN.md` section 8, M5 findings).
- A notification shows on the output that is focused when it becomes visible (`I3.focusedMonitor.name` matched to `ShellScreen.name`, through `Sway.focusedOutput`) and stays there until it leaves. OSD updates with the same synchronous tag stay where the OSD started, and a note that replaces the one on display through the tag keeps its output. While sway has not reported a focused output, or names one that Quickshell does not list, the first screen stands in.
  - A note that takes the span from the queue becomes visible at that moment, so it goes to the output focused then. If the focus moved since the previous note, that one leaves on its output and the next one enters on the focused output, without a roll (M6 choice, Q24). The same holds for a note pushed back by a critical when it shows again, and for an OSD of another app, which is a new OSD (Q5).
  - The core stamps the output on the entry before the slot changes, and each overlay's views draw only the entries placed on their output (`Notifs.osdOn()`, `Notifs.noteOn()`). The overlays of the other outputs stay unmapped.
  - A reload survivor goes to the output focused at the reload: the core does not keep the output across a reload (M6 choice, Q25).
- Plugging or unplugging an output (dock) must not crash the shell or leave a stale surface.
  - `Variants` keeps the bar and overlay of every output that stays. A new output gets its own pair, and its overlay stays unmapped while a notification shows elsewhere. The bars of the other outputs are never replaced or unmapped and keep their exclusive zone (matrix case HP).
  - When the output of a notification on display goes away, the notification moves to the output focused then (or the first screen) and enters there with the entry animation. A critical would otherwise stay out of sight until dismissed (M6 choice, Q23). The pause rule above applies again on the new output.

## 12. Compatibility contract

Other programs depend on the following behavior:

- **`GetCapabilities`** returns at least `body`, `body-markup`, `actions` and `icon-static`.
- **`screenshot.sh`** (`~/Documents/scripts/screenshot.sh`) runs `notify-send -A discard=Discard` in a background subshell. That call blocks until the notification closes, and prints the action identifier if one was invoked. All three outcomes must work:
  - A right click prints `discard`, and the script moves the file to the trash.
  - A left click prints nothing.
  - The 10 s timeout prints nothing.

  A notification that never closes leaves that subshell hanging forever.
- **`NotificationClosed`** reasons: 1 expired, 2 dismissed, 3 closed by `CloseNotification`.
- **OSD senders** (`~/bin/volume-helper`, the brightness and microphone bindings in `~/.config/sway/config.d/`) rely on replacement through the synchronous tag.
- **`battery-appindicator`**: its critical notifications show in DND.
- **Tray applets**: 11 items were registered on 2026-11-11, most through libayatana-appindicator. They must appear at login (through `wait-sni-ready`), and they must register again after a restart of bar.
- **`makoctl`** disappears with mako. Its only callers are `~/.config/waybar/scripts/mako-status.sh` and `mako-toggle-dnd.sh`, which nothing uses.
- **darkman**: the waybar hook (`~/.local/share/darkman/waybar.sh`, `pkill -SIGUSR2 waybar`) is retired at cutover. The sway hook needs no change.

## 13. Test matrix

Test notifications use fictional text only. `tests/matrix.sh` runs each case in the nested session, saves screenshots to `.test/shots/<case>/` and writes a bus monitor log from the private bus to `.test/logs/`.

Bar:

| # | Case | Expected |
|---|---|---|
| B1 | workspaces 1, 2 and 3 on HEADLESS-1, focus on 2 | colors per section 3; a click on 3 focuses it |
| B2 | a test client with `urgent enable` on a hidden workspace | that workspace button turns `base08` |
| B3 | `swaymsg mode resize`, then a mode with a name as long as the `present:` cheat sheet | italic label on `base04`, long name shown in full |
| B4 | click on the clock, hover on the clock | seconds shown and ticking, calendar popup with today highlighted |
| B5 | `tests/fake-sni.py` registers an item, sets `NeedsAttention`, then exposes a menu | icon appears, blinks, right click opens the menu, a click on an entry reaches the fake item |
| B6 | `SNI_WAIT_TIMEOUT=10 /usr/libexec/sway-systemd/wait-sni-ready` | logs `Successfully waited for org.kde.StatusNotifierHost` (the script exits 0 on failure too) |
| B7 | a fullscreen test client, then a volume OSD, a screenshot note and a plain note | bar covered, OSD and screenshot drawn above the client, plain note held |

Notifications:

| # | Case | Expected |
|---|---|---|
| N1 | `notify-send "Build finished" "demo-app compiled in 42 s"` | grows out of the clock, leaves after 5 s, reason 1 |
| N2 | a note with a 400-character body | marquee scroll after 1200 ms |
| N3 | three notes within 200 ms | first shows with `+2`, then the next two roll in |
| N4 | `notify-send -u critical -a battery-appindicator "Battery low" "5% remaining"` with DND on | red span, stays until clicked, visible in DND |
| N5 | five `volume` OSDs 100 ms apart, values 10 to 50, same synchronous tag | one full-width strip, fill animates through the values |
| N6 | `brightness` value 0, `microphone` value 0 | label readable over the empty bar |
| N7 | `-a screenshot -i <png> -A discard=Discard` | rich card. Right click prints `discard`, left click prints nothing, timeout after 10 s prints nothing |
| N8 | DND on, plain note | nothing drawn, reason 1 after 5 s, entry in history |
| N9 | `CloseNotification` on a visible note | leaves early, reason 3 |
| N10 | `notify-send -r <id>` update | text changes in place, timer restarts |
| N11 | `touch shell.qml` (reload) while a note is visible | note survives, no second entry animation |
| N12 | second output (`swaymsg create_output`), focus moved to it | next note shows on the focused output only, and stays there when the focus moves back. An OSD on the other output does not pause it, a same-tag OSD update stays where the OSD started, and the note queued behind it shows on the output focused when it takes the span |
| N13 | a critical note left visible, then a `-A discard=Discard` note queued behind it | the queued note expires after 30 s, and its `notify-send` exits with no output |
| N14 | DND on, `notify-send -u critical -a demo-app "Disk almost full" "fictional test"` | nothing drawn, reason 1 after 5 s |
| N15 | a note visible, click on a workspace button | the workspace switches (overlay mask) |
| N16 | idle after all cases | screenshot identical to the idle bar before the cases |
| N17 | fullscreen test client, a plain note, fullscreen off after 10 s; then the same with 35 s | first run: the note appears after the exit. Second run: nothing appears, the note is in history, reason 1 |
| N18 | two `-u critical -a battery-appindicator` notes 1 s apart, neither clicked, checked after 60 s | both still tracked, the newer one visible with `+1`, and dismissing it shows the older one |

N5 and N6 save frame series (`tests/frames.py`: shots at 0, 60, 120, 300 and 900 ms, each stamped with its frame time). N6 also saves palette sheets in both themes and checks that a click dismisses the OSD. B7 covers the OSD, the screenshot note with its card over the client, the held plain note and its appearance once fullscreen ends. N7 uses real clicks (`tests/nested.sh click`) on the card and the note line, and saves a frame series of the card rising after the wipe and falling before the leave.

`tests/matrix.sh` has twelve more cases:

- `SC`: `GetCapabilities` and the `screenshot.sh` contract of section 12 through IPC (`invoke discard` prints `discard`, the 10 s timeout prints nothing).
- `NX`: paths where a notification could get stuck or lose its place. A `resident` notification after its action, `replaces_id` updates of waiting and hidden notifications, and the order of `dismissAll`.
- `RP`: rapid OSD presses. Key repeat (30 presses 40 ms apart), a press during the fade-out and a reload while an OSD shows. One overlay map and one entry animation each time, an opaque fill in every frame of the key repeat, a fading strip in the frames before the late press, and no entry after the reload.
- `ON`: an OSD over an open note. The overlay is already mapped, so the entry runs without a new surface. The note pauses under the strip, then comes back with its timer and its input mask.
- `HO`: the handoff of section 2. With the note view held at its first and last frame, both frames and the bar after the unmap are pixel-identical to the idle bar.
- `NW`: the width rule of section 3. Beside the `present:` stand-in the mode shows in full, beside a longer fictional mode it elides so that the span keeps 600 px, and it comes back in full after the note.
- `CPU`: the idle cost of section 7. `top -b -n 5 -d 1` on the bar process, saved to `.test/logs/m4/cpu-idle.log`.
- `HV`: the hover pause of section 8. A frame series with the pointer on a 3 s note from 1 s to 4 s (the progress line stands still, the note closes after 6 s), the marquee standing still under the pointer, the card counting as the note, no hover left behind after an unmap under the pointer, and a note that opens under a resting pointer paused at once (Q21).
- `CL`: clicks per the rules table. A left click runs the default action, a right click only dismisses, a left click dismisses a critical without actions, a middle click dismisses the note and the whole queue, also from an OSD over a note.
- `HP`: hotplug (section 11). `create_output` and an unplug while a note shows on HEADLESS-1, then an unplug of the output that shows a critical and an OSD. The bar of HEADLESS-1 keeps its serial, connects and hides and its 1176 px workspace, the new overlay never maps, both notifications move to HEADLESS-1, and the Quickshell log gets no warning.
- `TH`: `theme set light` during an OSD and during a note (section 10). No map, no entry, no update, the bar kept, and frame series where the colors crossfade from dark to light without going back, the bar and the overlay showing the same color in every frame (M7, Q26).
- `END`: nothing is left tracked and the overlay is unmapped. It runs last, right after N16.

N1, N3 and N4 also save frame series of the bar strip (`tests/strip-frames.py`, with the slow-motion factor of the `debug` target), N2 and N15 at normal speed.
