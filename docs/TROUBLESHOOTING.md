# Troubleshooting

Every entry here is a failure that actually happened on this machine, with what
it looked like and what fixed it. They are written down because most of them
presented as something other than their cause.

## The shell shows nothing, but the process is running

`pgrep qs` reports a live process; there is no bar, no wallpaper, no widgets.

A process watchdog would not catch this, because nothing crashed. Quickshell had
lost every layer surface — the most likely cause is the output briefly
disappearing, at which point `Variants` over `Quickshell.screens` tears its
children down and does not rebuild them.

`bin/hypr-shell-guard` checks the **visible result** every 8 s — that the
namespaces `quickshell-bar`, `quickshell-wallpaper` and `quickshell-widgets`
exist in `hyprctl layers` — and restarts if any is missing.

```sh
hyprctl layers | grep namespace: | grep quickshell
```

Three lines is healthy.

## Panels open with an animation but vanish instantly

The window's `visible` is bound directly to the open flag, so the layer surface
is destroyed in the same frame the state changes and the closing animation never
renders.

```qml
visible: menus.open || card.opacity > 0.01   // not: visible: menus.open
```

## GNOME Settings does nothing when clicked

`gnome-control-center` exits immediately with

```
Running gnome-control-center is only supported under GNOME and Unity, exiting
```

and **exit status 0**, so it does not even look like a failure. The check is
`is_supported_desktop()` in `main.c`, reading `XDG_CURRENT_DESKTOP`.

`bin/hypr-settings` sets `XDG_CURRENT_DESKTOP=Hyprland:GNOME`. The variable is a
colon-separated *list*: gnome-control-center searches it for GNOME and finds it,
while xdg-desktop-portal takes the **first** match and stays on
hyprland-portals.conf. Setting it to plain `GNOME` also starts the settings but
redirects every portal call to xdg-desktop-portal-gnome.

Its `.desktop` file also needs `OnlyShowIn=GNOME` dropped, or it stays hidden
from every launcher, and `DBusActivatable=false`, or the wrapper is bypassed.

## Java files get no language server, and no error message

jdtls needs **Java 21 or newer**. On 17 it dies during OSGi startup with a bare
"An error has occurred" written to a log file — Neovim sees no client, no
message, nothing in `:messages`.

```sh
archlinux-java status          # what is default
ls /usr/lib/jvm                # what is installed
sudo pacman -S jdk21-openjdk
```

`java.lua` resolves a 21+ runtime explicitly rather than using `java` from
`PATH`, so the system default can stay at 17 for compiling.

If it still does not attach, check that nothing else started jdtls first:

```lua
-- mason-lspconfig enables every server Mason has on disk, since v2
automatic_enable = { exclude = { "jdtls", "ts_ls" } }
```

A second jdtls with the wrong runtime kills the working one.

## Three language servers attach to one TypeScript file

`vtsls` and `ts_ls` are two front ends for the same service, and Mason has both.
Every diagnostic and completion appears twice. Excluded by name as above.

`angularls` attaching to non-Angular projects is a separate issue: when no root
marker matches, Neovim still starts the server in single-file mode. A `root_dir`
function that simply does not call `on_dir` cancels the start.

## The bar lags behind by seconds

If the shell is polling rather than subscribing. Check:

```sh
systemctl --user status hypr-eventd
mosquitto_sub --unix /run/user/$(id -u)/mosquitto.sock -t 'hypr/#' -v -W 3
```

No output means the daemon is down and the shell is showing its last retained
values forever.

## The calendar is empty for the first 15 seconds after boot

The cache was in `$XDG_RUNTIME_DIR`, which systemd wipes when the user's last
session ends. With no cache the widget waits for a full EDS refresh —
`ECal.Client.connect_sync` blocks for its whole `wait_for_connected` window,
measured at exactly 10.01 s per calendar.

The cache is now in `~/.cache/hypr`, and `hypr-calendar-cache.service` rebuilds
it at login and again at shutdown.

```sh
ls ~/.cache/hypr/hypr-calendar-*.json | wc -l   # ~27 is healthy
```

## A text console flashes before the desktop

SDDM jumps to VT 1 before the compositor starts, and the console is black with
login text on it. Setting the console palette's colour 0 to the wallpaper's mean
colour makes the transition invisible:

```sh
printf '\033]P0%s\033[H\033[2J\033[3J\033[?25l' 3b3554 > /dev/tty1
```

Run for each VT from SDDM's `Xsetup` and `Xstop`, both of which run as root.

## Screenshots stop working until reboot

A stuck `slurp` used to make every subsequent key press do nothing silently. The
guard now kills an existing slurp and starts a fresh one, so a jammed state
heals itself on the next press.

Separately: a `flock` on fd 9 was never released, because `wl-copy` daemonises
and inherits the descriptor. There is no flock now.

## Every `git commit` hangs

If you use a global `core.hooksPath` with a dispatcher that chains to the
repository's own hooks, do **not** find them with:

```sh
git rev-parse --git-path hooks     # honours core.hooksPath -> returns itself
```

The dispatcher re-executes itself forever. Use:

```sh
git rev-parse --path-format=absolute --git-common-dir
```

and compare the result against the global hooks directory before executing.

## Diagnosing anything else

```sh
journalctl --user -u hypr-eventd -u mosquitto -n 50
hyprctl layers
systemctl --user list-units 'hypr*'
qs -c ~/.config/quickshell ipc show          # what the shell exposes
```

Quickshell logs QML errors to stdout; run it in a terminal to see them.
