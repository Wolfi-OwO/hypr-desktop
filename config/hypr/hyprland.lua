-- ============================================================================
--  Hyprland config — woofi
--  Written 2026-07-26 in Lua, the supported format since Hyprland 0.55
--  (hyprlang / hyprland.conf is deprecated upstream; window rules in
--  particular no longer parse in the old flat syntax).
--
--  Keybinds mirror the GNOME bindings this session replaces, so muscle
--  memory carries over: STRG+ALT+arrows switches workspace, STRG+ALT+S
--  opens the application launcher, SUPER+L locks, ALT+F4 closes.
--
--  Old config kept at ~/.config/hypr-backup-20260726/hyprland.conf
-- ============================================================================

------------------
---- MONITORS ----
------------------
-- Matched to your GNOME setup (~/.config/monitors.xml): scale 2 at 90 Hz.
hl.monitor({
    output   = "eDP-1",
    mode     = "2880x1800@90",
    position = "0x0",
    scale     = 2,
})

-- Your ultrawide profile from GNOME (scale 1). Plug it in, run
-- `hyprctl monitors` to confirm the connector name, then uncomment.
-- hl.monitor({ output = "DP-1", mode = "3440x1440@144", position = "auto", scale = 1 })

-- Catch-all for anything else.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })


---------------------
---- MY PROGRAMS ----
---------------------
local terminal    = "kitty"
local fileManager = "nautilus"
-- The application launcher is the Quickshell menu, not a separate program, so
-- it is invoked over IPC and has no entry here. rofi is still used for the
-- Alt+F2 run dialog, which takes an arbitrary command rather than a .desktop
-- entry -- the shell menu only lists installed applications.
local runDialog   = "rofi -show run"
-- Guarded, exactly as hypridle's lock_cmd is.
--
-- This was a bare "hyprlock". hypridle also locks -- on its own timer and
-- before suspend -- so pressing SUPER+L while a lock was already up or coming
-- up started a SECOND hyprlock against the same session. Two instances fight
-- over the same surface, one dies, and Hyprland puts up its lockdead screen
-- ("Oopsie daisy, it looks like you locked your screen but the lockscreen app
-- died"). That is what happened on 2026-08-01.
local lock        = "pidof hyprlock || hyprlock"
local browser     = "brave"


-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
    -- Make the session bus aware of Wayland, or xdg-desktop-portal and
    -- screen sharing silently misbehave.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Shell components
    -- waybar is gone: the bar is now part of Quickshell (Bar.qml). The only
    -- reason was the light/dark switch -- waybar listens for the portal's
    -- color-scheme itself and reloads completely in response, tearing its layer
    -- surface down and back up and visibly disappearing for around 100 ms
    -- (measured frame by frame). It could not be turned off.
    --
    -- The configuration under ~/.config/waybar is left in place: it costs
    -- nothing and is the way back should the new bar cause trouble -- `waybar &`
    -- is then all it takes.
    -- hyprpaper is gone: Quickshell draws the wallpaper itself now (shell.qml,
    -- layer "quickshell-wallpaper"). That makes it cross-fade on a light/dark
    -- switch instead of cutting over hard, and the widgets can no longer be
    -- covered by a newly created hyprpaper surface.
    -- No separate notification daemon: Quickshell (below) is the server. swaync
    -- had no calendar and no two-column layout, so the centre is hand-built.

    -- Desktop widgets on the wlr-layer-shell background layer. This is the
    -- capability GNOME never had: layer-shell surfaces are always present,
    -- so these cannot vanish the way azclock/conky did under Mutter.
    hl.exec_cmd("qs -c /home/woofi/.config/quickshell")

    -- Watchdog for the shell surfaces.
    --
    -- Quickshell once kept running but had not a single layer surface left --
    -- bar, wallpaper and widgets were gone while the process was alive. A
    -- process watchdog would not have noticed. This one checks every 8 s that
    -- the surfaces really exist and restarts otherwise.
    hl.exec_cmd("/home/woofi/.local/bin/hypr-shell-guard")

    -- Polkit agent is a systemd user unit now (hyprpolkitagent.service), not
    -- an autostart line. It replaces polkit-gnome, which cost 13.7 MB and
    -- dragged GTK into the session for a single password dialog;
    -- hyprpolkitagent is Qt/QML and matches the rest of the shell.
    --
    -- Without SOME agent running, GUI password prompts fail silently -- no
    -- dialog, no error, the action just does not happen.

    -- Clipboard history (replaces the GNOME clipboard-indicator extension)
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- No application launcher in the autostart any more. ULauncher had to run
    -- permanently because its window was only shown and hidden. The launcher is
    -- now the Quickshell applications menu, which is part of the shell that is
    -- already running.
end)


--------------------------------
---- RAISE FOCUSED TO FRONT ----
--------------------------------
-- With every window floating, the focused one must come to the front or it
-- stays buried. Hyprland has no `raise_on_focus` option (checked: "no such
-- option"), so hook the window.active event and raise on every focus change.
hl.on("window.active", function()
    hl.dispatch(hl.dsp.window.bring_to_top())
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
hl.env("XCURSOR_THEME", "Vimix-white-cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Vimix-white-cursors")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt: prefer Wayland, fall back to XWayland
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Run Electron apps (VS Code, Discord) natively on Wayland instead of
-- XWayland. On a 2880x1800 panel at scale 2 this is the difference between
-- crisp and blurry: XWayland clients render at 1x and get upscaled.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Firefox-family browsers (harmless if not installed)
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- The GDM-launched session only inherits PATH=/usr/local/bin:/usr/bin:
-- /var/lib/snapd/snap/bin, so ~/.local/bin was missing entirely — which is
-- why `claude` (installed at ~/.local/bin/claude) could not be found.
hl.env("PATH", "/home/woofi/.local/bin:/home/woofi/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/var/lib/snapd/snap/bin")


-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
    general = {
        -- No gaps: you wanted the padding around windows gone.
        gaps_in  = 0,
        gaps_out = 0,

        border_size = 1,

        col = {
            -- Magenta -> sky blue: the two colours the femboy and trans flags
            -- have in common, as a gradient across the border.
            active_border   = { colors = { "rgba(f279b9ee)", "rgba(5bcefaee)" }, angle = 45 },
            inactive_border = "rgba(362c45aa)",
        },

        resize_on_border = true,
        allow_tearing    = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 0,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee15111c,
        },

        blur = {
            enabled  = true,
            size     = 6,
            passes   = 2,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        -- Quickshell draws the wallpaper, so the built-in ones are off.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,

        -- Base colour of the empty surface.
        --
        -- Without this it is BLACK, and because the wallpaper only appears with
        -- the shell since it moved from hyprpaper into Quickshell, logging in
        -- showed a black screen for a few seconds.
        --
        -- The value is not arbitrary: it is the mean of flag-mesh-2880x1800.png
        -- measured across every pixel. The same value appears in Theme.qml
        -- (`wall`) and in /usr/share/sddm/scripts/Xsetup as colour 0 of the text
        -- console. Console, empty desktop and not-yet-loaded wallpaper therefore
        -- share exactly one tone -- all that remains visible is the structure of
        -- the image fading in.
        background_color        = 0xff3b3554,
        -- false: a window that asks to be activated does NOT snatch focus
        -- away from what you are working in. Notifications, background
        -- launches and chat pings stay put.
        focus_on_activate       = false,
    },

    cursor = {
        -- Stop the pointer being teleported to the centre of whatever window
        -- gains focus. That warp is why opening a bar menu yanked your mouse
        -- to the middle of the screen.
        no_warps = true,
    },

    xwayland = {
        -- Stop the compositor upscaling XWayland surfaces. Combined with
        -- GDK_SCALE=2 on XWayland launches makes GTK render natively at 2x
        -- instead of being blown up from 1x — that is the pixelation fix.
        -- Safe here because code/brave/nautilus/discord all run native
        -- Wayland already (verified: hyprctl clients shows xwayland=false).
        force_zero_scaling = true,
    },
})

-----------------------------------
---- TITLE BARS (hyprbars) --------
-----------------------------------
-- Hyprland has no server-side decorations, so close/minimise/maximise
-- buttons come from the hyprbars plugin (installed via hyprpm).
--
-- Icons must be built from codepoints, never pasted as literal glyphs:
-- literal Nerd Font characters get stripped in transit. utf8.char is Lua 5.3+
-- and Hyprland may embed LuaJIT, so encode by hand.
local function u(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + math.floor(cp / 0x1000) % 0x40,
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
end

local ICON_CLOSE = u(0xf0156)  -- md-window-close
local ICON_MAX   = u(0xf0176)  -- md-window-maximize
local ICON_MIN   = u(0xf0177)  -- md-window-minimize

-- Button commands go through `hyprctl dispatch`, which evaluates LUA on 0.56 —
-- legacy dispatcher names fail with a Lua syntax error.
-- Plugin settings deliberately live in ~/.local/bin/hypr-plugins-init, NOT
-- here. `hyprctl reload` unloads all plugins and the Lua config is parsed
-- before plugins are re-loaded, so a plugin block here fails on every reload
-- with "unknown config key 'plugin.hyprbars.bar_height'" and throws the red
-- error overlay. The init script applies them after the plugin is loaded.
hl.on("hyprland.start", function()
    -- hypr-plugins-init is gone.
    --
    -- The script loaded hyprpm plugins and then waited up to twenty times
    -- 0.25 s for hyprbars to register its options. hyprbars is permanently
    -- disabled though (see #20: `hyprbars-button` is a legacy keyword and
    -- unreachable from a Lua configuration),
    -- so the loop ran to completion every single time: a measured 5.1 seconds of
    -- a black screen at startup.
    --
    -- The call was also `hyprpm reload -n` -- the `-n` is exactly the "Plugins
    -- loaded" message that appeared in the top right.
    --
    -- Not a single plugin is enabled. As soon as one is needed again:
    -- `hyprpm enable <name>` and the script from
    -- ~/.local/share/hypr-archiv/ zurueckholen.
end)


--------------------
---- ANIMATIONS ----
--------------------
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

-- `speed` is a DURATION in units of 100 ms, so smaller = faster. These are
-- roughly half the upstream defaults, which felt sluggish. The window
-- animations also moved off the "easy" spring (bouncy, and it overshoots,
-- which reads as slow) onto easeOutQuint.
hl.animation({ leaf = "global",        enabled = true, speed = 5,    bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 2.5,  bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 2.4,  bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 2.0,  bezier = "easeOutQuint", style = "popin 92%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.0,  bezier = "quick",        style = "popin 92%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 0.9,  bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 0.8,  bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 1.4,  bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 1.0,  bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.0,  bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 0.5,  bezier = "quick",        style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 0.5,  bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 0.4,  bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.0,  bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 0.9,  bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 0.9,  bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 3.5,  bezier = "quick" })


--------------------
---- WORKSPACES ----
--------------------
-- You use GNOME's STATIC workspace model (dynamic-workspaces = false,
-- num-workspaces = 4). Marking 1-4 persistent reproduces that exactly, so
-- STRG+ALT+Left/Right always has all four to move between.
for i = 1, 4 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end


---------------
---- INPUT ----
---------------
hl.config({
    input = {
        -- Matched to GNOME (org.gnome.desktop.input-sources): German layout.
        -- The autogenerated config shipped "us", which swaps y/z.
        kb_layout  = "de",
        kb_variant = "",
        kb_model   = "",
        kb_options = "terminate:ctrl_alt_bksp",
        kb_rules   = "",

        -- 0 = click-to-focus, like GNOME. Must NOT be 1 (focus-follows-mouse):
        -- combined with the raise-on-focus hook above, hovering a window would
        -- pull it to the front. Now only a real click raises it.
        follow_mouse = 0,
        -- follow_mouse=0 alone is NOT enough: float_switch_override_focus
        -- defaults to 1, which hands focus to whatever floating window the
        -- pointer is over. Since every window here floats, that reintroduced
        -- focus-on-hover. 0 disables it.
        float_switch_override_focus = 0,
        -- Don't let a newly-mapped window steal focus from what you're using.
        focus_on_close = 1,
        sensitivity  = 0,

        touchpad = {
            -- Mirrors your GNOME touchpad settings
            natural_scroll       = true,
            tap_to_click         = true,
            -- false: otherwise libinput silences the touchpad while typing,
            -- which makes the pointer "stick" mid-sentence.
            disable_while_typing = false,
            scroll_factor        = 0.4,
        },
    },
})

-- 3-finger horizontal swipe switches workspaces, like GNOME.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })


---------------------
---- KEYBINDINGS ----
---------------------
local mainMod = "SUPER"

-- ---- Workspace switching: STRG+ALT+Left/Right (your GNOME binding) ------
hl.bind("CTRL + ALT + left",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CTRL + ALT + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("CTRL + ALT + up",    hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CTRL + ALT + down",  hl.dsp.focus({ workspace = "e+1" }))

-- GNOME's alternate bindings for the same action
hl.bind(mainMod .. " + Page_Up",     hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + Page_Down",   hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + ALT + left",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + Home",        hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + End",         hl.dsp.focus({ workspace = 4 }))

-- ---- Move window to workspace: STRG+SHIFT+ALT+Left/Right ----------------
hl.bind("CTRL + SHIFT + ALT + left",  hl.dsp.window.move({ workspace = "e-1" }))
hl.bind("CTRL + SHIFT + ALT + right", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind("CTRL + SHIFT + ALT + up",    hl.dsp.window.move({ workspace = "e-1" }))
hl.bind("CTRL + SHIFT + ALT + down",  hl.dsp.window.move({ workspace = "e+1" }))

hl.bind(mainMod .. " + SHIFT + Page_Up",   hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + Page_Down", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + Home",      hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + End",       hl.dsp.window.move({ workspace = 4 }))

-- Direct workspace access (Hyprland convention; GNOME has no analogue
-- because SUPER+1..9 there launches dash favourites)
for i = 1, 4 do
    hl.bind(mainMod .. " + " .. i,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i,   hl.dsp.window.move({ workspace = i }))
end

-- ---- Alt+Tab with overlay (GNOME switch-applications) ------------------
-- These two binds OPEN the overlay. Everything else -- cycling, expanding,
-- committing, cancelling -- lives in AltTab.qml; see the reasoning below.
hl.bind("ALT + Tab",         hl.dsp.exec_cmd("qs ipc call alttab next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd("qs ipc call alttab prev"))
-- The arrow keys, Escape and Enter are NOT here any more but in AltTab.qml.
-- Reason: once the overlay is up it holds the exclusive keyboard focus, and
-- Hyprland binds then stop firing. Measured with the overlay open and
-- CTRL+ALT+Right sent through wtype -- the workspace did not change. The binds
-- below therefore only worked while the overlay was not yet open, which made
-- them useless.
--
-- The two Tab binds stay: they are needed for exactly the first press, while
-- the overlay is not yet up.

-- Releasing Alt commits the selection.
-- The release of Alt is NOT caught here. A bindr on Alt_L fires neither with
-- nor without a modifier: Alt_L is processed as a modifier and never appears in
-- the bind system as a key event of its own. AltTab.qml takes the keyboard
-- focus instead and sees the event directly.

-- Super+Tab remains the plain cycling without an overlay.
local function cycle(prev)
    return function()
        hl.dispatch(hl.dsp.window.cycle_next({ prev = prev }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end
end
hl.bind(mainMod .. " + Tab",         cycle(false))
hl.bind(mainMod .. " + SHIFT + Tab", cycle(true))

-- ---- Window management, matching GNOME ----------------------------------
hl.bind("ALT + F4", hl.dsp.window.close())                              -- GNOME: close
-- mode must be "maximized" or "fullscreen" — verified against hyprctl;
-- "maximize"/"none" are rejected. Calling it toggles, so SUPER+Down and
-- ALT+F5 un-maximize by toggling the same state back off.
hl.bind(mainMod .. " + Up",   hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + Down", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("ALT + F10", hl.dsp.window.fullscreen({ mode = "maximized" }))  -- toggle-maximized
hl.bind("ALT + F5",  hl.dsp.window.fullscreen({ mode = "maximized" }))  -- unmaximize
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- GNOME "minimize" (SUPER+H). Hyprland has no minimise, so stash the window
-- on a hidden special workspace; SUPER+SHIFT+H reveals the stash.
hl.bind(mainMod .. " + H",           hl.dsp.window.move({ workspace = "special:minimized", silent = true }))
hl.bind(mainMod .. " + SHIFT + H",   hl.dsp.workspace.toggle_special("minimized"))

-- Move window between monitors: SUPER+SHIFT+arrows (GNOME move-to-monitor)
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ monitor = "r" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ monitor = "u" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ monitor = "d" }))

-- Focus between tiled windows (tiling-specific, no GNOME analogue)
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- ---- Launchers ----------------------------------------------------------
-- Application launcher on CTRL+ALT+S, as in GNOME.
--
-- History: this was ULauncher first. It runs on XWayland and did not get the
-- input focus reliably -- the compositor reported the window as active, but
-- the keystrokes never reached the search field and you had to click into it
-- with the mouse. The documented workaround stay_focused=true was already in
-- the rule below and did not help.
--
-- Then fuzzel, which speaks Wayland directly and takes focus through
-- wlr-layer-shell with exclusive keyboard input -- the same mechanism the
-- Alt+Tab overlay in this configuration uses successfully.
--
-- Now the Quickshell applications menu, for one reason: fuzzel is a separate
-- program and cannot carry the shell's open/close transition, so this one key
-- opened something that looked and moved differently from every other panel.
-- The Quickshell menu has the same search-as-you-type filter, and openMenu()
-- toggles, so pressing the key twice closes it again the way fuzzel did.
hl.bind("CTRL + ALT + S", hl.dsp.exec_cmd("qs ipc call menu apps"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs ipc call menu apps"))  -- GNOME: app view
hl.bind("ALT + F2",        hl.dsp.exec_cmd(runDialog))     -- GNOME: run dialog
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lock))          -- GNOME: lock
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("wlogout")) -- GNOME: logout
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("dunstctl history-pop"))

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",      hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd("qs ipc call menu apps"))

-- ---- Tiling-specific ---------------------------------------------------
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + grave",           hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + grave",   hl.dsp.window.move({ workspace = "special:magic" }))

-- Exit. The old default put this on plain SUPER+M, which killed the session
-- instantly with no confirmation.
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag to move / resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ---- Screenshots (matches GNOME's Print / Shift+Print / Alt+Print) ------
-- All screenshots go through one guarded helper. Calling slurp directly meant
-- every Print press stacked another selection overlay, and each overlay's dim
-- layer compounded, washing the screen out more each time.
hl.bind("Print",         hl.dsp.exec_cmd("/home/woofi/.local/bin/hypr-screenshot region"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("/home/woofi/.local/bin/hypr-screenshot full"))
hl.bind("ALT + Print",   hl.dsp.exec_cmd("/home/woofi/.local/bin/hypr-screenshot window"))
hl.bind("CTRL + Print",  hl.dsp.exec_cmd("/home/woofi/.local/bin/hypr-screenshot copy"))

-- ---- Clipboard history (replaces clipboard-indicator) ------------------
hl.bind(mainMod .. " + SHIFT + V",
    hl.dsp.exec_cmd([[bash -c 'cliphist list | rofi -dmenu -p Clipboard | cliphist decode | wl-copy']]))

-- ---- Media & brightness (hardware keys) -------------------------------
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && qs ipc call bar refresh"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && qs ipc call bar refresh"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && qs ipc call bar refresh"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
-- Night light overrides. hyprsunset follows a schedule (hyprsunset.conf); these
-- are for the times you want to overrule it -- editing photos in the evening,
-- or wanting the warm filter early on a dark afternoon.
--
-- SUPER+SHIFT+N toggles: if a filter is active it resets to identity, otherwise
-- it applies the evening temperature. `hyprctl hyprsunset` talks to the running
-- daemon, so this does not fight the schedule -- the next profile boundary
-- takes over again on its own.
-- One toggle rather than two binds. SUPER+SHIFT+M was NOT free -- it already
-- exits Hyprland (see above) -- and shadowing the quit key with a colour filter
-- is exactly the kind of collision that gets discovered at the worst moment.
hl.bind(mainMod .. " + SHIFT + N",
    hl.dsp.exec_cmd([[bash -c 'hyprctl hyprsunset temperature | grep -q "^6500\\|identity" && hyprctl hyprsunset temperature 4000 || hyprctl hyprsunset identity']]))

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+ && qs ipc call bar refresh"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%- && qs ipc call bar refresh"),                  { locked = true, repeating = true })

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------
-- Ignore maximize requests from all apps.
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- GNOME-like window behaviour: every window floats and opens MAXIMISED, so
-- windows stack behind each other instead of tiling side by side. Alt+Tab
-- cycles and raises, exactly like GNOME.
--
-- Uses maximize rather than size="92% 92%": that percentage form produced a
-- 989px-wide window instead of the expected 1325px, which is only ~72
-- terminal columns — hence "Terminal size too small: Width = 73" from btop
-- and nmtui, which both need 80. maximize has no such arithmetic to get
-- wrong and always fills the usable area below the bar.
-- Size is computed from the actual monitor rather than written as a
-- percentage: size = "92% 92%" and maximize = true are both accepted by the
-- parser but do NOTHING (windows fell back to their own default, 989x801 for
-- kitty — about 72 columns, which is why btop and nmtui complained
-- "Terminal size too small: Width = 73"). Explicit pixels do work.
local BAR_H = 36
local FILL_W, FILL_H = 1440, 900 - BAR_H   -- fallback: eDP-1 at scale 2
do
    local ok, mons = pcall(hl.get_monitors)
    if ok and mons then
        local m = mons[1]
        if m and m.width and m.height and m.scale and m.scale > 0 then
            FILL_W = math.floor(m.width / m.scale)
            FILL_H = math.floor(m.height / m.scale) - BAR_H
        end
    end
end

-- Matches only native Wayland clients. XWayland-Clients bleiben aussen vor
-- client here (verified: hyprctl clients shows xwayland=false for
-- (code/brave/nautilus/discord all run natively), so they size themselves
-- itself naturally and grow with its results, exactly as it did on GNOME.
-- Forcing a size on it made it either a huge empty box or too small.
hl.window_rule({
    name  = "gnome-like-stacking",
    match = { class = ".*", xwayland = false },
    float = true,
    size  = FILL_W .. " " .. FILL_H,
    move  = "0 " .. BAR_H,
})

-- Fix XWayland drag-and-drop cursor glitches.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- No rule needed for the launcher: the applications menu is a layer-shell
-- surface and therefore not a window that window rules could apply to.

-- Dialogs and small utility windows. Each needs an explicit `size` for the
-- same reason: maximize=false does not undo the blanket rule,
-- only a later `size` can.
hl.window_rule({
    name   = "float-dialogs",
    match  = { class = "^(pavucontrol|blueman-manager|nm-connection-editor|nm-applet|iwgtk|org.gnome.NautilusPreferences)$" },
    float  = true,
    size   = "900 640",
    center = true,
})

hl.window_rule({
    name   = "float-file-chooser",
    match  = { title = "^(Open File|Save File|Choose Files|Öffnen|Speichern)$" },
    float  = true,
    size   = "1000 700",
    center = true,
})

-- Screenshot editor (swappy, opened by ~/.local/bin/hypr-screenshot).
--
-- Without this it is just another window in the GNOME-like stack: the catch-all
-- blows it up to 1440x864, swappy then shrinks itself to the aspect ratio of the
-- captured image, so a region shot of 144x92 px became a 392x160 window and a
-- full-screen shot a 1100x743 one. Every shot produced a differently sized,
-- differently placed box -- it never read as one self-contained dialog.
--
-- Needs its own `size` for the same reason: `maximize` is a
-- no-op on 0.56, only a later rule's `size` can exempt a window from the
-- catch-all. swappy may still shrink to fit the image, but it now always starts
-- from one fixed geometry and stays centred.
hl.window_rule({
    name   = "screenshot-editor",
    match  = { class = "^(swappy)$" },
    float  = true,
    size   = "1100 760",
    center = true,
})

-- rofi draws its own surface and never appears in `hyprctl clients`, so the
-- catch-all cannot reach it; this rule is belt-and-braces.
hl.window_rule({
    name   = "rofi",
    match  = { class = "(?i)rofi" },
    float  = true,
    size   = "460 600",
})

-- Picture-in-picture floats on top at video size.
hl.window_rule({
    name   = "pip",
    match  = { title = "^(Picture-in-Picture)$" },
    float  = true,
    size   = "640 360",
    pin    = true,
})
