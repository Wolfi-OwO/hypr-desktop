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

    // Horizontal centre of the bar icon that opened this panel, in bar
    // coordinates. -1 falls back to the right edge, which is where all three
    // panels used to be pinned regardless of which icon was clicked.
    property real anchorX: -1
    readonly property int barHeight: 40

    // Resource figures behind the "system" panel — the one the download, RAM
    // and temperature readings in the bar open. They used to open Quick
    // Settings, which shows battery, power mode and shutdown: nothing to do
    // with what was clicked.
    property int    sysCpu: 0
    property string sysMem: "—"
    property int    sysTemp: 0
    property string sysDown: "0 B/s"
    property string sysUptime: "—"

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
        // The bare forms stay for keybindings and manual `qs ipc call`, where
        // there is no trigger to anchor to; the *At forms take the icon centre.
        function showBrightness(): void { ctl.openPanel("brightness"); }
        function showVolume(): void     { ctl.openPanel("volume"); }
        function showBluetooth(): void  { ctl.openPanel("bluetooth"); }
        function brightnessAt(x: real): void { ctl.openPanel("brightness", x); }
        function volumeAt(x: real): void     { ctl.openPanel("volume", x); }
        function bluetoothAt(x: real): void  { ctl.openPanel("bluetooth", x); }
        function showSystem(): void     { ctl.openPanel("system"); }
        function systemAt(x: real): void     { ctl.openPanel("system", x); }
        function hide(): void           { ctl.active = ""; }
    }

    function openPanel(which, centreX) {
        ctl.anchorX = (centreX === undefined || centreX === null) ? -1 : centreX;
        if (ctl.active === which) { ctl.active = ""; return; }
        ctl.active = which;
        // No reader kick for volume or brightness: both arrive on the bus and
        // are already current before the panel opens. Bluetooth still needs one
        // -- the device list is not on the bus, only the power state is.
        if (which === "bluetooth") { ctl.btBusy = true; readBt.running = true; }
    }

    // Detached: see the note in Menus.qml. A reload must not kill what the
    // shell started.
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    // ---- Reading ----------------------------------------------------------
    //
    // Volume and brightness come off the event bus, not from re-running
    // `wpctl` and `brightnessctl` on a timer.
    //
    // They used to be read once when the panel opened and then again every 4 s.
    // So pressing a volume or brightness key while the panel was open moved the
    // slider anywhere up to four seconds later -- the value was already correct
    // in the bar, because the bar was on the bus, and only this panel lagged.
    //
    // hypr-eventd publishes both from their real event sources: PipeWire's
    // `pactl subscribe` for audio, and poll() on the backlight's
    // actual_brightness for brightness. Measured end to end at ~24 ms and ~5 ms.
    // Values arrive on the shared Bus singleton -- one subscription for the
    // whole shell instead of one per file. See Bus.qml.
    Connections {
        target: Bus
        function onMessage(topic, d) {
            // Each topic carries only its own keys; an absent field means
            // unchanged, not empty.
            //
            // While a slider is being dragged its own value wins: otherwise the
            // reading still in flight from the previous drag position snaps the
            // handle backwards under the finger.
            if (d.vol !== undefined && !ctl.volumeDragging)         ctl.volume = d.vol;
            if (d.muted !== undefined)                              ctl.muted = d.muted;
            if (d.bright !== undefined && !ctl.brightnessDragging)  ctl.brightness = d.bright;
            if (d.bt !== undefined)                                 ctl.btPowered = d.bt === "on";
            // Resource figures for the system panel.
            if (d.cpu !== undefined)    ctl.sysCpu = d.cpu;
            if (d.mem !== undefined)    ctl.sysMem = d.mem;
            if (d.temp !== undefined)   ctl.sysTemp = d.temp;
            if (d.down !== undefined)   ctl.sysDown = d.down;
            if (d.uptime !== undefined) ctl.sysUptime = d.uptime;
        }
    }


    // Set while a slider handle is held, so incoming bus updates do not fight
    // the drag. See the binding above.
    property bool volumeDragging: false
    property bool brightnessDragging: false

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

    // Bluetooth device list only. Volume and brightness are on the bus and need
    // no timer at all; the device list has no event source here, so it is
    // refreshed while its panel is open and not otherwise.
    Timer {
        interval: 4000
        running: ctl.active === "bluetooth"
        repeat: true
        onTriggered: readBt.running = true
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
        // Exclusive while open, NOT OnDemand.
        //
        // OnDemand hands the keyboard over when THIS surface is clicked. These
        // panels are opened by clicking a bar icon, so the click lands on the
        // bar's surface and this one never receives the keyboard at all. The
        // Keys.onEscapePressed below has been here the whole time and could
        // never fire, which is why Escape did not close anything.
        //
        // Exclusive takes the keyboard as soon as the panel appears. The cost
        // is that Hyprland binds do not fire while a panel is open, so the same
        // keybind cannot toggle it shut -- Escape and a click outside are the
        // close paths.
        WlrLayershell.keyboardFocus: ctl.active !== "" ? WlrKeyboardFocus.Exclusive
                                                       : WlrKeyboardFocus.None
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
            // Scale out of the corner nearest the icon that opened it.
            transformOrigin: ctl.anchorX < 0
                             ? Item.TopRight
                             : (ctl.anchorX > ctlWin.width / 2 ? Item.TopRight : Item.TopLeft)
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            y: ctl.barHeight + (ctl.active !== "" ? 4 : -6)
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            // right-aligned; these are all icons from the right half of the bar
            // Centred under the icon, clamped to the screen.
            x: ctl.anchorX < 0
               ? parent.width - width - 6
               : Math.max(6, Math.min(parent.width - width - 6, ctl.anchorX - width / 2))
            Behavior on x { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
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
                        : ctl.active === "volume" ? "LAUTSTÄRKE"
                        : ctl.active === "system" ? "SYSTEM" : "BLUETOOTH"
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
                            onDraggingChanged: ctl.brightnessDragging = dragging
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
                            onDraggingChanged: ctl.volumeDragging = dragging
                            onMoved: function (v) {
                                ctl.volume = v;
                                ctl.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + (v / 100).toFixed(2));
                            }
                        }
                    }
                }

                // ---------------- System resources ----------------
                //
                // What the download, memory and temperature readings in the bar
                // now open. Same figures they show, from the same bus topics,
                // so the panel can never disagree with the bar that opened it.
                Column {
                    visible: ctl.active === "system"
                    width: parent.width
                    spacing: 6

                    component Metric: Rectangle {
                        property string label: ""
                        property string value: ""
                        property int    icon: 0
                        property color  accent: Theme.text
                        width: parent.width
                        height: 42
                        radius: 12
                        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.ico(parent.icon)
                            color: parent.accent
                            font.family: Theme.uiFont
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.label
                            color: Theme.subtext
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.value
                            color: parent.accent
                            font.family: Theme.uiFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }

                    Metric {
                        label: "Download"; icon: 0xf01da
                        value: ctl.sysDown; accent: Theme.maroon
                    }
                    Metric {
                        label: "Arbeitsspeicher"; icon: 0xf035b
                        value: ctl.sysMem + " GB"; accent: Theme.text
                    }
                    Metric {
                        label: "Prozessor"; icon: 0xf0ee0
                        value: ctl.sysCpu + " %"
                        // Same thresholds as the bar's temperature colouring, so
                        // "warm" means the same thing in both places.
                        accent: ctl.sysCpu >= 85 ? Theme.red
                              : ctl.sysCpu >= 60 ? Theme.yellow : Theme.green
                    }
                    Metric {
                        label: "Temperatur"; icon: 0xf050f
                        value: ctl.sysTemp + " °C"
                        accent: ctl.sysTemp >= 85 ? Theme.red
                              : ctl.sysTemp >= 70 ? Theme.yellow : Theme.peach
                    }
                    Metric {
                        label: "Laufzeit"; icon: 0xf0954
                        value: ctl.sysUptime; accent: Theme.subtext
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
                                    // rfkill FIRST, then bluetoothctl.
                                    //
                                    // `bluetoothctl power on` cannot lift an
                                    // rfkill soft block -- it reports success or
                                    // silently does nothing while the adapter
                                    // stays down, which is exactly how Bluetooth
                                    // became impossible to switch on: hci0 sat
                                    // soft-blocked and the toggle had no way to
                                    // clear it. Suspend/resume and the firmware
                                    // hotkey can both set that block.
                                    //
                                    // Blocking on the way off too, so the switch
                                    // is symmetric and the adapter does not come
                                    // back by itself after a resume.
                                    ctl.run(ctl.btPowered
                                        ? "bluetoothctl power off; rfkill block bluetooth"
                                        : "rfkill unblock bluetooth; sleep 0.3; bluetoothctl power on");
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
        // Held while the handle is dragged. The panel uses it to ignore bus
        // updates mid-drag, which would otherwise snap the handle back to the
        // last value the daemon published while the finger is still moving.
        property bool dragging: false

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
            onPressed: function (m) { parent.dragging = true; parent.apply(m.x); }
            onPositionChanged: function (m) { if (pressed) parent.apply(m.x); }
            onReleased: parent.dragging = false
            onCanceled: parent.dragging = false
        }

        function apply(px) {
            const v = Math.round(Math.max(0, Math.min(1, px / width)) * 100);
            moved(v);
        }
    }
}
