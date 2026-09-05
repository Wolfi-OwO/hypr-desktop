//  GNOME-style notification centre.
//
//  Why build this rather than use swaync: swaync has NO calendar widget and
//  no two-column layout -- it only knows title/dnd/mpris/notifications/...
//  GNOME, however, shows notifications on the left and the calendar on the
//  right, with DND at the bottom left and "clear" at the bottom right.
//  Quickshell ships its own NotificationServer, so that can be rebuilt
//  exactly.
//
//  Quickshell is therefore the notification daemon; swaync must not run
//  (the two cannot own org.freedesktop.Notifications at the same time).

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Scope {
    id: nc

    property bool panelOpen: false
    onPanelOpenChanged: {
        if (nc.panelOpen) Exclusivity.claim("notifications");
        else Exclusivity.release("notifications");
    }
    Connections {
        target: Exclusivity
        function onOwnerChanged() {
            if (Exclusivity.owner !== "notifications" && nc.panelOpen) nc.panelOpen = false;
        }
    }
    // Seeded from disk, not hardcoded to false.
    //
    // Do-not-disturb used to reset on every shell restart -- and the shell
    // restarts on any config change and whenever the watchdog fires. Switching
    // it on and finding it silently off again an hour later makes the setting
    // untrustworthy, which is worse than not having it.
    //
    // blockLoading, so the value is present before the first notification can
    // arrive rather than being applied a moment later.
    property bool dnd: {
        try {
            const t = dndCache.text();
            if (t.length > 0) return JSON.parse(t).dnd === true;
        } catch (e) { /* first run, or a half-written file */ }
        return false;
    }

    // Persist on every change. ONE handler: QML permits a single onDndChanged
    // per object, and a second silently costs the whole file.
    onDndChanged: dndCache.setText(JSON.stringify({ dnd: nc.dnd }))

    FileView {
        id: dndCache
        path: "/home/woofi/.cache/hypr/dnd.json"
        blockLoading: true
        printErrors: false
    }

    // Calendar navigation.
    //
    // Derived from the shared CalendarData singleton rather than held here, so
    // this calendar and the desktop widget can never drift onto different
    // months. Paging goes through CalendarData.shiftMonth().
    readonly property date viewDate: new Date(CalendarData.year, CalendarData.month, 1)

    // Which day's events show below the grid. The grid itself only ever
    // showed dots -- there was no way to see what a dot meant, which is why
    // the calendar read as decorative even after CalendarData gave it real
    // data. shell.qml's desktop widget already solved this (selectedDay +
    // an event list); this mirrors that pattern instead of inventing a
    // second one.
    property string selectedDay: CalendarData.todayKey()

    function selectedDayLabel() {
        const p = nc.selectedDay.split("-");
        const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        return d.toLocaleDateString(Qt.locale(Strings.locale), "dddd, d. MMMM").toUpperCase();
    }

    // Open whatever sent a notification, then close the centre.
    //
    // USED to be: invoke the sender's own "default"/single action if it has
    // one, and only fall back to hypr-launch (raise-or-start the app) for
    // senders that offer no actions at all. That's why "click brings me to
    // the app + workspace" kept not working -- most senders DO register a
    // default action, so hypr-launch (the only route that actually asks
    // Hyprland to focus the window and switch workspace) never ran at all.
    // Invoking a notification action tells the SENDING app "handle this
    // click" over its own private channel (D-Bus ActionInvoked); on this
    // stack nothing requires that channel to also carry a window-activation
    // token, and in practice it usually doesn't -- the app may open the
    // right conversation internally without ever asking the compositor to
    // raise or focus its window.
    //
    // Now both happen, unconditionally, every click:
    //  1. hypr-launch, matched against desktopEntry (preferred) or appName
    //     (fallback -- fine here specifically because raising only touches a
    //     window that's already open; it can't start the WRONG app, unlike
    //     guessing a whole launch command from free-text appName). This is
    //     the part that actually satisfies "bring me to the app +
    //     workspace" -- it dispatches hl.dsp.focus + bring_to_top for real.
    //  2. The sender's own default/single action, if it has one, so
    //     app-specific deep-linking (open THIS conversation, not just the
    //     app) still happens same as before.
    //
    // If hypr-launch finds no window open for that needle, it falls through
    // to its own EXEC argument -- gtk-launch for a real desktopEntry, or a
    // harmless shell no-op when only appName is available, so an
    // appName-only notification can still raise an ALREADY-open window
    // without risking starting the wrong program from guessed free text.
    function activate(n) {
        if (!n) return;

        const entry = (n.desktopEntry || "").replace(/\.desktop$/, "");
        const needle = entry !== "" ? entry : (n.appName || "");
        // Trust boundary: desktopEntry and appName come straight from the
        // D-Bus sender. These two used to be concatenated into an `sh -c`
        // string, so a sender setting desktop-entry to  x'; touch /tmp/x; '
        // got arbitrary shell as the user the moment the toast was clicked.
        //
        // The shape check is what closes that, not the argv form: hypr-launch
        // runs `setsid sh -c "$EXEC"` by design, so the exec words reach a
        // shell however they are passed. argv only removes the second
        // concatenation.
        //
        // It guards `entry` specifically, because entry is the only value that
        // becomes EXEC and reaches that shell. `needle` is $1 in hypr-launch
        // and from there only ever sees `printf '%s' "$1" | tr` and
        // `jq --arg` -- never a shell. Guarding the needle instead was
        // measured to break the appName-only raise for every app whose name
        // has a space in it ("Google Chrome", "Visual Studio Code"): the click
        // silently stopped raising an already-open window. Desktop entry IDs
        // really are this shape, so the check costs nothing.
        //
        // Either way a rejected entry skips only the raise, never the sender's
        // own actions below.
        if (needle !== "" && (entry === "" || /^[A-Za-z0-9._-]+$/.test(entry))) {
            Quickshell.execDetached(entry !== ""
                ? ["/home/woofi/.local/bin/hypr-launch", needle, "gtk-launch", entry]
                : ["/home/woofi/.local/bin/hypr-launch", needle, ":"]);
        }

        const acts = n.actions || [];
        let invoked = false;
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                acts[i].invoke();
                invoked = true;
                break;
            }
        }
        if (!invoked && acts.length === 1) acts[0].invoke();

        nc.panelOpen = false;
    }

    // ---- Palette (Catppuccin Mocha) ---------------------------------------
    // Bound to Theme instead of hard-wired. This used to hold
    // literals, which is why these surfaces stayed dark in light mode
    // while the bar and the GTK apps had already switched.
    readonly property color cBase:     Theme.base
    readonly property color cMantle:   Theme.mantle
    readonly property color cCrust:    Theme.crust
    readonly property color cSurface0: Theme.surface0
    readonly property color cSurface1: Theme.surface1
    readonly property color cSurface2: Theme.surface2
    readonly property color cText:     Theme.text
    readonly property color cSubtext:  Theme.subtext
    readonly property color cMauve:    Theme.mauve
    readonly property color cLavender: Theme.lavender
    readonly property color cRed:      Theme.red
    readonly property string uiFont: Theme.uiFont

    SystemClock {
        id: clk
        precision: SystemClock.Minutes
    }

    // ---- Notification-Server ----------------------------------------------
    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true

        onNotification: function (n) {
            // tracked = the notification stays in trackedNotifications;
            // without it, it disappears from the history immediately.
            n.tracked = true;
            // Drop it from the toast display after 10 s. The notification
            // stays in the centre; only the toast goes away.
            nc.hideAfter(n);
        }
    }

    // Switchable from waybar:  qs ipc call notifications toggle
    IpcHandler {
        target: "notifications"
        function toggle(): void { nc.panelOpen = !nc.panelOpen; }
        function open(): void { nc.panelOpen = true; }
        function close(): void { nc.panelOpen = false; }
        function clear(): void { nc.clearAll(); }
        // Switchable from outside -- which also lets the state be
        // checked without having to click inside the panel.
        function dnd(): void { nc.dnd = !nc.dnd; }
    }

    // Toasts that have already expired -- they stay visible in the history.
    property var expired: ({})

    Timer {
        id: sweeper
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            let changed = false;
            for (const key in nc.expired) {
                if (nc.expired[key] <= now) { delete nc.expired[key]; changed = true; }
            }
            if (changed) nc.expiredChanged();
        }
    }

    function hideAfter(n) {
        const e = nc.expired;
        e[n.id] = Date.now() + 10000;   // 10 seconds
        nc.expired = e;
        nc.expiredChanged();
    }

    function toastVisible(n) {
        return nc.expired[n.id] !== undefined && nc.expired[n.id] > Date.now();
    }

    function clearAll() {
        const list = server.trackedNotifications.values.slice();
        for (const n of list) n.dismiss();
    }

    function twoDigit(n) { return n < 10 ? "0" + n : "" + n; }

    // A usable image source for a notification, or "" if none resolves.
    //
    // `image` looked like the safe field to trust outright -- it is what
    // NotificationServer already resolved appIcon into. But it resolves an
    // icon NAME the same way the "image://icon/" provider does: unconditionally,
    // as "image://icon/<name>", even when the icon theme has no such icon. The
    // theme then substitutes its own broken-image checkerboard for the load,
    // which is a successful Image.Ready -- there is no failure to check
    // `status` against. That checkerboard is what "notification icons are
    // broken" turned out to be. A real embedded image (a screenshot, a
    // contact photo) arrives as a genuine path or data URI, never this
    // prefix, so only the icon-provider form needs validating here.
    function resolveIcon(n) {
        if (!n) return "";
        if (n.image !== "") {
            if (n.image.indexOf("image://icon/") === 0) {
                const name = n.image.substring("image://icon/".length);
                return Quickshell.hasThemeIcon(name) ? n.image : "";
            }
            return n.image;
        }
        if (n.appIcon !== "" && Quickshell.hasThemeIcon(n.appIcon))
            return "image://icon/" + n.appIcon;
        return "";
    }

    // =======================================================================
    //  TOASTS -- centred at the top
    // =======================================================================
    PanelWindow {
        id: toasts
        visible: !nc.dnd && toastRepeater.count > 0

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-notification-toasts"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true }
        implicitHeight: Math.max(1, toastCol.implicitHeight + 56)

        // Input clipped to the toast column, because the panel is far bigger
        // than the toasts drawn in it. Anchoring left AND right is what lets a
        // toast be centred, but it also made the layer surface 1440x130 at 0,0
        // (measured with `hyprctl layers` while a toast was up) -- a band
        // across the entire top of the screen, sitting on the overlay layer
        // ON TOP of the 1440x40 bar. A layer surface takes input over its
        // whole extent unless masked, so the transparent remainder ate every
        // click: with a toast up, clicking logical (200,110) over a window
        // there did NOT move focus, while the same click at (200,300), just
        // below the band, did. The bar was unreachable for the toast's full
        // 10 s lifetime. The column is exactly the 440 px of drawn card, and
        // the close button sits inside it, so nothing clickable is lost.
        mask: Region { item: toastCol }

        Column {
            id: toastCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // 48 rather than 8: the panel sits on the overlay layer and sets
            // `exclusionMode: Ignore`, so it starts at y=0 and NOT below the
            // 40 px bar. At 8 px the top edge of the card, red X and all,
            // disappeared behind the bar, which made the X look as though it
            // sat outside the card.
            //
            // Ignore has to stay: without it the panel would reserve space
            // itself and push every window down for as long as a notification
            // is on screen.
            anchors.topMargin: 48
            spacing: 8

            Repeater {
                id: toastRepeater
                // only show the three most recent as toasts
                model: ScriptModel {
                    values: {
                        const v = server.trackedNotifications.values
                                     .filter(n => nc.toastVisible(n));
                        return v.slice(Math.max(0, v.length - 3));
                    }
                }

                delegate: Rectangle {
                    id: toastCard
                    required property var modelData
                    width: 440
                    height: Math.max(74, toastBody.implicitHeight + 26)
                    radius: 18

                    // Same hover and click behaviour as the rows in the
                    // centre: a toast is the first place you see a notification,
                    // so it should be the first place you can act on it.
                    scale: toastHov.hovered ? 1.015 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    HoverHandler {
                        id: toastHov
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: nc.activate(toastCard.modelData)
                    }
                    // The accent colour is the card's BASE surface. The
                    // previous approach -- a separate bar on the left -- stuck
                    // out of the rounding whatever corner radii were used.
                    // Here the accent colour sits underneath and the actual
                    // card surface on top of it, inset by 5 px on the left.
                    // What stays visible is exactly one edge, and it follows
                    // the card's rounding.
                    color: modelData.urgency === NotificationUrgency.Critical
                           ? nc.cRed
                           : (modelData.urgency === NotificationUrgency.Low
                              ? nc.cSurface2 : nc.cMauve)
                    border.width: 1
                    border.color: nc.cSurface1

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1
                        anchors.rightMargin: 1
                        radius: 17
                        color: Qt.rgba(nc.cBase.r, nc.cBase.g, nc.cBase.b, 0.99)
                    }


                    // Red X at the top right: deletes exactly this
                    // notification. Sits above the content so it gets the
                    // click first.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        width: 22; height: 22
                        radius: 11
                        z: 10
                        color: closeHov.hovered ? nc.cRed : "transparent"
                        border.width: closeHov.hovered ? 0 : 1
                        border.color: nc.cSurface1
                        Behavior on color { ColorAnimation { duration: 90 } }

                        HoverHandler { id: closeHov }

                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: closeHov.hovered ? nc.cCrust : nc.cRed
                            font.family: nc.uiFont
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: modelData.dismiss()
                        }
                    }

                    Row {
                        id: toastBody
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 14
                        anchors.topMargin: 13
                        anchors.bottomMargin: 13
                        spacing: 13

                        // App-Logo
                        Rectangle {
                            width: 46; height: 46
                            radius: 13
                            color: nc.cSurface0
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: toastIcon
                                anchors.fill: parent
                                anchors.margins: 3
                                source: nc.resolveIcon(modelData)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                // See Menus.qml: without sourceSize the icon
                                // provider is asked for 100x100, which fails
                                // for icons the theme only ships smaller and
                                // decodes far more than is drawn.
                                sourceSize.width: 96
                                sourceSize.height: 96
                                asynchronous: true
                                // hasThemeIcon, not just appIcon !== "": the
                                // icon theme substitutes its own broken-image
                                // checkerboard for a name it does not carry
                                // instead of failing to load, so checking
                                // Image.status never saw a failure -- the
                                // lookup itself has to be validated first.
                                // That checkerboard is what "notification
                                // icons are broken" turned out to be.
                                visible: source !== "" && status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: toastIcon.source === "" || toastIcon.status !== Image.Ready
                                text: (modelData.appName || "?").charAt(0).toUpperCase()
                                color: nc.cMauve
                                font.family: nc.uiFont
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }
                        }

                        Column {
                            width: parent.width - 46 - 13
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.summary || modelData.appName
                                color: nc.cText
                                font.family: nc.uiFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.body
                                color: nc.cSubtext
                                font.family: nc.uiFont
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }

                }
            }
        }
    }

    // =======================================================================
    //  CONTROL CENTER — two columns, laid out like the GNOME original
    // =======================================================================
    PanelWindow {
        id: panel

        // Tied to the card's opacity rather than straight to `panelOpen`, so
        // the layer surface outlives the closing fade. With
        // `visible: nc.panelOpen` the surface disappeared in the same frame the
        // state flipped, and the close animation was never seen — it opened
        // with a transition and vanished instantly. Same fix as in Menus.qml.
        visible: nc.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-notification-center"
        // Exclusive while open. OnDemand only grants the keyboard when THIS
        // surface is clicked, but the centre is opened from the bar clock, so
        // the click lands elsewhere and the Escape handler below could never
        // fire. See Controls.qml for the full reasoning.
        WlrLayershell.keyboardFocus: nc.panelOpen ? WlrKeyboardFocus.Exclusive
                                                  : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        // A click anywhere beside the card closes the panel.
        MouseArea {
            anchors.fill: parent
            onClicked: nc.panelOpen = false
        }

        // Escape closes as well, not just the click beside it (#50).
        Item {
            anchors.fill: parent
            focus: nc.panelOpen
            Keys.onEscapePressed: nc.panelOpen = false
        }

        // Scrim, identical to the one behind the applications menu.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: nc.panelOpen ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card

            // Same transition as every other panel: opacity, scale and a short
            // slide out from beneath the bar, all on one duration and one curve
            // so it reads as a single movement. This card is centred under the
            // clock, so it scales from Item.Top rather than from a corner.
            readonly property int animMs: 190

            opacity: nc.panelOpen ? 1 : 0
            scale: nc.panelOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: nc.panelOpen ? 8 : -2
            Behavior on anchors.topMargin { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            width: 880
            height: Math.min(parent.height - 60, 620)
            radius: 22
            color: Qt.rgba(nc.cMantle.r, nc.cMantle.g, nc.cMantle.b, 0.98)
            border.width: 2
            border.color: nc.cSurface1

            // do not pass clicks inside the panel through
            MouseArea { anchors.fill: parent }

            // ---------------- left column: notifications -------------------
            Item {
                id: leftCol
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 16
                width: parent.width * 0.52

                Text {
                    id: leftTitle
                    text: Strings.t.notifications
                    color: nc.cText
                    font.family: nc.uiFont
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Flickable {
                    anchors.top: leftTitle.bottom
                    anchors.topMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: dndRow.top
                    anchors.bottomMargin: 12
                    contentHeight: notifCol.implicitHeight
                    clip: true

                    Column {
                        id: notifCol
                        width: parent.width
                        spacing: 8

                        Text {
                            visible: server.trackedNotifications.values.length === 0
                            text: Strings.t.noNotifications
                            color: nc.cSurface2
                            font.family: nc.uiFont
                            font.pixelSize: 13
                        }

                        Repeater {
                            model: ScriptModel {
                                values: server.trackedNotifications.values.slice().reverse()
                            }
                            delegate: Rectangle {
                                id: notifCard
                                required property var modelData
                                width: notifCol.width
                                height: Math.max(62, itemRow.implicitHeight + 20)
                                radius: 14

                                // Hover: lift the surface, warm the border and
                                // nudge it right by a pixel. All three on the
                                // same short duration so it reads as one motion
                                // rather than three separate reactions.
                                color: rowHov.hovered
                                       ? Qt.rgba(nc.cSurface0.r, nc.cSurface0.g, nc.cSurface0.b, 0.96)
                                       : Qt.rgba(nc.cBase.r, nc.cBase.g, nc.cBase.b, 0.9)
                                border.width: 1
                                border.color: rowHov.hovered ? nc.cMauve : nc.cSurface0
                                // NO x shift on hover.
                                //
                                // This used to move the card 2 px right, which
                                // pushed it past the column's right edge: the
                                // card fills the width, so any rightward shift
                                // clips the border and the lit surface against
                                // the edge instead of showing them. The colour
                                // and border change carry the hover on their
                                // own -- motion was never needed to say "this
                                // one".

                                Behavior on color       { ColorAnimation  { duration: 120; easing.type: Easing.OutCubic } }
                                Behavior on border.color{ ColorAnimation  { duration: 120; easing.type: Easing.OutCubic } }


                                HoverHandler {
                                    id: rowHov
                                    cursorShape: Qt.PointingHandCursor
                                }


                                // Red X at the top right: deletes exactly this
                                // notification. Sits above the content so it
                                // gets the click first.
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: 6
                                    anchors.topMargin: 6
                                    width: 20; height: 20
                                    radius: 10
                                    z: 10
                                    color: closeHov2.hovered ? nc.cRed : "transparent"
                                    border.width: closeHov2.hovered ? 0 : 1
                                    border.color: nc.cSurface1
                                    Behavior on color { ColorAnimation { duration: 90 } }

                                    HoverHandler { id: closeHov2 }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u00d7"
                                        color: closeHov2.hovered ? nc.cCrust : nc.cRed
                                        font.family: nc.uiFont
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: modelData.dismiss()
                                    }
                                }

                                Row {
                                    id: itemRow
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 11

                                    Rectangle {
                                        width: 38; height: 38
                                        radius: 11
                                        color: nc.cSurface0
                                        anchors.verticalCenter: parent.verticalCenter
                                        Image {
                                            id: listIcon
                                            anchors.fill: parent
                                            anchors.margins: 3
                                            source: nc.resolveIcon(modelData)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            // See Menus.qml.
                                            sourceSize.width: 96
                                            sourceSize.height: 96
                                            asynchronous: true
                                            // See the toast icon above -- an
                                            // appIcon the theme cannot resolve
                                            // must fall back, not show the
                                            // broken-image checkerboard.
                                            visible: source !== "" && status === Image.Ready
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: listIcon.source === "" || listIcon.status !== Image.Ready
                                            text: (modelData.appName || "?").charAt(0).toUpperCase()
                                            color: nc.cMauve
                                            font.family: nc.uiFont
                                            font.pixelSize: 16
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Column {
                                        width: parent.width - 38 - 11 - 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: modelData.summary || modelData.appName
                                            color: nc.cText
                                            font.family: nc.uiFont
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: modelData.body
                                            color: nc.cSubtext
                                            font.family: nc.uiFont
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            visible: text !== ""
                                        }
                                    }
                                }

                                // A single click opens whatever sent the
                                // notification; the red X deletes it.
                                //
                                // Used to be onDoubleClicked, left over from a
                                // design where a single click dismissed the
                                // card (so the first click of a double-click
                                // would have destroyed the delegate before the
                                // second arrived). That dismiss-on-click
                                // behaviour is gone -- the X button owns
                                // dismissal now -- but the double-click
                                // requirement stayed, so a normal single click
                                // (what every other notification centre uses)
                                // silently did nothing.
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: nc.activate(notifCard.modelData)
                                }
                            }
                        }
                    }
                }

                // DND at the bottom left, as in GNOME
                Row {
                    id: dndRow
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 10

                    Text {
                        text: Strings.t.dnd
                        color: nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 44; height: 24
                        radius: 12
                        color: nc.dnd ? nc.cMauve : nc.cSurface1
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 18; height: 18
                            radius: 9
                            color: nc.cText
                            y: 3
                            x: nc.dnd ? 23 : 3
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: nc.dnd = !nc.dnd
                        }
                    }
                }
            }

            // Trennlinie
            Rectangle {
                anchors.left: leftCol.right
                anchors.leftMargin: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                width: 1
                color: nc.cSurface0
            }

            // ---------------- right column: date and calendar --------------
            Item {
                id: rightCol
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 16
                anchors.left: leftCol.right
                anchors.leftMargin: 24

                Text {
                    id: dayName
                    text: clk.date.toLocaleDateString(Qt.locale(Strings.locale), "dddd")
                    color: nc.cSubtext
                    font.family: nc.uiFont
                    font.pixelSize: 13
                }
                Text {
                    id: dayFull
                    anchors.top: dayName.bottom
                    text: clk.date.toLocaleDateString(Qt.locale(Strings.locale), "d. MMMM yyyy")
                    color: nc.cText
                    font.family: nc.uiFont
                    font.pixelSize: 21
                    font.weight: Font.Bold
                }

                // Month header with paging
                Item {
                    id: monthHead
                    anchors.top: dayFull.bottom
                    anchors.topMargin: 16
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 26

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "‹"
                        color: prevMa.containsMouse ? nc.cMauve : nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 18
                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                CalendarData.shiftMonth(-1);
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: nc.viewDate.toLocaleDateString(Qt.locale(Strings.locale), "MMMM yyyy")
                        color: nc.cText
                        font.family: nc.uiFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            // Jumps back to today's month AND re-selects today,
                            // matching the desktop widget's month-label behaviour.
                            onClicked: {
                                CalendarData.goToday();
                                nc.selectedDay = CalendarData.todayKey();
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: nextMa.containsMouse ? nc.cMauve : nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 18
                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                CalendarData.shiftMonth(1);
                            }
                        }
                    }
                }

                // Weekday names (Monday first, as is usual in Austria)
                Row {
                    id: weekHead
                    anchors.top: monthHead.bottom
                    anchors.topMargin: 10
                    width: parent.width
                    Repeater {
                        model: Strings.t.weekdays
                        delegate: Text {
                            required property var modelData
                            width: weekHead.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: nc.cLavender
                            font.family: nc.uiFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                // Tagesraster
                Grid {
                    id: dayGrid
                    anchors.top: weekHead.bottom
                    anchors.topMargin: 6
                    width: parent.width
                    columns: 7
                    rowSpacing: 2

                    Repeater {
                        model: 42
                        delegate: Item {
                            id: dayCell
                            required property int index
                            width: dayGrid.width / 7
                            height: 30

                            // Montag-first: JS getDay() liefert 0=So
                            readonly property var firstOfMonth: new Date(nc.viewDate.getFullYear(), nc.viewDate.getMonth(), 1)
                            readonly property int offset: (firstOfMonth.getDay() + 6) % 7
                            readonly property var cellDate: new Date(nc.viewDate.getFullYear(), nc.viewDate.getMonth(), index - offset + 1)
                            readonly property string cellKey: CalendarData.dayKey(cellDate)
                            readonly property bool inMonth: cellDate.getMonth() === nc.viewDate.getMonth()
                            readonly property bool isToday:
                                cellDate.getDate() === clk.date.getDate() &&
                                cellDate.getMonth() === clk.date.getMonth() &&
                                cellDate.getFullYear() === clk.date.getFullYear()
                            readonly property bool picked: cellKey === nc.selectedDay
                            readonly property var dayEvents: CalendarData.eventsFor(cellKey)

                            // Selection ring -- otherwise there was no visible
                            // difference between "clicked" and "not clicked",
                            // which is half of why the calendar read as inert.
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                radius: 13
                                color: "transparent"
                                border.width: 1.5
                                border.color: nc.cLavender
                                opacity: (dayCell.picked && !dayCell.isToday) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 90 } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                radius: 13
                                color: nc.cSurface1
                                opacity: (dayHov.containsMouse && !dayCell.isToday) ? 0.6 : 0
                                Behavior on opacity { NumberAnimation { duration: 90 } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                radius: 13
                                color: dayCell.isToday ? nc.cMauve : "transparent"
                            }
                            Text {
                                id: dayNum
                                anchors.centerIn: parent
                                text: dayCell.cellDate.getDate()
                                color: dayCell.isToday ? nc.cCrust
                                     : (dayCell.inMonth ? nc.cText : nc.cSurface2)
                                font.family: nc.uiFont
                                font.pixelSize: 12
                                font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                            }

                            // Event dots -- the whole point of the exercise.
                            //
                            // This grid previously had no data behind it at
                            // all, so no appointment could ever show up here
                            // however long you waited. The events now come from
                            // the shared CalendarData singleton, which is the
                            // same fetch and the same cache the desktop widget
                            // reads, so the two can never disagree.
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: dayNum.bottom
                                anchors.topMargin: -3
                                spacing: 2
                                visible: dayCell.inMonth

                                Repeater {
                                    // At most three, otherwise a busy day pushes
                                    // the dots wider than the cell.
                                    model: Math.min(3, dayCell.dayEvents.length)
                                    delegate: Rectangle {
                                        required property int index
                                        width: 3; height: 3; radius: 1.5
                                        // Through dayCell's id, not a parent
                                        // chain: inside this nested Repeater's
                                        // delegate, an unqualified `isToday`
                                        // silently resolved to undefined (always
                                        // falsy), so every dot -- including on
                                        // today's own filled circle -- rendered
                                        // mauve instead of the crust colour that
                                        // would actually contrast there.
                                        color: dayCell.isToday ? nc.cCrust : nc.cMauve
                                    }
                                }
                            }

                            // Clicking a day only ever moved dots around a grid
                            // with nothing behind them to look at -- there was
                            // no MouseArea here at all before. Selecting a day
                            // now drives the event list below the grid.
                            MouseArea {
                                id: dayHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: nc.selectedDay = dayCell.cellKey
                            }
                        }
                    }
                }

                // ---------------- selected day's events ---------------------
                Rectangle {
                    id: calDivider
                    anchors.top: dayGrid.bottom
                    anchors.topMargin: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: nc.cSurface0
                }

                Text {
                    id: selDayLabel
                    anchors.top: calDivider.bottom
                    anchors.topMargin: 10
                    text: nc.selectedDayLabel()
                    color: nc.cSubtext
                    font.family: nc.uiFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                ListView {
                    id: evtList
                    anchors.top: selDayLabel.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    // Stop above the "Clear all" button rather than under it.
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 44
                    clip: true
                    spacing: 6
                    model: CalendarData.eventsFor(nc.selectedDay)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Row {
                        required property var modelData
                        width: evtList.width
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; height: 16; radius: 1.5
                            color: modelData.colour || nc.cMauve
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 46
                            text: modelData.allday ? "ganztg" : modelData.time
                            color: nc.cSubtext
                            font.family: nc.uiFont
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: evtList.width - 62
                            text: modelData.title
                            color: nc.cText
                            font.family: nc.uiFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    // A flat "wird geladen …" string looked identical whether
                    // hypr-calendar was one second in or hung, so there was no
                    // way to tell a slow fetch from a stuck one. Three dots
                    // pulsing in a travelling wave at least says "still alive".
                    Row {
                        anchors.top: parent.top
                        visible: evtList.count === 0 && CalendarData.loading
                        spacing: 5

                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: loadDot
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5; height: 5; radius: 2.5
                                color: nc.cMauve

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: CalendarData.loading
                                    PauseAnimation { duration: loadDot.index * 150 }
                                    NumberAnimation { from: 0.25; to: 1;    duration: 350; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 1;    to: 0.25; duration: 350; easing.type: Easing.InOutQuad }
                                    PauseAnimation { duration: (2 - loadDot.index) * 150 }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.top: parent.top
                        visible: evtList.count === 0 && !CalendarData.loading
                        text: Strings.t.noEvents
                        color: nc.cSurface2
                        font.family: nc.uiFont
                        font.pixelSize: 12
                    }
                }

                // "clear" at the bottom right, like GNOME's Clear
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: clearText.implicitWidth + 26
                    height: 32
                    radius: 12
                    color: clearArea.containsMouse ? nc.cRed : Qt.rgba(nc.cSurface0.r, nc.cSurface0.g, nc.cSurface0.b, 0.9)
                    border.width: 1
                    border.color: nc.cSurface1

                    Text {
                        id: clearText
                        anchors.centerIn: parent
                        text: Strings.t.clearAll
                        color: clearArea.containsMouse ? nc.cCrust : nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: nc.clearAll()
                    }
                }
            }
        }
    }
}
