pragma Singleton

//  Central palette for every Quickshell surface.
//
//  Why: the bar, the panels and the menus each had their own hard-wired
//  colours. Switching between light and dark therefore only changed GTK apps
//  -- the shell itself stayed dark. The palette lives here once, and follows
//  org.gnome.desktop.interface color-scheme.
//
//  TWO things depend on this, and both only work because every other file
//  takes its colours from here instead of setting its own:
//
//    1. Switching at all. shell.qml, NotificationCenter.qml and
//       QuickSettings.qml had their own literals -- those stayed dark in light
//       mode while the bar had already switched.
//
//    2. The cross-fade. The Behavior blocks below animate every colour change;
//       because all surfaces are bound to these properties, the entire shell
//       fades together without a single other file needing to know about it.
//
//  This is also why the properties are NOT readonly: a Behavior cannot be
//  attached to a readonly property, and without one the colour jumps.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: theme

    // Seeded from disk, NOT hardcoded to true.
    //
    // This used to read `property bool dark: true`, which is why the wrong
    // wallpaper flashed up at every login. The shell drew the dark image
    // because that was the hardcoded assumption, then hypr/theme arrived a
    // moment later and, in light mode, cross-faded to the other one. What you
    // saw was a background briefly showing the wrong picture before settling.
    //
    // The scheme is now persisted on every change and read back synchronously
    // here -- blockLoading, so the value is present before the first frame is
    // drawn rather than arriving as an update after it. The bus still has the
    // last word; this only removes the guess.
    //
    // If the file is missing or unreadable the fallback is dark, which is the
    // old behaviour and the right default for a first run.
    property bool dark: {
        try {
            const t = schemeCache.text();
            if (t.length > 0) return JSON.parse(t).dark === true;
        } catch (e) { /* first run, or a half-written file */ }
        return true;
    }

    FileView {
        id: schemeCache
        path: "/home/woofi/.cache/hypr/theme.json"
        blockLoading: true
        // Absent on a first run; the property initialiser above handles that.
        printErrors: false
    }

    // Cross-fade duration -- set once here, applies to everything.
    //
    // 170 ms is a compromise, and a measured one. Programs that do not animate
    // their colours but switch them outright -- kitty, GTK apps, browsers --
    // are done immediately. The animated surfaces started on the same frame
    // but, at 260 ms, needed roughly two frames longer to reach their final
    // state. That trailing edge was exactly what looked like "some things take
    // slightly longer".
    //
    // At 60 frames per second, 170 ms is still around ten intermediate frames,
    // so the fade stays smooth -- it just arrives sooner.
    readonly property int fadeMs: 170

    // Is a cross-fade running right now?
    //
    // Needed by everything that does NOT repaint itself when a bound colour
    // changes -- above all the Canvas clock face. A Canvas only paints when
    // requestPaint() is called, and that used to happen once per second. So
    // during the fade the clock kept its old colour and only jumped on the
    // next tick, while everything around it faded smoothly.
    property bool fading: false
    // ONE handler: QML permits only a single onDarkChanged per object, and
    // declaring a second silently costs you the whole file ("Property value set
    // multiple times"). Both jobs live here.
    onDarkChanged: {
        theme.fading = true;
        fadeWindow.restart();
        // Persist the scheme so the next startup can seed `dark` from disk
        // instead of guessing. See the property initialiser above.
        schemeCache.setText(JSON.stringify({ dark: theme.dark }));
    }

    Timer {
        id: fadeWindow
        // A little margin, so the last frame of the animation is definitely
        // still picked up.
        interval: theme.fadeMs + 60
        repeat: false
        onTriggered: theme.fading = false
    }

    // ---- Palette: rose, lilac and sky blue on plum ------------------------
    //
    // The surfaces are deliberately NOT a neutral blue but tinted towards plum
    // (#14101a to #473852). That is the real difference: pink on a neutral
    // navy looks cold and bolted on, whereas on a warm violet-grey it looks
    // soft and visibly belongs there.
    //
    // Three accents rather than two, so the bar does not become monotonous:
    //   mauve     rose    -- primary accent (active workspace, selection)
    //   lavender  lilac   -- second accent
    //   blue      sky     -- the cool counterweight that keeps it fresh
    //
    // Light is not a mirror image but the same hues with darkened accents on a
    // rose-tinted white. Every pair measured against `base`: 5.5 and up in
    // dark, 3.95 and up in light.
    property color base:     dark ? "#241d2f" : "#fdf7fc"
    property color mantle:   dark ? "#1c1725" : "#f4ecf7"
    property color crust:    dark ? "#15111c" : "#eadff0"
    property color surface0: dark ? "#362c45" : "#e2d4ea"
    property color surface1: dark ? "#4b3d5c" : "#c8b6d4"
    property color surface2: dark ? "#a294b6" : "#6b5c77"
    property color text:     dark ? "#fdf6fb" : "#241c2e"
    property color subtext:  dark ? "#d3c5dd" : "#55485f"
    property color mauve:    dark ? "#f279b9" : "#c22e7d"
    property color lavender: dark ? "#d3aaf7" : "#7841c4"
    property color blue:     dark ? "#5bcefa" : "#0d6f9e"
    property color sapphire: dark ? "#8fdcfc" : "#0c6b85"
    property color teal:     dark ? "#7fe0d8" : "#0d766c"
    property color green:    dark ? "#9fe6ae" : "#2e8b57"
    property color yellow:   dark ? "#f7d9a0" : "#96660f"
    property color peach:    dark ? "#ffb89a" : "#ad4a14"
    property color maroon:   dark ? "#f5a9c8" : "#bd3570"
    property color red:      dark ? "#ff7a9c" : "#b81d3e"

    // Mean of the corresponding wallpaper, measured across every pixel of
    // flag-mesh*.png. This is the colour that is visible BEFORE the image is
    // there -- which is why the same value appears in two further places
    // outside Quickshell:
    //
    //   hyprland.lua   misc:background_color   -> empty desktop
    //   Xsetup         console palette colour 0 -> text console on VT 1
    //
    // Every stage between login and the finished shell therefore has the same
    // tone; all that remains visible is the structure of the image fading in,
    // instead of a jump from black to picture.
    property color wall:     dark ? "#3b3554" : "#f0e9f8"

    Behavior on base     { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on wall     { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on mantle   { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on crust    { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on surface0 { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on surface1 { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on surface2 { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on text     { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on subtext  { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on mauve    { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on lavender { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on blue     { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on sapphire { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on teal     { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on green    { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on yellow   { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on peach    { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on maroon   { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }
    Behavior on red      { ColorAnimation { duration: theme.fadeMs; easing.type: Easing.OutCubic } }

    readonly property string uiFont: "FiraCode Nerd Font"

    // Nerd Font characters built from code points: literal glyphs get lost
    // when these files are written out.
    function ico(cp) { return String.fromCodePoint(cp); }

    // Subscribed to the event bus, not polling gsettings.
    //
    // This used to run `gsettings get` on a 3 s timer. That kept the state, but
    // it meant the shell surfaces could lag up to three seconds behind the GTK
    // applications, so switching light/dark visibly happened in two stages.
    //
    // hypr-eventd holds a `gsettings monitor` open and publishes the moment the
    // key changes. The retained message is delivered on connect too, so the
    // very first frame after login already has the right scheme rather than
    // defaulting to dark and correcting itself.
    // The scheme arrives on the shared Bus singleton. See Bus.qml.
    Connections {
        target: Bus
        function onMessage(topic, d) {
            if (topic === "hypr/theme" && d.dark !== undefined) theme.dark = d.dark;
        }
    }


}
