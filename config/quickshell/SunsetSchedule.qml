//  Editor for the colour temperature schedule.
//
//  Reads and writes ~/.config/hypr/sunset-schedule.json, which
//  hypr-sunset-scheduler applies. hyprsunset itself has no weekday support --
//  its format is one flat profile list for every day alike -- which is why the
//  schedule lives in JSON beside it rather than in hyprsunset.conf.
//
//  DELIBERATELY ITS OWN FILE, not an addition to QuickSettings.qml. An earlier
//  attempt to insert even a simple toggle into that file by text replacement
//  broke its Row/Rectangle nesting and stopped the whole config loading. A new
//  component cannot do that to anything that already works.
//
//  Layout choice: a 7x24 grid would be 168 cells, unclickable on this panel.
//  Instead: pick a day, edit its switch points as a short list, and copy that
//  day to all others. That covers the real case -- weekday differs from weekend
//  -- without 168 targets.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: sched

    property bool panelOpen: false
    readonly property int barHeight: 40

    readonly property var dayKeys:   ["mon","tue","wed","thu","fri","sat","sun"]
    readonly property var dayLabels: ["Mo","Di","Mi","Do","Fr","Sa","So"]
    property int selectedDay: 0

    // The whole document, kept as a JS object. Written back in one piece so a
    // partial edit can never leave the file half-valid.
    property var doc: ({ enabled: true, days: {} })
    property bool loaded: false

    // Presets rather than a free number field: these are the values that
    // actually mean something, and typing 4137 K helps nobody.
    readonly property var steps: [
        { k: 6500, label: "Tageslicht" },
        { k: 5500, label: "Neutral" },
        { k: 4500, label: "Warm" },
        { k: 3800, label: "Wärmer" },
        { k: 3200, label: "Sehr warm" }
    ]

    IpcHandler {
        target: "sunset"
        function toggle(): void { sched.panelOpen = !sched.panelOpen; }
        function show(): void   { sched.panelOpen = true; }
        function hide(): void   { sched.panelOpen = false; }
    }

    FileView {
        id: file
        path: "/home/woofi/.config/hypr/sunset-schedule.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: sched.load()

    function load() {
        try {
            const t = file.text();
            if (t.length > 0) {
                const d = JSON.parse(t);
                if (d && d.days) { sched.doc = d; sched.loaded = true; return; }
            }
        } catch (e) { /* fall through to the default below */ }
        // A missing or corrupt file must not leave an empty editor that then
        // overwrites a good one with nothing.
        sched.doc = { enabled: true, days: {
            mon: [{h:6,temp:6500},{h:20,temp:4500}], tue: [{h:6,temp:6500},{h:20,temp:4500}],
            wed: [{h:6,temp:6500},{h:20,temp:4500}], thu: [{h:6,temp:6500},{h:20,temp:4500}],
            fri: [{h:6,temp:6500},{h:21,temp:4500}], sat: [{h:8,temp:6500},{h:21,temp:4500}],
            sun: [{h:8,temp:6500},{h:20,temp:4500}] } };
        sched.loaded = true;
    }

    function entries() {
        const k = sched.dayKeys[sched.selectedDay];
        const e = sched.doc.days ? sched.doc.days[k] : undefined;
        return e === undefined ? [] : e.slice().sort((a,b) => a.h - b.h);
    }

    function save() {
        file.setText(JSON.stringify(sched.doc, null, 2));
        // The scheduler reads the file on each run; kicking it makes the change
        // visible now instead of at the next timer tick.
        Quickshell.execDetached(["systemctl","--user","start","hypr-sunset-scheduler"]);
    }

    function setEntry(i, field, value) {
        const k = sched.dayKeys[sched.selectedDay];
        const list = sched.doc.days[k].slice().sort((a,b) => a.h - b.h);
        if (field === "h")    list[i].h = Math.max(0, Math.min(23, value));
        if (field === "temp") list[i].temp = value;
        const d = JSON.parse(JSON.stringify(sched.doc));
        d.days[k] = list;
        sched.doc = d;
        sched.save();
    }

    function addEntry() {
        const k = sched.dayKeys[sched.selectedDay];
        const d = JSON.parse(JSON.stringify(sched.doc));
        const list = d.days[k] || [];
        // New point one hour after the last, so it lands somewhere sensible
        // rather than colliding with an existing entry.
        const last = list.length ? Math.max.apply(null, list.map(e => e.h)) : 6;
        list.push({ h: Math.min(23, last + 1), temp: 4500 });
        d.days[k] = list;
        sched.doc = d;
        sched.save();
    }

    function removeEntry(i) {
        const k = sched.dayKeys[sched.selectedDay];
        const d = JSON.parse(JSON.stringify(sched.doc));
        const list = d.days[k].slice().sort((a,b) => a.h - b.h);
        list.splice(i, 1);
        d.days[k] = list;
        sched.doc = d;
        sched.save();
    }

    function copyToAll() {
        const k = sched.dayKeys[sched.selectedDay];
        const d = JSON.parse(JSON.stringify(sched.doc));
        for (let i = 0; i < sched.dayKeys.length; i++)
            d.days[sched.dayKeys[i]] = JSON.parse(JSON.stringify(d.days[k]));
        sched.doc = d;
        sched.save();
    }

    function setEnabled(v) {
        const d = JSON.parse(JSON.stringify(sched.doc));
        d.enabled = v;
        sched.doc = d;
        sched.save();
    }

    function tempLabel(k) {
        for (let i = 0; i < sched.steps.length; i++)
            if (sched.steps[i].k === k) return sched.steps[i].label;
        return k + " K";
    }
    function tempColour(k) {
        // Warmer values drift towards the peach end, so the list reads at a
        // glance without needing the number.
        if (k >= 6000) return Theme.sapphire;
        if (k >= 5000) return Theme.teal;
        if (k >= 4200) return Theme.yellow;
        if (k >= 3500) return Theme.peach;
        return Theme.maroon;
    }
    function nextTemp(k) {
        for (let i = 0; i < sched.steps.length; i++)
            if (sched.steps[i].k === k)
                return sched.steps[(i + 1) % sched.steps.length].k;
        return 4500;
    }

    // =======================================================================
    PanelWindow {
        id: win
        visible: sched.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-sunset"
        WlrLayershell.keyboardFocus: sched.panelOpen ? WlrKeyboardFocus.Exclusive
                                                     : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }

        MouseArea { anchors.fill: parent; onClicked: sched.panelOpen = false }

        Item {
            anchors.fill: parent
            focus: sched.panelOpen
            Keys.onEscapePressed: sched.panelOpen = false
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: sched.panelOpen ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card
            readonly property int animMs: 190

            opacity: sched.panelOpen ? 1 : 0
            scale: sched.panelOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            anchors.horizontalCenter: parent.horizontalCenter
            y: sched.barHeight + (sched.panelOpen ? 6 : -6)
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            width: 460
            height: Math.min(parent.height - sched.barHeight - 40, body.implicitHeight + 26)
            radius: 20
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.98)
            border.width: 2
            border.color: Theme.surface1

            MouseArea { anchors.fill: parent }

            Column {
                id: body
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 10

                Text {
                    text: "NACHTLICHT"
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                // ---- master switch ----
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 14
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Zeitplan aktiv"
                        color: Theme.text
                        font.family: Theme.uiFont
                        font.pixelSize: 13
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 24; radius: 12
                        color: sched.doc.enabled ? Theme.mauve : Theme.surface2
                        Behavior on color { ColorAnimation { duration: 130 } }
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            color: Theme.crust
                            anchors.verticalCenter: parent.verticalCenter
                            x: sched.doc.enabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sched.setEnabled(!sched.doc.enabled)
                    }
                }

                // ---- day picker ----
                Row {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            required property int index
                            width: (body.width - 24) / 7
                            height: 34
                            radius: 10
                            color: index === sched.selectedDay ? Theme.mauve
                                 : (dayHover.hovered ? Theme.surface1 : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9))
                            Behavior on color { ColorAnimation { duration: 100 } }
                            HoverHandler { id: dayHover }
                            Text {
                                anchors.centerIn: parent
                                text: sched.dayLabels[parent.index]
                                color: parent.index === sched.selectedDay ? Theme.crust : Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                font.weight: parent.index === sched.selectedDay ? Font.Bold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sched.selectedDay = parent.index
                            }
                        }
                    }
                }

                // ---- switch points for the selected day ----
                Column {
                    width: parent.width
                    spacing: 5

                    Repeater {
                        model: sched.entries()
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            radius: 12
                            color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                            // hour, adjustable with - / +
                            Text {
                                id: hourText
                                anchors.left: parent.left
                                anchors.leftMargin: 44
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.h < 10 ? "0" : "") + modelData.h + ":00"
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: "−"
                                color: Theme.subtext
                                font.family: Theme.uiFont
                                font.pixelSize: 17
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sched.setEntry(index, "h", modelData.h - 1)
                                }
                            }
                            Text {
                                anchors.left: hourText.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "+"
                                color: Theme.subtext
                                font.family: Theme.uiFont
                                font.pixelSize: 17
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sched.setEntry(index, "h", modelData.h + 1)
                                }
                            }

                            // temperature: click cycles through the presets
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 44
                                anchors.verticalCenter: parent.verticalCenter
                                width: 132; height: 30; radius: 9
                                color: Qt.rgba(sched.tempColour(modelData.temp).r,
                                               sched.tempColour(modelData.temp).g,
                                               sched.tempColour(modelData.temp).b, 0.22)
                                border.width: 1
                                border.color: sched.tempColour(modelData.temp)
                                Text {
                                    anchors.centerIn: parent
                                    text: sched.tempLabel(modelData.temp)
                                    color: sched.tempColour(modelData.temp)
                                    font.family: Theme.uiFont
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sched.setEntry(index, "temp", sched.nextTemp(modelData.temp))
                                }
                            }

                            // remove
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 15
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×"
                                color: Theme.red
                                font.family: Theme.uiFont
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sched.removeEntry(index)
                                }
                            }
                        }
                    }
                }

                // ---- actions ----
                Row {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 36
                        radius: 11
                        color: addHover.hovered ? Theme.surface1 : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: addHover }
                        Text {
                            anchors.centerIn: parent
                            text: "+ Umschaltpunkt"
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sched.addEntry()
                        }
                    }
                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 36
                        radius: 11
                        color: copyHover.hovered ? Theme.surface1 : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: copyHover }
                        Text {
                            anchors.centerIn: parent
                            text: "auf alle Tage"
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sched.copyToAll()
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Änderungen wirken sofort. SUPER+SHIFT+N schaltet manuell um; "
                        + "der Zeitplan übernimmt beim nächsten Umschaltpunkt wieder."
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    leftPadding: 4
                }
            }
        }
    }
}
