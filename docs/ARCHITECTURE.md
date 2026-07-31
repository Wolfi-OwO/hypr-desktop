# Architecture

## The shape of it

```
                       ┌──────────────────────────────┐
   kernel / daemons    │  /proc  /sys  PipeWire  NM   │
                       └───────────────┬──────────────┘
                                       │  events + reads, no forks
                       ┌───────────────▼──────────────┐
                       │        hypr-eventd           │  one Python process
                       │  4 watcher threads + 750 ms  │
                       └───────────────┬──────────────┘
                                       │  MQTT publish, retained
                       ┌───────────────▼──────────────┐
                       │   mosquitto (unix socket)    │  8.4 MB RSS
                       └───────────────┬──────────────┘
                                       │  mosquitto_sub, one line per change
   ┌───────────────────────────────────▼──────────────────────────────┐
   │                        Quickshell (one process)                   │
   │  Bar   Menus   QuickSettings   Controls   NotificationCentre      │
   │  AltTab   wallpaper   desktop widgets      ← all bound to Theme   │
   └───────────────────────────────────────────────────────────────────┘
```

Hyprland sits alongside this, not under it: window and workspace events reach
Quickshell through Hyprland's own IPC, which is already event-driven, so routing
them through the broker would add a hop for no gain.

## Why a message broker on a single machine

The honest answer is that D-Bus would have covered the system signals. UPower,
NetworkManager, BlueZ and logind all emit exactly what the bar needs, and
Quickshell speaks D-Bus natively.

MQTT was chosen for a different reason: **anything can subscribe**. A script, a
different shell, a phone on the same network through the loopback listener — all
of them get the current value the moment they connect, because the topics are
retained. That property is what D-Bus does not give you without writing a
service that caches state.

It is also cheap. Measured:

```
mosquitto        8.4 MB RSS   (2.8 MB PSS)
hypr-eventd     16.0 MB RSS
5 subscribers   25.0 MB RSS
```

`config/mosquitto/mosquitto.conf` is tuned for that: no persistence, no `$SYS`
tree, a 16 MB `memory_limit`, an 8 KiB packet cap, 30 connections, errors and
warnings only. It listens on a unix socket (cheapest transport, filesystem
permissions do the access control) plus `127.0.0.1:1883` for client libraries
that only speak TCP — bound explicitly, because without `bind_address` mosquitto
listens on every interface and puts desktop state on the local network.

## Topics

All retained, so a late subscriber gets the current value immediately.

| Topic | Payload | Source |
|---|---|---|
| `hypr/state` | everything, one object | the bar consumes this |
| `hypr/audio` | `{vol, muted}` | `pactl subscribe` |
| `hypr/brightness` | `{bright}` | `poll()` on `actual_brightness` |
| `hypr/battery` | `{batt, battState}` | `/sys/class/power_supply` |
| `hypr/network` | `{net, ssid, down}` | `ip monitor` + `/proc/net/route` |
| `hypr/bluetooth` | `{bt}` | `/sys/class/rfkill` |
| `hypr/system` | `{cpu, mem, temp, uptime}` | `/proc/stat`, `/proc/meminfo`, hwmon |
| `hypr/theme` | `{dark}` | `gsettings monitor` |
| `hypr/power` | `{profile}` | `/sys/firmware/acpi/platform_profile` |
| `hypr/weather` | full forecast object | Open-Meteo, refreshed every 15 min |

Only changes are published. An idle desktop produces no traffic at all.

## Why the readings are medians

Both CPU and temperature report the **median across cores**, not the maximum.

On this machine the coretemp package sensor (`temp1_input`) read 96 °C while the
individual cores sat between 62 and 66 and only Core 0 was at 96 — the package
sensor is by definition the maximum. Displaying it makes the machine look
permanently on fire. The same reasoning applies to CPU load: one core pinned by
a single thread pushes a max-based reading to 100 % on an idle system.

## The theme singleton

`config/quickshell/Theme.qml` holds every colour once. Two things depend on it,
and both only work because no other file defines its own colours:

1. **Switching at all.** Several files used to carry their own literals, which
   stayed dark in light mode while the bar had already switched.
2. **The cross-fade.** `Behavior` blocks animate each colour change, so the
   whole shell fades on one curve from one source.

This is why the properties are deliberately *not* `readonly` — a `Behavior`
cannot attach to a readonly property, and without one the colour jumps.

`fadeMs` is 170. It was 260, which was measurably too slow: programs that switch
colours outright rather than animating (kitty, GTK apps, browsers) finish
immediately, and the animated surfaces arrived about two frames later. That trail
was visible as "some things take slightly longer".

## Panel lifetime, and the bug worth knowing about

Every panel binds its window visibility to the card's opacity, not to the open
flag:

```qml
visible: menus.open || card.opacity > 0.01
```

With `visible: menus.open` the layer surface is destroyed in the same frame the
state flips, so the closing animation never renders. The panel opened with a
transition and vanished instantly. This pattern is repeated in `Menus.qml`,
`QuickSettings.qml`, `Controls.qml` and `NotificationCenter.qml`.

The shared transition is 190 ms: opacity, scale from 0.94 anchored at the corner
under the button that opened it, and a short slide out from beneath the bar,
behind a 0.18 scrim.

## Boot and login

- `docker.service` is socket-activated. It took 22.9 s and `graphical.target`
  waited behind it.
- Widget caches live in `~/.cache/hypr`. `$XDG_RUNTIME_DIR` is wiped when the
  user's last session ends, so every reboot started from nothing — and an empty
  calendar cache means waiting for a full EDS refresh at ~10 s per calendar.
- `hypr-calendar-cache.service` rebuilds the whole look-ahead at login and again
  at shutdown (`ExecStop`, which needs `RemainAfterExit=yes` to fire at all).
- The console palette, `misc:background_color` and the wallpaper fallback share
  one colour: `#3b3554`, the measured mean of the wallpaper.

## Neovim

`lazy.nvim`, 56 plugins. LSP through `mason-lspconfig` with `vtsls`, `pyright`,
`gopls`, `lua_ls` and friends; **Java through `nvim-jdtls`, not lspconfig** —
jdtls needs a per-project workspace and loads its debug support as OSGi bundles,
and starting it twice corrupts that workspace.

Two things that will bite anyone copying this:

- jdtls requires **Java 21+**. On 17 it dies during OSGi startup with a bare
  "An error has occurred" that reaches Neovim as nothing at all — no client, no
  message. `config/nvim/lua/plugins/languages/java.lua` resolves a 21+ runtime
  explicitly and leaves the system default alone.
- `mason-lspconfig` since v2 enables **every** server Mason has on disk. It
  started a second jdtls, and gave `.ts` buffers three servers at once. Both are
  excluded by name.

Debugging is `nvim-dap` with adapters for Python, JS/TS, Go and codelldb, on the
IDE key layout (F5/F9/F10/F11/F12) plus a `<leader>d` group.
