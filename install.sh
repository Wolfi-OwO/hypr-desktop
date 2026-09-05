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
#
# -n/--dry-run prints the full plan (packages, paths, units, conflicts) and
# exits 0 without installing, copying or enabling anything.
# -y/--yes skips the confirmation prompt after the plan is printed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
step()  { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info()  { printf '  %s\n' "$1"; }
warn()  { printf '  %s%s%s\n' "$YELLOW" "$1" "$RESET"; }
ok()    { printf '  %s%s%s\n' "$GREEN" "$1" "$RESET"; }

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unknown option: $arg (supported: -n/--dry-run, -y/--yes)" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$SCRIPT_DIR/README.md" || ! -d "$SCRIPT_DIR/config" ]]; then
    echo "Run this from inside the cloned hypr-desktop repo." >&2
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    echo "No pacman found -- this config is Arch-only (see docs/INSTALL.md)." >&2
    exit 1
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

# A pre-existing file or directory is backed up, never silently clobbered --
# ".pre-install" plus a timestamp, so re-running this doesn't chain backups
# of backups.
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo pre-install)"
backup_if_exists() {
    local target="$1"
    if [[ -L "$target" ]]; then
        # Measured: a symlinked ~/.config/hypr (dotfiles-managed configs are
        # commonly symlinks) passed the old `-e && ! -L` guard untouched,
        # and the `cp -r` right after it followed the symlink and wrote
        # straight into whatever it pointed at -- silently editing the
        # user's own separate dotfiles repo through their config directory.
        # No safe automatic move here (the real target lives elsewhere and
        # moving the link doesn't move it), so this aborts by name instead.
        echo "Refusing to overwrite symlink: $target -> $(readlink "$target")" >&2
        echo "Move or remove it yourself, then re-run this script." >&2
        exit 1
    fi
    if [[ -e "$target" ]]; then
        warn "backing up existing $target -> $target.pre-install-$STAMP"
        mv "$target" "$target.pre-install-$STAMP"
    fi
}

# Same four directories the Layout step below deploys, plus the single
# fontconfig file (see step 2 for why that one isn't a whole-directory
# copy) -- named once here and reused so the preflight conflict scan and
# the actual deploy loop can't drift apart.
DEPLOY_CONFIG_DIRS=(hypr quickshell nvim mosquitto)
FONTCONF_TARGET="$HOME/.config/fontconfig/conf.d/50-math-symbol-fallback.conf"

show_not_done() {
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
}

# ---------------------------------------------------------------------------
step "Plan -- nothing above this point has installed, copied or enabled anything"
# ---------------------------------------------------------------------------
info "Packages via pacman:"
info "  hyprland hyprlock xdg-desktop-portal-hyprland qt6-declarative qt6-wayland"
info "  mosquitto"
info "  wireplumber brightnessctl bluez-utils networkmanager iw jq grim slurp swappy wl-clipboard cliphist rofi wlogout kitty nautilus"
info "  evolution-data-server gnome-online-accounts python-gobject python-dateutil"
info "  ttf-firacode-nerd noto-fonts noto-fonts-emoji"
info "  (only if you say yes at the step 1 prompt) neovim ripgrep fd nodejs npm python jdk21-openjdk go"
info "Packages via $AUR (AUR): quickshell ttf-unifont"
info ""
info "Paths written or backed up (existing targets moved to *.pre-install-$STAMP):"
for d in "${DEPLOY_CONFIG_DIRS[@]}"; do
    info "  ~/.config/$d"
done
info "  $FONTCONF_TARGET (this file only -- see step 2 for why not the whole directory)"
info "  ~/.local/bin/hypr-*"
info "  ~/.config/systemd/user/*.service, *.timer"
info "  ~/.config/hypr/weather.conf (only if you answer the step 4 prompt; left alone if it already exists)"
info ""
info "systemd --user units enabled: mosquitto hypr-eventd hypr-calendar-cache(+.timer)"
info "  hypr-resume-refresh.timer hypridle hyprpolkitagent hyprsunset"
info "  hypr-sunset-scheduler(+.timer) hypr-boot-report"
info "  NOT enabled: hypr-backup.timer (needs a restic destination you choose)"

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on PATH -- the hypr-* scripts installed there won't run by bare name." ;;
esac

CONFLICTS=()
for d in "${DEPLOY_CONFIG_DIRS[@]}"; do
    [[ -L "$HOME/.config/$d" ]] && CONFLICTS+=("$HOME/.config/$d")
done
[[ -L "$FONTCONF_TARGET" ]] && CONFLICTS+=("$FONTCONF_TARGET")
if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    warn "Symlink conflicts -- cp writes THROUGH a symlink into whatever it points at, so these will NOT be backed up automatically:"
    for c in "${CONFLICTS[@]}"; do
        warn "  $c -> $(readlink "$c")"
    done
fi

info ""
info "What this script deliberately will NOT do:"
show_not_done

if [[ "$DRY_RUN" == "1" ]]; then
    [[ ${#CONFLICTS[@]} -gt 0 ]] && warn "Dry run: a real run would abort here for the conflict(s) above."
    ok "Dry run: nothing was installed, copied or enabled."
    exit 0
fi

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo "Aborting: resolve the symlink conflict(s) above, then re-run." >&2
    exit 1
fi

if [[ "$ASSUME_YES" != "1" ]]; then
    read -r -p "Proceed with the plan above? [y/N] " proceed
    [[ "$proceed" =~ ^[Yy]$ ]] || { echo "Aborted, nothing changed."; exit 0; }
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

"$AUR" -S --needed quickshell
if command -v quickshell >/dev/null 2>&1; then
    qs_ver="$(quickshell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ -n "$qs_ver" ]]; then
        lowest="$(printf '%s\n%s\n' "$qs_ver" "0.3.1" | sort -V | head -1)"
        [[ "$lowest" == "0.3.1" ]] || warn "quickshell $qs_ver is older than 0.3.1 -- shell.qml may rely on newer APIs; consider updating."
    fi
fi
# GNU Unifont: last-resort glyph fallback for Discord/Electron sidebar text.
# noto-fonts (above) does not cover Fullwidth Forms (U+FF00-FFEF) -- only
# noto-fonts-cjk does, at ~300MB installed, disproportionate for a handful
# of decorative badge glyphs. Unifont is ~37MB and covers the whole BMP as a
# fallback; see config/fontconfig/conf.d/50-math-symbol-fallback.conf.
"$AUR" -S --needed ttf-unifont

# ---------------------------------------------------------------------------
step "2/7  Layout"
# ---------------------------------------------------------------------------
mkdir -p ~/.config ~/.local/bin ~/.config/systemd/user

for d in "${DEPLOY_CONFIG_DIRS[@]}"; do
    backup_if_exists "$HOME/.config/$d"
    cp -r "config/$d" ~/.config/
done

# fontconfig is deliberately NOT in the loop above: unlike hypr/quickshell/
# nvim/mosquitto, ~/.config/fontconfig is a directory lots of OTHER things
# drop files into (font-manager, distro packages, hand-written hinting
# tweaks) -- backing up the whole directory just to add one file would
# move aside conf.d rules this install has nothing to do with. Deploy just
# the one file, additively, into a conf.d that's created if missing and
# left alone (other than this one file) if it already exists.
mkdir -p "$(dirname "$FONTCONF_TARGET")"
backup_if_exists "$FONTCONF_TARGET"
cp "config/fontconfig/conf.d/50-math-symbol-fallback.conf" "$FONTCONF_TARGET"

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
show_not_done

ok "Done. Log out and back into Hyprland (or start it) to pick everything up."
