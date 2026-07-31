//  Apps, Places and Wi-Fi menus as Quickshell panels.
//
//  These replace the former rofi dropdowns. The reasons are the same ones that
//  applied to Quick Settings:
//    * Under Wayland rofi never receives clicks outside its own surface, so
//      -click-to-exit does not fire there — the menus stayed open.
//    * rofi does not show up in `hyprctl layers`, so its position could not be
//      pinned below the bar (the menus sat far too low).
//    * rofi themes carry fixed colours and do not follow light/dark.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: menus

    property string active: ""       // "apps" | "places" | "wifi" | ""

    // Horizontal centre of the bar item that opened the menu, in bar
    // coordinates. -1 means "not told", in which case the card falls back to
    // the left edge.
    //
    // Before this existed, every menu was pinned to a screen edge: apps and
    // places to x=6, Wi-Fi to the far right. The Wi-Fi icon is nowhere near
    // the right edge, so the list opened detached from the icon that produced
    // it. Now the card is centred under its trigger and clamped to the screen.
    property real anchorX: -1
    readonly property int barHeight: 40

    property var appList: []
    property var wifiList: []
    property string wifiActive: ""
    property bool wifiBusy: false

    IpcHandler {
        target: "menu"
        // The x variants take the trigger's centre; the bare ones stay for
        // keybindings and manual `qs ipc call`, where there is no trigger.
        function apps(): void         { menus.openMenu("apps"); }
        function places(): void       { menus.openMenu("places"); }
        function wifi(): void         { menus.openMenu("wifi"); }
        function appsAt(x: real): void   { menus.openMenu("apps", x); }
        function placesAt(x: real): void { menus.openMenu("places", x); }
        function wifiAt(x: real): void   { menus.openMenu("wifi", x); }
        function hide(): void   { menus.active = ""; }
    }

    function openMenu(which, centreX) {
        menus.anchorX = (centreX === undefined || centreX === null) ? -1 : centreX;
        if (menus.active === which) { menus.active = ""; return; }
        menus.active = which;
        if (which === "apps") loadApps.running = true;
        if (which === "places") loadPlaces.running = true;
        if (which === "wifi") { menus.wifiBusy = true; loadWifi.running = true; }
    }

    Process { id: runner }
    function run(cmd) {
        runner.command = ["sh", "-c", cmd];
        runner.running = true;
        menus.active = "";
    }

    // ---- Applications, read from the .desktop files ------------------------
    Process {
        id: loadApps
        command: ["sh", "-c", `
            for d in /usr/share/applications "$HOME/.local/share/applications" \
                     /var/lib/flatpak/exports/share/applications; do
              [ -d "$d" ] || continue
              for f in "$d"/*.desktop; do
                [ -f "$f" ] || continue
                grep -q '^NoDisplay=true' "$f" && continue
                n=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
                e=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed 's/%[fFuUdDnNickvm]//g')
                ic=$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)
                wc=$(grep -m1 '^StartupWMClass=' "$f" | cut -d= -f2-)
                [ -z "$wc" ] && wc=$(basename "$f" .desktop)
                [ -n "$n" ] && [ -n "$e" ] && printf '%s\\t%s\\t%s\\t%s\\n' "$n" "$e" "$ic" "$wc"
              done
            done | sort -u -f
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n").filter(l => l.indexOf("\t") > 0);
                menus.appList = rows.map(l => {
                    const p = l.split("\t");
                    return { name: p[0], exec: p[1], icon: p[2] || "", wmclass: p[3] || "" };
                });
            }
        }
    }

    // ---- Wi-Fi -------------------------------------------------------------
    Process {
        id: loadWifi
        // `--rescan no` reads the cache in about 40 ms; letting nmcli scan
        // implicitly took 2.5 s and delayed the menu by exactly that much.
        command: ["sh", "-c",
            "nmcli -t -f NAME connection show --active | head -1; echo '---'; " +
            "nmcli --terse --fields SSID,SIGNAL,SECURITY dev wifi list --rescan no " +
            "| awk -F: '$1 != \"\" { if (!seen[$1]++) print }' | sort -t: -k2 -nr | head -12"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("---");
                menus.wifiActive = (parts[0] || "").trim();
                const rows = (parts[1] || "").trim().split("\n").filter(l => l.length);
                menus.wifiList = rows.map(l => {
                    const c = l.split(":");
                    return { ssid: c[0], signal: parseInt(c[1] || "0"), sec: c[2] || "" };
                });
                menus.wifiBusy = false;
                // Rescan in the background so the next invocation is fresh.
                rescan.running = true;
            }
        }
    }
    Process { id: rescan; command: ["nmcli", "dev", "wifi", "rescan"] }

    // ---- Places ------------------------------------------------------------
    // Read from a script instead of hard-coding: the XDG paths on this machine
    // deviate a lot (downloads lower-case, pictures and videos below
    // documents/private/), so fixed names such as ~/Downloads pointed nowhere.
    property var placeList: []
    Process {
        id: loadPlaces
        command: ["/home/woofi/.local/bin/hypr-places"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n").filter(l => l.indexOf("\t") > 0);
                menus.placeList = rows.map(l => {
                    const c = l.split("\t");
                    return { label: c[0], path: c[1], icon: parseInt(c[2]) };
                });
            }
        }
    }

    function wifiIcon(sig) {
        if (sig >= 75) return Theme.ico(0xf0928);
        if (sig >= 50) return Theme.ico(0xf0925);
        if (sig >= 25) return Theme.ico(0xf0922);
        return Theme.ico(0xf091f);
    }

    // =======================================================================
    //  Shared panel
    // =======================================================================
    PanelWindow {
        id: menuWin

        readonly property bool open: menus.active !== ""

        // NOT `visible: menus.active !== ""`.
        //
        // That is how it used to read, and it is why the closing animation was
        // never visible: the moment `active` goes empty the layer surface is
        // gone, so the card had no surface left to fade out on. It opened with
        // a transition and vanished in a single frame.
        //
        // The window lifetime now hangs on the card's opacity: it stays alive
        // until the fade has run to completion.
        visible: menuWin.open || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-menus"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        // Clicking beside the card closes it — precisely what rofi could not do.
        //
        // MouseArea AND TapHandler: in the apps/places menus the focused
        // TextInput swallowed the first click, so the MouseArea alone did not
        // fire reliably. The TapHandler triggers independently of that. Escape
        // closes as well.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: menus.active = ""
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: menus.active = ""
        }

        Item {
            anchors.fill: parent
            focus: menus.active !== ""
            Keys.onEscapePressed: menus.active = ""
        }

        // Scrim behind the card. It accepts no clicks — a plain Rectangle has
        // no input area — so the MouseArea above still closes the menu.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: menuWin.open ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card

            // ---- Opening and closing transition ----------------------------
            //
            // Three quantities at once, all on the same duration and curve so
            // that it reads as one movement rather than three:
            //
            //   opacity   0 -> 1
            //   scale     0.94 -> 1, with the origin at the corner underneath
            //             the button the card belongs to (left or right)
            //   position  6 px higher -> final place, so it slides out from
            //             beneath the bar
            //
            // 190 ms rather than the previous 110: the old fade was so short it
            // read as a flicker. At 60 frames per second this is about eleven
            // intermediate frames.
            readonly property int animMs: 190

            opacity: menuWin.open ? 1 : 0
            scale: menuWin.open ? 1 : 0.94
            // Scale out of the corner nearest the trigger, so the motion reads
            // as coming from the thing that was clicked.
            transformOrigin: menus.anchorX < 0
                             ? Item.TopLeft
                             : (menus.anchorX > menuWin.width / 2 ? Item.TopRight : Item.TopLeft)
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            // Apps and Places hang on the left, Wi-Fi on the right — each below
            // its own button in the bar.
            //
            // NO switching left/right anchors: assigning undefined did not
            // reliably drop the previous binding, so at times both sides were
            // anchored and the card stretched across the full screen width. An
            // explicit x is unambiguous.
            y: menus.barHeight + (menuWin.open ? 4 : -6)
            // Centred under the trigger, then clamped so it never runs off
            // either edge. Without the clamp the Wi-Fi card -- which sits far
            // right in the bar -- would hang past the screen.
            x: menus.anchorX < 0
               ? 6
               : Math.max(6, Math.min(parent.width - width - 6, menus.anchorX - width / 2))
            Behavior on x { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            // Switching between applications and Wi-Fi moves the card to the
            // other side and changes its width at the same time. Without these
            // two transitions it jumped.
            Behavior on x     { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            width: menus.active === "apps" ? 460 : 340
            height: Math.min(parent.height - menus.barHeight - 40, body.implicitHeight + 26)
            radius: 20
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.98)
            border.width: 2
            border.color: Theme.surface1

            MouseArea { anchors.fill: parent }

            Column {
                id: body
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 8

                Text {
                    text: menus.active === "apps" ? "ANWENDUNGEN"
                        : menus.active === "places" ? "ORTE" : "WLAN"
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                // ---- Search field, applications only ----
                Rectangle {
                    visible: menus.active === "apps"
                    width: parent.width
                    height: 38
                    radius: 12
                    color: Qt.rgba(Theme.crust.r, Theme.crust.g, Theme.crust.b, 0.9)
                    border.width: 1
                    border.color: Theme.surface0

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 9
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.ico(0xf0349)
                            color: Theme.mauve
                            font.family: Theme.uiFont
                            font.pixelSize: 14
                        }
                        TextInput {
                            id: search
                            width: parent.width - 40
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 13
                            focus: menus.active === "apps"
                            clip: true
                            onAccepted: {
                                const hits = menus.appList.filter(a =>
                                    a.name.toLowerCase().indexOf(text.toLowerCase()) !== -1);
                                if (hits.length) menus.run(hits[0].exec);
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text.length === 0
                                text: "Suchen…"
                                color: Theme.surface2
                                font.family: Theme.uiFont
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                // ---- List ----
                Flickable {
                    width: parent.width
                    height: Math.min(430, listCol.implicitHeight)
                    contentHeight: listCol.implicitHeight
                    clip: true

                    Column {
                        id: listCol
                        width: parent.width
                        spacing: 2

                        // --- Applications ---
                        Repeater {
                            model: menus.active !== "apps" ? [] :
                                   menus.appList.filter(a =>
                                       search.text.length === 0 ||
                                       a.name.toLowerCase().indexOf(search.text.toLowerCase()) !== -1)
                                   .slice(0, 40)
                            delegate: MenuRow {
                                required property var modelData
                                required property int index
                                label: modelData.name
                                iconName: modelData.icon
                                icon: 0xf0349
                                stagger: Math.min(index * 16, 260)
                                // hypr-launch raises an already running app
                                // (switching workspace if needed) instead of
                                // starting a second instance.
                                onTriggered: menus.run(
                                    "/home/woofi/.local/bin/hypr-launch '"
                                    + modelData.wmclass + "' " + modelData.exec)
                            }
                        }

                        // --- Places ---
                        Repeater {
                            model: menus.active !== "places" ? [] : menus.placeList
                            delegate: MenuRow {
                                required property var modelData
                                required property int index
                                label: modelData.label
                                icon: modelData.icon
                                stagger: Math.min(index * 16, 260)
                                onTriggered: menus.run(
                                    "nautilus --new-window \"" + modelData.path + "\"")
                            }
                        }

                        // --- Wi-Fi ---
                        Text {
                            visible: menus.active === "wifi" && menus.wifiBusy
                            text: "Suche Netzwerke…"
                            color: Theme.subtext
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            padding: 10
                        }
                        Repeater {
                            model: menus.active !== "wifi" ? [] : menus.wifiList
                            delegate: MenuRow {
                                required property var modelData
                                required property int index
                                label: modelData.ssid
                                iconText: menus.wifiIcon(modelData.signal)
                                stagger: Math.min(index * 16, 260)
                                trailing: (modelData.sec !== "" && modelData.sec !== "--"
                                           ? Theme.ico(0xf033e) : "")
                                          + (modelData.ssid === menus.wifiActive
                                             ? "  " + Theme.ico(0xf012c) : "")
                                onTriggered: menus.run(
                                    "nmcli connection up id '" + modelData.ssid + "' || " +
                                    "nmcli dev wifi connect '" + modelData.ssid + "'")
                            }
                        }
                        MenuRow {
                            visible: menus.active === "wifi"
                            label: "Netzwerkeinstellungen"
                            icon: 0xf0493
                            onTriggered: menus.run("nm-connection-editor")
                        }
                    }
                }
            }
        }
    }

    // A single row in the menu — hover highlights it, a click triggers it.
    component MenuRow: Rectangle {
        id: menuRow

        // ---- Staggered entrance -------------------------------------------
        //
        // The rows come in one after another instead of all in the same frame.
        // That is the real difference in the applications menu: a list that
        // appears as one block reads as a still image, one that runs in from
        // top to bottom reads as a movement.
        //
        // The offset is capped at 16 ms per row, otherwise row 40 would arrive
        // a full second late; this way everything has landed after at most
        // 260 ms of offset plus the 200 ms fade.
        //
        // Why this runs on every open: the Repeater models are bound to
        // `menus.active` and are therefore empty while the menu is closed. The
        // rows are built afresh each time, and an animation used as a value
        // source starts when its component completes.
        property int stagger: 0

        opacity: 0
        SequentialAnimation on opacity {
            PauseAnimation { duration: menuRow.stagger }
            NumberAnimation { from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
        // The leftward offset is cut off by the Flickable's `clip: true`, so
        // the row slides out from under the card edge rather than floating
        // outside it.
        SequentialAnimation on x {
            PauseAnimation { duration: menuRow.stagger }
            NumberAnimation { from: -14; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }

        property string label
        property int icon: 0
        property string iconText: ""
        property string iconName: ""     // app icon out of the .desktop file
        property string trailing: ""
        signal triggered()

        // IMPORTANT: parent.width, NOT listCol.width. This component is
        // declared outside the PanelWindow, and listCol does not resolve there
        // — the row ended up 0 wide, which left the MouseArea without an area,
        // which is why clicks did nothing.
        width: parent ? parent.width : 300
        height: 34
        radius: 11
        color: hov.hovered ? Theme.surface1 : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }

        HoverHandler { id: hov }

        Image {
            id: appIcon
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            visible: menuRow.iconName !== "" && status === Image.Ready
            source: menuRow.iconName !== "" ? "image://icon/" + menuRow.iconName : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            visible: !appIcon.visible
            text: menuRow.iconText !== "" ? menuRow.iconText
                : (menuRow.icon !== 0 ? Theme.ico(menuRow.icon) : "")
            color: Theme.subtext
            font.family: Theme.uiFont
            font.pixelSize: 14
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.right: parent.right
            anchors.rightMargin: 70
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.label
            color: Theme.text
            font.family: Theme.uiFont
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.trailing
            color: Theme.mauve
            font.family: Theme.uiFont
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            onClicked: menuRow.triggered()
        }
    }
}
