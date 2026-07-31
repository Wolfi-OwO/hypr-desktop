//  Brightness, volume and Bluetooth as panels of their own.
//
//  The bar icons used to open foreign programs (pavucontrol,
//  blueman-manager) -- a window instead of a menu. Here they are sliders and a
//  device list directly under the icon that opened them, in the same style as
//  every other panel, and closing on a click beside them.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: ctl

    property string active: ""        // "brightness" | "volume" | "bluetooth" | ""
    readonly property int barHeight: 40

    property int brightness: 50
    property int volume: 50
    property bool muted: false
    property bool btPowered: false
    property var btDevices: []
    property bool btBusy: false

    // The function names must NOT match the property names: brightness and
    // volume both exist as properties, which made "volume" wrongly open the
    // brightness panel.
    IpcHandler {
        target: "controls"
        function showBrightness(): void { ctl.openPanel("brightness"); }
        function showVolume(): void     { ctl.openPanel("volume"); }
        function showBluetooth(): void  { ctl.openPanel("bluetooth"); }
        function hide(): void           { ctl.active = ""; }
    }

    function openPanel(which) {
        if (ctl.active === which) { ctl.active = ""; return; }
        ctl.active = which;
        readBrightness.running = true;
        readVolume.running = true;
        if (which === "bluetooth") { ctl.btBusy = true; readBt.running = true; }
    }

    Process { id: runner }
    function run(cmd) { runner.command = ["sh", "-c", cmd]; runner.running = true; }

    // ---- Reading ----------------------------------------------------------
    Process {
        id: readBrightness
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text.trim());
                if (!isNaN(v)) ctl.brightness = v;
            }
        }
    }
    Process {
        id: readVolume
        command: ["sh", "-c",
                  "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                ctl.muted = t.indexOf("MUTED") !== -1;
                const m = t.match(/([0-9]+\.[0-9]+)/);
                if (m) ctl.volume = Math.round(parseFloat(m[1]) * 100);
            }
        }
    }
    Process {
        id: readBt
        command: ["sh", "-c",
            "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off; " +
            "echo '---'; " +
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "  st=$(bluetoothctl info \"$mac\" 2>/dev/null | grep -c 'Connected: yes'); " +
            "  printf '%s\\t%s\\t%s\\n' \"$mac\" \"$name\" \"$st\"; done | head -8"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("---");
                ctl.btPowered = (parts[0] || "").trim() === "on";
                const rows = (parts[1] || "").trim().split("\n").filter(l => l.indexOf("\t") > 0);
                ctl.btDevices = rows.map(l => {
                    const c = l.split("\t");
                    return { mac: c[0], name: c[1], connected: c[2] === "1" };
                });
                ctl.btBusy = false;
            }
        }
    }

    Timer {
        interval: 4000
        running: ctl.active !== ""
        repeat: true
        onTriggered: { readBrightness.running = true; readVolume.running = true; }
    }

    // =======================================================================
    PanelWindow {
        id: ctlWin

        // Bound to the card's opacity, not to `active` directly, so the layer
        // surface survives the closing fade. See Menus.qml for the full
        // reasoning — without this the panel vanished in a single frame.
        visible: ctl.active !== "" || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-controls"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: ctl.active = ""
        }
        TapHandler { onTapped: ctl.active = "" }

        // Escape closes as well, not just the click beside it (#50).
        Item {
            anchors.fill: parent
            focus: ctl.active !== ""
            Keys.onEscapePressed: ctl.active = ""
        }


        // Scrim, identical to the one behind the applications menu.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: ctl.active !== "" ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card

            // Same transition as every other panel — see Menus.qml.
            readonly property int animMs: 190

            opacity: ctl.active !== "" ? 1 : 0
            scale: ctl.active !== "" ? 1 : 0.94
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            y: ctl.barHeight + (ctl.active !== "" ? 4 : -6)
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            // right-aligned; these are all icons from the right half of the bar
            x: parent.width - width - 6
            width: 330
            height: body.implicitHeight + 26
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
                    text: ctl.active === "brightness" ? "HELLIGKEIT"
                        : ctl.active === "volume" ? "LAUTSTÄRKE" : "BLUETOOTH"
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                // ---------------- brightness ----------------
                Rectangle {
                    visible: ctl.active === "brightness"
                    width: parent.width
                    height: 64
                    radius: 14
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        spacing: 9

                        Row {
                            width: parent.width
                            Text {
                                text: Theme.ico(0xf00de)
                                color: Theme.yellow
                                font.family: Theme.uiFont
                                font.pixelSize: 16
                            }
                            Item { width: parent.width - 60; height: 1 }
                            Text {
                                text: ctl.brightness + "%"
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                        }

                        Slider {
                            width: parent.width
                            value: ctl.brightness
                            accent: Theme.yellow
                            onMoved: function (v) {
                                ctl.brightness = v;
                                ctl.run("brightnessctl set " + Math.max(1, v) + "%");
                            }
                        }
                    }
                }

                // ---------------- volume ----------------
                Rectangle {
                    visible: ctl.active === "volume"
                    width: parent.width
                    height: 64
                    radius: 14
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        spacing: 9

                        Row {
                            width: parent.width
                            Text {
                                text: ctl.muted ? Theme.ico(0xf0581)
                                    : (ctl.volume >= 50 ? Theme.ico(0xf057e) : Theme.ico(0xf0580))
                                color: ctl.muted ? Theme.surface2 : Theme.sapphire
                                font.family: Theme.uiFont
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: {
                                        ctl.run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
                                        ctl.muted = !ctl.muted;
                                    }
                                }
                            }
                            Item { width: parent.width - 60; height: 1 }
                            Text {
                                text: ctl.muted ? "stumm" : ctl.volume + "%"
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                        }

                        Slider {
                            width: parent.width
                            value: ctl.volume
                            accent: ctl.muted ? Theme.surface2 : Theme.sapphire
                            onMoved: function (v) {
                                ctl.volume = v;
                                ctl.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + (v / 100).toFixed(2));
                            }
                        }
                    }
                }

                // ---------------- Bluetooth ----------------
                Column {
                    visible: ctl.active === "bluetooth"
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: 14
                        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.ico(ctl.btPowered ? 0xf00af : 0xf00b2)
                            color: ctl.btPowered ? Theme.blue : Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 44
                            anchors.verticalCenter: parent.verticalCenter
                            text: ctl.btPowered ? "Eingeschaltet" : "Ausgeschaltet"
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 13
                        }

                        // toggle
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 24
                            radius: 12
                            color: ctl.btPowered ? Theme.mauve : Theme.surface1
                            Behavior on color { ColorAnimation { duration: 110 } }

                            Rectangle {
                                width: 18; height: 18; radius: 9
                                color: Theme.text
                                y: 3
                                x: ctl.btPowered ? 23 : 3
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    ctl.run("bluetoothctl power " + (ctl.btPowered ? "off" : "on"));
                                    ctl.btPowered = !ctl.btPowered;
                                }
                            }
                        }
                    }

                    Text {
                        visible: ctl.btBusy
                        text: "Suche Geräte…"
                        color: Theme.subtext
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        padding: 8
                    }

                    Text {
                        visible: !ctl.btBusy && ctl.btDevices.length === 0 && ctl.btPowered
                        text: "Keine gekoppelten Geräte"
                        color: Theme.surface2
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        padding: 8
                    }

                    Repeater {
                        model: ctl.active === "bluetooth" ? ctl.btDevices : []
                        delegate: Rectangle {
                            required property var modelData
                            width: body.width
                            height: 36
                            radius: 11
                            color: bh.hovered ? Theme.surface1 : "transparent"
                            Behavior on color { ColorAnimation { duration: 90 } }
                            HoverHandler { id: bh }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.ico(modelData.connected ? 0xf00af : 0xf00b1)
                                color: modelData.connected ? Theme.green : Theme.subtext
                                font.family: Theme.uiFont
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: Theme.text
                                font.family: Theme.uiFont
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    ctl.run("bluetoothctl " +
                                            (modelData.connected ? "disconnect " : "connect ") +
                                            modelData.mac);
                                    ctl.active = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A slim slider of our own -- Qt Quick Controls would otherwise need
    // separate styling that does not match this palette.
    component Slider: Item {
        property int value: 0
        property color accent: Theme.mauve
        signal moved(int v)

        height: 18

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Theme.surface1

            Rectangle {
                width: Math.max(0, Math.min(1, parent.parent.value / 100)) * parent.width
                height: parent.height
                radius: 3
                color: parent.parent.accent
            }
        }

        Rectangle {
            id: knob
            width: 16; height: 16; radius: 8
            color: parent.accent
            border.width: 2
            border.color: Theme.crust
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(1, parent.value / 100)) * (parent.width - width)
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onPressed: function (m) { parent.apply(m.x); }
            onPositionChanged: function (m) { if (pressed) parent.apply(m.x); }
        }

        function apply(px) {
            const v = Math.round(Math.max(0, Math.min(1, px / width)) * 100);
            moved(v);
        }
    }
}
