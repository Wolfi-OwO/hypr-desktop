# hypr-desktop

A Hyprland desktop built to replace GNOME without losing what GNOME did well.

The bar, the notification centre, the panels, the wallpaper, the Alt+Tab
switcher and the desktop widgets are all one [Quickshell](https://quickshell.org)
process. System state reaches them over a local MQTT broker rather than through
polling. Neovim is configured for TypeScript, Java, Python and Go with LSP,
debugging and formatting.

Everything here runs on one machine — an Arch laptop with a 2880x1800 display at
scale 2. It is published because the reasoning is written down, not because it
is a framework: read the comments, take the parts that apply, ignore the rest.

## Screenshot

_(add one)_

## Install

```sh
git clone https://github.com/Wolfi-OwO/hypr-desktop.git
cd hypr-desktop
./install.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for what that does and what it
deliberately leaves for you (your monitor config, the boot-time console-palette
fix).

## What is here

| Path | What it is |
|---|---|
| `config/hypr/` | Hyprland (Lua config), lock screen, wallpaper |
| `config/quickshell/` | The whole shell: bar, panels, widgets, notifications |
| `config/nvim/` | Neovim: lazy.nvim, LSP, nvim-dap, conform, treesitter |
| `config/mosquitto/` | The event bus broker, tuned for a small footprint |
| `bin/` | Helper scripts the shell calls (`hypr-*`) |
| `systemd/user/` | Broker, event daemon, calendar cache units |
| `docs/` | Architecture, install, keybindings, troubleshooting |

## The short version of why

**The bar is not waybar.** waybar listens for the portal's `color-scheme`
itself and reloads completely when it changes — tearing down its layer surface
and rebuilding it, visibly disappearing for about 100 ms. Measured frame by
frame. It cannot be turned off. Here every colour is bound to one `Theme`
singleton that animates them, so the whole shell cross-fades together.

**Nothing polls.** A daemon (`bin/hypr-eventd`) reads `/proc` and `/sys`
directly and subscribes to the real event sources — `pactl subscribe`,
`ip monitor`, `gsettings monitor`, and `poll()` on the backlight's
`actual_brightness`. It publishes to MQTT; the shell subscribes. Measured end
to end:

```
brightness   ~5 ms     sysfs_notify
volume/mute  ~24 ms    pactl subscribe
theme        ~82 ms    gsettings monitor
sensors      <=750 ms  daemon tick (no event source exists)
```

What it replaced ran a shell script every 2 s that forked **107 `clone()` and
75 `execve()` calls per run** — measured with strace.

**Login lands on a warm desktop.** Widget caches live in `~/.cache`, not
`$XDG_RUNTIME_DIR`, which systemd wipes when the last session ends. MQTT topics
are retained, so the first painted frame carries real values instead of zeros.
The calendar cache is rebuilt at login and again at shutdown.

**One colour across every boot stage.** The console palette, Hyprland's empty
desktop and the wallpaper's fallback are all `#3b3554` — the measured mean of
the wallpaper image. There is no black flash between the greeter and the shell,
only the structure of the image fading in.

## Requirements

Arch, Hyprland 0.55+ (the Lua config format), Quickshell, mosquitto, a Nerd
Font. Full list and setup in [docs/INSTALL.md](docs/INSTALL.md).

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit, and why
- [INSTALL.md](docs/INSTALL.md) — dependencies, setup, what to change first
- [KEYBINDINGS.md](docs/KEYBINDINGS.md) — every binding
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — failures hit here, and the fixes
- [CONTRIBUTING.md](CONTRIBUTING.md) — conventions, if you send a patch

## Licence

MIT. See [LICENSE](LICENSE).
