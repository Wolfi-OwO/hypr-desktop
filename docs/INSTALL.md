# Install

This is a personal configuration, not a distribution. Read it before running it.
Several paths are absolute (`/home/woofi/...`) and the UI labels are German.
Both are called out below.

## Dependencies

```sh
# Compositor and shell
sudo pacman -S hyprland hyprlock xdg-desktop-portal-hyprland \
               qt6-declarative qt6-wayland

# Event bus
sudo pacman -S mosquitto

# Tools the shell calls
sudo pacman -S wireplumber brightnessctl bluez-utils networkmanager \
               iw jq grim slurp swappy wl-clipboard cliphist \
               rofi wlogout kitty nautilus

# Calendar (reads the Evolution data server, so a GNOME Online Account works)
sudo pacman -S evolution-data-server gnome-online-accounts python-gobject \
               python-dateutil

# Fonts
sudo pacman -S ttf-firacode-nerd noto-fonts noto-fonts-emoji

# Neovim
sudo pacman -S neovim ripgrep fd nodejs npm python jdk21-openjdk go
```

Quickshell is in the AUR:

```sh
paru -S quickshell
```

`jdk21-openjdk` is not optional if you write Java — see ARCHITECTURE.md.

## Layout

```sh
git clone https://github.com/Wolfi-OwO/hypr-desktop.git
cd hypr-desktop

cp -r config/hypr        ~/.config/
cp -r config/quickshell  ~/.config/
cp -r config/nvim        ~/.config/
cp -r config/mosquitto   ~/.config/
cp    bin/hypr-*         ~/.local/bin/
cp    systemd/user/*     ~/.config/systemd/user/

chmod +x ~/.local/bin/hypr-*
```

## Services

```sh
systemctl --user daemon-reload
systemctl --user enable --now mosquitto hypr-eventd
systemctl --user enable hypr-calendar-cache.service hypr-calendar-cache.timer
```

Check the bus is alive:

```sh
mosquitto_sub --unix /run/user/$(id -u)/mosquitto.sock -t 'hypr/#' -v
```

You should see one line per topic within a second.

## Change these first

**1. Absolute paths.** Nine files contain `/home/woofi`. Quickshell's `Process`
does not expand `~` or `$HOME`, which is why they are literal:

```sh
grep -rl /home/woofi ~/.config/quickshell ~/.config/hypr ~/.local/bin \
  | xargs sed -i "s|/home/woofi|$HOME|g"
```

**2. The MQTT socket path** is `/run/user/1000/mosquitto.sock` in the QML. If
your uid is not 1000:

```sh
grep -rl 'run/user/1000' ~/.config/quickshell \
  | xargs sed -i "s|/run/user/1000|/run/user/$(id -u)|g"
```

**3. Your monitor.** `config/hypr/hyprland.lua` starts with `eDP-1` at
`2880x1800@90`, scale 2. Run `hyprctl monitors` and set yours.

**4. Weather location.** `~/.config/hypr/weather.conf`, deliberately not in this
repository:

```
LAT=47.2692
LON=11.4041
TZ=Europe/Vienna
PLACE=Innsbruck
```

Look coordinates up without an API key:

```sh
curl 'https://geocoding-api.open-meteo.com/v1/search?name=Innsbruck&count=1'
```

Without this file the widget shows Vienna.

**5. UI language.** Labels in the shell are German ("Einstellungen", "Keine
Termine", "Nicht stören"). Comments and documentation are English throughout;
the labels are not, because this desktop is used in German. Grep for them in
`config/quickshell/*.qml` if you want them changed.

## Neovim

First launch installs everything:

```sh
nvim --headless "+Lazy! sync" +qa
nvim --headless -c 'MasonToolsInstallSync' -c 'qa!'
nvim --headless -c 'MasonInstall debugpy delve' -c 'qa!'
nvim --headless -c 'TSUpdateSync' -c 'qa!'
```

Expect a few minutes. Verify:

```sh
nvim --headless --startuptime /dev/stdout somefile.py -c 'qa!' | tail -1
```

Around 175 ms here with 56 plugins.

## Optional: the boot-time bits

The console flash before the greeter is fixed by a script that sets the console
palette. It needs root and touches SDDM's `Xsetup`/`Xstop`, so it is not copied
by the steps above — see TROUBLESHOOTING.md if you want it.
