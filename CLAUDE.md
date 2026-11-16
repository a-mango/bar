# bar

Status bar and notification daemon for sway, written as one Quickshell (QML) config. Workspaces and sway mode on the left, clock and notifications in the center, tray on the right. It owns `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher`, and replaces both waybar and mako.
Spec: `docs/SPEC.md` · Plan and milestones: `docs/PLAN.md` · Configs being replaced: `docs/reference/`. Read only the sections the current task needs.

## Commands
<!-- M0 creates these. Keep this list in sync with the Makefile. -->
- `make nested`: start the isolated test desktop (headless sway, private D-Bus, quickshell on this tree). `make nested-stop` ends it.
- `tests/nested.sh run <command>`: run a command inside the nested session (`env -i`, nested display and bus). `tests/nested.sh click <x> <y> [button]` clicks at logical coordinates.
- `tests/scene.sh setup`: workspaces 1, 2, 3 and `4:demo`, urgent 3, two fake tray items, once per session. Then `mode`, `present`, `focus-other`, `focus-main`, `hover`, `tray <n> <status>`.
- `make reference`: nested session running waybar with `docs/reference/waybar/`, screenshot of its bar (visual target)
- `make matrix`: run the `docs/SPEC.md` test matrix against the nested session (about 5 minutes). `make matrix CASE=N5` runs one case, `CASE="N13 N18"` several.
- `make shots`: screenshot the nested output into `.test/shots/`
- `tests/nested.sh run tests/frames.py <dir> "<ms> run <command>" "<ms> shot" ...`: frame series. Commands and region shots on a schedule, each shot stamped with its frame time, plus `<dir>/sheet.png` and `frames.json`
- `make log`: follow the nested Quickshell log
- `make test`: `node --test tests/*.test.mjs` (unit tests for `services/Rules.js` and `services/Markup.js`)
- `tests/strip-frames.py <dir> <label> <slow> <ms...> [-- command]`: frame series of the bar strip through grim, from the host. Pair it with `call debug slow <factor>`, and reset the factor to 1 afterwards.
- `make shaders`: compile `shaders/*.frag` to `.qsb` with `/usr/lib64/qt6/bin/qsb`
- `make lint`: `qmllint` on all QML files through `tests/lint.sh` (needs `qt6-qtdeclarative-devel`)
- `make install`: copy the tree to `~/.local/share/bar` as the live copy (M8 only, after the owner's go-ahead)

## Rules
- Quickshell API: check every type, property, signal and enum in `/usr/lib64/qt6/qml/Quickshell/**/*.qmltypes` before using it, never from memory. Fedora ships snapshot `0.2.1^git20260209.dacfa9d`, and the online docs track a newer version.
- IMPORTANT: the live session is off limits until M8 is approved. Do not stop, reload or reconfigure mako or waybar. Do not edit `~/.config/sway`, `~/.config/waybar`, `~/.config/mako`, `~/.local/share/darkman`, `~/.local/share/dbus-1` or `~/.config/systemd/user`. Never run `quickshell`, `notify-send` or a tray test against the real `WAYLAND_DISPLAY` or session bus.
- Read the replaced configs from `docs/reference/`, not from the live directories.
- Nested sway only through `tests/nested.sh` (absolute paths, overridden `SWAYSOCK`, minimal config, private bus). Never start sway with the user's config.
- Real tray applets act on the real system (network, Bluetooth, audio). If one runs in the nested session, only open and close its menu, never trigger an entry. Activation and menu-click tests use `tests/fake-sni.py`.
- The bar window is never hidden or unmapped, and a theme change never calls `Quickshell.reload()`. Both drop the exclusive zone and re-tile every window.
- All transient content (OSD, notes, critical, rich card) goes in the overlay window, never in the bar window.
- Colors only from `Theme`, durations and easing only from `Motion`. No raw hex values in views.
- `services/Rules.js` and `services/Markup.js` stay pure JS (no QML imports) so `node` can test them.
- Every tracked notification must close eventually (expire, dismiss, action or `CloseNotification`). A notification that never closes hangs blocking senders such as `notify-send -A`.
- IMPORTANT: test notifications, screenshots and docs use fictional text only.

## Workflow
- One milestone per branch (`mN-slug`). Small commits with conventional subjects (`feat:`, `fix:`, `test:`…).
- A milestone is done when its "Done when" checks in `docs/PLAN.md` pass. Report evidence (command output, `.test/shots/` paths), not claims.
- Write spike findings into `docs/PLAN.md` section 8, and update `docs/SPEC.md` when a finding changes behavior.
- Decisions D1 to D7 (`docs/PLAN.md` section 7) are settled. Changing one, or any new question about how bar should look or behave, is the owner's call: ask, do not guess.

## Gotchas
<!-- Add one line per non-obvious lesson learned; prune when obsolete. -->
- The binary is `quickshell`, not `qs`. IPC: `quickshell ipc -p <config dir> call <target> <fn>`, and it only sees instances on the current Wayland display.
- Use the long form `--no-duplicate`: the help text lists `-n` for both `--newest` and `--no-duplicate`.
- Quickshell hot-reloads on every file change, but can miss the second of two quick edits. If the log shows no second `Configuration Loaded`, `touch` the file. The live copy (M8) runs from `~/.local/share/bar` with `Quickshell.watchFiles` set to false, never from this tree.
- `Notifs.current` passes through `null` when the next note takes the span. Views read it through `Qt.callLater`, or a queue roll looks like a leave and an entry.
- The note view draws from snapshots: the leave and the roll run after the notification closed. The overlay's visibility follows `NoteView.active`, not `Notifs.current`.
- A host suspend during `make matrix` breaks the timing checks of the running case (a 1.5 s timeout measured as 40,049 s). Before chasing a timing failure, check `journalctl | grep 'will suspend now'`.
- A running animation group keeps its starting durations. Restart looping animations when a duration they bind to changes.
- The overlay must use `ExclusionMode.Ignore` to lie on the bar. With a zero exclusive zone, the compositor stacks it above the bar's 24 px.
- Set `n.tracked = true` inside the `notification` handler, or the server closes the notification as soon as the handler returns.
- After a reload, surviving notifications come back through the same handler with `lastGeneration` set: re-track them and skip the entry animation.
- `replaces_id` updates emit no new `notification` signal. Bind to the properties and listen to their change signals.
- The OSD senders never pass `replaces_id`. They replace through the `x-canonical-private-synchronous` hint, which arrives in `hints` with `value`.
- The server has no expiry timers. All timeouts are QML `Timer`s.
- QML timers are coarse (Qt allows 5 % error, 250 ms on 5 s). The scheduler in `services/Notifs.qml` wakes at 90 % of the wait and arms again. Do not add a plain `Timer` for a deadline that a test measures.
- `expireTimeout` arrives in milliseconds as sent (800, -1, 0). `urgency` arrives as 0, 1 or 2 (`Rules.LOW`, `NORMAL`, `CRITICAL`).
- `notify-send -i <file>` arrives as `image` = `image://icon/<path>`, not as `appIcon`.
- `expire()`, `dismiss()` and `invoke()` emit `closed` before they return, and the object is deleted right after. Put the queue state in order before closing, and never keep `e.n` past `onClosed`.
- `notify-send -A` calls `CloseNotification` after an action. Test a `resident` notification through `gdbus call ... Notify`.
- `dbus-run-session` with the default config would activate mako from `/usr/share/dbus-1/services` on the first notification. `tests/session.conf` lists no service directories.
- At login, `wait-sni-ready` gives the tray watcher 25 s. `bar.service` must be enabled under `sway-session.target`, not only D-Bus-activated.
- darkman runs every executable file in `~/.local/share/darkman/`, whatever its extension: disable a hook with `chmod -x`, not a rename. It runs as a user service that may lack `WAYLAND_DISPLAY`, so its hook calls `quickshell ipc --any-display`.
- `darkman get` can fail at login before darkman is up. Fall back to the theme mode stored in `state.json`.
- Harness paths (`SWAYSOCK`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, the sway config) must be absolute. A relative `XDG_*` value is likely to be ignored, and test state would land in the real `~/.local/state`.
- sway reuses an inherited `SWAYSOCK` and unlinks the path. A nested sway without an overridden `SWAYSOCK` breaks the live session's IPC.
- `swaymsg reload` on the live session also re-runs every `exec_always` (the wallpaper rotation). M8 applies sway changes with direct `swaymsg` commands.
- Run everything that talks to the nested session through `tests/nested.sh run`. A plain shell still has the live `WAYLAND_DISPLAY`, `SWAYSOCK` and bus address.
- `console.log` and `console.debug` are hidden by default. Log with `console.info`.
- Singletons load on first use. One that must run from startup (`Notifs`, `Sway`) is named in `shell.qml`.
- `//@ pragma` lines in `shell.qml` take effect at process start, not on a hot reload. `UseQApplication` is required by `QsMenuAnchor`. `NativeTextRendering` (decision D7) gives hinted grayscale text and the pixel-exact handoff.
- In `PersistentProperties`, a `property var` holding a JS array or object is `undefined` after a reload. Use `property list<var>`.
- A headless sway seat has no pointer. `seat seat0 cursor` commands only reach clients while `tests/vpointer.py` runs (the harness starts it). Keyboard tests hold a keyboard with `wtype -s 3600000` in the background.
- sway gives an `OnDemand` layer surface the keyboard only on a click. Setting `OnDemand` after the click that opens a tray menu is too late.
- `wait-sni-ready` exits 0 on failure too. Check its `Successfully waited` log line.
- The I3 event listener also delivers the reply to `SUBSCRIBE` as an event of type `subscribe`.
- `pkill -f <pattern>` matches the shell that runs it when the pattern is on its own command line. Kill by PID.
- A QML type named `State` loses to QtQuick's `State`. Do not name a singleton after a QtQuick type.
- `swaymsg` joins its arguments into one command string: quote names with spaces inside the argument (`mode "\"$name\""`), and pass `--` before commands that contain `--custom`.
- sway places a new output (`create_output`) first and moves HEADLESS-1. `tests/scene.sh focus-other` puts both outputs back at x 0 and 1920.
- `seat seat0 cursor set 0 <y>` leaves x unchanged: a 0 coordinate means "keep".
- sway does not slide popups of layer surfaces back onto the output. Anchor popups near an edge so that they grow away from it.
- The nested session has `tests/bin` first on `PATH`: `darkman get` is the stub, which answers from `.test/darkman-mode` or fails.
- grim reads back the whole 3840x2400 output for every shot, even with `-g`. That blocks the compositor (and Quickshell) for about 80 ms. Use `tests/frames.py` for anything timed.
- After an edit to a singleton file alone (seen with `services/Motion.qml`), the hot reload kept the old values. Touch `shell.qml` as well.
- A newly mapped window shows its first frame about 30 ms later, and Qt's first tick after `start()` only registers an animation. Entry animations start on the window's first `frameSwapped` (`OsdView`, `NoteView`).
- `PanelWindow` does not expose `_backingWindow` to QML. Use an item's attached `Window.window` for `frameSwapped`.
- `mask: Region { item: null }` is an empty input region: every click goes through to the bar.
- `debug state` lists the overlays of every output. Until M6 each overlay maps, so tests count maps and entries on HEADLESS-1 only.
- The pointer on a note pauses its timer, and `tests/nested.sh click` leaves the pointer where it clicked. Park it (`scene hover 960 600`, `park` in `tests/matrix.sh`) before a timing check. Hover follows pointer motion: a note that maps under a resting pointer is not hovered.
- In `swaymsg -t get_tree`, every workspace node reports `fullscreen_mode: 1`. Count only `con` and `floating_con` nodes.
- An `Image` without `asynchronous: true` decodes on the GUI thread: a screenshot PNG blocks for 150 to 350 ms.
- A `tests/client` window killed through sway leaves its `quickshell` process running. Kill it by PID.
- The notification history keeps 20 entries, and a full matrix run fills it. Check `newest` in `notify status`, not a count that grows.
