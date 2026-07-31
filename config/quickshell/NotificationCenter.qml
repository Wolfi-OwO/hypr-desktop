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
    property bool dnd: false

    // Calendar navigation
    property date viewDate: new Date()

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
                    required property var modelData
                    width: 440
                    height: Math.max(74, toastBody.implicitHeight + 26)
                    radius: 18
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
                                anchors.fill: parent
                                anchors.margins: 3
                                source: modelData.image !== "" ? modelData.image
                                      : (modelData.appIcon !== "" ? "image://icon/" + modelData.appIcon : "")
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                visible: source !== ""
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: modelData.image === "" && modelData.appIcon === ""
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

                    // Clicking the toast opens the centre -- the same one the
                    // bell button opens. Dismissing is what the red X at the
                    // top right is for.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: nc.panelOpen = true
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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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
                    text: "Benachrichtigungen"
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
                            text: "Keine Benachrichtigungen"
                            color: nc.cSurface2
                            font.family: nc.uiFont
                            font.pixelSize: 13
                        }

                        Repeater {
                            model: ScriptModel {
                                values: server.trackedNotifications.values.slice().reverse()
                            }
                            delegate: Rectangle {
                                required property var modelData
                                width: notifCol.width
                                height: Math.max(62, itemRow.implicitHeight + 20)
                                radius: 14
                                color: Qt.rgba(nc.cBase.r, nc.cBase.g, nc.cBase.b, 0.9)
                                border.width: 1
                                border.color: nc.cSurface0


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
                                            anchors.fill: parent
                                            anchors.margins: 3
                                            source: modelData.image !== "" ? modelData.image
                                                  : (modelData.appIcon !== "" ? "image://icon/" + modelData.appIcon : "")
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            visible: source !== ""
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: modelData.image === "" && modelData.appIcon === ""
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

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: modelData.dismiss()
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
                        text: "Nicht stören"
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
                    text: clk.date.toLocaleDateString(Qt.locale("de_DE"), "dddd")
                    color: nc.cSubtext
                    font.family: nc.uiFont
                    font.pixelSize: 13
                }
                Text {
                    id: dayFull
                    anchors.top: dayName.bottom
                    text: clk.date.toLocaleDateString(Qt.locale("de_DE"), "d. MMMM yyyy")
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
                        color: nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                const d = new Date(nc.viewDate);
                                d.setMonth(d.getMonth() - 1);
                                nc.viewDate = d;
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: nc.viewDate.toLocaleDateString(Qt.locale("de_DE"), "MMMM yyyy")
                        color: nc.cText
                        font.family: nc.uiFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: nc.cSubtext
                        font.family: nc.uiFont
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                const d = new Date(nc.viewDate);
                                d.setMonth(d.getMonth() + 1);
                                nc.viewDate = d;
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
                        model: ["Mo","Di","Mi","Do","Fr","Sa","So"]
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
                            required property int index
                            width: dayGrid.width / 7
                            height: 30

                            // Montag-first: JS getDay() liefert 0=So
                            readonly property var firstOfMonth: new Date(nc.viewDate.getFullYear(), nc.viewDate.getMonth(), 1)
                            readonly property int offset: (firstOfMonth.getDay() + 6) % 7
                            readonly property var cellDate: new Date(nc.viewDate.getFullYear(), nc.viewDate.getMonth(), index - offset + 1)
                            readonly property bool inMonth: cellDate.getMonth() === nc.viewDate.getMonth()
                            readonly property bool isToday:
                                cellDate.getDate() === clk.date.getDate() &&
                                cellDate.getMonth() === clk.date.getMonth() &&
                                cellDate.getFullYear() === clk.date.getFullYear()

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                radius: 13
                                color: parent.isToday ? nc.cMauve : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: parent.cellDate.getDate()
                                color: parent.isToday ? nc.cCrust
                                     : (parent.inMonth ? nc.cText : nc.cSurface2)
                                font.family: nc.uiFont
                                font.pixelSize: 12
                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                            }
                        }
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
                        text: "Alle löschen"
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
