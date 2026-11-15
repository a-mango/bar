# bar: build plan

This plan splits the build of bar (behavior in `SPEC.md`) into milestones that an agent can take one at a time. Each milestone lists its tasks and the evidence required before it counts as done. Milestones M0 to M7 run only inside an isolated nested sway session with a private D-Bus. M8 replaces waybar and mako on the live desktop and starts only after the owner's explicit go-ahead in the session.

## Contents

1. Decision record
2. Verified facts
3. Repository layout
4. Test harness
5. Milestones
6. Cutover and rollback
7. Decisions
8. Spike results

## 1. Decision record

- **2026-11-10, goal.** Show every notification, OSDs included, in the bottom bar, with animation, and draw nothing extra while idle.
- **2026-11-10, toolkit.** Quickshell was picked over a waybar module, SwayNotificationCenter, Eww, GTK4 with `gtk4-layer-shell`, and a hand-written C client. It is packaged in Fedora 44, renders through the GPU with eased animations, `MultiEffect` and OpenGL Shading Language (GLSL) shaders, reloads live, and ships a notification server, a tray watcher and sway IPC support.
- **2026-11-10, notification server.** Quickshell owns the notification bus name itself. mako's API drops the hints the OSDs need (section 2), so a bridge would have needed D-Bus eavesdropping and would still have required rewriting the DND rules.
- **2026-11-11, no mako.** DND, screenshot and critical notifications live in bar. mako is uninstalled at cutover.
- **2026-11-11, no waybar.** bar draws the whole bar: workspaces and sway mode on the left, notifications and clock in the center, tray on the right. One process means no overlay alignment with a foreign bar.
- **2026-11-11, placement.** Notes grow out of the clock and fill the center span. OSDs take the full width.
- **2026-11-11, layers.** The bar window sits on the bottom layer with an exclusive zone, as waybar does. Transient content goes in a separate overlay-layer window, so that OSDs and critical notifications show over fullscreen windows.
- **2026-11-11, detail decisions.** D1 to D6 are answered in section 7.

## 2. Verified facts

These were checked on 2026-11-10 and 2026-11-11. Re-check a fact before relying on it if the package versions change.

### System

- Fedora 44, sway 1.11, waybar 0.15.0, mako 1.11.0, darkman 2.2.0.
- Quickshell `0.2.1^git20260209.dacfa9d-5.fc44` and `qt6-qtdeclarative-devel` 6.11.2 (for `qmllint`, at `/usr/lib64/qt6/bin/qmllint`) are installed since 2026-11-11. Qt 6.11.2 `qtbase`, `qtdeclarative`, `qtshadertools` (provides `qsb`) and `qt5compat` are installed. `node` v22, `python3-dbus-next`, `python3-tenacity`, Pillow, ImageMagick 7, `grim`, `wtype` and `wf-recorder` are available. foot, weston, `wlrctl` and `python3-pywayland` are not installed.
- eDP-1 is 1920x1200 logical at scale 2. External outputs come and go with the docks.
- waybar runs as `waybar -b bar-0` from the `bar {}` block in `~/.config/sway/config.d/90-bar.conf`. Its config has no `"ipc": true`, so it ignores sway's `mode hide`. The bar is always docked and 24 px high (the workspace is 1176 px tall out of 1200), and `$mod+m` (`bar hidden_state toggle`) does nothing.
- sway modes: `resize`, `passthrough` and the `present:` cheat-sheet mode (`60-bindings-present.conf`), whose name waybar cuts short.
- Session units: `sway-session.target` exists (sway-systemd). `95-xdg-desktop-autostart.conf` runs `/usr/libexec/sway-systemd/wait-sni-ready`, which waits up to 25 s (`SNI_WAIT_TIMEOUT`) for `org.kde.StatusNotifierWatcher` with `IsStatusNotifierHostRegistered`, then starts `sway-xdg-autostart.target`.
- Tray: 11 items were registered on 2026-11-11 (blueman, pasystray, nm-applet, solaar, gammastep, udiskie, `battery_app`, among others), most through libayatana-appindicator. waybar currently owns the watcher.
- mako starts through D-Bus activation: `/usr/share/dbus-1/services/fr.emersion.mako.service` has `Name=org.freedesktop.Notifications` and `SystemdService=mako.service`. `mako.service` is disabled and only ever activated. No installed package requires or recommends mako.
- mako's API (`ListNotifications`, `makoctl list -j`) drops every hint (no `value`, no image) and the timeout. mako was in DND mode when this was written.
- darkman: `darkman get` prints the current mode (`dark` or `light`). Hooks live in `~/.local/share/darkman/` (`waybar.sh`, `sway.sh`, `rofi.sh`). darkman runs every file in that directory that has the executable bit set, whatever its extension (`man darkman`). It runs as the `darkman.service` user unit. On 2026-11-11 its environment had `WAYLAND_DISPLAY=wayland-1`, but at login it may start before sway exports that variable. `sway.sh` avoids `swaymsg reload` because reloading respawns the bar and re-tiles every window.

Notification senders:

- `~/bin/volume-helper`: app `volume`, `--expire-time 800`, `--transient`, synchronous tag `volume`, `int:value`.
- Brightness and microphone bindings in `~/.config/sway/config.d/60-bindings-brightness.conf` and `60-bindings-volume.conf`: same pattern with apps `brightness` and `microphone`.
- `~/Documents/scripts/screenshot.sh`: app `screenshot`, `-i <file>`, `-A discard=Discard`, blocking in a background subshell.
- `~/bin/battery-appindicator`: Rust binary sending over zbus. Its battery alerts are critical.

### Quickshell snapshot `dacfa9d`

Source: the `.qmltypes` files from the RPM (installed under `/usr/lib64/qt6/qml/Quickshell/`) and the upstream source at commit `dacfa9d`.

General:

- The binary is `quickshell`. The RPM ships no `qs` symlink.
- Command-line flags:
  - `-p/--path` selects a config directory, `-c` a named config.
  - `-d` daemonizes, `--no-duplicate` refuses a second instance of the same config. The help text lists `-n` for both `--newest` and `--no-duplicate`, so scripts and units use the long forms.
  - The subcommands are `ipc`, `log` and `list`.
  - IPC only sees instances on the current Wayland display unless `--any-display` is passed.
- Modules are imported with `import qs.path.to.module` (since 0.2.0). The `Quickshell` module exports `Singleton`, `PersistentProperties`, `Variants`, `Region`, `ScriptModel`, `LazyLoader`, `SystemClock`, `QsMenuAnchor` and `QsMenuOpener`. The `Quickshell` global has `stateDir`, `statePath()`, `iconPath()`, `screens`, `watchFiles` and `reload()`.

Windows:

- `PanelWindow`: `anchors`, `margins`, `exclusiveZone`, `exclusionMode` (`Normal`, `Ignore`, `Auto`), `aboveWindows`, `focusable`. `QsWindow` adds `mask` (a `Region`), `visible`, `screen` and `color`.
- `WlrLayershell`: `layer` (`Background`, `Bottom`, `Top`, `Overlay`), `namespace`, `keyboardFocus` (`None`, `Exclusive`, `OnDemand`).
- `PopupWindow` (`parentWindow`, `relativeX`, `relativeY`, `anchor`, `grabFocus`) and `FloatingWindow` (a normal toplevel, usable as a fullscreen test client).

Notifications (`Quickshell.Services.Notifications`, source `src/services/notifications/`):

- `NotificationServer` properties: `keepOnReload`, `bodySupported`, `bodyMarkupSupported`, `actionsSupported`, `imageSupported`, `persistenceSupported`, `extraHints`, `trackedNotifications`. It has one signal, `notification(n)`.
  - A notification that is not tracked when the handler returns is closed and deleted at once.
  - A `replaces_id` update calls `updateProperties` on the existing object. No new `notification` signal fires.
  - On reload with `keepOnReload`, tracked notifications are re-emitted with `lastGeneration = true`.
  - If the bus name is taken, the server logs a warning and retries when the owner leaves (`QDBusServiceWatcher`).
- `Notification`:
  - Properties: `id`, `tracked`, `lastGeneration`, `expireTimeout`, `appName`, `appIcon`, `summary`, `body`, `urgency`, `actions`, `resident`, `transient`, `desktopEntry`, `image`, `hints`.
  - Methods: `expire()`, `dismiss()`. Signal: `closed(reason)`.
  - `hints` holds every hint except image data: `image-data`, `image_data`, `icon_data` and `image-path` become `image`. So `value` and `x-canonical-private-synchronous` arrive in `hints`.
- The server runs no expiry timers.
- `NotificationAction.invoke()` emits `ActionInvoked(id, identifier)`, then closes the notification as Dismissed unless it is `resident`.
- Close reasons are `Expired`, `Dismissed` and `CloseRequested`, sent as D-Bus reasons 1, 2 and 3.

Tray and sway:

- `Quickshell.Services.SystemTray`: `SystemTray.items`. `SystemTrayItem` has `id`, `title`, `status` (`Passive`, `Active`, `NeedsAttention`), `category`, `icon`, `tooltipTitle`, `tooltipDescription`, `hasMenu`, `menu`, `onlyMenu`, and the methods `activate()`, `secondaryActivate()`, `scroll()` and `display()`.
- The watcher (`src/services/status_notifier/watcher.cpp`) registers `org.kde.StatusNotifierWatcher` and retries when the current owner leaves.
- `Quickshell.I3`: the `I3` singleton (`focusedMonitor`, `focusedWorkspace`, `monitors`, `workspaces`, `dispatch()`), `I3Monitor` (`name`, `focused`, `scale`, `focusedWorkspace`), `I3Workspace` (`name`, `number`, `focused`, `active`, `urgent`, `monitor`, `activate()`). It works with sway. `I3IpcListener` (`subscriptions`) delivers `I3Event` objects (`type`, `data`) for events such as `mode`.
- `Quickshell.Io` provides `FileView`, `Process`, `SplitParser` and `IpcHandler` (`target`, `enabled`).

## 3. Repository layout

M0 creates this tree, and later milestones fill it in:

```
bar/
  CLAUDE.md               agent guide: commands, rules, gotchas
  Makefile
  shell.qml               ShellRoot: services, bar and overlay per screen, IPC handlers
  services/
    Notifs.qml            Singleton: NotificationServer, queue, timers, DND, history
    Rules.js              pure JS rules and classify(), no QML imports
    Markup.js             pure JS text of the note line (body markup subset)
    StateFile.qml         Singleton: state.json (theme mode, DND), one key per service
    Theme.qml             Singleton: palettes, darkman mode, theme IPC
    Motion.qml            Singleton: durations and easing curves
    Sway.qml              Singleton: workspaces per output, binding mode
  bar/
    Bar.qml               PanelWindow (Bottom layer) per screen
    BarText.qml           text line with the bar font, spacing and vertical position
    Workspaces.qml
    Mode.qml
    Clock.qml             clock and calendar popup
    Calendar.qml          month grid of the calendar popup
    Tray.qml
  overlay/
    Overlay.qml           PanelWindow (Overlay layer) per screen, mask, kind switching
    OsdView.qml
    NoteView.qml
    RichView.qml
  themes/
    base16-default-dark.css
    base16-default-light.css
  shaders/
    wipe.frag             compiled to wipe.frag.qsb by make shaders
  tests/
    nested.sh             headless sway on a private bus, running quickshell on this tree
    sway-nested.conf      minimal sway config for the nested session
    session.conf          private D-Bus config without service directories
    matrix.sh             the SPEC.md test matrix
    scene.sh              puts a nested session into a known state (workspaces, mode, tray)
    vpointer.py           virtual pointer, so that seat cursor commands reach clients
    pixel.py, rows.py, pixdiff.py   screenshot checks in logical px
    frames.py             frame series: commands and region shots on a schedule (M3)
    strip-frames.py       frame series of the bar strip with slow motion (grim grabs, M4)
    lint.sh               qmllint with the qs.* modules resolved
    bin/darkman           darkman stand-in on the nested PATH
    fake-sni.py           fake tray item with a menu (python3-dbus-next)
    fake-screenshot.sh    the notify part of screenshot.sh, without grimshot or gio trash
    client/shell.qml      FloatingWindow test client (urgent and fullscreen cases)
    rules.test.mjs        node --test unit tests for services/Rules.js
    markup.test.mjs       node --test unit tests for services/Markup.js
  packaging/
    bar.service                                 systemd user unit (M8)
    org.freedesktop.Notifications.service       D-Bus activation file (M8)
    darkman-bar.sh                              darkman hook (M8)
    sway-bindings.conf                          notification keys, decision D3 (M8)
  docs/
    SPEC.md
    PLAN.md
    reference/            waybar and mako configs that bar replaces (read-only)
```

`.test/` holds all runtime output (sockets, bus address, logs, screenshots, the test state directory) and is ignored by git.

## 4. Test harness

`tests/nested.sh` starts an isolated desktop:

1. `dbus-run-session --config-file=tests/session.conf` starts a private session bus. `session.conf` lists no service directories, so a notification sent before Quickshell is ready cannot activate mako, which stays installed until cutover.
2. Inside it, `env -i` keeps only `HOME`, `PATH`, `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`. It then sets `SWAYSOCK=$REPO/.test/sway.sock`, `WLR_BACKENDS=headless`, `WLR_LIBINPUT_NO_DEVICES=1`, `XDG_STATE_HOME=$REPO/.test/state` and `XDG_CACHE_HOME=$REPO/.test/cache`, and starts `sway -c $REPO/tests/sway-nested.conf`. Every path is absolute (`$REPO` is the repository root). A relative `XDG_*` value is likely to be ignored, which would put test state in the real `~/.local/state`.
3. `sway-nested.conf`:
   - `xwayland disable`
   - `output HEADLESS-1 mode --custom 3840x2400 scale 2`, to match eDP-1
   - the modes used by case B3: `resize`, and a mode named like the `present:` cheat sheet
   - no `bar {}` block
   - `exec quickshell -p $REPO`
   - an `exec` that writes `$WAYLAND_DISPLAY` and the bus address to `$REPO/.test/env`
4. The script waits until `org.freedesktop.Notifications` has an owner on the private bus (`gdbus call` to `GetNameOwner`) before returning.

As built in M0, the two `exec` lines are one: `exec "$BAR_REPO/tests/nested.sh" _inside`. That step writes `.test/env`, starts `tests/vpointer.py` (spike S4) and then the client of the chosen variant: `bar` (quickshell on this tree), `bare` (nothing, for spike S5) or `waybar` (`make reference`). `NESTED_DIR` selects the runtime directory, so the reference session uses `.test/reference/`.

Using the session:

- `tests/nested.sh run <command>` runs a command inside the session under `env -i`, so nothing from the live session leaks in. It is the safe way to run `notify-send`, `grim -o HEADLESS-1`, `quickshell ipc -p $REPO call ...`, `tests/fake-sni.py` and the test client. `source .test/env` also works in a shell that is used for nothing else.
- Clicks: `tests/nested.sh click <x> <y> [button]` in logical coordinates. It runs `swaymsg seat seat0 cursor set <x> <y>`, then `cursor press` and `cursor release`. These only reach clients because `tests/vpointer.py` gives the headless seat a pointer (spike S4).
- Keys: `tests/nested.sh run wtype -k <key>`. For a test that depends on keyboard focus, hold a keyboard on the seat first with `wtype -s 3600000` in the background.
- Image checks: `tests/rows.py` summarizes the rows of a screenshot, `tests/pixdiff.py` compares two screenshots exactly, `tests/pixel.py` reads colors, runs and color counts in logical px.
- Frame series: `tests/nested.sh run tests/frames.py <dir> "<ms> run <command>" "<ms> shot" ...` starts commands and screenshots of a region (default: the overlay window) on a schedule. Each shot carries the time of the frame it shows, from the compositor's `ready` event. It does not use grim, whose full-output readback slows the compositor down (M3 findings in section 8). It writes `t<ms>.png`, `frames.json` and a contact sheet `sheet.png`.
- Outputs: `swaymsg create_output` and `output HEADLESS-2 unplug` simulate a dock.
- Test client: `quickshell -p $REPO/tests/client` opens a `FloatingWindow`. `swaymsg` makes it urgent or fullscreen.
- Tray: `tests/fake-sni.py` registers a fake item with a menu and logs every call to `.test/logs/fake-sni.log`.
- Bus log: `dbus-monitor` on the private bus, saved to `.test/logs/`.
- Quickshell log: `quickshell log -p $REPO` with the nested `WAYLAND_DISPLAY`.
- `make reference` starts a second nested session running waybar with `docs/reference/waybar/config.jsonc` and `style.css` (plus a `base16-theme.css` copy of the dark palette next to them), and saves a screenshot of its bar. It is the visual target for M2.

## 5. Milestones

Dependencies:

| Milestone | Starts after | Session model and effort |
|---|---|---|
| M0 bootstrap and spike | | Fable 5.2, `high` |
| M1 notification core | M0 | Fable 5.2, `high` |
| M2 bar | M0 | Opus 5.5, `xhigh` |
| M3 OSD view | M1 | Opus 5.5, `xhigh` |
| M4 note view | M1 and M2 | Opus 5.5, `xhigh` |
| M5 rich mode and input | M4 | Opus 5.5, `xhigh` |
| M6 outputs and theme transitions | M2 and M3 | Opus 5.5, `xhigh` |
| M7 polish | M5 and M6 | Opus 5.5, `high` |
| M8 cutover | M7 | Fable 5.2, `high` |

M1 and M2 run in parallel, then M3 and M4, then M5 and M6. Each milestone gets its own branch (`mN-slug`).

Model choice: Fable 5.2 takes the milestones where a mistake is expensive or hard to see. M0 lays the harness and answers the unknowns, M1 holds the D-Bus contract and the rule that every notification closes, and M8 changes the live desktop. Fable 5.2 works best from `high` effort, with uneven gains above it. Opus 5.5 at `xhigh` builds the UI milestones, which have clear specs and screenshot checks. M7 is a quick back-and-forth with the owner, so it runs at `high`.

### M0: bootstrap and spike

Done on 2026-11-12 (branch `m0-bootstrap`). Results are in section 8, with two open questions for the owner.

Tasks:

1. Create the layout from section 3, the `.gitignore` (`.test/`) and a `Makefile` with the targets listed in `CLAUDE.md`.
2. Write `tests/nested.sh`, `tests/sway-nested.conf`, `tests/session.conf` and `make reference` as described in section 4. The script cleans up the nested sway on exit or interrupt.
3. Write a minimal `shell.qml`: a bottom-layer bar with a static label per screen, and an overlay that shows a solid `base0D` strip through a temporary IPC function `notify.debugShow(on: bool)`.
4. Write `tests/client/shell.qml` and a first version of `tests/fake-sni.py`.
5. Run the spikes below and write each result, with evidence paths, into section 8.

Spikes:

- **S1** The bar's exclusive zone works at scale 2: with bar running, the workspace rect is 1176 px tall (`swaymsg -t get_workspaces`).
- **S2** The overlay lies on the bar: with `ExclusionMode.Ignore`, the overlay's bottom edge is the output's bottom edge, not 24 px above it. Proof: a screenshot of the bottom 30 px, with the strip covering exactly the bar's rows.
- **S3** The overlay mask passes input through: with the strip shown over part of the bar only, a click on a bar label outside it reaches the bar. With the overlay unmapped, no surface remains.
- **S4** `seat seat0 cursor` commands synthesize clicks in headless sway. If they do not, input tests go through IPC, and clicks become a manual check in M8.
- **S5** With `session.conf`, a `notify-send` sent before Quickshell starts fails, and no mako process appears.
- **S6** A fullscreen test client covers the bottom-layer bar, and the overlay strip still shows above it.
- **S7** Handoff: a screenshot of the idle bar center and one of the overlay's first frame, drawing the same clock, are identical (`compare -metric AE` from ImageMagick, or a small Python diff).
- **S8** `PersistentProperties` keeps a `var` array of plain objects across a reload.
- **S9** Tray: `SNI_WAIT_TIMEOUT=10 /usr/libexec/sway-systemd/wait-sni-ready` exits 0 in the nested session. The fake item appears, and its menu opens through `QsMenuAnchor` from the bottom-layer bar. Sub-check: the menu accepts arrow keys and Escape while the bar's keyboard focus is `None`. Record whether `OnDemand` is needed.
- **S10** sway events: an `I3IpcListener` subscribed to `mode` receives the event after `swaymsg mode resize`, and `swaymsg -t get_binding_state` gives the initial mode. A listener subscribed to `window` receives `fullscreen_mode` changes when the test client goes fullscreen and back (needed for decision D5). Note the format `subscriptions` expects.
- **S11** Setting `Quickshell.watchFiles` to false stops the reload when a file changes. The live copy (M8) depends on it.

Done when: `make nested` and `make reference` start and stop cleanly twice in a row, and section 8 holds all eleven results.

### M1: notification core

Tasks:

1. `services/Rules.js` with the table from SPEC section 5, and `tests/rules.test.mjs` covering every row, the timeout resolution and the DND exceptions.
2. `services/Notifs.qml`:
   - `NotificationServer` with `keepOnReload: true`, `bodySupported`, `bodyMarkupSupported`, `actionsSupported` and `imageSupported` set to true.
   - Tracking on arrival, re-tracking of reload survivors, timers per SPEC section 6, the queue with its 30 s limit, synchronous-tag replacement and the reaction to `replaces_id` updates.
   - DND and the last theme mode in `state.json` under `Quickshell.stateDir`, DND off by default (decision D6). History in `PersistentProperties`.
3. The `notify` IPC handler with every function from SPEC section 9.
4. A debug view in the overlay: the current notification as plain text in the center, without animation.

Done when:

- `make test` passes.
- Matrix cases N1, N3, N5, N8, N9, N10, N11, N13, N14 and N18 pass, and the bus log shows the expected `NotificationClosed` reasons at the expected times.
- The `screenshot.sh` contract passes through IPC: `tests/fake-screenshot.sh` waits in the background, `quickshell ipc ... call notify invoke discard` makes it print `discard`, and a second run that just times out prints nothing and exits.

Status (2026-11-14, branch `m1-notifications`, stacked on `m2-bar`): `make test` passes with 27 tests (`.test/logs/m1/make-test.log`). The whole matrix passes on a fresh session (`.test/logs/m1/matrix.log`): the ten M1 cases, B1 to B6, and the added cases SC (the `screenshot.sh` contract and `GetCapabilities`), NX (resident actions, updates of waiting and hidden notifications, `dismissAll`) and END (nothing left tracked). The `NotificationClosed` reasons and times are in the bus logs of that run, `.test/logs/m1/bus-<case>.log` (read one with `tests/buslog.py <log>`), and the checked values in `.test/logs/m1/closed.log`. The overlay shows the debug view until M3 and M4. Seven spec gaps that M1 filled wait for the owner as Q3 to Q9 in section 8.

### M2: bar

Tasks:

- `bar/Bar.qml` per screen, with `Workspaces.qml`, `Mode.qml`, `Clock.qml` (with the calendar popup) and `Tray.qml`, per SPEC section 3.
- `services/Sway.qml` and `services/Theme.qml` (palettes in `themes/`, startup mode from `darkman get` with the state fallback, the `theme` IPC handler).

Done when:

- Matrix cases B1 to B6 pass.
- A screenshot of the idle bar next to the `make reference` screenshot shows the same layout, colors and font. The owner has compared the two.
- Dark and light screenshots exist, switched with `call theme set`.

Status (2026-11-14, branch `m2-bar`): B1 to B6 pass (`.test/logs/m2/matrix.log`). The comparison image is `.test/shots/m2/reference-vs-bar.png` (waybar on top), the theme shots are `.test/shots/m2/theme-dark.png` and `theme-light.png`. The owner's comparison is still owed, together with Q2 from section 8 (Q1 became decision D7).

### M3: OSD view

Tasks: `overlay/OsdView.qml` per SPEC sections 4 and 7, with fill colors from the rules and the split label.

Done when:

- Matrix cases N5 and N6 produce frame series (screenshots at 0, 60, 120, 300 and 900 ms).
- Rapid presses never show a second surface or replay the entry animation.
- Case B7 passes for the OSD part.
- The owner has looked at the frames.

Status (2026-11-15, branch `m3-osd`): the whole matrix passes on a fresh session, 23 cases in 4 min 43 s at commit `8ddaf8e` (`.test/logs/m3/matrix.log`).

- N5 keeps every M1 check and adds a frame series: requested at 0, 60, 120, 300 and 900 ms, the frames shown are from 2, 63, 128, 307 and 901 ms. It also checks one overlay map, one entry and four updates.
- N6 adds the brightness and microphone series at value 0, palette sheets in both themes, and a click that dismisses the OSD (reason 2).
- B7 passes for the OSD over a fullscreen client.
- Two new cases:
  - RP covers rapid presses: 30 presses 40 ms apart, a press during the fade-out (with a fading frame before it) and a reload, each with one map and no second entry.
  - ON covers an OSD over an open note: no new surface, the note paused, then back with its timer and its input mask.

The frames are in `.test/shots/m3/`:

- `N5-volume-frames.png`
- `N6-brightness-frames.png`, `N6-microphone-frames.png`
- `N6-palette-dark.png`, `N6-palette-light.png`
- `RP-fade-frames.png`, `RP-repeat-frames.png`
- `B7-osd-fullscreen.png`
- `ON-osd-over-note.png`

Their `frames.json` files and the N5 and N6 bus logs are in `.test/logs/m3/`. An earlier full run, `matrix-suspended.log`, failed N3 only because the laptop suspended in the middle of that case. `make test` passes 27 tests, and `make lint` shows the same 9 warnings as `main`, all from the Quickshell type files.

Still owed: the owner's look at the frames, and answers to Q10 to Q12 from section 8.

### M4: note view

Tasks:

- The center span and its width rule (SPEC section 4), the clock handoff (SPEC section 2).
- The entry and exit animations, the marquee, the progress line, the queue roll with its `+N` counter, and the critical style.

Done when:

- Matrix cases N1 to N4 and N15 produce frame series, and N16 passes.
- The first and last overlay frames match the idle bar center (the S7 method).
- With the long mode name active, the note still gets at least 600 px.
- The marquee does not start when the text fits.
- While idle, the Quickshell process stays near 0 % CPU (`top -b -n 5 -d 1 -p <pid>`, output saved to `.test/logs/`).

Status (2026-11-15, branch `m4-notes`): the whole matrix passes on a fresh session, 26 cases with exit status 0 (`.test/logs/m4/matrix.log`). That covers B1 to B6, every M1 case, and the M4 cases N2, N4, N15, N16, HO, NW and CPU. `make test` passes with 37 tests (`.test/logs/m4/make-test.log`), and `make lint` shows only the known warnings from the Quickshell type files (`.test/logs/m4/lint.log`). A first full run failed one NX timing check because the host suspended for 11 hours in the middle of it (`.test/logs/m4/matrix-suspended.log`, section 8). `.test/shots/m4/overview.png` stacks the key frames for review. The checks, one by one:

- Frame series: `.test/shots/N1/enter-series.png` and `leave-series.png`, `N2/marquee-series.png`, `N3/roll-series.png`, `N4/enter-series.png` and `pulse-series.png`, `N15/click-series.png`. N1, N3 and N4 use slow motion x10, so a 60 ms step is 600 ms of real time. Each sheet labels its frames with the nominal and the measured grab time. N16 passes: the idle bar after all cases matches the one before them, clock digits left out (`.test/shots/N16/`).
- Handoff (case HO, S7 method with a hold at both ends): the first frame, the last frame and the bar after the unmap each differ from the idle bar in 0 of 9,216,000 pixels (`.test/shots/HO/`).
- Long mode (case NW): beside the `present:` stand-in the label stays in full and the span gets 991 px. Beside a longer fictional mode the label elides and the span gets exactly 600 px, and the label is back in full after the note (`.test/shots/NW/`).
- Marquee (case N2): a line that fits has no overflow, no marquee and no offset, and its pixels do not move between 2 and 3.5 s. A 400-character body holds until about 1.8 s (wipe plus 1200 ms), then scrolls at a measured 60 px/s within the IPC jitter.
- Idle CPU (case CPU): the case first runs a marquee, a pulsing critical and a roll, checks that the view is idle with no pulse, marquee or roll left, then measures. After the whole matrix and that case, `top` shows 0.0 % on every sample and the process CPU time stays at 0:29.19 (`.test/logs/m4/cpu-idle.log`, `matrix-cpu.log`).
- Note line rendering, checked once by hand: a note sent with `-i <png>` and a body with `<b>`, `&amp;`, `<i>`, `<u>`, a newline and an `<img>` shows the icon, the three styles, `&`, ` · ` and no image (`.test/shots/m4/icon-markup.png`).

Clicks on the note (dismiss, actions) and the hover pause belong to M5: N4 dismisses its critical through IPC. Q13 to Q15 in section 8 list the choices M4 made (numbered Q10 to Q12 on the branch, renumbered at the merge with M3).

Merged into `main` with M3 on 2026-11-16: the whole matrix passes on a fresh session, 30 cases in 6 min 58 s (`.test/logs/merge/matrix.log`). Two checks changed after the merge. ON read the note background on the row of M4's progress line. HO's 1.5 s note could expire before the case's first release, because the full-output shot of the first frame takes about 0.9 s, and the release then ended the hold at the last frame (2 failures in 3 runs). HO now sends a 3 s note. M4's `tests/frames.py` is now `tests/strip-frames.py`, since M3's screencopy tool keeps the name.

### M5: rich mode and input

Builds decisions D1 (card for `screenshot` only) and D5 (hold notes during fullscreen) from section 7.

Tasks:

- `overlay/RichView.qml` and the card animation.
- Click handling per the rules table, the middle click and hover pause.
- The overlay mask for the card.
- Fullscreen tracking per output in `services/Sway.qml` (SPEC section 11) and the hold in the queue (SPEC sections 5 and 6).

Done when:

- Matrix case N7 passes all three outcomes with `tests/fake-screenshot.sh` and a generated PNG.
- Hover pause is shown by moving the cursor onto the note and back.
- Case B7 passes for the screenshot and plain-note parts, and case N17 passes.

### M6: outputs and theme transitions

Tasks:

- `Variants` over the screens for both windows, workspaces per output, focused-output selection for notifications, hotplug handling.
- Theme transitions while a note or an OSD is visible.

Done when:

- Matrix case N12 passes.
- `create_output` and `unplug` while a note is visible leave no error in the Quickshell log, and the remaining bar keeps its exclusive zone.
- `call theme set light` during an OSD changes colors without unmapping anything (the workspace rect height does not change).

### M7: polish

Tasks:

- The wipe edge as a GLSL shader (`shaders/wipe.frag`, built by `make shaders` with `qsb`), or a `MultiEffect` glow if the shader brings nothing visible.
- Tuning the `Motion.qml` values with the owner.
- A review session: frame series, or a `wf-recorder` clip of the nested output if that tool is installed.

Done when: the owner signs off on the visuals.

### M8: cutover

This milestone replaces waybar and mako on the live desktop. It starts only after the owner gives an explicit go-ahead in the session. See section 6.

Done when:

- bar owns `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher`.
- The live checks in section 6 pass, including a logout and login.
- The owner has used it for a day without rolling back.

## 6. Cutover and rollback

The live instance runs from a copy, with file watching off. Quickshell reloads whenever its files change, and a reload of the live bar would unmap it and re-tile every window.

Cutover steps:

1. `make install` copies the tagged tree to `~/.local/share/bar` (`rsync`, excluding `.git`, `.test`, `docs` and `tests`) and marks the copy as live, so that it sets `Quickshell.watchFiles` to false.
2. Install `packaging/bar.service` to `~/.config/systemd/user/`:
   - `[Unit]`: `PartOf=graphical-session.target`, `After=graphical-session.target`, `StartLimitIntervalSec=60`, `StartLimitBurst=5`
   - `[Service]`: `Type=dbus`, `BusName=org.freedesktop.Notifications`, `ExecCondition=/bin/sh -c '[ -n "$WAYLAND_DISPLAY" ]'`, `ExecStart=/usr/bin/quickshell -p %h/.local/share/bar --no-duplicate`, `Restart=on-failure`, `RestartSec=1`
   - `[Install]`: `WantedBy=sway-session.target`, so the watcher is up within `wait-sni-ready`'s 25 s at login

   Then run `systemctl --user daemon-reload` and `systemctl --user enable bar.service`.
3. Install `packaging/org.freedesktop.Notifications.service` to `~/.local/share/dbus-1/services/`: `Name=org.freedesktop.Notifications`, `Exec=/usr/bin/quickshell -p /home/acm/.local/share/bar --no-duplicate` (D-Bus files do not expand `%h`), `SystemdService=bar.service`.
4. The owner runs `systemctl --user stop mako.service && sudo dnf remove mako`. This also deletes mako's activation file, so bar's file is the only one claiming the name. Then ask the bus to reload (`busctl --user call org.freedesktop.DBus / org.freedesktop.DBus ReloadConfig`).
5. Count the tray items: `busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems` (11 on 2026-11-11).
6. In `~/.config/sway/config.d/90-bar.conf`, comment out the `bar {}` block first, so that no later `swaymsg reload` brings waybar back. Remove `bindsym $mod+m bar hidden_state toggle` (decision D4) and drop it live with `swaymsg unbindsym $mod+m`. Do not reload sway: `exec_always` entries (the wallpaper rotation) would run again.
7. `pkill -x waybar`, then check for 10 s that sway does not start it again.
8. `systemctl --user start bar.service`. Check that `busctl --user status org.freedesktop.Notifications` and `busctl --user status org.kde.StatusNotifierWatcher` both show `quickshell`, then count the tray items again. An applet that did not register again gets restarted, and its name goes in the CLAUDE.md gotchas.
9. darkman: `chmod -x ~/.local/share/darkman/waybar.sh` (renaming is not enough, since darkman runs any executable file in the directory). Install `packaging/darkman-bar.sh` as `~/.local/share/darkman/bar.sh` with the executable bit set. The hook calls `quickshell ipc --any-display -p ~/.local/share/bar call theme set "$1"` (SPEC section 10).
10. Install `packaging/sway-bindings.conf` as `~/.config/sway/config.d/60-bindings-notifications.conf` (decision D3: `$mod+n`, `$mod+Shift+n`, `$mod+Ctrl+n`, `$mod+Shift+d`). Apply each binding live with `swaymsg bindsym ...` (again without a reload).

Live checks, with fictional text where a notification is involved:

- All tray icons present. One menu opened and closed, with no entry clicked.
- A click on a workspace button, `$mod+r` for the `resize` label, the `present:` mode text in full.
- Clock toggle and calendar popup.
- One press each of the volume, brightness and microphone keys, also over a fullscreen window.
- A screenshot followed by a right click (the file must go to the trash).
- `$mod+Shift+d` twice (DND on and off), a plain note dismissed with `$mod+n` and brought back with `$mod+Ctrl+n`, then a critical note.
- A plain note sent while a fullscreen window is focused: it appears once fullscreen ends.
- `darkman toggle` twice.
- `systemctl --user restart bar.service`, then the tray count is back to its value from step 5.
- A logout and login: bar is up, and the tray count matches.

About a week later: `sudo dnf remove waybar` (optional), and archive `~/.config/waybar` and `~/.config/mako` (copies are in `docs/reference/`).

Rollback:

1. `systemctl --user disable --now bar.service`, then remove `~/.local/share/dbus-1/services/org.freedesktop.Notifications.service`.
2. `sudo dnf install mako`.
3. Restore the `bar {}` block in `90-bar.conf`, `chmod +x ~/.local/share/darkman/waybar.sh`, and remove `bar.sh`.
4. `swaymsg reload` to start waybar again (this one reload is accepted). Remove `60-bindings-notifications.conf`, and run `makoctl mode -a do-not-disturb` if DND is wanted.

## 7. Decisions

The owner answered these on 2026-11-11. A change to one of them is the owner's call, so agents ask before deviating.

| # | Question | Answer | Used in |
|---|---|---|---|
| D1 | Screenshots and other image notifications | 72 px thumbnail card above the center span, for the `screenshot` app only. Other apps' images fill the 16 px icon. | M5 |
| D2 | Critical notifications | Stay until clicked or closed by the sender (mako expired them after 5 s). | M1, M4 |
| D3 | Sway bindings | `$mod+n` dismiss, `$mod+Shift+n` dismiss all, `$mod+Ctrl+n` restore, `$mod+Shift+d` toggle DND. | M8 |
| D4 | `$mod+m` | Remove the binding. The bar has no hide function. | M8 |
| D5 | Notes over fullscreen windows | Hold them in the queue while the target output shows a fullscreen window. OSDs, screenshots and critical notifications still show. The 30 s queue limit applies, so long-held notes go to history. | M5 |
| D6 | DND at first start | Off. | M1 |
| D7 | Text rendering (Q1 in section 8) | The best possible rendering: Qt's native (FreeType) renderer, hinted, grayscale antialiasing. Answered 2026-11-14. | M2 |

## 8. Spike results

Run on 2026-11-11 and 2026-11-12 in the nested session (sway 1.11 headless, HEADLESS-1 at 3840x2400 scale 2, Quickshell `dacfa9d`). Each entry gives the result, the evidence in `.test/` and what it changes. `.test/` is not in git: `.test/logs/spikes/S<n>.log` holds the command output, `.test/shots/spikes/` the screenshots. The bar's 24 px are the physical rows 2352 to 2399 of a screenshot.

Summary:

| Spike | Result | Changes |
|---|---|---|
| S1 exclusive zone | pass | none |
| S2 overlay on the bar | pass | none |
| S3 overlay mask | pass | none |
| S4 synthetic clicks | pass, with a virtual pointer | harness: `tests/vpointer.py` |
| S5 no activation on the private bus | pass | none |
| S6 fullscreen layering | pass | none |
| S7 handoff | pass with grayscale text only | `shell.qml` pragma, decision D7 |
| S8 `PersistentProperties` | fails for `property var`, passes for `list<var>` | SPEC section 6 |
| S9 tray | pass, keys need `OnDemand` at click time | `shell.qml` pragma, SPEC sections 3 and 8, question Q2 |
| S10 sway events | pass | none |
| S11 `watchFiles` | pass | none |

### S1: exclusive zone at scale 2

Pass. With bar running, `swaymsg -t get_workspaces` gives the rect `1920x1176` on a `1920x1200` output at scale 2.

Evidence: `.test/logs/spikes/S1.log`.

### S2: the overlay lies on the bar

Pass. The overlay (`ExclusionMode.Ignore`, 96 px high, anchored left, right and bottom) puts its bottom edge on the output's bottom edge. With the full-width strip shown, rows 2352 to 2399 are one color (`#7cafc2`, `base0D`) over all 3840 columns, and rows 2340 to 2351 above them are unchanged. The Wayland trace shows `set_exclusive_zone(-1)` for the overlay and `set_exclusive_zone(24)` for the bar.

Evidence: `.test/logs/spikes/S2.log`, `.test/shots/spikes/S2-idle.png`, `S2-strip.png` and their `-bottom30` crops.

### S3: the overlay mask passes input through

Pass. With the strip drawn over the middle third only (`mask: Region { item: content }`):

- A click on the bar label at (40, 1188), inside the overlay window and outside its mask, reaches the bar.
- A click on the strip at (960, 1188) reaches the overlay and not the bar.
- The trace shows `wl_region.add(640, 72, 640, 24)` followed by `set_input_region`.

With the overlay unmapped, no surface remains. Quickshell creates the layer surface only when `visible` becomes true, and it sends `zwlr_layer_surface_v1.destroy` and `wl_surface.destroy` when `visible` becomes false. `swaymsg -t get_outputs` lists no layer surfaces in sway 1.11, so the proof is a `WAYLAND_DEBUG=1` trace.

Evidence: `.test/logs/spikes/S3.log` (clicks and the filtered trace), `S3-wayland-debug.raw` (full trace), `.test/shots/spikes/S3-part.png`.

### S4: synthetic clicks in headless sway

Pass, with one addition to the harness. A plain headless sway has no input device: `get_seats` reports capabilities 0, the `seat seat0 cursor` commands answer `success` and no client receives anything. Once a pointer exists, the same commands produce real pointer events.

`tests/vpointer.py` creates that pointer through the `zwlr_virtual_pointer_manager_v1` protocol and keeps it until the compositor exits. It speaks the Wayland wire protocol directly, since `python3-pywayland` and `wlrctl` are not installed. `tests/nested.sh` starts it with every session and waits for it. `tests/nested.sh click <x> <y> [button]` wraps the three cursor commands, with logical coordinates.

Input tests therefore stay automatic, and clicks do not become a manual check in M8.

Keyboard: `wtype` is installed and works in the nested session. A single `wtype -k <key>` adds a keyboard to the seat only for the length of the call. A test that depends on keyboard focus first starts `wtype -s 3600000` in the background to hold a keyboard on the seat (S9).

Evidence: `.test/logs/spikes/S4.log`.

### S5: nothing activates on the private bus

Pass. In a session without Quickshell (`tests/nested.sh start bare`), `ListActivatableNames` returns only `org.freedesktop.DBus`. `notify-send` fails with `org.freedesktop.DBus.Error.ServiceUnknown` and exit status 1. The only mako process before and after is the live one (same PID).

Evidence: `.test/logs/spikes/S5.log`.

### S6: fullscreen client

Pass. With the test client fullscreen, rows 2340 to 2399 show only the client's color: the bottom-layer bar is covered. With the strip shown, rows 2352 to 2399 are `base0D` again and the rows above stay the client's.

Evidence: `.test/logs/spikes/S6.log`, `.test/shots/spikes/S6-tiled.png`, `S6-fullscreen.png`, `S6-fullscreen-strip.png`.

### S7: handoff

Pass, but only with grayscale text antialiasing. The comparison is exact: `tests/pixdiff.py` compares two full screenshots pixel by pixel and prints the count and the largest channel difference.

| Text rendering | Idle bar against the overlay redrawing the clock |
|---|---|
| Qt default (distance field, subpixel antialiasing) | 9 to 18 pixels differ, each by 1/255 on one channel |
| `//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING = gray` | 0 of 9,216,000 pixels differ |
| `//@ pragma NativeTextRendering` | 0 of 9,216,000 pixels differ (also grayscale) |

The 1/255 differences sit on the colored fringes of the glyphs. They cannot be seen, but they are not "pixel for pixel". M0 used the `QSG_DISTANCEFIELD_ANTIALIASING = gray` pragma. After decision D7 (2026-11-14), `shell.qml` uses `//@ pragma NativeTextRendering` instead: hinted glyphs, grayscale, and the handoff is still exact with the M2 clock box (`.test/shots/q1/bar.png` against `overlay.png`: 0 of 9,216,000 pixels differ). The result is the same with `//@ pragma UseQApplication` (needed by S9).

Two observations for M2, from `make reference`:

- waybar draws subpixel text (521 of the 524 colors in its clock are not gray). Grayscale text in bar is therefore a visible difference from the reference at high zoom. See Q1.
- waybar's clock is 254 physical px wide, the Qt clock at `font.pixelSize: 15` is 238 px. Measured in M2: the glyphs have the same ink widths (13 physical px for a digit) and the same height in both, but waybar places them 16 physical px apart and Qt 15. So Pango rounds the font's 7.5 px advance to 8 px. M2 matches it with `font.letterSpacing: 0.5` on every bar text (`Theme.letterSpacing`), which gives the same box edges as waybar and glyph starts within 0.5 px.

Evidence: `.test/logs/spikes/S7.log`, `.test/shots/spikes/S7-bar-idle.png`, `S7-overlay-handoff.png`, the `S7a-subpixel-*` and `S7v-*` pairs, `.test/shots/reference-vs-m0-center.png`.

### S8: `PersistentProperties` across a reload

Fails as the spike states it, passes with another property type.

- A `property var` holding a JS array or a JS object is `undefined` after the reload, and the log says `JSValue can't be reassigned to another engine.`. After a second reload it is back at its default.
- A `property list<var>` holding plain objects keeps them over two reloads. The objects come back as maps with sorted keys (`{"n":1,"text":"first entry"}`).
- `list<string>`, `string`, `int`, and a `var` holding a string or a number are kept.

Change: history (SPEC section 6, item 9) is a `property list<var>` in `PersistentProperties`. A JSON string is the fallback if an entry ever needs a type that `list<var>` does not carry.

Evidence: `.test/logs/spikes/S8.log`, `S8-variants.qml` (the scratch config with one property per type).

### S9: tray

Watcher and host: pass. `SNI_WAIT_TIMEOUT=10 /usr/libexec/sway-systemd/wait-sni-ready` logs `Successfully waited for org.kde.StatusNotifierHost` after 0.4 s. The script exits 0 on failure too (checked in a session without a watcher), so the log line is the check, not the exit status. Matrix case B6 changes accordingly.

Item and menu: pass. `tests/fake-sni.py` registers, the icon appears, a left click logs `Activate`, a right click opens the menu through `QsMenuAnchor` above the bottom-layer bar, a click on an entry logs `Event 2 clicked 'Sync demo data'`, and a click outside closes the menu.

- `QsMenuAnchor` needs `//@ pragma UseQApplication` at the top of `shell.qml`. Without it, `open()` only logs an error.
- The menu is a QtWidgets menu. It ignores `Theme` (white background in the nested session, `S9-menu-open-crop.png`). A menu in the bar's colors would need `QsMenuOpener` and a `PopupWindow` drawn in QML. See Q2.

Keyboard sub-check, with a keyboard held on the seat and the test client focused (it logs the keys it gets):

| Bar keyboard focus | Arrow keys, Return, Escape in the menu | Keyboard after the menu closes |
|---|---|---|
| `None` | ignored, they go to the focused window | stays with the window |
| `OnDemand` only while a menu is open (SPEC section 8 as written) | ignored: sway gives the focus on a click, and the click happens while the focus is still `None` | stays with the window |
| `OnDemand` always | work | stays with the bar until a window is clicked |
| `OnDemand` while the pointer is on the tray or a menu is open | work | back with the window |

So `OnDemand` is needed, and it has to be set before the click that opens the menu. The fourth row is the variant that works without side effects. See Q2.

Evidence: `.test/logs/spikes/S9.log`, `.test/logs/fake-sni.log`, `.test/logs/client.log`, `.test/shots/spikes/S9-menu-open.png` and its crop.

### S10: sway events

Pass.

- `subscriptions` takes a list of event names, as in the i3 `SUBSCRIBE` payload: `subscriptions: ["mode", "window"]`.
- The reply to `SUBSCRIBE` arrives through `ipcEvent` as an event of type `subscribe`. Handlers ignore it.
- `event.data` is a JSON string. `mode` events carry `change` (the mode name), `window` events carry `change` and `container`.
- `swaymsg mode resize` gives `{type: "mode", change: "resize"}`. `swaymsg -t get_binding_state` gives `{"name": "default"}` at startup.
- Fullscreen on and off give `window` events with `change: "fullscreen_mode"` and `container.fullscreen_mode` 1, then 0.
- Quickshell logs `I3 event socket disconnected.` at start and at reloads. The events arrive all the same.

Evidence: `.test/logs/spikes/S10.log`.

### S11: `Quickshell.watchFiles`

Pass. After `Quickshell.watchFiles = false`, touching `shell.qml`, `bar/Bar.qml` and `services/Theme.qml` and changing the content of a file cause no reload (the reload count in the log and a counter in memory both stay). After setting it back to true, the earlier changes are not replayed, and the next touch reloads. The spike set the property at run time through IPC. The live copy (M8) sets it at startup.

Evidence: `.test/logs/spikes/S11.log`.

### Done-when checks

`make nested`, `make nested-stop` and `make reference` each ran twice in a row with exit status 0. After every stop, one sway, one waybar and one mako process remain (the live ones), no `quickshell`, one Wayland socket, and no `.test/sway.sock`. Evidence: `.test/logs/done-when.log`, `.test/shots/reference-bar.png`.

No test state reached the real home: `~/.local/state/quickshell`, `~/.cache/quickshell`, `~/.local/share/quickshell` and `~/.config/quickshell` do not exist. Quickshell does leave one directory per instance under `$XDG_RUNTIME_DIR/quickshell/by-id/` (the real runtime directory, cleared at logout).

### Other findings

- `console.log` and `console.debug` are hidden by default (category `qml`, level debug). The tree logs with `console.info`. `--log-rules 'qml.debug=true'` shows the rest.
- Singletons load on first use. `shell.qml` names `Notifs` and `Sway` in a property, or the notification server would not start until something reads it.
- `//@ pragma` lines in `shell.qml` are read at process start, not on a hot reload. This snapshot knows `UseQApplication`, `NativeTextRendering`, `IgnoreSystemSettings`, `RespectSystemStyle`, `IconTheme <name>`, `Env VAR = VALUE`, `ShellId`, `DataDir`, `StateDir` and `CacheDir` (from the strings of `/usr/bin/quickshell`).
- QML's `font` group has no `styleStrategy`, so subpixel antialiasing cannot be turned off per `Text`.
- `node --test tests/` fails on node 22 (it takes the directory for a module). `make test` runs `node --test tests/*.test.mjs`.
- `qmllint` cannot resolve `import qs.<dir>`. `tests/lint.sh` builds the modules under `.test/lint/` first. Four warnings remain, all from the Quickshell type files (listed in the script).
- The nested `FloatingWindow` client is tiled by sway like any toplevel. Its title is `bar-test-client`.

### M1 findings

Measured in the nested session on 2026-11-14 (bus logs in `.test/logs/m1/bus-<case>.log`).

- `expireTimeout` arrives in milliseconds, as sent: 800, -1 and 0.
- `urgency` arrives as an integer: 0 low, 1 normal, 2 critical.
- `notify-send -i <file>` arrives as `image` with the value `image://icon/<path>`, not as `appIcon`.
- `GetCapabilities` returns `body`, `body-markup`, `actions` and `icon-static` with `bodySupported`, `bodyMarkupSupported`, `actionsSupported` and `imageSupported` set.
- `expire()`, `dismiss()` and `invoke()` emit `closed` before they return, and the server deletes the object right after. `services/Notifs.qml` puts its own state in order before it closes anything, and drops its reference in the `closed` handler.
- QML timers are coarse: Qt allows 5 % error, 250 ms on 5 s. One scheduler timer that wakes at 90 % of the wait and arms again closes within about 10 ms (N1: 5.00 s, N13: 30.00 s).
- `notify-send -A` calls `CloseNotification` once an action came back. A `resident` notification sent that way closes with reason 3, so case NX sends its resident notification through `gdbus call`.
- A `notify-send -r` update that repeats the same text restarts the time as well (measured: closed 5.0 s after the update, `.test/logs/m1/bus-same-update.log`).
- After a reload each survivor gets its full timeout again, and a waiting one a new 30 s limit.

### M3 findings

Measured in the nested session on 2026-11-14 (logs in `.test/logs/m3/`, frames in `.test/shots/m3/`).

- **Frame series need a light capture.** grim 1.5 uses ext-image-copy-capture and reads back the whole 3840x2400 output for every shot, even with `-g`. Each shot blocks the compositor for about 80 ms. Shots requested at 60 and 120 ms showed the frames of 114 and 193 ms, and notifications sent at 100, 200 and 300 ms got their reply only at 398 ms, because Quickshell was waiting for the compositor. `tests/frames.py` uses wlr-screencopy's `capture_output_region` on one connection instead. It copies only the region, the frames land within one 60 Hz frame of the requested time, and the senders get their reply in about 22 ms. Dense series still cost frames: 31 shots 10 ms apart got only 7 distinct compositor frames, and the fade ran slower. Five shots do not change the result: one shot at 120 ms and three shots at 0, 60 and 120 ms both show opacity 0.49 at about 125 ms.
- **Frame time.** The `ready` event of wlr-screencopy (and `presentation_time` in ext-image-copy-capture) carries the time of the copied output frame in `CLOCK_MONOTONIC`. Checked against the client's own clock, it lies within 0.2 ms of the capture request.
- **First frame of the overlay.** The overlay's first frame comes about 30 ms after the OSD reaches the view (layer surface, configure, first render). Animations started on arrival ticked irregularly while the surface was set up: the first visible frame came between 35 and 71 ms, at opacity 0.33, and the 100 ms fade stretched to about 150 ms. `OsdView` therefore starts the entry on the window's first `frameSwapped`. Qt's first tick after `start()` only registers an animation, so the visible fade starts at opacity 0.33 about 65 ms after the arrival. It then moves in 16.7 ms steps and ends 100 ms after the first frame. Seen from the sender, the strip appears at about 80 ms and is opaque at about 150 ms. The probe output is in `.test/logs/m3/first-frame.log`. M4's note entry starts from the same first frame.
- **Fade-out after the entry is gone.** The core sets `Notifs.osd` to null when the OSD closes, so the view keeps its own copy of the label, the value and the color roles, and `active` keeps the overlay mapped until the 150 ms fade ends. During the fade the input mask is empty (`Region { item: null }`). Checked with the fade stretched to 3 s: a click on workspace 3 under the fading strip focused workspace 3.
- **Rapid presses.** The core sets the new OSD before it closes the old one, so `Notifs.osd` is never null between presses. In case RP, 30 presses 40 ms apart give one map, one entry and 29 updates, and every frame from 300 to 1400 ms shows an opaque fill past 50 %. A press during the fade-out fades the same strip back in. Its frames show opacity 0.90 at 357 ms and 0.67 at 407 ms, then an opaque strip at 456 ms, with one map and one entry for both presses.
- **The window of an item.** `PanelWindow` does not expose `_backingWindow` to QML (it reads as `undefined`). The attached property `Window.window` of an item gives the `QQuickWindow`, with `frameSwapped`, `afterAnimating` and `beforeSynchronizing`.
- **Hot reload of a singleton.** After an edit to `services/Motion.qml` alone, Quickshell logged a reload but kept the old value of `osdFadeOut`: 150 after the change to 3000, and 3000 after the change back. Touching `shell.qml` applied the new value. This happened both times.
- **Label contrast.** WCAG contrast ratios from the two palettes: base05 on base00 is 12.5:1 in dark mode and 11.0:1 in light mode. base00 on the fills is 7.4 (volume), 11.6 (brightness) and 6.3 (microphone) in dark mode, but 2.3, 1.4 and 2.7 in light mode, where base00 is `#f8f8f8`. base05 on the light fills would give 4.9, 7.7 and 4.1. See Q10 and `.test/shots/m3/N6-palette-light.png`.

### M4 findings

Measured in the nested session on 2026-11-14 (evidence in `.test/logs/m4/` and `.test/shots/<case>/`).

- Handoff: the overlay can reproduce the bar's idle center exactly, but only if it waits. A layer surface is configured before its first frame, and an animation started at map time has moved on by then. The view therefore holds the first frame (the bar's clock box) until the window reports `frameSwapped`, and unmaps only after the frame with the clock box back in place has been swapped. `root.Window.window` (the attached `Window` property) reaches the backing `QQuickWindow`, its `frameSwapped` signal and its `update()` slot from QML. The debug state reports `frameVia: "frame"` when the wait ended on a swap, `"timeout"` after the 250 ms fallback. In every run it ended on a swap.
- Result of the S7 method with a hold at both ends (case HO): first frame, last frame and the bar after the unmap each differ from the idle bar in 0 of 9,216,000 pixels.
- `Notifs.current` passes through `null` when the next note takes the span (`onClosed` sets it to null, then `showNext()`). The view reads it through `Qt.callLater`, so a queue change is a roll and not a leave followed by an entry, and the overlay never unmaps between two notes.
- The leave animation runs after the notification closed and its object is deleted. The view draws from snapshots: `Notifs.snapshot()` now also keeps `image` and `appIcon`.
- Entries are plain JS objects without change signals. `Notifs.timing` is bumped when a display timer starts, pauses or restarts, so the progress line follows a pause under an OSD.
- A running animation group keeps the durations it started with. The slow-motion factor (`debug slow`) therefore restarts the looping animations (pulse, marquee) when it changes.
- Quickshell can miss the second of two file changes made in quick succession (the first triggers the reload, the second is not picked up). `touch` the file again when the log shows no second `Configuration Loaded`.
- A property named `left` or `right` in an `Item` fails with "Cannot override FINAL property" (they are anchor lines).
- Frame series: `grim -l 0 -g "0,1176 1920x24"` grabs only the bar strip without compression. Started on their own schedule, the grabs begin within 1 ms of their target time. `tests/strip-frames.py` (named `frames.py` on the M4 branch) combines that with the slow-motion factor (x10 for 60 ms steps). M3 measured that grim reads back the whole output and stalls the compositor for about 80 ms per shot (M3 findings), which the slow motion hides.
- The clock compacts by clipping its full text from the left. In some middle frames a sliver of a date digit shows at the box's left edge (N1 and N4 entry series at 160 ms). M7 can fade the date part instead.
- The leading-edge glow (`MultiEffect` shadow, `blurMax` 12) is faint at 1x viewing. M7 tunes it or replaces it with the shader.
- Idle cost: with no notification, `top -b -n 5 -d 1` reports 0.0 % CPU on every sample for the bar process, and its CPU time does not change, also right after a marquee, a critical pulse and a roll (`.test/logs/m4/cpu-idle.log`).
- A host suspend during a matrix run breaks the timing checks of the case that is running. In the first full M4 run the host suspended at 17:16:55, between two closes in NX. The 1.5 s timeout of the updated waiting note was measured as 40,049 s, and the note closed 0.4 s after the resume (`journalctl`: `The system will suspend now!`, `System returned from sleep`). The rerun passed.

### Open questions for the owner

These are questions about how bar looks or behaves, so M0 does not settle them. Q3 to Q9 are gaps in the SPEC that M1 had to fill to build the core, Q10 to Q12 are the same for the OSD view (M3), and Q13 to Q15 for the note view (M4). Each is built as described and stays that way unless the owner decides otherwise.

- **Q1, text antialiasing.** Answered 2026-11-14 as decision D7 (native rendering). Original question: grayscale text makes the handoff exact (S7) and is what the tree does now. Subpixel text is what waybar draws, and it leaves a handful of pixels off by 1/255 at each handoff, which cannot be seen. The choice is between the SPEC's "pixel for pixel" and the reference's text rendering. If subpixel wins, the handoff check in M4 becomes "largest channel difference 1/255".
- **Q2, tray menus.** Two points. First, the keyboard: keep the bar at `WlrKeyboardFocus.None` and menus mouse-only, or switch to `OnDemand` while the pointer is on the tray. Second, the look: accept the QtWidgets menu of `QsMenuAnchor`, or draw the menu in QML with `QsMenuOpener` so that it uses `Theme`.
- **Q3, `value` hint from an unlisted app.** SPEC section 4 names the `value` hint as the OSD trigger, and section 5 lists three OSD apps. Built: the rules table decides, so another app that sends `value` stays a note. The other choice is a full-width OSD for any notification with a `value`.
- **Q4, DND switched on while notes wait.** Built: the waiting notes that DND hides move to the hidden path (5 s, then history), and the one on display stays until it leaves. The other choices are to hide the visible one too, or to let the waiting ones show.
- **Q5, a second OSD with another tag.** Built: one OSD at a time. A brightness OSD that arrives while the volume OSD shows expires the volume one and takes the strip.
- **Q6, queue limit of a note pushed back by a critical.** Built: the note goes back to the front of the queue with its remaining display time and a new 30 s limit. A critical can stay for hours, and without a limit the note would never close. The other choice is to count the 30 s from its arrival, which expires it sooner.
- **Q7, target of `dismiss()`.** Built: the OSD while one shows, else the note. `$mod+n` during a volume change removes the OSD, and a second press removes the note under it.
- **Q8, `restore()`.** Built: the newest history entry leaves the list, shows as a plain note for 5 s without its actions, and returns to the list when it closes. Repeated calls bring back older entries one after the other, and they wait in the queue like any note. It also shows while DND is on, since it answers a key press.
- **Q9, a `replaces_id` update that changes the urgency.** Built: the rules are read again on every update. A note on display that turns critical becomes a critical in place (no timeout, `base08`), and a waiting note that turns critical takes the span like a new critical. An update never moves a notification between the OSD strip and the note span.
- **Q10, label over the fill in light mode.** Built as SPEC section 7 says: base00 over the fill, base05 over the empty part. In light mode base00 is `#f8f8f8`, which gives 1.4:1 on the brightness fill (`#f7ca88`), 2.3:1 on volume (`#7cafc2`) and 2.7:1 on microphone (`#ba8baf`). The label is hard to read at high values (`.test/shots/m3/N6-palette-light.png`). mako drew its light-mode OSD text in `#383838`. The choices: keep it; use base05 (dark in light mode) over the fill in light mode, which gives 7.7, 4.9 and 4.1 but the same color on both sides of the edge; or pick another palette role for the text over the fill.
- **Q11, an OSD of another app takes the strip (Q5).** Built: the strip stays, its fill color changes at once, and the fill moves from the old value to the new one in 120 ms, as for a same-tag update. The other choice is to run the entry again (the fill grows from 0 in 180 ms) without fading the strip.
- **Q12, position of the OSD label.** Built: centered on the output, where the clock is, in the regular bar font. Near 50 % the fill edge runs through the label, which is where the split shows (`.test/shots/m3/N5-volume-frames.png`, last frame). mako aligned its text to the left.
- **Q13, a mode name that runs under the clock.** The bar draws its clock box above the mode label, so a mode name longer than about 90 characters already passes under the clock when idle. While a note shows, the overlay covers the bar's clock with an empty `base00` box (the handoff needs it), so that box stays in the middle of the label while the clock sits compact in the span (`.test/shots/NW/long.png`). Built: as described. The other choices are to elide the mode before the clock box while a note shows, or to hide the bar's clock while a note shows, which needs the two windows to change in the same frame.
- **Q14, what the 600 px measure.** Built: the whole center span (compact clock, separator and note region), as SPEC section 4 defines the span. The note region itself then gets 538 px. The other choice is 600 px for the note region, which elides the mode 62 px sooner.
- **Q15, small choices in the note view.** Built, each open to change in M7: with seconds shown in the bar, the compact clock keeps `HH:mm:ss` (only the date leaves). The leading edge stays at the span's end while the note shows, static on a note and pulsing on a critical. The progress line runs over the note region only, not over the compact clock. The `+N` counter is `base04`. On a critical, the app name, the body and the counter are `base07` like the summary. During a roll the background crossfades (`base01` to `base08` when a critical follows a note). A note that arrives during a leave opens the span again from where it is, without first unmapping.
