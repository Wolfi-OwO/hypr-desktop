//  Clipboard history as a shell panel.
//
//  Replaces the last rofi dependency on this desktop: SUPER+V used to run
//  `cliphist list | rofi -dmenu | cliphist decode | wl-copy`. rofi is the wrong
//  tool here for the same reasons it was dropped everywhere else -- under
//  Wayland it never receives clicks outside its own surface, it does not appear
//  in `hyprctl layers` so its position cannot be pinned, and its theme carries
//  fixed colours that ignore light/dark.
//
//  cliphist stays as the backend. It is already running as two wl-paste
//  watchers from the autostart and holds the history; only the picker changes.
//
//  ITS OWN FILE, like SunsetSchedule.qml. Inserting into an existing panel by
//  text replacement broke QuickSettings.qml earlier tonight.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: cb

    property bool panelOpen: false
    readonly property int barHeight: 40

    property var entries: []
    property string query: ""
    property int selIndex: 0

    IpcHandler {
        target: "clipboard"
        function toggle(): void { cb.panelOpen ? cb.close() : cb.open(); }
        function hide(): void   { cb.close(); }
    }

    function open() {
        cb.query = "";
        cb.selIndex = 0;
        cb.panelOpen = true;
        load.running = true;      // always fresh: the history changes constantly
    }
    function close() { cb.panelOpen = false; }

    // cliphist's own format is "<id>\t<preview>". The id is what `decode` needs;
    // the preview is what a human recognises. Both are kept.
    Process {
        id: load
        running: false
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -80"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.split("\n").filter(l => l.indexOf("\t") > 0);
                cb.entries = rows.map(l => {
                    const i = l.indexOf("\t");
                    return { id: l.substring(0, i), text: l.substring(i + 1) };
                });
                cb.selIndex = 0;
            }
        }
    }

    readonly property var filtered: {
        const q = cb.query.toLowerCase();
        if (q.length === 0) return cb.entries;
        return cb.entries.filter(e => e.text.toLowerCase().indexOf(q) !== -1);
    }

    function paste(entry) {
        if (!entry) return;
        // decode by id, not by the preview text: the preview is truncated and
        // binary entries have no usable text at all.
        //
        // wl-copy detaches and holds the selection as its own process, which is
        // mandatory under Wayland -- the clipboard belongs to a living process,
        // so copying from something that then exits leaves it empty.
        Quickshell.execDetached(["sh", "-c",
            "printf '%s\\t' " + JSON.stringify(entry.id)
            + " | cliphist decode | wl-copy"]);
        cb.close();
    }

    function wipe() {
        Quickshell.execDetached(["sh", "-c", "cliphist wipe"]);
        cb.entries = [];
        cb.close();
    }

    function move(d) {
        const n = cb.filtered.length;
        if (n === 0) return;
        cb.selIndex = Math.max(0, Math.min(n - 1, cb.selIndex + d));
    }

    // cliphist marks non-text entries as "[[ binary data ... ]]". Showing that
    // raw is noise; a short label plus the size is what identifies them.
    function isBinary(t) { return t.indexOf("[[ binary data") === 0; }
    function label(t) {
        if (!cb.isBinary(t)) return t;
        const m = t.match(/binary data (\S+ \S+) (\S+) (\S+)/);
        return m ? ("Bild  " + m[3] + "  (" + m[1] + ")") : "Bild";
    }

    // =======================================================================
    PanelWindow {
        id: win
        visible: cb.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-clipboard"
        // Exclusive so the search field can be typed into at once and Escape
        // works -- see the long note in Menus.qml.
        WlrLayershell.keyboardFocus: cb.panelOpen ? WlrKeyboardFocus.Exclusive
                                                    : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }

        MouseArea { anchors.fill: parent; onClicked: cb.close() }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: cb.panelOpen ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card
            readonly property int animMs: 190

            opacity: cb.panelOpen ? 1 : 0
            scale: cb.panelOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            anchors.horizontalCenter: parent.horizontalCenter
            y: cb.barHeight + (cb.panelOpen ? 6 : -6)
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            width: 560
            height: Math.min(parent.height - cb.barHeight - 40, body.implicitHeight + 26)
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
                    text: "ZWISCHENABLAGE"
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                // ---- search ----
                Rectangle {
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
                            clip: true
                            focus: cb.panelOpen

                            // Deferred: the surface does not exist yet when
                            // panelOpen flips, so an immediate claim is made
                            // against a window with no keyboard to give.
                            onVisibleChanged: if (visible) {
                                search.text = "";
                                Qt.callLater(search.forceActiveFocus);
                            }
                            onTextChanged: { cb.query = search.text; cb.selIndex = 0; }

                            Keys.onEscapePressed: cb.close()
                            Keys.onUpPressed:   cb.move(-1)
                            Keys.onDownPressed: cb.move(1)
                            onAccepted: cb.paste(cb.filtered[cb.selIndex])

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

                // ---- history ----
                Flickable {
                    width: parent.width
                    height: Math.min(430, listCol.implicitHeight)
                    contentHeight: listCol.implicitHeight
                    clip: true

                    Column {
                        id: listCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: cb.filtered.slice(0, 60)
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: listCol.width
                                height: 34
                                radius: 11
                                color: (index === cb.selIndex || rowHov.hovered)
                                       ? Theme.surface1 : "transparent"
                                Behavior on color { ColorAnimation { duration: 90 } }

                                HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Theme.ico(cb.isBinary(modelData.text) ? 0xf021f : 0xf0219)
                                    color: cb.isBinary(modelData.text) ? Theme.peach : Theme.surface2
                                    font.family: Theme.uiFont
                                    font.pixelSize: 13
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 36
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cb.label(modelData.text)
                                    color: Theme.text
                                    font.family: Theme.uiFont
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: cb.paste(modelData)
                                }
                            }
                        }

                        Text {
                            visible: cb.filtered.length === 0
                            text: cb.entries.length === 0
                                  ? "Verlauf ist leer"
                                  : "Nichts gefunden"
                            color: Theme.subtext
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            padding: 10
                        }
                    }
                }

                // ---- wipe ----
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 11
                    color: wipeHov.hovered ? Theme.red
                                           : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    HoverHandler { id: wipeHov }
                    Text {
                        anchors.centerIn: parent
                        text: "Verlauf löschen"
                        color: wipeHov.hovered ? Theme.crust : Theme.subtext
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cb.wipe()
                    }
                }
            }
        }
    }
}
