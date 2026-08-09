//  Brightness, volume and Bluetooth as panels of their own.
//
//  The bar icons used to open foreign programs (pavucontrol,
//  blueman-manager) -- a window instead of a menu. Here they are sliders and a
//  device list directly under the icon that opened them, in the same style as
//  every other panel, and closing on a click beside them.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import QtQuick

Scope {
    id: ctl

    property string active: ""        // "brightness" | "volume" | "bluetooth" | ""
    onActiveChanged: {
        if (ctl.active !== "") Exclusivity.claim("controls");
        else Exclusivity.release("controls");
    }
    Connections {
        target: Exclusivity
        function onOwnerChanged() {
            if (Exclusivity.owner !== "controls" && ctl.active !== "") ctl.active = "";
        }
    }

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

    // ---- Bluetooth state ----------------------------------------------------
    //
    // Off Quickshell.Bluetooth (BlueZ over D-Bus) instead of polling
    // `bluetoothctl show`/`devices`/`info` every 4 s. `bluetoothctl devices`
    // only ever lists devices BlueZ already knows about -- there was no way to
    // discover and pair a NEW device from this panel at all, which was the
    // actual reason blueman-manager stayed necessary. Live and reactive now,
    // same as volume and brightness already were.
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btPowered: ctl.btAdapter ? ctl.btAdapter.enabled : false
    readonly property bool btScanning: ctl.btAdapter ? ctl.btAdapter.discovering : false
    readonly property var btAllDevices: ctl.btAdapter && ctl.btAdapter.devices
                                         ? ctl.btAdapter.devices.values : []
    readonly property var btPairedDevices: ctl.btAllDevices.filter(d => d.paired || d.bonded)
    readonly property var btNearbyDevices: ctl.btAllDevices.filter(d => !d.paired && !d.bonded)

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
        // No reader kick needed anywhere any more: volume and brightness
        // arrive on the bus, and the Bluetooth device list is now live off
        // Quickshell.Bluetooth (see the Binding below for scanning).
    }

    // Scanning for NEW devices only while the Bluetooth panel is actually
    // open and the adapter is powered -- there is no reason to keep
    // discovery running in the background once nobody is looking at the
    // list, and BlueZ can't discover with the adapter off anyway.
    Binding {
        target: ctl.btAdapter
        property: "discovering"
        value: ctl.active === "bluetooth" && ctl.btPowered
        when: ctl.btAdapter !== null
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
            // Bluetooth power no longer comes off this bus topic for THIS
            // panel -- ctl.btPowered now reads BlueZ directly and live via
            // Quickshell.Bluetooth. The "bt" topic still exists for Bar.qml's
            // own icon, which is unrelated and untouched.
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

    // ---- Per-application mixer ----------------------------------------------
    //
    // The master slider above stays off the wpctl/bus path -- it already works
    // and Bar.qml's own icon depends on the same bus values, no reason to
    // duplicate that source of truth. What was actually missing next to it,
    // and the real reason pavucontrol still got opened, is a per-app mixer:
    // there is no bus topic for individual streams, and there was no UI for
    // one at all. Built off Quickshell.Services.Pipewire, which talks to
    // PipeWire directly -- nothing here shells out.
    readonly property var pwStreams: Pipewire.nodes
        ? Pipewire.nodes.values.filter(n => n.isStream && n.audio
                                             && (n.type & PwNodeType.AudioOutStream))
        : []

    // Nodes are only live-updated while something is tracking them -- without
    // this, a stream's volume/muted properties do not refresh as it changes
    // elsewhere (the app itself, or another mixer).
    PwObjectTracker { objects: ctl.pwStreams }

    // Bluetooth adapter/device power-on needs the rfkill soft-block lifted
    // first (see the note by the toggle below); this is the delay between
    // that unblock and the moment BlueZ's Powered setter is actually tried.
    Timer {
        id: btPowerOnDelay
        interval: 300
        onTriggered: if (ctl.btAdapter) ctl.btAdapter.enabled = true
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
            // enabled: ctl.active !== "" -- without it this ran on the very
            // FIRST open too, animating in from whatever `x` happened to
            // default to before anything had ever opened (anchorX starts at
            // -1). Same fix as QuickSettings.qml and Menus.qml.
            Behavior on x { enabled: ctl.active !== ""; NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
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

                // ---------------- per-app mixer ----------------
                Text {
                    visible: ctl.active === "volume" && ctl.pwStreams.length > 0
                    text: "ANWENDUNGEN"
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                    topPadding: 2
                }

                Flickable {
                    visible: ctl.active === "volume" && ctl.pwStreams.length > 0
                    width: parent.width
                    height: Math.min(220, mixerCol.implicitHeight)
                    contentHeight: mixerCol.implicitHeight
                    clip: true

                    Column {
                        id: mixerCol
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: ctl.active === "volume" ? ctl.pwStreams : []
                            delegate: Rectangle {
                                id: streamRow
                                required property var modelData
                                width: mixerCol.width
                                height: 52
                                radius: 14
                                color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    spacing: 6

                                    Row {
                                        width: parent.width
                                        Text {
                                            width: parent.width - 60
                                            text: streamRow.modelData.description.length > 0
                                                  ? streamRow.modelData.description
                                                  : streamRow.modelData.name
                                            color: Theme.text
                                            font.family: Theme.uiFont
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 50
                                            horizontalAlignment: Text.AlignRight
                                            text: streamRow.modelData.audio.muted ? "stumm"
                                                : Math.round(streamRow.modelData.audio.volume * 100) + "%"
                                            color: Theme.subtext
                                            font.family: Theme.uiFont
                                            font.pixelSize: 11
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 8
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Theme.ico(streamRow.modelData.audio.muted ? 0xf0581 : 0xf057e)
                                            color: streamRow.modelData.audio.muted ? Theme.surface2 : Theme.sapphire
                                            font.family: Theme.uiFont
                                            font.pixelSize: 13
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                onClicked: streamRow.modelData.audio.muted = !streamRow.modelData.audio.muted
                                            }
                                        }
                                        Slider {
                                            width: parent.width - 24
                                            value: Math.round(streamRow.modelData.audio.volume * 100)
                                            accent: streamRow.modelData.audio.muted ? Theme.surface2 : Theme.sapphire
                                            onMoved: function (v) { streamRow.modelData.audio.volume = v / 100; }
                                        }
                                    }
                                }
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
                            text: ctl.btPowered ? (ctl.btAdapter ? ctl.btAdapter.name : "Eingeschaltet")
                                                 : "Ausgeschaltet"
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
                                    // rfkill FIRST, then the adapter's own
                                    // Powered property (Quickshell.Bluetooth,
                                    // i.e. BlueZ directly -- no more shelling to
                                    // bluetoothctl for this half).
                                    //
                                    // BlueZ's Powered setter cannot lift an
                                    // rfkill soft block itself -- it reports
                                    // success or silently does nothing while the
                                    // adapter stays down, which is exactly how
                                    // Bluetooth became impossible to switch on:
                                    // hci0 sat soft-blocked and the toggle had no
                                    // way to clear it. Suspend/resume and the
                                    // firmware hotkey can both set that block.
                                    // btPowerOnDelay gives the kernel a beat
                                    // before BlueZ is asked to power up.
                                    //
                                    // Blocking on the way off too, so the switch
                                    // is symmetric and the adapter does not come
                                    // back by itself after a resume.
                                    if (ctl.btPowered) {
                                        if (ctl.btAdapter) ctl.btAdapter.enabled = false;
                                        ctl.run("rfkill block bluetooth");
                                    } else {
                                        ctl.run("rfkill unblock bluetooth");
                                        btPowerOnDelay.restart();
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: ctl.btPowered && ctl.btPairedDevices.length === 0
                                 && ctl.btNearbyDevices.length === 0
                        text: ctl.btScanning ? "Suche Geräte…" : "Keine Geräte gefunden"
                        color: Theme.subtext
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        padding: 8
                    }

                    // Paired first -- these are the everyday case (headphones,
                    // mouse) and should not scroll below whatever happens to be
                    // discoverable nearby at the moment.
                    Repeater {
                        model: ctl.active === "bluetooth" ? ctl.btPairedDevices : []
                        delegate: DeviceRow { paired: true }
                    }

                    Text {
                        visible: ctl.active === "bluetooth" && ctl.btNearbyDevices.length > 0
                        text: "VERFÜGBAR"
                        color: Theme.surface2
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        leftPadding: 4
                        topPadding: 4
                    }

                    // Unpaired devices BlueZ can currently see -- this is the
                    // part that did not exist before at all: the old panel only
                    // ever showed `bluetoothctl devices` (already-paired), so
                    // pairing something new had no path except blueman-manager.
                    Repeater {
                        model: ctl.active === "bluetooth" ? ctl.btNearbyDevices : []
                        delegate: DeviceRow { paired: false }
                    }

                    Rectangle {
                        visible: ctl.active === "bluetooth" && ctl.btPowered
                        width: parent.width
                        height: 34
                        radius: 11
                        color: scanHover.hovered ? Theme.surface1 : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }
                        HoverHandler { id: scanHover }

                        Text {
                            anchors.centerIn: parent
                            text: ctl.btScanning ? "Suche läuft…" : "Nach Geräten suchen"
                            color: ctl.btScanning ? Theme.subtext : Theme.mauve
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !ctl.btScanning
                            onClicked: if (ctl.btAdapter) ctl.btAdapter.discovering = true
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

    // A Bluetooth device row -- paired (click connects/disconnects, has a
    // forget button) or nearby-and-unpaired (click pairs). All the actions
    // are methods on the BluetoothDevice object itself (Quickshell.Bluetooth),
    // so this needs nothing from the outer scope.
    //
    // Declared as a top-level component, not inline in the Repeater delegate,
    // for the same reason as MenuRow in Menus.qml: `width: parent.width` HAS
    // to mean the Repeater's own parent, not some Column further up that a
    // component boundary can no longer see.
    component DeviceRow: Rectangle {
        id: devRow
        required property var modelData
        property bool paired: false

        width: parent ? parent.width : 300
        height: 36
        radius: 11
        color: dh.hovered ? Theme.surface1 : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        HoverHandler { id: dh }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (devRow.modelData.connected) devRow.modelData.disconnect();
                else if (devRow.paired) devRow.modelData.connect();
                else devRow.modelData.pair();
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.ico(devRow.modelData.connected ? 0xf00af : 0xf00b1)
            color: devRow.modelData.connected ? Theme.green
                 : (devRow.modelData.pairing ? Theme.yellow : Theme.subtext)
            font.family: Theme.uiFont
            font.pixelSize: 14
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 42
            anchors.right: trailing.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: devRow.modelData.name.length > 0 ? devRow.modelData.name : devRow.modelData.deviceName
            color: Theme.text
            font.family: Theme.uiFont
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Row {
            id: trailing
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                visible: devRow.modelData.batteryAvailable
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(devRow.modelData.battery * 100) + "%"
                color: Theme.subtext
                font.family: Theme.uiFont
                font.pixelSize: 11
            }

            // Forget -- paired devices only. Plain text, not a Nerd Font glyph:
            // every other icon here reuses a codepoint already proven to exist
            // in this font from elsewhere in the shell; there was no already-
            // verified one for "remove" and guessing one risks a blank box.
            Text {
                visible: devRow.paired
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: fh.hovered ? Theme.red : Theme.surface2
                font.pixelSize: 12
                HoverHandler { id: fh }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: devRow.modelData.forget()
                }
            }
        }
    }
}
