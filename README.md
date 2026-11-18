# bar

A status bar and notification daemon for [sway](https://swaywm.org), written as a single [Quickshell](https://quickshell.org) (QML) config. It replaces waybar and mako on one desktop, and keeps waybar's look when nothing is happening.

- **Bar** on every output: workspaces (click or scroll) and the sway mode on the left, the clock in the center (a click shows seconds, hovering opens a calendar), the system tray on the right with menus drawn in QML.
- **Notifications** (`org.freedesktop.Notifications`, spec 1.2): a note grows out of the clock and fills the center of the bar. Waiting notes roll in one after another, long lines scroll, and criticals turn the span red until clicked. Actions, Do Not Disturb, a history of 20 with restore, and fullscreen-aware placement are built in. Screenshot notifications show the picture in a card above the bar, and a right click discards the file.
- **OSDs** for volume, brightness and the microphone take the full width of the bar for a moment (the `x-canonical-private-synchronous` hint with an `int:value:` hint).
- **Tray**: bar is the `org.kde.StatusNotifierWatcher` and the host.
- **Themes**: base16 Default Dark and Light, switched live by [darkman](https://gitlab.com/WhyNotHugo/darkman) with a 300 ms crossfade. The bar never unmaps, so windows don't re-tile.

It's built for one laptop (1920x1200 at scale 2, Fedora), so expect to adjust things. `docs/SPEC.md` describes every behavior.

## Requirements

- sway 1.11
- Quickshell. bar is tested against Fedora's snapshot `0.2.1^git20260209.dacfa9d` on Qt 6.11, and newer Quickshell releases may differ.
- The IosevkaTerm Nerd Font, and the AdwaitaLegacy icon theme for tray icons
- darkman (optional), for the theme switch

## Install

`docs/PLAN.md` section 6 has the full cutover and rollback steps. In short:

1. `make install` copies the tagged, committed HEAD to `~/.local/share/bar`, with file watching turned off. `DEST=/abs/path` installs elsewhere.
2. Copy `packaging/bar.service` to `~/.config/systemd/user/`, then run `systemctl --user enable --now bar.service`. The unit starts under `sway-session.target`.
3. Copy `packaging/org.freedesktop.Notifications.service` to `~/.local/share/dbus-1/services/`. Edit the absolute path in it first, since D-Bus files don't expand `%h`.
4. Stop waybar and mako. Comment out sway's `bar {}` block, so that a reload doesn't bring waybar back.
5. Optional: add `packaging/sway-bindings.conf` to your sway config (dismiss, dismiss all, restore, toggle DND), and install `packaging/darkman-bar.sh` as an executable darkman hook.

## IPC

```sh
quickshell ipc -p ~/.local/share/bar call notify dismiss       # also: dismissAll, restore, toggleDnd, setDnd, invoke, status
quickshell ipc -p ~/.local/share/bar call theme set light      # or dark
```

## Development

Every test runs in an isolated nested sway session (headless outputs, a private D-Bus, Quickshell on this tree), never against the live desktop.

```sh
make nested        # start the nested session; make nested-stop ends it
make matrix        # the docs/SPEC.md test matrix, about 10 minutes; CASE=N5 runs one case
make test          # unit tests for services/Rules.js and services/Markup.js (node)
make lint          # qmllint (needs qt6-qtdeclarative-devel)
```

- `docs/SPEC.md`: what bar does.
- `docs/PLAN.md`: the milestones, the test harness, decisions, and the findings with evidence.
- `CLAUDE.md`: instructions and gotchas for coding agents working on the tree.

## License

MIT, see `LICENSE`.
