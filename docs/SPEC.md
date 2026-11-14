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
- The upper 72 px exist only for the rich card. They are outside the mask and transparent.
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
- The mode name always shows in full while no note is visible. The `present:` mode doubles as a cheat sheet (`~/.config/sway/config.d/60-bindings-present.conf`), and waybar cuts it short today. The text only elides on the right if a note would otherwise get less than 600 px.

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

Center span: while a note is visible, it runs from the end of the left section (plus 8 px) to the start of the tray (minus 8 px). From left to right, it holds the compact clock `HH:mm`, a `│` separator in `base03`, then the note line.

Note line, left to right:

- Icon (16 px), from `image` or `appIcon` through `Quickshell.iconPath()`. Browsers and chat apps often send `image-data` (avatars, site icons). Outside rich mode, that image only fills this icon.
- App name in `base04`, summary in `base07`, body in `base05`.
- Newlines in the body become ` · `. The body advertises and renders a safe markup subset (`<b>`, `<i>`, `<u>`), and other tags are stripped.
- While others wait, a counter `+N` sits at the right end of the span.

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

Timeout resolution: a positive `expireTimeout` from the sender wins (the OSD senders pass 800 ms). `-1` takes the rule's value. `0` never expires. One exception overrides all three: a notification that DND hides always expires after 5000 ms, because nobody can click a notification that is never drawn.

Fullscreen (decision D5): a notification whose rule does not show over fullscreen waits in the queue while its target output shows a fullscreen window. This matches what the owner sees today, since mako's normal notifications were on the top layer, under fullscreen windows. OSDs, screenshots and critical notifications still show over the fullscreen window. Screenshots get the same reasoning as their DND exception in the mako config: they answer a key press, and without them a successful shot looks like nothing happened.

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
4. **DND.** A notification hidden by DND stays tracked, and a 5000 ms timer starts at once, whatever its rule's timeout (a hidden critical with timeout "none" would otherwise never close). It expires silently (`NotificationClosed` reason 1) and goes to history.
5. **Synchronous tag.** If `hints["x-canonical-private-synchronous"]` matches a tracked notification, the old one is closed with `expire()`. The OSD keeps its surface and animates from the old value to the new one, and the timer restarts. The OSD senders never pass `replaces_id`, so this is the only replacement path they use.
6. **`replaces_id` updates.** The server updates the existing object and emits no new `notification` signal. Views bind to the properties (`summary`, `body`, `hints`, `urgency`, `image`). The core listens to `expireTimeoutChanged`, `hintsChanged`, `summaryChanged` and `bodyChanged` to restart the timer.
7. **Queue.** One note is visible at a time:
   - Order: critical notifications first (newest first), then the others in arrival order (oldest first).
   - An OSD draws above the current note. The note's timer pauses and resumes once the OSD leaves.
   - A critical notification pushes the current note back to the front of the queue with its remaining time. A newer critical also takes the span from an older one, which goes back to the front of the queue. `battery-appindicator` sends 20 %, 5 % and suspend warnings in a row, and the latest one must be the one on screen.
   - While the target output shows a fullscreen window, notes whose rule does not show over fullscreen stay in the queue (decision D5). The first one appears when the fullscreen window leaves.
   - A notification that has waited 30 s in the queue without being shown expires into history (reason 1). This includes notes held during fullscreen, so most notes that arrive during a film end up in history. Critical notifications are exempt: they stay until clicked (decision D2), so they wait in the queue as long as needed. Blocking senders such as `screenshot.sh` would otherwise wait for as long as the queue lasts.
8. **Timers.** The server has no expiry timer, so all timers live in QML. Expiry calls `n.expire()` (reason 1). A dismiss click calls `n.dismiss()` (reason 2). An action click calls `action.invoke()`, which emits `ActionInvoked` and then closes with reason 2 unless the notification is `resident`. A sender's `CloseNotification` closes with reason 3, and the views react to the `closed` signal. Every tracked notification must close eventually.
9. **History.** The last 20 closed notifications whose rule keeps history and that are not `transient`. Entries are plain objects (app, summary, body, urgency, time), not `Notification` objects, kept across reloads in a `property list<var>` of a `PersistentProperties`. A `property var` holding a JS array comes back `undefined` after a reload (spike S8). `restore()` shows the newest entry again as a note without actions.
10. **State.** `state.json` under `Quickshell.stateDir` stores the DND flag and the last theme mode. With no state file, DND starts off (decision D6).

## 7. Animation

Durations and easing curves are starting values for tuning. They live in one `Motion.qml` singleton.

Note:

- **Enter.** The overlay maps showing exactly the bar's idle center. The clock compacts from `yyyy-MM-dd HH:mm` to `HH:mm` while sliding to the left edge of the span (240 ms, `Easing.OutCubic`). The separator appears, then the note wipes in from the separator to the right end of the span (320 ms, `Easing.OutCubic`). The span background (`base01`) grows with the wipe. The leading edge is a 2 px `base0D` line with a soft glow (`MultiEffect`, or the shader from M7). The text sits at its final position and is revealed by the clip, so it does not move.
- **Stay.** A line wider than the space it has holds for 1200 ms, then scrolls left at 60 px/s. It holds for 1000 ms at the end, then fades back to the start in 150 ms. A 2 px progress line on the top edge of the span shrinks to zero over the timeout (`base03`, `base07` on critical).
- **Leave.** The note retracts into the separator (240 ms, `Easing.InCubic`). Then the clock slides back to the center and expands to the full format (240 ms, `Easing.OutCubic`). The overlay unmaps on the frame that matches the bar's idle center.
- **Next in queue.** While the span is open, the old line moves up out of the strip and the new one comes in from below, 200 ms (`Easing.OutQuad`). The clock stays compact, and there is no second wipe.

OSD (full width):

- **Enter.** The strip fades in over 100 ms while the fill grows from 0 to the value in 180 ms (`Easing.OutCubic`).
- **Update** (same synchronous tag): the fill width animates to the new value in 120 ms (`Easing.OutQuad`).
- **Leave.** Fade out over 150 ms, back to the bar (or to the open note span).
- The label (the summary, for example `Brightness: 40%`) is drawn twice and split at the fill edge with clipping: `base05` over the empty part, `base00` over the filled part. It stays readable at 0 % and at 100 %, which matters for the muted microphone (value 0).

Critical: the leading-edge glow pulses between 0.4 and 1.0 opacity with a 1600 ms period while shown.

Rich: the card slides up from behind the strip in 220 ms (`Easing.OutCubic`) after the note's wipe, and slides back down before the note leaves.

Cost: no animation runs while idle. The overlay is unmapped, the bar redraws only when its content changes, and the marquee, pulse and blink timers stop when nothing uses them.

## 8. Input

- Overlay clicks land only on drawn content. Everything else reaches the bar.
- Note clicks follow the rules table. A middle click dismisses the current notification and the whole queue.
- Hovering a note pauses its timer and its marquee. Leaving resumes both.
- An OSD covers the whole bar for up to 2 s. A click on it dismisses it.
- Tray menus open as popups of the bar window. They are the only part of bar that may need keyboard input. Spike S9 showed that they get none while the bar's keyboard focus is `None`: arrow keys and Escape go to the focused window, and the menu only reacts to the pointer. Switching to `WlrKeyboardFocus.OnDemand` once a menu is open does not help, because sway gives the focus on a click and that click has already happened. What works is `OnDemand` while the pointer is on the tray or a menu is open: the opening click then focuses the bar, and the focus returns to the window when the menu closes. `OnDemand` at all times is ruled out, since the bar would keep the keyboard after any click on it. Whether menus get keyboard input at all is question Q2 in `PLAN.md` section 8. Until it is answered, the bar stays at `None`.

## 9. Inter-Process Communication (IPC)

Calls use `quickshell ipc -p <config dir> call <target> <function> [args]`. Typed arguments follow what `IpcHandler` supports in this snapshot (check with `quickshell ipc --help`).

`notify` target:

| Function | Effect |
|---|---|
| `toggleDnd(): bool` | flips DND and returns the new state |
| `setDnd(on: bool)` | sets DND |
| `dnd(): bool` | returns the DND state |
| `dismiss()` | dismisses the current notification |
| `dismissAll()` | dismisses the current notification and the queue |
| `restore()` | shows the newest history entry again |
| `invoke(action: string)` | invokes the named action on the current notification |
| `status(): string` | JSON `{dnd, visible, kind, queued, current: {id, app, summary}}`, for tests and scripts |

`theme` target: `set(mode: string)` with `dark` or `light`, and `mode(): string`.

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
- A theme change only changes the bound color properties. It never calls `Quickshell.reload()`, which would unmap the bar.

## 11. Outputs

- One bar window and one overlay window per screen, through `Variants { model: Quickshell.screens }`.
- Each bar shows the workspaces of its own output. The clock and tray appear on every bar.
- Fullscreen state per output comes from sway IPC: `swaymsg -t get_tree` at startup, then `window` events (`fullscreen_mode` changes) and `workspace` events through an `I3IpcListener`. An output counts as fullscreen when its visible workspace holds a fullscreen container, or when a global fullscreen window exists.
- A notification shows on the output that is focused when it becomes visible (`I3.focusedMonitor.name` matched to `ShellScreen.name`) and stays there until it leaves. OSD updates with the same synchronous tag stay where the OSD started.
- Plugging or unplugging an output (dock) must not crash the shell or leave a stale surface.

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
| N12 | second output (`swaymsg create_output`), focus moved to it | next note shows on the focused output |
| N13 | a critical note left visible, then a `-A discard=Discard` note queued behind it | the queued note expires after 30 s, and its `notify-send` exits with no output |
| N14 | DND on, `notify-send -u critical -a demo-app "Disk almost full" "fictional test"` | nothing drawn, reason 1 after 5 s |
| N15 | a note visible, click on a workspace button | the workspace switches (overlay mask) |
| N16 | idle after all cases | screenshot identical to the idle bar before the cases |
| N17 | fullscreen test client, a plain note, fullscreen off after 10 s; then the same with 35 s | first run: the note appears after the exit. Second run: nothing appears, the note is in history, reason 1 |
| N18 | two `-u critical -a battery-appindicator` notes 1 s apart, neither clicked, checked after 60 s | both still tracked, the newer one visible with `+1`, and dismissing it shows the older one |
