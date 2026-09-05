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

## Application icons show as a magenta checkerboard

That pattern is Qt's placeholder for an icon that failed to LOAD, not one that
is missing -- a genuinely absent icon renders blank. Two separate causes
produced it here.

**The active icon theme's `Inherits` chain is too short.** `WhiteSur-dark`
shipped with `Inherits=hicolor,breeze`, and several common names
(`preferences-system-network`, `network-wired`, `display`) simply do not exist
in that short chain, though they exist in themes already installed
(Papirus-Dark, Tela-circle). Extend the chain in
`/usr/share/icons/<theme>/index.theme` -- back it up first, it is not owned by
any package so an update will not restore it if broken:

```sh
sudo sed -i 's|^Inherits=.*|Inherits=Papirus-Dark,Tela-circle,breeze,Adwaita,hicolor|' \
    /usr/share/icons/WhiteSur-dark/index.theme
```

**`QIconLoader` caches a lookup failure for the running process's lifetime.**
Installing an icon file while Quickshell is already running does NOT fix a name
it already failed to resolve once -- the negative result is cached, and a
config reload (`hyprctl reload`, editing a `.qml` file) does not clear it. Only
a full process restart does. If an icon still shows the checkerboard after
adding the file, that is why -- restart the shell (see "Full shell restart" in
this document) before concluding the fix did not work.

The reliable placement for a one-off icon, regardless of what the packaged
theme chain resolves: `~/.local/share/icons/hicolor/scalable/apps/<name>.svg`.
`hicolor` is always the final, guaranteed fallback per the freedesktop icon
spec, so this works even when the active theme is broken or absent.

## Black screen after opening the lid, sometimes

Lid closed, machine suspends normally; lid opened later and the panel stays
black, unresponsive to keys or the trackpad. Not every time -- reproduced once
after a 52-minute suspend, not on shorter ones.

Investigated via `journalctl -b -1` around the actual resume timestamp rather
than guessed at: the kernel's own resume sequence completed cleanly (i915 GuC/
HuC firmware reload, NVMe re-init, Wi-Fi re-association), hypridle's
`after_sleep_cmd` ran and reported `hyprctl dispatch 'hl.dsp.dpms("on")'` ->
`ok`, and `hypr-resume-refresh.service` finished without error -- every
software-level signal says the resume succeeded. That combination -- a clean
software resume with a still-black panel that a DPMS toggle does not fix --
points below the compositor, at the display's own power state rather than
anything Hyprland or hypridle can see or retry.

This machine is Alder Lake-P (`Intel Iris Xe Graphics`, confirmed via
`lspci -k`), and ADL-P has a long-documented i915 bug where deep display
C-states (DC5/DC6) fail to re-link the eDP panel after an s2idle resume. The
kernel cmdline already carried `i915.enable_psr=0` (Panel Self Refresh, the
usual first suspect for this exact symptom) from an earlier round of this same
problem, plus a since-dead `i915.enable_rc6=0` -- that parameter no longer
exists under `/sys/module/i915/parameters/` on this kernel, so it has been
inert for a while. Checked what was still live:

```sh
for f in enable_dc enable_fbc enable_psr2_sel_fetch; do
    echo "$f = $(sudo cat /sys/module/i915/parameters/$f)"
done
# enable_dc = -1   <- platform default, i.e. NOT disabled
```

`enable_dc = -1` means the deep DC states this bug is attributed to were still
live. Added `i915.enable_dc=0` to `GRUB_CMDLINE_LINUX_DEFAULT` in
`/etc/default/grub`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg` to
regenerate. **Needs a reboot to take effect**, and because this only
reproduced after a long suspend, confirming the fix means normal use over a
few days, not a single quick lid close/open.

Known trade-off: disabling DC5/DC6 gives up some of the panel's deepest idle
power state, which costs a small amount of battery during long suspends. Kept
anyway -- an unusable black screen after a suspend that should just work costs
more than the battery does.

**Second contributing factor, found on a repeat of this same problem:**
`journalctl -k` around actual resume events (not just this one, a second one
caught live in a later session) shows

```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PC00.LPCB.EC0._Q44.WM00], AE_NOT_FOUND
ACPI Error: Aborting method \_SB.PC00.LPCB.EC0._Q44 due to previous error (AE_NOT_FOUND)
```

Do not confuse this with `_Q70.SEN5`, which throws the identical class of
error but fires on a constant ~2 s cycle around the clock, resume or not --
that one is unrelated background EC sensor-poll noise from the same buggy
table and has nothing to do with this. `_Q44.WM00` is different: across two
separate boots it appeared ONLY within seconds of an actual resume/wake event,
never during idle runtime. It correlates with a hypridle crash
("Disconnected from pollfd", see the systemd Restart=always fix elsewhere in
this document) in one case and with the black screen in the other.

This is Lenovo's own DSDT referencing an EC query method (`WM00`, plausibly
"wake monitor") that does not exist in the loaded ACPI table -- a firmware
bug, not something Linux, i915 or Hyprland can retry around. If the EC's own
attempt to signal the panel to wake fails silently here, that would explain a
black screen that looks completely clean from the OS side (kernel resume,
hypridle's DPMS-on, hypr-resume-refresh -- everything already checked out
above).

Machine: Lenovo Yoga 7 14IAL7 (type 82QE), BIOS J1CN45WW (2024-06-24) -- read
with `sudo dmidecode -s bios-version`. Lenovo's download page for this model
is at support.lenovo.com (search "Yoga 7 14IAL7 BIOS update"); it blocks
automated fetches, so check by hand whether a BIOS newer than J1CN45WW is
listed and whether its release notes mention sleep/resume/EC fixes -- a
firmware update is the correct fix for a DSDT bug, safer than hand-patching
the ACPI tables. An SSDT override that stubs out the missing `WM00` method is
possible but was deliberately not attempted here: it touches EC
communication, which battery, thermal and keyboard backlight all also depend
on, and a mistake there is a much worse afternoon than this one.

**Third confirmation, 2026-08-04, lid close/open specifically (not a general
suspend):** live `journalctl -k -f` around a deliberate lid-close-then-open
cycle caught

```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PC00.LPCB.EC0._Q12.WM00], AE_NOT_FOUND
ACPI Error: Aborting method \_SB.PC00.LPCB.EC0._Q12 due to previous error (AE_NOT_FOUND)
```

-- five times back to back, all at the same second, at the exact moment of
the lid event. Same missing `WM00` symbol as `_Q44` above, different EC query
number: this DSDT has more than one `_Qxx` handler that references the
undefined symbol, and the lid switch specifically trips `_Q12`. Still firmware,
still not something to retry around from Linux.

Symptom as reported this time was more specific than "black for up to a
minute": screen shows briefly, goes black again for about 30s, then recovers
on its own. `hypr-dpms-ensure-on`'s polling window was widened from 20s to 44s
to cover that 30s mark with margin, and it no longer trusts a single "on"
reading (Hyprland's own dpmsStatus can say true while the panel is still
physically dark if the fault is below Hyprland) -- it now waits for two
consecutive "on" readings 2s apart before giving up. This is still a
mitigation, not a fix; the SSDT-override trade-off above is unchanged and
still not attempted for the same reason.

## BetterDiscord stops working after Discord updates itself

Discord on Linux self-updates independently of pacman: it downloads a fresh
`app-<version>` directory under `~/.config/discord/` and launches from there,
leaving the pacman-tracked version's directory behind. `bdcli discover`
showed the mismatch directly:

```
pacman -Qs discord            # local/discord 1:1.0.155-1
ps -eo comm,args | grep discord   # running from .../app-1.0.156/Discord
bdcli discover                # BD INJECTED: no, for the live 1.0.156 path
```

BetterDiscord's injection lives inside the specific `app-<version>/resources`
directory it was installed into. A self-update never carries that over, so
every self-update is functionally a fresh, unpatched Discord install as far
as BD is concerned -- unrelated to BD's own "survives Discord's updates"
changelog, which is about BD's plugin/asar loading surviving Discord's
in-app JS hot-patches, not about surviving Discord replacing its own
directory on disk.

Fix: re-run the installer against whatever the currently running version is.
`bdcli install` auto-detects the live install (`--channel stable` is enough
here; there is only one channel installed) and is safe to re-run any number
of times -- `install` is an alias for `reinstall`.

```sh
bdcli install --channel stable
```

Confirmed injected, not just present on disk, by screenshotting the
restarted client (`grim` on the window's logical geometry from
`hyprctl clients -j`) and reading the result: BD's own changelog modal and
its "Addon Updater" plugin toast were both visible and listing the user's
actual installed plugins.

`bdcli` is the one tool to use for this. `betterdiscord-installer-bin` (the
GUI installer) is also installed and does the same job through a window
instead of a terminal -- redundant with `bdcli` for this machine's actual
(headless-scriptable) usage, kept installed but not the one to reach for.

No watcher or systemd unit for this: Discord does not self-update often
enough to justify a background process polling for it, and `bdcli install`
being a safe, idempotent single command is already the smallest thing that
holds. ponytail: manual re-run, no auto-detection of Discord's own
self-update -- upgrade to a small path-watcher only if this is still
happening more than once every few weeks.
