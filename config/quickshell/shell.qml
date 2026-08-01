//  Quickshell desktop widgets — woofi
//
//  On the wlr-layer-shell BACKGROUND layer: layer-shell surfaces are always
//  present, so these cannot vanish the way azclock/conky did under GNOME
//  (Mutter exposes no layer-shell at all).
//
//  Layout:  analog clock + digital time (top centre)
//           weather (below left) and system stats (below right),
//           side by side
//
//  Palette: Catppuccin Mocha, matching waybar, rofi, hyprlock and SDDM.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

ShellRoot {
    // GNOME-style notification centre (its own file, to keep shell.qml
    // readable). Quickshell is therefore the notification daemon.
    NotificationCenter { id: notifCentre }

    // Quick Settings (battery, power profile, appearance, system).
    // Replaces the rofi dropdowns: under Wayland those did not close on a
    // click beside them, and sat far too low.
    QuickSettings { id: quickSettings }

    // Apps, Places and Wi-Fi menus as panels instead of rofi.
    Menus { id: menus }

    // Brightness, volume and Bluetooth as panels instead of foreign programs.
    Controls { id: controls }

    // Alt+Tab switcher with an overlay.
    AltTab { id: altTab }

    // Top bar. Replaces waybar -- see the header of Bar.qml: waybar reloads
    // itself on every colour-scheme change and visibly disappears for around
    // 100 ms while doing so. Here the colours are bound to Theme and animate
    // along with it; nothing is rebuilt.
    Bar {
        dnd: notifCentre.dnd

        // Wire the bar straight to the panels. These all live in this one
        // ShellRoot, so a click is a function call -- not `sh -c "qs ipc call"`,
        // which launched a shell and a second Quickshell binary per click just
        // to reach the process it was already running in.
        onRequestMenu: function (which, cx) { menus.openMenu(which, cx); }
        onRequestControl: function (which, cx) { controls.openPanel(which, cx); }
        onRequestQuickSettings: function (cx) { quickSettings.toggleAt(cx); }
        onRequestNotifications: notifCentre.panelOpen = !notifCentre.panelOpen
        onRequestAltTab: altTab.step(1)
    }

    // Immediate light/dark switching.
    //
    // Theme.qml polls color-scheme every 3 s. That is enough not to lose the
    // state, but on its own it was visibly sluggish: the bar and the GTK
    // programs switched instantly while the Quickshell surfaces followed up to
    // three seconds later -- it looked as though everything was loading in
    // sequence. `hypr-appearance` calls this directly, and the poll now only
    // remains as a fallback for changes that bypass that script.
    IpcHandler {
        target: "theme"
        function dark(): void  { Theme.dark = true; }
        function light(): void { Theme.dark = false; }
    }

    // =====================================================================
    //  WALLPAPER
    // =====================================================================
    //  This used to be hyprpaper's job. Two reasons for moving it here:
    //
    //    1. hyprpaper cuts over hard. Right beside it the widgets cross-faded
    //       smoothly -- which is exactly why the break stood out.
    //    2. hyprpaper creates a new layer surface on every change. That ended
    //       up above the widgets (same layer, stacked by creation order) and
    //       covered them. And because `preload` loads asynchronously, a
    //       different image briefly flashed up while switching.
    //
    //  Both images stay in memory permanently and the fade is a pure opacity
    //  change -- which runs at the monitor's full frame rate.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bg
            required property var modelData
            screen: bg.modelData

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell-wallpaper"
            exclusionMode: ExclusionMode.Ignore

            // NOT Theme.crust but the mean of the image: that is exactly the
            // colour Hyprland already shows on the empty desktop
            // (misc:background_color). The moment this surface appears
            // therefore no longer stands out -- previously it jumped from the
            // Hyprland colour to the near-black crust until the image had
            // loaded.
            color: Theme.wall

            anchors { top: true; bottom: true; left: true; right: true }

            // Both images in one group so they can fade in TOGETHER: until the
            // image is there the flat colour is on top, and the transition onto
            // it is a fade rather than a jump.
            Item {
                anchors.fill: parent

                // Only the currently visible image counts. Waiting for the
                // other one would delay startup for something nobody sees.
                opacity: (Theme.dark ? darkWall.status : lightWall.status) === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                Image {
                    id: lightWall
                    anchors.fill: parent
                    source: "file:///home/woofi/.local/share/backgrounds/flag-mesh-light-2880x1800.png"
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    // Decode at SCREEN size, not at the file's 2880x1800.
                    //
                    // Without this, Qt decodes the full image and keeps it as
                    // uncompressed RGBA: 2880 x 1800 x 4 = 20.7 MB. Both
                    // variants are held at once so they can cross-fade, so the
                    // pair cost 41.5 MB of the shell's baseline -- to draw on a
                    // 1440x900 panel that can show a quarter of those pixels.
                    //
                    // The file and the screen share the same 1.6 aspect ratio,
                    // so this loses nothing at all: it is the downscale the GPU
                    // was doing on every frame anyway, done once at decode
                    // time. 5.2 MB each instead of 20.7 MB.
                    sourceSize.width: bg.width
                    sourceSize.height: bg.height
                    // Only the ACTIVE variant's image is loaded synchronously.
                    // This used to say `false` twice, so two 2880x1800 images
                    // were decoded and pushed to the GPU at startup before
                    // anything at all became visible -- measured at roughly
                    // 90 ms decode time per image plus 20 MB of texture. The
                    // second one is loaded on a background thread and is ready
                    // long before the first switch.
                    asynchronous: Theme.dark
                }

                // The dark version sits on top and fades out when switching to
                // light. That cross-fades one image into the other rather than
                // having one disappear and the next appear.
                Image {
                    id: darkWall
                    anchors.fill: parent
                    source: "file:///home/woofi/.local/share/backgrounds/flag-mesh-2880x1800.png"
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    // See lightWall: decode at screen size, not 2880x1800.
                    sourceSize.width: bg.width
                    sourceSize.height: bg.height
                    asynchronous: !Theme.dark
                    opacity: Theme.dark ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            screen: root.modelData

            // Bottom, NOT Background: hyprpaper also sits on Background, and
            // within one layer the stacking follows creation order. As soon as
            // the wallpaper was changed, hyprpaper created a new surface --
            // which then landed above the widgets and covered them completely.
            //
            // Bottom is guaranteed to be above Background, no matter when which
            // surface was created.
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell-widgets"
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            // ---- palette ------------------------------------------------
            // Bound to Theme instead of hard-wired. This used to hold literals,
            // which is why these surfaces stayed dark in light mode while the
            // bar and the GTK apps had already switched.
            readonly property color cBase:     Theme.base
            readonly property color cSurface0: Theme.surface0
            readonly property color cSurface1: Theme.surface1
            readonly property color cSurface2: Theme.surface2
            readonly property color cText:     Theme.text
            readonly property color cSubtext:  Theme.subtext
            readonly property color cMauve:    Theme.mauve
            readonly property color cBlue:     Theme.blue
            readonly property color cSapphire: Theme.sapphire
            readonly property color cGreen:    Theme.green
            readonly property color cYellow:   Theme.yellow
            readonly property color cPeach:    Theme.peach
            readonly property color cMaroon:   Theme.maroon
            readonly property color cRed:      Theme.red
            readonly property color cLavender: Theme.lavender
            readonly property color cCrust:    Theme.crust

            readonly property string uiFont: Theme.uiFont

            // ---- live data ----------------------------------------------
            property string cpuPct: "—"
            property string memUsed: "—"
            property string tempC: "—"
            property string battPct: "—"
            property string battState: ""
            property string uptime: "—"

            // Placeholder only -- the real place name arrives with the
            // weather payload a moment later. A dash rather than a hardcoded
            // village keeps the published config free of the author's home
            // location, matching the generic coordinates in hypr-weather.
            property var wx: ({ place: "—", temp: "—", icon: "",
                                desc: "…", wind: "—", humidity: "—",
                                hourly: [], daily: [], stale: false })

            // ---- calendar ------------------------------------------------
            // calMonth is 0-based, as in JavaScript.
            property int    calYear:  new Date().getFullYear()
            property int    calMonth: new Date().getMonth()
            property string selectedDay: dayKey(new Date())
            property var    calDays: ({})      // { "2026-07-28": [ … ] }
            property bool   calLoading: true

            function pad(n) { return (n < 10 ? "0" : "") + n; }
            function dayKey(d) {
                return d.getFullYear() + "-" + pad(d.getMonth() + 1)
                     + "-" + pad(d.getDate());
            }
            function todayKey() { return dayKey(new Date()); }
            function eventsFor(key) {
                const v = root.calDays[key];
                return v === undefined ? [] : v;
            }
            function monthLabel() {
                return new Date(root.calYear, root.calMonth, 1)
                       .toLocaleDateString(Qt.locale("de_DE"), "MMMM yyyy");
            }
            function selectedLabel() {
                const p = root.selectedDay.split("-");
                const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
                return d.toLocaleDateString(Qt.locale("de_DE"), "dddd, d. MMMM")
                       .toUpperCase();
            }
            function shiftMonth(dir) {
                let m = root.calMonth + dir, y = root.calYear;
                if (m < 0)       { m = 11; y -= 1; }
                else if (m > 11) { m = 0;  y += 1; }
                root.calYear = y; root.calMonth = m;
                loadCalendar();
            }
            function goToday() {
                const n = new Date();
                root.calYear = n.getFullYear();
                root.calMonth = n.getMonth();
                root.selectedDay = dayKey(n);
                loadCalendar();
            }
            function loadCalendar() {
                calProc.command = ["/home/woofi/.local/bin/hypr-calendar",
                                   String(root.calYear), String(root.calMonth + 1)];
                calProc.running = true;
            }

            Process {
                id: calProc
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const d = JSON.parse(this.text.trim());
                            // Only accept the answer if it belongs to the month
                            // currently on screen -- when paging quickly,
                            // answers can otherwise arrive out of order.
                            const soll = root.calYear + "-" + root.pad(root.calMonth + 1);
                            if (d.month !== soll) return;
                            root.calDays = d.days || ({});
                            root.calLoading = d.loading === true;
                        } catch (e) { /* keep the previous state */ }
                    }
                }
            }

            Timer {
                // The first call returns the cache and kicks off the refresh in
                // the background; a second call shortly afterwards picks up the
                // fresh events.
                interval: 8000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: root.loadCalendar()
            }

            SystemClock {
                id: clock
                precision: SystemClock.Seconds
            }

            // System readings, subscribed rather than polled.
            //
            // This ran `hypr-widget-stats` every 5 s, which itself slept a
            // second between two /proc/stat samples -- so the CPU figure on
            // screen was always at least a second old, and the script held a
            // process open for a fifth of every interval doing nothing but
            // waiting.
            //
            // hypr-eventd samples continuously and publishes on change. Two
            // subscriptions rather than one: the battery lives on its own topic
            // because the bar and this card both want it and neither should
            // wake for the other's changes.
            // Values arrive on the shared Bus singleton. See Bus.qml.
            Connections {
                target: Bus
                function onMessage(topic, d) {
                    // One handler for several topics: each message carries only
                    // its own keys, so anything absent is left as it was rather
                    // than being cleared.
                    if (d.cpu !== undefined)       root.cpuPct    = d.cpu + "%";
                    if (d.mem !== undefined)       root.memUsed   = d.mem + " GB";
                    if (d.temp !== undefined)      root.tempC     = d.temp + "\u00b0C";
                    if (d.uptime !== undefined)    root.uptime    = d.uptime;
                    if (d.batt !== undefined)      root.battPct   = d.batt + "%";
                    if (d.battState !== undefined) root.battState = d.battState;
                }
            }



            // The cached reading, straight off disk at startup.


            //


            // Same reasoning as the application list: the bus is the live path but not


            // a guaranteed one, and a weather card that depends on the broker being up


            // shows dashes when it is not. hypr-weather serves its own cache from


            // ~/.cache/hypr immediately, without touching the network.


            // Weather arrives on the shared Bus singleton. See Bus.qml.
            Connections {
                target: Bus
                function onMessage(topic, d) {
                    if (topic === "hypr/weather" && d && d.place) root.wx = d;
                }
            }










            // =============================================================
            //  ANALOG CLOCK (centre)
            // =============================================================
            // Height of the whole block: clock + gap + the taller of the two
            // columns below it. By construction the right column is exactly as
            // tall as the weather card, so that height is enough.
            readonly property real clusterHeight: clockWidget.height + 22 + wxCard.height

            Item {
                id: clockWidget
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                // The block no longer hangs from the top at a fixed distance
                // but sits vertically centred in the area BELOW the bar.
                // Previously it stuck to the top edge and left a large empty
                // area underneath.
                //
                // The +BAR_H in the numerator shifts the centre down by the
                // height of the bar: the panel itself reaches all the way up
                // (ExclusionMode.Ignore), but the bar covers the topmost
                // 40 px.
                readonly property int barH: 40
                anchors.topMargin: Math.max(24,
                    (parent.height + barH - root.clusterHeight) / 2)
                width: 260
                height: 260

                Canvas {
                    id: face
                    anchors.fill: parent
                    antialiasing: true

                    Connections {
                        target: clock
                        function onDateChanged() { face.requestPaint(); }
                    }

                    // Repaint as soon as the desktop becomes visible again.
                    //
                    // A Canvas keeps its content as a texture. While the
                    // surface is completely covered by windows the compositor
                    // stops repainting it and requestPaint calls merely pile up.
                    // On uncovering, whether anything is drawn depends on there
                    // being a reason to draw at all -- hence an explicit one
                    // here: every workspace change and every closed window
                    // nudges the clock face.
                    Connections {
                        target: Hyprland
                        function onRawEvent(event) {
                            const n = event.name;
                            if (n === "workspace" || n === "closewindow"
                                || n === "movewindow" || n === "fullscreen"
                                || n === "changefloatingmode")
                                face.requestPaint();
                        }
                    }

                    // Repaint as soon as the desktop becomes visible again.
                    //
                    // While the widget surface is completely covered by
                    // windows, the compositor stops sending frame callbacks --
                    // drawing stands still. The time itself keeps running
                    // (SystemClock is driven by a timer, not by the paint
                    // cycle), but the clock face is a Canvas and keeps the
                    // texture it last drew.
                    //
                    // A workspace change or a closed window is exactly the
                    // moment the desktop reappears. A repaint is therefore
                    // requested immediately, so the first visible frame already
                    // shows the current time rather than the one after it.
                    Connections {
                        target: Hyprland
                        function onRawEvent(event) {
                            const n = event.name;
                            if (n === "workspace" || n === "closewindow"
                                || n === "movewindow" || n === "fullscreen"
                                || n === "changefloatingmode")
                                face.requestPaint();
                        }
                    }

                    // Repaint at full frame rate during a light/dark switch.
                    //
                    // A Canvas does NOT recolour itself when a bound colour
                    // changes -- it paints only when requestPaint() is called,
                    // and above that happened just once per second. During the
                    // 260 ms fade the clock face therefore stayed in the old
                    // colour and only jumped on the next tick, while cards,
                    // text and background around it faded smoothly. That is
                    // exactly what looked like stutter.
                    Timer {
                        running: Theme.fading
                        interval: 16          // ~60 frames per second
                        repeat: true
                        onTriggered: face.requestPaint()
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        const w = width, h = height;
                        const cx = w / 2, cy = h / 2;
                        const r = Math.min(w, h) / 2 - 8;
                        ctx.reset();
                        ctx.clearRect(0, 0, w, h);

                        // --- clock face: two rings rather than a flat disc,
                        //     which gives depth without any image assets.
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(root.cCrust.r, root.cCrust.g, root.cCrust.b, 0.72);
                        ctx.fill();

                        ctx.beginPath();
                        ctx.arc(cx, cy, r - 3, 0, Math.PI * 2);
                        ctx.lineWidth = 1.5;
                        ctx.strokeStyle = Qt.rgba(root.cSurface1.r, root.cSurface1.g, root.cSurface1.b, 0.75);
                        ctx.stroke();

                        // Outer accent ring, left open at the top
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI * 0.42, Math.PI * 1.42);
                        ctx.lineWidth = 3;
                        ctx.strokeStyle = Qt.rgba(root.cMauve.r, root.cMauve.g, root.cMauve.b, 0.55);
                        ctx.stroke();

                        // --- hour numerals rather than mere ticks
                        ctx.font = "600 13px 'FiraCode Nerd Font'";
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        for (let i = 1; i <= 12; i++) {
                            const a = (i / 12) * Math.PI * 2 - Math.PI / 2;
                            const rr = r - 24;
                            ctx.fillStyle = (i % 3 === 0) ? root.cText : root.cSubtext;
                            ctx.fillText(i, cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
                        }

                        // Minute dots, understated
                        for (let i = 0; i < 60; i++) {
                            if (i % 5 === 0) continue;
                            const a = (i / 60) * Math.PI * 2 - Math.PI / 2;
                            ctx.beginPath();
                            ctx.arc(cx + Math.cos(a) * (r - 8), cy + Math.sin(a) * (r - 8), 1, 0, Math.PI * 2);
                            ctx.fillStyle = Qt.rgba(root.cSurface1.r, root.cSurface1.g, root.cSurface1.b, 0.9);
                            ctx.fill();
                        }

                        const now = clock.date;
                        const hrs = now.getHours() % 12;
                        const min = now.getMinutes();
                        const sec = now.getSeconds();

                        // Tapered hands: drawn as a polygon so they are narrower
                        // at the tip than at the pivot.
                        function taperedHand(angle, len, wBase, wTip, col) {
                            const nx = Math.cos(angle), ny = Math.sin(angle);
                            const px = -ny, py = nx;             // normal
                            const bx = cx - nx * (len * 0.16);
                            const by = cy - ny * (len * 0.16);
                            const tx = cx + nx * len;
                            const ty = cy + ny * len;
                            ctx.beginPath();
                            ctx.moveTo(bx + px * wBase, by + py * wBase);
                            ctx.lineTo(tx + px * wTip,  ty + py * wTip);
                            ctx.lineTo(tx - px * wTip,  ty - py * wTip);
                            ctx.lineTo(bx - px * wBase, by - py * wBase);
                            ctx.closePath();
                            ctx.fillStyle = col;
                            ctx.fill();
                        }

                        const aH = ((hrs + min / 60) / 12) * Math.PI * 2 - Math.PI / 2;
                        const aM = ((min + sec / 60) / 60) * Math.PI * 2 - Math.PI / 2;
                        const aS = (sec / 60) * Math.PI * 2 - Math.PI / 2;

                        taperedHand(aH, r * 0.46, 4.5, 1.6, root.cText);
                        taperedHand(aM, r * 0.66, 3.4, 1.2, root.cLavender);

                        // Thin second hand, with a short counterweight
                        ctx.beginPath();
                        ctx.moveTo(cx - Math.cos(aS) * (r * 0.14), cy - Math.sin(aS) * (r * 0.14));
                        ctx.lineTo(cx + Math.cos(aS) * (r * 0.74), cy + Math.sin(aS) * (r * 0.74));
                        ctx.lineWidth = 1.4;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = root.cRed;
                        ctx.stroke();

                        // Hub: a ring rather than a solid dot
                        ctx.beginPath();
                        ctx.arc(cx, cy, 5, 0, Math.PI * 2);
                        ctx.fillStyle = root.cCrust;
                        ctx.fill();
                        ctx.lineWidth = 2;
                        ctx.strokeStyle = root.cRed;
                        ctx.stroke();
                    }
                }

                // digital time inside the dial, below the hub
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // 30 rather than 46: at 46 the date line ran into the "6"
                    // at the bottom edge of the dial.
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 28
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                        color: root.cText
                        font.family: root.uiFont
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.date.toLocaleDateString(Qt.locale("de_DE"), "ddd, dd. MMM")
                        color: root.cSubtext
                        font.family: root.uiFont
                        font.pixelSize: 12
                    }
                }
            }

            // =============================================================
            //  WEATHER (right)
            // =============================================================
            Rectangle {
                id: wxCard
                // Side by side (nebeneinander) with the stats card, both
                // beneath the clock. anchors.right of centre.
                anchors.right: parent.horizontalCenter
                anchors.rightMargin: 12
                anchors.top: clockWidget.bottom
                anchors.topMargin: 22

                width: 370
                height: wxCol.implicitHeight + 40
                radius: 22
                color: Qt.rgba(root.cBase.r, root.cBase.g, root.cBase.b, 0.72)
                border.width: 1
                border.color: Qt.rgba(root.cSurface0.r, root.cSurface0.g, root.cSurface0.b, 0.9)

                Column {
                    id: wxCol
                    anchors.centerIn: parent
                    width: parent.width - 44
                    spacing: 14

                    // --- current conditions ---
                    Item {
                        width: parent.width
                        height: 64

                        Text {
                            id: wxIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.wx.icon || ""
                            color: root.cYellow
                            font.family: root.uiFont
                            font.pixelSize: 46
                        }
                        Column {
                            anchors.left: wxIcon.right
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: root.wx.temp + "°C"
                                color: root.cText
                                font.family: root.uiFont
                                font.pixelSize: 28
                                font.weight: Font.Bold
                            }
                            Text {
                                text: root.wx.desc || ""
                                color: root.cSubtext
                                font.family: root.uiFont
                                font.pixelSize: 12
                            }
                        }
                        Column {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                anchors.right: parent.right
                                text: root.wx.place + (root.wx.stale ? "  (alt)" : "")
                                color: root.cMauve
                                font.family: root.uiFont
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                anchors.right: parent.right
                                text: root.wx.wind + " km/h · " + root.wx.humidity + "%"
                                color: root.cSubtext
                                font.family: root.uiFont
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(root.cSurface0.r, root.cSurface0.g, root.cSurface0.b, 0.9)
                    }

                    // --- next hours ---
                    Row {
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: root.wx.hourly ? root.wx.hourly.slice(0, 7) : []
                            Column {
                                required property var modelData
                                width: wxCol.width / 7
                                spacing: 3
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.time
                                    color: root.cSubtext
                                    font.family: root.uiFont
                                    font.pixelSize: 10
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    color: root.cSapphire
                                    font.family: root.uiFont
                                    font.pixelSize: 18
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.temp + "°"
                                    color: root.cText
                                    font.family: root.uiFont
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.pop > 0 ? modelData.pop + "%" : " "
                                    color: root.cBlue
                                    font.family: root.uiFont
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(root.cSurface0.r, root.cSurface0.g, root.cSurface0.b, 0.9)
                    }

                    // --- next days ---
                    Column {
                        width: parent.width
                        spacing: 7
                        Repeater {
                            model: root.wx.daily ? root.wx.daily.slice(0, 6) : []
                            Item {
                                required property var modelData
                                width: wxCol.width
                                height: 20

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.day
                                    color: root.cSubtext
                                    font.family: root.uiFont
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 60
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon
                                    color: root.cSapphire
                                    font.family: root.uiFont
                                    font.pixelSize: 16
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 92
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.pop > 0 ? modelData.pop + "%" : ""
                                    color: root.cBlue
                                    font.family: root.uiFont
                                    font.pixelSize: 10
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.max + "°  /  " + modelData.min + "°"
                                    color: root.cText
                                    font.family: root.uiFont
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }


            // =============================================================
            //  PHOTO STACK
            // =============================================================
            //  Three pictures like a pile of photographs: rotated slightly
            //  against each other and offset, so each one is still recognisable
            //  rather than stacked exactly on top of the last.
            //
            //  Each picture sits in a light card with a border -- which is why
            //  the square images do not jar: the rounded frame belongs to the
            //  card, not to the image. (In Qt Quick `clip` always clips
            //  rectangularly anyway; rounded clipping would need an
            //  OpacityMask.)
            Item {
                id: photoStack
                // Top left corner, below the bar. The whole block is tilted
                // slightly, which makes it look laid down rather than aligned.
                // It is the GROUP that is rotated, not the individual pictures:
                // that preserves their arrangement relative to each other and
                // only the stack as a whole sits at an angle.
                x: 44
                y: 62
                width: 240
                height: 285
                rotation: -5
                transformOrigin: Item.Center

                component Photo: Rectangle {
                    property alias source: photoImage.source
                    property bool animated: false
                    width: 150; height: 150
                    radius: 10
                    color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(root.cSurface1.r, root.cSurface1.g,
                                          root.cSurface1.b, 0.9)
                    antialiasing: true

                    // Schatten: leicht versetztes, dunkles Rechteck dahinter.
                    // No DropShadow effect -- that would need Qt5Compat, and
                    // for this purpose a plain offset rectangle is enough.
                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.leftMargin: 2
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0.32)
                    }

                    AnimatedImage {
                        id: photoImage
                        anchors.fill: parent
                        anchors.margins: 6
                        anchors.bottomMargin: 18   // bottom border, as on a Polaroid
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        playing: parent.animated
                        cache: true
                        asynchronous: true
                        // Decode at roughly twice the drawn size, not at the
                        // file's own resolution.
                        //
                        // These frames are 150x150. The sources are not:
                        // 03.png is 1937x1903 and decodes to 14.1 MB, 02.png is
                        // 1999x704 for 5.4 MB, and 01.gif is 500x500 across 14
                        // frames, all of which are held at once, for 13.4 MB.
                        // That is 32.8 MB of RGBA to draw three thumbnails that
                        // between them need about 0.26 MB.
                        //
                        // 300x300 is 2x the drawn size, which keeps the crop
                        // and any future scaling sharp while cutting the cost
                        // by more than 95%.
                        sourceSize.width: 300
                        sourceSize.height: 300
                    }
                }

                // Order = stacking order; the last one is on top.
                Photo {
                    source: "file:///home/woofi/.local/share/backgrounds/gallery/03.png"
                    x: 0;  y: 58; rotation: -13
                }
                Photo {
                    source: "file:///home/woofi/.local/share/backgrounds/gallery/01.gif"
                    animated: true
                    x: 74; y: 40; rotation: 11
                }
                Photo {
                    // The kiss picture goes on top.
                    source: "file:///home/woofi/.local/share/backgrounds/gallery/02.png"
                    x: 32; y: 0; rotation: -3
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: "My only Love <3"
                    color: root.cMauve
                    font.family: root.uiFont
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
            }

            // =============================================================
            //  SYSTEM AND CALENDAR -- one card
            // =============================================================
            //  Previously two separate cards stacked on top of each other.
            //  Merged because they always appeared together anyway and the gap
            //  between them tore the right column apart.
            //
            //  The events come from `hypr-calendar`, which reads the Evolution
            //  data server -- the Google account is already wired in there
            //  through GNOME Online Accounts. New accounts added in the GNOME
            //  settings show up here by themselves.
            Rectangle {
                id: calCard
                anchors.left: parent.horizontalCenter
                anchors.leftMargin: 12
                anchors.top: clockWidget.bottom
                anchors.topMargin: 22

                width: 320
                // Exactly as tall as the weather card on the left, so the two
                // columns end on the same line at the bottom.
                height: wxCard.height
                radius: 22
                color: Qt.rgba(root.cBase.r, root.cBase.g, root.cBase.b, 0.72)
                border.width: 1
                border.color: Qt.rgba(root.cSurface0.r, root.cSurface0.g, root.cSurface0.b, 0.9)
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    // 5 rather than the original 10: across seven elements that
                    // is 35 px more for the event list. Together with the
                    // narrower grid rows it gets to roughly five visible entries
                    // instead of just under four.
                    spacing: 5

                    // ---- system readings ------------------------------
                    Row {
                        id: statCol
                        width: parent.width
                        spacing: 0

                        component Stat: Column {
                            property string label
                            property string value
                            property color accent
                            width: statCol.width / 4
                            spacing: 1

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.label
                                color: root.cSubtext
                                font.family: root.uiFont
                                font.pixelSize: 10
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.value
                                color: parent.accent
                                font.family: root.uiFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }
                        }

                        Stat { label: "CPU";  value: root.cpuPct;  accent: root.cMaroon }
                        Stat { label: "RAM";  value: root.memUsed; accent: root.cBlue }
                        Stat { label: "Temp"; value: root.tempC;   accent: root.cPeach }
                        Stat {
                            label: "Akku"
                            value: root.battPct
                            accent: root.battState === "Charging" ? root.cGreen : root.cMaroon
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(root.cSurface0.r, root.cSurface0.g,
                                       root.cSurface0.b, 0.8)
                    }

                    // ---- month header with paging ---------------------
                    Item {
                        width: parent.width
                        height: 24

                        Text {
                            id: navPrev
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹"
                            color: prevMa.containsMouse ? root.cMauve : root.cSubtext
                            font.family: root.uiFont
                            font.pixelSize: 18
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                anchors.margins: -10
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.shiftMonth(-1)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.monthLabel()
                            color: root.cMauve
                            font.family: root.uiFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                cursorShape: Qt.PointingHandCursor
                                // Clicking the month name jumps back to today.
                                onClicked: root.goToday()
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: nextMa.containsMouse ? root.cMauve : root.cSubtext
                            font.family: root.uiFont
                            font.pixelSize: 18
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                anchors.margins: -10
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.shiftMonth(1)
                            }
                        }
                    }

                    // ---- Wochentage, Montag zuerst --------------------
                    Row {
                        id: calHead
                        width: parent.width
                        Repeater {
                            model: ["Mo","Di","Mi","Do","Fr","Sa","So"]
                            delegate: Text {
                                required property var modelData
                                width: calHead.width / 7
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: root.cSubtext
                                font.family: root.uiFont
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }
                    }

                    // ---- Tagesraster ----------------------------------
                    Grid {
                        id: calGrid
                        width: parent.width
                        columns: 7
                        rowSpacing: 1

                        // 30 gave the dot enough clearance from the bottom edge
                        // of the cell but left only 34 px for the event list --
                        // scrolling two lines is pointless. 26 wins 24 px back,
                        // and thanks to the smaller text offset the dot still
                        // sits clearly next to the right day.
                        readonly property real cellH: 24

                        Repeater {
                            model: 42
                            delegate: Item {
                                id: dayCell
                                required property int index
                                width: calGrid.width / 7
                                height: calGrid.cellH

                                readonly property var first:
                                    new Date(root.calYear, root.calMonth, 1)
                                readonly property int off: (first.getDay() + 6) % 7
                                readonly property var cell:
                                    new Date(root.calYear, root.calMonth, index - off + 1)
                                readonly property bool inMonth:
                                    cell.getMonth() === root.calMonth
                                readonly property string key: root.dayKey(cell)
                                readonly property bool isToday: key === root.todayKey()
                                readonly property bool picked: key === root.selectedDay
                                readonly property bool isWeekend: (index % 7) >= 5
                                readonly property var events: root.eventsFor(key)

                                // selection ring
                                Rectangle {
                                    anchors.centerIn: parent
                                    // Same offset as the numeral: it was raised
                                    // by 3 px to make room for the event dots
                                    // while the circle stayed centred, which
                                    // left the numeral visibly too high.
                                    anchors.verticalCenterOffset: -3
                                    width: 24; height: 24
                                    radius: 12
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: root.cLavender
                                    opacity: (dayCell.picked && !dayCell.isToday) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }
                                // Heute
                                Rectangle {
                                    anchors.centerIn: parent
                                    // Same offset as the numeral: it was raised
                                    // by 3 px to make room for the event dots
                                    // while the circle stayed centred, which
                                    // left the numeral visibly too high.
                                    anchors.verticalCenterOffset: -3
                                    width: 24; height: 24
                                    radius: 12
                                    color: root.cMauve
                                    opacity: dayCell.isToday ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }
                                // hover
                                Rectangle {
                                    anchors.centerIn: parent
                                    // Same offset as the numeral: it was raised
                                    // by 3 px to make room for the event dots
                                    // while the circle stayed centred, which
                                    // left the numeral visibly too high.
                                    anchors.verticalCenterOffset: -3
                                    width: 24; height: 24
                                    radius: 12
                                    color: root.cSurface1
                                    opacity: (dayMa.containsMouse && !dayCell.isToday) ? 0.6 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -3
                                    text: dayCell.cell.getDate()
                                    color: dayCell.isToday ? root.cCrust
                                         : (!dayCell.inMonth ? root.cSurface1
                                            : (dayCell.isWeekend ? root.cMaroon : root.cText))
                                    font.family: root.uiFont
                                    font.pixelSize: 11
                                    font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                                }

                                // Dots for events -- one per calendar, at most
                                // three, so the cell does not overflow.
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    spacing: 2
                                    Repeater {
                                        model: Math.min(3, dayCell.events.length)
                                        delegate: Rectangle {
                                            required property int index
                                            width: 3; height: 3; radius: 1.5
                                            // Through the cell's id, not through
                                            // parent.parent.parent: inside a
                                            // Repeater delegate `parent` points
                                            // at the Row, so the chain was off by
                                            // one and evaluated to undefined.
                                            color: dayCell.isToday
                                                   ? root.cCrust
                                                   : dayCell.events[index].colour
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedDay = dayCell.key
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(root.cSurface0.r, root.cSurface0.g,
                                       root.cSurface0.b, 0.8)
                    }

                    // ---- events for the selected day -----------------
                    Text {
                        width: parent.width
                        text: root.selectedLabel()
                        color: root.cSubtext
                        font.family: root.uiFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }

                    ListView {
                        id: evtList
                        width: parent.width
                        // Takes up the rest of the card. `y` is set by the
                        // Column, so parent.height - y is exactly the remaining
                        // space -- regardless of how tall the weather card
                        // happens to be.
                        height: Math.max(60, parent.height - y)
                        clip: true
                        spacing: 4
                        model: root.eventsFor(root.selectedDay)
                        boundsBehavior: Flickable.StopAtBounds

                        // Scrollbar permanently visible as soon as there is more
                        // than fits -- AsNeeded fades it out after a moment, and
                        // then nothing about the card suggests there is more
                        // below.
                        ScrollBar.vertical: ScrollBar {
                            policy: evtList.contentHeight > evtList.height
                                    ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 4
                            contentItem: Rectangle {
                                radius: 2
                                color: root.cSurface2
                                opacity: 0.7
                            }
                        }

                        delegate: Row {
                            required property var modelData
                            width: evtList.width - 6      // room for the scrollbar
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3; height: 15; radius: 1.5
                                color: modelData.colour
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                text: modelData.allday ? "ganztg" : modelData.time
                                color: root.cSubtext
                                font.family: root.uiFont
                                font.pixelSize: 10
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: evtList.width - 61
                                text: modelData.title
                                color: root.cText
                                font.family: root.uiFont
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // Placeholder while there is nothing. A child of the
                        // list, so it sits in the same place.
                        Text {
                            anchors.top: parent.top
                            visible: evtList.count === 0
                            text: root.calLoading ? "wird geladen …" : "Keine Termine"
                            color: root.cSurface2
                            font.family: root.uiFont
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
