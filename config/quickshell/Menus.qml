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

    // Keyboard selection index into the CURRENTLY FILTERED list, not into
    // appList -- the filter changes what row 0 means, so an index into the
    // unfiltered list would point at something the user cannot see.
    property int selIndex: 0
    // The filtered list, computed once here rather than in the Repeater's
    // model binding. Enter and the arrow keys have to agree with what is on
    // screen, and they cannot if each recomputes its own copy.
    readonly property var filteredApps: {
        const q = menus.query.toLowerCase();
        const out = [];
        for (let i = 0; i < menus.appList.length; i++) {
            if (q.length === 0 || menus.appList[i].name.toLowerCase().indexOf(q) !== -1)
                out.push(menus.appList[i]);
            if (out.length >= 40) break;
        }
        return out;
    }
    // Mirrors the search field, so filteredApps can depend on it without
    // reaching into a component declared much further down the file.
    property string query: ""

    function moveSel(d) {
        const n = menus.filteredApps.length;
        if (n === 0) return;
        // Clamped, not wrapped: wrapping from the last row back to the first
        // makes it easy to lose track of where you are in a long list.
        menus.selIndex = Math.max(0, Math.min(n - 1, menus.selIndex + d));
    }

    function launchSel() {
        const a = menus.filteredApps[menus.selIndex];
        if (!a) return;
        menus.run("/home/woofi/.local/bin/hypr-launch '" + a.wmclass + "' " + a.exec);
    }

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
        // No loader kick for "apps": the list arrives on the bus and is already
        // in appList before the menu opens.
        if (which === "places") loadPlaces.running = true;
        if (which === "wifi") { menus.wifiBusy = true; loadWifi.running = true; }
    }

    // Launch detached, NOT through a Process object.
    //
    // A Quickshell Process owns the thing it starts, and 0.3.0 has no opt-out
    // (there is no manageLifetime property on Process in this version). Two
    // things followed from that, and both were reported as the shell "closing
    // everything":
    //
    //   * Editing any file under ~/.config/quickshell triggers a hot reload.
    //     Reload destroys every QML object, the Process objects go with them,
    //     and every application ever started from a menu is killed. A terminal
    //     opened from the launcher died the moment a config file was touched.
    //   * A single shared `runner` was reused for every launch, so starting a
    //     second application tore down the first.
    //
    // execDetached hands the child to init and keeps no claim on it, which is
    // the correct relationship: the shell starts applications, it does not own
    // them.
    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
        menus.active = "";
    }

    // ---- Applications, subscribed from the event bus ----------------------
    //
    // This used to be an inline shell loop that ran four greps plus cut, sed
    // and basename per .desktop file, EVERY time the menu opened. Measured on
    // this machine: 225 files, 1463 forked processes, 927 ms. That is what made
    // the menu feel like it took seconds to react -- the panel animated open
    // immediately and then sat empty while the scan ran.
    //
    // hypr-applist does the same work in one process (29 ms cold, 17 ms from
    // cache) and hypr-eventd publishes it retained, so the list is already here
    // before the menu is opened. Opening it now costs nothing at all.
    // The application list arrives on the shared Bus singleton. See Bus.qml.
    Connections {
        target: Bus
        function onMessage(topic, d) {
            if (topic === "hypr/apps" && d && d.apps) menus.appList = d.apps;
        }
    }



    // The cache file, read once at startup, BEFORE the bus is consulted.
    //
    // The bus is the live path, but it is not the guaranteed one: the broker is
    // a separate service, and if it is slow, down, or restarted, a
    // bus-only menu is an empty menu -- which is exactly what happened, and why
    // CTRL+ALT+S stopped finding anything. hypr-applist keeps its own cache in
    // ~/.cache/hypr, so the list can always be loaded from disk in a few
    // milliseconds with nothing else running.
    //
    // Whatever the bus delivers afterwards replaces this. Reading the file
    // costs one process at startup and removes the shell's dependency on the
    // broker being up for the launcher to work at all.
    Process {
        id: appsFromFile
        running: true
        command: ["/home/woofi/.local/bin/hypr-applist"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Only if the bus has not already provided a newer list.
                if (menus.appList.length > 0) return;
                try {
                    const d = JSON.parse(this.text.trim());
                    if (d && d.apps) menus.appList = d.apps;
                } catch (e) { /* the bus is the other path */ }
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
        // Exclusive while open, for two separate reasons.
        //
        // OnDemand hands the keyboard over only when THIS surface is clicked.
        // Every one of these menus is opened from the bar or from a keybind, so
        // the click never lands here -- which meant the menu had no keyboard at
        // all. Two consequences: Escape could not close it, and the search
        // field could not be typed into until you clicked it first.
        //
        // Exclusive takes the keyboard the moment the surface appears, so the
        // applications menu can be typed into immediately and Escape works
        // everywhere. The cost is that Hyprland binds do not fire while a menu
        // is open, so CTRL+ALT+S no longer toggles it shut -- Escape and a
        // click outside are the close paths.
        WlrLayershell.keyboardFocus: menuWin.open ? WlrKeyboardFocus.Exclusive
                                                  : WlrKeyboardFocus.None
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

        // Escape for the menus that have nothing to type into.
        //
        // Deliberately NOT active for "apps". This Item and the search field are
        // siblings both declaring `focus`, and two claims in one focus scope
        // means whichever binding re-evaluates last wins — which is how the
        // search field ended up without the keyboard even when it looked
        // focused. The apps menu carries its own Escape handler on the TextInput
        // instead, so only one thing here ever asks for focus.
        Item {
            anchors.fill: parent
            focus: menuWin.open && menus.active !== "apps"
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
            // Centred on the TARGET width, never on `width`.
            //
            // `width` carries a Behavior, so it is animated: on the first open
            // after switching menus it still holds the PREVIOUS menu's value for
            // the first frames. Computing x from it therefore placed the card
            // using the old width and let it slide across afterwards -- which is
            // exactly the "spawns in the wrong place the first time" report.
            // Removing the duplicate Behavior on x was necessary but not
            // sufficient; this is the other half.
            x: menus.anchorX < 0
               ? 6
               : Math.max(6, Math.min(parent.width - card.targetWidth - 6,
                                      menus.anchorX - card.targetWidth / 2))
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            // Switching between applications and Wi-Fi moves the card to the
            // other side and changes its width at the same time. Without these
            // two transitions it jumped.
            //
            // `enabled: menuWin.open` is what fixes the menu appearing in the
            // wrong place the first time it is opened. x and width depend on
            // which menu is active and on the trigger it was opened from, so
            // opening a different menu than last time changes both. With the
            // animation always on, the card was still standing at the PREVIOUS
            // menu's position when it faded in, and slid across afterwards --
            // it looked like it had spawned in the wrong spot. While the panel
            // is closed the animation is off, so the new position is taken
            // instantly and the card fades in already where it belongs. Once
            // open, switching between menus animates as before.
            //
            // There used to be a SECOND `Behavior on x` a few lines up. Qt
            // rejects the duplicate at runtime -- "Attempting to set another
            // interceptor on QQuickRectangle property x - unsupported" in the
            // log -- so which of the two won was not something to rely on.
            Behavior on x     { enabled: menuWin.open; NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: menuWin.open; NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            // The width the card is heading for, independent of the animation.
            readonly property int targetWidth: menus.active === "apps" ? 460 : 340
            width: card.targetWidth
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

                            // The declarative `focus` above is not enough on its
                            // own: the surface does not exist yet at the moment
                            // `active` flips, so the claim is made against a
                            // window that has no keyboard to give. Qt.callLater
                            // defers it to after the surface is up.
                            //
                            // The text is cleared at the same time — reopening
                            // the launcher and finding the previous query still
                            // in it, with the list already filtered down, looked
                            // like the search was broken.
                            onVisibleChanged: if (visible) {
                                search.text = "";
                                menus.query = "";
                                menus.selIndex = 0;
                                Qt.callLater(search.forceActiveFocus);
                            }

                            // Typing changes what row 0 means, so the selection
                            // returns to the top. Leaving it where it was
                            // pointed at an unrelated application after every
                            // keystroke.
                            onTextChanged: {
                                menus.query = search.text;
                                menus.selIndex = 0;
                            }

                            Keys.onEscapePressed: menus.active = ""

                            // Arrow keys move the selection; the TextInput
                            // would otherwise consume them as cursor movement,
                            // which is useless on a single-line field.
                            Keys.onUpPressed:   menus.moveSel(-1)
                            Keys.onDownPressed: menus.moveSel(1)
                            Keys.onPressed: function (e) {
                                if (e.key === Qt.Key_Home)      { menus.selIndex = 0; e.accepted = true; }
                                else if (e.key === Qt.Key_End)  { menus.selIndex = Math.max(0, menus.filteredApps.length - 1); e.accepted = true; }
                                else if (e.key === Qt.Key_PageDown) { menus.moveSel(8);  e.accepted = true; }
                                else if (e.key === Qt.Key_PageUp)   { menus.moveSel(-8); e.accepted = true; }
                                // Tab moves the selection rather than focus:
                                // there is nowhere else in this panel to focus.
                                else if (e.key === Qt.Key_Tab)      { menus.moveSel(1);  e.accepted = true; }
                                else if (e.key === Qt.Key_Backtab)  { menus.moveSel(-1); e.accepted = true; }
                            }

                            // Enter launches the SELECTED row, not
                            // unconditionally the first one. Same launch path as
                            // clicking it: hypr-launch raises a running instance
                            // instead of starting a second copy.
                            onAccepted: menus.launchSel()
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
                            model: menus.active !== "apps" ? [] : menus.filteredApps
                            delegate: MenuRow {
                                required property var modelData
                                required property int index
                                label: modelData.name
                                iconName: modelData.icon
                                icon: 0xf0349
                                selected: index === menus.selIndex
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
        // Selected by keyboard, highlighted the same way as hover: both mean
        // "this is the row Enter will act on", so they must not look different.
        property bool selected: false
        color: (hov.hovered || menuRow.selected) ? Theme.surface1 : "transparent"
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
            // Ask the icon provider for the size actually drawn.
            //
            // Without sourceSize, Quickshell requests 100x100 -- the log filled
            // with "Could not load icon ... at size QSize(100, 100)", repeating
            // on every refresh. Two costs: the theme may have no 100px variant
            // of an icon it does have at 48, so the lookup fails and the row
            // draws blank; and every success decoded a 100x100 RGBA buffer to
            // paint 22x22.
            //
            // 44 is 2x the drawn size, which stays sharp on a scaled output and
            // matches a size real icon themes actually ship.
            sourceSize.width: 44
            sourceSize.height: 44
            // Themes disagree about which names they carry, and a missing icon
            // is not an error worth logging on every repaint.
            asynchronous: true
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
