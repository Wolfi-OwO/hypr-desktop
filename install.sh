#!/usr/bin/env bash
# Automates docs/INSTALL.md. Read that file first if anything here surprises
# you -- this script does exactly what it describes, in the same order, and
# is not a substitute for understanding what it changes on your machine.
#
# This is still a personal configuration, not a distribution: it targets
# Arch (or an Arch derivative with pacman), assumes Hyprland + Quickshell,
# and writes into $HOME and your user systemd instance. Nothing here touches
# the boot/login path -- the console-palette fix in TROUBLESHOOTING.md is
# root-owned and SDDM-specific, and stays a manual step on purpose.
#
# Safe to re-run: every step is idempotent, and anything this script would
# overwrite in $HOME is backed up first (see backup_if_exists below).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
step()  { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info()  { printf '  %s\n' "$1"; }
warn()  { printf '  %s%s%s\n' "$YELLOW" "$1" "$RESET"; }
ok()    { printf '  %s%s%s\n' "$GREEN" "$1" "$RESET"; }

if [[ ! -f "$SCRIPT_DIR/README.md" || ! -d "$SCRIPT_DIR/config" ]]; then
    echo "Run this from inside the cloned hypr-desktop repo." >&2
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    echo "No pacman found -- this config is Arch-only (see docs/INSTALL.md)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
step "1/7  Dependencies"
# ---------------------------------------------------------------------------
# Left as normal interactive `pacman -S` calls (no --noconfirm) so you see
# and approve what's being installed on your own machine, same as if you'd
# typed these yourself from docs/INSTALL.md.

sudo pacman -S --needed hyprland hyprlock xdg-desktop-portal-hyprland \
                        qt6-declarative qt6-wayland

sudo pacman -S --needed mosquitto

sudo pacman -S --needed wireplumber brightnessctl bluez-utils networkmanager \
                        iw jq grim slurp swappy wl-clipboard cliphist \
                        rofi wlogout kitty nautilus

sudo pacman -S --needed evolution-data-server gnome-online-accounts \
                        python-gobject python-dateutil

sudo pacman -S --needed ttf-firacode-nerd noto-fonts noto-fonts-emoji

read -r -p "  Also install Neovim + its language toolchain (nvim, ripgrep, fd, nodejs, npm, python, jdk21-openjdk, go)? [y/N] " nvim_deps
if [[ "$nvim_deps" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed neovim ripgrep fd nodejs npm python jdk21-openjdk go
    WITH_NEOVIM=1
else
    WITH_NEOVIM=0
fi

AUR=""
for cand in paru yay; do
    command -v "$cand" >/dev/null 2>&1 && { AUR="$cand"; break; }
done
if [[ -z "$AUR" ]]; then
    echo "Need an AUR helper (paru or yay) to install quickshell -- none found." >&2
    echo "Install one first, then re-run this script." >&2
    exit 1
fi
"$AUR" -S --needed quickshell

# ---------------------------------------------------------------------------
step "2/7  Layout"
# ---------------------------------------------------------------------------
# A pre-existing file is backed up, never silently clobbered -- ".pre-install"
# plus a timestamp, so re-running this doesn't chain backups of backups.
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo pre-install)"
backup_if_exists() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        warn "backing up existing $target -> $target.pre-install-$STAMP"
        mv "$target" "$target.pre-install-$STAMP"
    fi
}

mkdir -p ~/.config ~/.local/bin ~/.config/systemd/user

for d in hypr quickshell nvim mosquitto; do
    backup_if_exists "$HOME/.config/$d"
    cp -r "config/$d" ~/.config/
done

cp bin/hypr-* ~/.local/bin/
chmod +x ~/.local/bin/hypr-*

cp systemd/user/*.service systemd/user/*.timer ~/.config/systemd/user/

ok "Config, scripts and user systemd units copied into place."

# ---------------------------------------------------------------------------
step "3/7  Fix absolute paths for this machine"
# ---------------------------------------------------------------------------
# Quickshell's Process does not expand ~ or \$HOME, so the repo carries the
# author's own literal /home/woofi -- rewritten here to your actual $HOME,
# and only in the deployed copies, never in this checkout.
grep -rl '/home/woofi' ~/.config/quickshell ~/.config/hypr ~/.local/bin \
                        ~/.config/systemd/user 2>/dev/null \
    | xargs -r sed -i "s|/home/woofi|$HOME|g"

# Same idea for the MQTT socket path, which is uid-specific.
if [[ "$(id -u)" != "1000" ]]; then
    grep -rl 'run/user/1000' ~/.config/quickshell 2>/dev/null \
        | xargs -r sed -i "s|/run/user/1000|/run/user/$(id -u)|g"
fi

ok "Rewrote /home/woofi and the mosquitto socket path to match this account."

# ---------------------------------------------------------------------------
step "4/7  Weather location"
# ---------------------------------------------------------------------------
# Deliberately not copied from config/ -- weather.conf is gitignored in this
# repo because it is personal, and skipped here if you already have one so a
# re-run never overwrites a location you already set.
WEATHER_CONF="$HOME/.config/hypr/weather.conf"
if [[ -f "$WEATHER_CONF" ]]; then
    info "weather.conf already exists, leaving it alone: $WEATHER_CONF"
else
    read -r -p "  Place name for the weather widget (blank = skip, defaults to Vienna): " place
    if [[ -n "$place" ]]; then
        geo="$(curl -fsS "https://geocoding-api.open-meteo.com/v1/search?name=$(printf '%s' "$place" | sed 's/ /%20/g')&count=1" 2>/dev/null || true)"
        lat="$(printf '%s' "$geo" | grep -o '"latitude":[0-9.-]*' | head -1 | cut -d: -f2)"
        lon="$(printf '%s' "$geo" | grep -o '"longitude":[0-9.-]*' | head -1 | cut -d: -f2)"
        tz="$(printf '%s' "$geo" | grep -o '"timezone":"[^"]*"' | head -1 | cut -d: -f2- | tr -d '"')"
        name="$(printf '%s' "$geo" | grep -o '"name":"[^"]*"' | head -1 | cut -d: -f2- | tr -d '"')"
        if [[ -n "$lat" && -n "$lon" ]]; then
            cat > "$WEATHER_CONF" <<EOF
LAT=$lat
LON=$lon
TZ=${tz:-UTC}
PLACE=${name:-$place}
EOF
            ok "Wrote $WEATHER_CONF ($name: $lat, $lon)."
        else
            warn "Could not geocode '$place' -- skipping."
            warn "Copy config/hypr/weather.conf.example to $WEATHER_CONF and fill it in by hand."
        fi
    else
        info "Skipped. The widget shows Vienna until you copy"
        info "config/hypr/weather.conf.example to $WEATHER_CONF and fill it in."
    fi
fi

# ---------------------------------------------------------------------------
step "5/7  Services"
# ---------------------------------------------------------------------------
systemctl --user daemon-reload
systemctl --user enable --now mosquitto.service hypr-eventd.service
systemctl --user enable --now hypr-calendar-cache.service hypr-calendar-cache.timer
systemctl --user enable --now hypr-resume-refresh.timer
systemctl --user enable --now hypridle.service hyprpolkitagent.service hyprsunset.service
systemctl --user enable --now hypr-sunset-scheduler.service hypr-sunset-scheduler.timer
systemctl --user enable --now hypr-boot-report.service

# NOT enabled: hypr-backup.{service,timer}. It needs its own `restic init`
# against a destination and password file that are yours to choose -- see
# step 7 below rather than getting a repository silently created for you.

if timeout 2 mosquitto_sub --unix "/run/user/$(id -u)/mosquitto.sock" -t 'hypr/#' -C 1 >/dev/null 2>&1; then
    ok "Event bus is alive."
else
    warn "No message on the bus within 2s -- check: systemctl --user status mosquitto hypr-eventd"
fi

# ---------------------------------------------------------------------------
step "6/7  Neovim"
# ---------------------------------------------------------------------------
if [[ "$WITH_NEOVIM" == "1" ]]; then
    info "First-run plugin/LSP/tool install -- this takes a few minutes."
    nvim --headless "+Lazy! sync" +qa
    nvim --headless -c 'MasonToolsInstallSync' -c 'qa!'
    nvim --headless -c 'MasonInstall debugpy delve' -c 'qa!'
    nvim --headless -c 'TSUpdateSync' -c 'qa!'
    ok "Neovim bootstrapped."
else
    info "Skipped (you declined the Neovim toolchain in step 1)."
fi

# ---------------------------------------------------------------------------
step "7/7  What this script did NOT do"
# ---------------------------------------------------------------------------
cat <<'EOF'

  Your monitor. config/hypr/hyprland.lua starts with eDP-1 at 2880x1800@90,
  scale 2 -- guessing at your actual output would risk a broken display, so
  this is left for you: run `hyprctl monitors` once Hyprland is up and edit
  hyprland.lua to match.

  The boot-time console flash (docs/TROUBLESHOOTING.md, "A text console
  flashes before the desktop"). It needs root and edits SDDM's Xsetup/Xstop
  directly -- exactly the kind of login-path change that costs you the
  whole machine if it's wrong, so it is not automated. Follow that section
  by hand if you want it.

  UI language. The shell's own labels are German. Comments and docs are
  English throughout; the labels are not, because this desktop is used in
  German. Grep config/quickshell/*.qml for the strings you want changed.

  Daily backups (hypr-backup.service/.timer, not enabled). Needs a restic
  repository you choose the destination and password for -- read
  bin/hypr-backup's header, then:
    restic init -r /var/backups/restic   # or wherever you want it
    systemctl --user enable --now hypr-backup.timer

EOF

ok "Done. Log out and back into Hyprland (or start it) to pick everything up."
