//  Top bar -- replacement for waybar.
//
//  The one and only reason for the move is the light/dark switch. waybar
//  listens for the portal's color-scheme itself and reloads completely in
//  response ("Received new appearance 'light'" -> "Reloading..."). In doing so
//  it tears its layer surface down and builds it back up, so the bar visibly
//  disappears. Measured frame by frame: roughly a 100 ms gap. It cannot be
//  turned off; it is waybar's own behaviour.
//
//  Here every colour is bound to Theme, and Theme animates them. Nothing is
//  rebuilt -- the bar fades on the same curve as the rest of the shell.
//
//  All values arrive on one MQTT subscription. waybar started a separate
//  process per module on its own schedule, which made the readings drift
//  apart; the replacement polled one script that forked twenty processes per
//  run. Now hypr-eventd publishes a single consistent object and this
//  subscribes to it -- no forks, and every field on screen comes from the same
//  sample.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
    id: bar

    readonly property int barH: 40

    // Set by shell.qml from the notification centre.
    property bool dnd: false

    // ---- State ------------------------------------------------------------
    property int    cpu: 0
    property string mem: "—"
    property int    temp: 0
    property int    batt: 0
    property string battState: ""
    property string down: "0 B/s"
    property int    vol: 0
    property bool   muted: false
    property int    bright: 0
    property string bt: "off"
    property string net: "off"
    property string ssid: ""

    property string taskText: ""
    property string taskTip: ""

    Process {
        id: state


        // Subscribed to the event bus, not polling a script.
        //
        // This used to run `hypr-bar-state` on a 2 s timer. Measured with
        // strace, one run of that script costs 107 clone() and 75 execve()
        // calls -- it shells out to hypr-widget-stats, ip, cat, date, wpctl,
        // grep, awk, brightnessctl, bluetoothctl and iwctl. Running it fast
        // enough to feel immediate was never an option; at 500 ms it would
        // have meant roughly 360 process creations per second.
        //
        // hypr-eventd now reads the same values out of /proc and /sys with no
        // forks at all and publishes them here. mosquitto_sub holds one
        // long-lived connection and writes one line per change.
        //
        // The retained message is deliberately NOT suppressed (no -R): it is
        // delivered the moment this subscribes, so the bar draws real values on
        // its first frame instead of zeros. That is the same reason the widget
        // caches moved to ~/.cache -- nothing on this desktop should come up
        // empty and fill in afterwards.
        // A subscription that exits must come back.
        //
        // Quickshell does not restart a Process on its own, so when mosquitto_sub
        // exited -- because the broker restarted, or simply because the shell won
        // the race against it at login -- the subscription stayed dead for the whole
        // session. The panel then kept showing its last received values forever,
        // with no error anywhere. That is what froze the whole shell after the
        // broker was restarted.
        onExited: reconnect.start()
        running: true
        command: ["mosquitto_sub",
                  "--unix", "/run/user/1000/mosquitto.sock",
                  "-t", "hypr/state",
                  "-q", "0"]
        stdout: SplitParser {
            onRead: function (line) {
                try {
                    const d = JSON.parse(line.trim());
                    bar.cpu = d.cpu; bar.mem = d.mem; bar.temp = d.temp;
                    bar.batt = d.batt; bar.battState = d.battState;
                    bar.down = d.down; bar.vol = d.vol; bar.muted = d.muted;
                    bar.bright = d.bright; bar.bt = d.bt;
                    bar.net = d.net; bar.ssid = d.ssid;
                } catch (e) { /* keep the previous state */ }
            }
        }
    }

    Timer {
        id: reconnect
        interval: 1000
        repeat: false
        onTriggered: state.running = true
    }


    Process {
        id: task
        running: false
        command: ["/home/woofi/.local/bin/hypr-taskbar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text.trim());
                    bar.taskText = d.text || "";
                    bar.taskTip  = d.tooltip || "";
                } catch (e) { /* leave it empty */ }
            }
        }
    }

    // ---- Events rather than polling --------------------------------------
    //
    // Everything the bar shows arrives over the event bus above. The audio
    // watcher that used to live here -- a second `pactl subscribe` -- moved
    // into hypr-eventd, so there is now one subscription to PipeWire on this
    // machine instead of one per consumer.
    //
    // Measured end to end, from the change to the value being on screen:
    //   volume, mute      ~24 ms   (pactl subscribe)
    //   brightness        ~5 ms    (sysfs_notify on actual_brightness)
    //   everything else   <=750 ms (the daemon tick; no event source exists)

    // Window list. Hyprland reports opens, closes and focus changes.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "openwindow" || n === "closewindow"
                || n === "activewindow" || n === "movewindow"
                || n === "windowtitle")
                task.running = true;
        }
    }

    // Kept for the volume and brightness keys in hyprland.lua, which still call
    // it. The state half is now a no-op -- hypr-eventd sees those changes
    // itself, through PipeWire and sysfs_notify, faster than an IPC round trip
    // would deliver them -- so this only refreshes the task list.
    IpcHandler {
        target: "bar"
        function refresh(): void { task.running = true; }
    }

    // The task list still needs a nudge: Hyprland reports window events, but a
    // title changing inside an already-open window does not always raise one.
    // 5 s rather than the old 2 s, because the window events above cover every
    // case that matters and this is only the safety net.
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: task.running = true
    }

    SystemClock { id: clk; precision: SystemClock.Minutes }

    Process { id: runner }
    function run(cmd) { runner.command = ["sh", "-c", cmd]; runner.running = true; }
    // Panel requests are SIGNALS, not IPC calls.
    //
    // Every one of these used to run `sh -c "qs ipc call ..."`: a shell, then a
    // full Quickshell binary with all of Qt behind it, launched purely to send a
    // message to the process that launched it. Measured at ~20 ms per click on
    // an idle machine, and there is nothing bounding it under load.
    //
    // The bar and every panel are children of the same ShellRoot, so shell.qml
    // simply connects these signals to the panels directly. Same process, one
    // function call, no subprocess.
    //
    // The IpcHandlers on the panels stay -- keybindings in hyprland.lua and
    // manual `qs ipc call` still use them.
    signal requestMenu(string which, real centreX)
    signal requestControl(string which, real centreX)
    signal requestQuickSettings(real centreX)
    signal requestNotifications()
    signal requestAltTab()

    // ---- Icons ------------------------------------------------------------
    // Volume: the louder it is, the more waves on the icon.
    //
    // The code points are NOT ordered by loudness -- in Material Design
    // F057F is "low" and F0580 is "medium", exactly the other way round from
    // what the numbering suggests. Built in swapped at first; it showed up on
    // screen.
    function volIcon() {
        if (bar.muted)     return 0xf075f;   // muted
        if (bar.vol === 0) return 0xf0581;   // off
        if (bar.vol < 34)  return 0xf057f;   // one wave
        if (bar.vol < 67)  return 0xf0580;   // two waves
        return 0xf057e;                      // three waves
    }

    // ...and the brighter. The mix runs between the muted surface colour and
    // the full accent, so low volumes look visibly held back instead of just
    // showing a different glyph. Because both end points come from Theme, this
    // recolours along with the light/dark switch.
    function volColour() {
        if (bar.muted) return Theme.surface2;
        const t = Math.max(0, Math.min(1, bar.vol / 100));
        const k = 0.30 + 0.70 * t;           // never fully off, never overdrawn
        const a = Theme.surface2, b = Theme.teal;
        return Qt.rgba(a.r + (b.r - a.r) * k,
                       a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, 1);
    }
    // Brightness, following the same pattern as volume: the icon gets fuller
    // and the colour stronger the brighter the screen is.
    // 0xf00da..0xf00de are the steps from brightness_1 to brightness_5.
    function brightIcon() {
        if (bar.bright < 20) return 0xf00da;
        if (bar.bright < 40) return 0xf00db;
        if (bar.bright < 60) return 0xf00dc;
        if (bar.bright < 80) return 0xf00dd;
        return 0xf00de;
    }

    function brightColour() {
        const t = Math.max(0, Math.min(1, bar.bright / 100));
        const k = 0.30 + 0.70 * t;
        const a = Theme.surface2, b = Theme.yellow;
        return Qt.rgba(a.r + (b.r - a.r) * k,
                       a.g + (b.g - a.g) * k,
                       a.b + (b.b - a.b) * k, 1);
    }

    function netIcon() {
        if (bar.net === "wifi") return 0xf05a9;
        if (bar.net === "eth")  return 0xf059f;
        return 0xf092f;
    }
    function battIcon() {
        if (bar.battState === "Charging") return 0xf0084;
        if (bar.batt >= 90) return 0xf0079;
        if (bar.batt >= 60) return 0xf0082;
        if (bar.batt >= 30) return 0xf007f;
        if (bar.batt >= 10) return 0xf007b;
        return 0xf007a;
    }

    // =======================================================================
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"
            anchors { top: true; left: true; right: true }
            implicitHeight: bar.barH
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Theme.crust.r, Theme.crust.g, Theme.crust.b, 0.94)

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: Qt.rgba(Theme.surface0.r, Theme.surface0.g,
                                   Theme.surface0.b, 0.8)
                }

                // ----------------------------------------------------- LEFT
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    TextButton {
                        text: "Apps"; bold: true
                        onActivated: function (cx) { bar.requestMenu("apps", cx); }
                    }
                    TextButton {
                        text: "Places"; bold: true
                        onActivated: function (cx) { bar.requestMenu("places", cx); }
                    }

                    // Arbeitsflaechen. Quickshell.Hyprland liefert sie
                    // event-driven -- no polling needed.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        leftPadding: 8
                        rightPadding: 8

                        Repeater {
                            model: 4
                            // No colour animation here either: active and
                            // hovered are drawn with surfaces that fade in, so
                            // the theme switch is driven by Theme alone.
                            delegate: Item {
                                required property int index
                                readonly property int wsId: index + 1
                                readonly property bool active:
                                    Hyprland.focusedWorkspace
                                    && Hyprland.focusedWorkspace.id === wsId

                                anchors.verticalCenter: parent.verticalCenter
                                width: active ? 34 : 24
                                height: 26
                                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Theme.surface1
                                    opacity: (!parent.active && ma.containsMouse) ? 0.85 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Theme.mauve
                                    opacity: parent.active ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.wsId
                                    color: Theme.subtext
                                    font.family: Theme.uiFont
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    opacity: parent.active ? 0 : 1
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.wsId
                                    color: Theme.crust
                                    font.family: Theme.uiFont
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    opacity: parent.active ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }

                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                                }
                            }
                        }
                    }

                    // Open applications
                    Pill {
                        visible: bar.taskText.trim().length > 0
                        content: bar.taskText
                        mono: true
                        pixel: 14
                        colour: Theme.lavender
                        onActivated: function () { bar.requestAltTab(); }
                    }
                }

                // --------------------------------------------------- CENTRE
                Item {
                    anchors.centerIn: parent
                    width: dateText.implicitWidth + 32
                    height: 26

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Theme.surface1
                        opacity: clockMa.containsMouse ? 0.7 : 0
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                    }

                    Text {
                        id: dateText
                        anchors.centerIn: parent
                        text: clk.date.toLocaleDateString(Qt.locale("de_DE"), "dd. MMM")
                              + "  " + clk.date.toLocaleTimeString(Qt.locale("de_DE"), "HH:mm")
                        color: Theme.text
                        font.family: Theme.uiFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: clockMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bar.requestNotifications()
                    }
                }

                // ---------------------------------------------------- RIGHT
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    // Messwerte
                    Pill {
                        items: [
                            { ico: 0xf01da, txt: bar.down,          col: Theme.maroon },
                            { ico: 0xf035b, txt: bar.mem + " GB",   col: Theme.text },
                            { ico: 0xf050f, txt: bar.temp + "°C",
                              col: bar.temp >= 85 ? Theme.red
                                 : bar.temp >= 70 ? Theme.yellow : Theme.peach }
                        ]
                        onActivated: function (cx) { bar.requestQuickSettings(cx); }
                    }

                    // Notifications
                    Pill {
                        content: Theme.ico(0xf009a)
                        mono: true
                        pixel: 13
                        // Struck through and muted while "do not disturb" is on.
                        strike: bar.dnd
                        colour: bar.dnd ? Theme.surface2 : Theme.lavender
                        onActivated: function () { bar.requestNotifications(); }
                    }

                    // toggle
                    Pill {
                        icons: [
                            { ico: 0xf00b1, col: bar.bt === "on" ? Theme.blue : Theme.surface2,
                              act: function (cx) { bar.requestControl("bluetooth", cx); } },
                            { ico: bar.netIcon(),
                              col: bar.net === "off" ? Theme.red : Theme.sapphire,
                              act: function (cx) { bar.requestMenu("wifi", cx); } },
                            { ico: bar.volIcon(), col: bar.volColour(),
                              act: function (cx) { bar.requestControl("volume", cx); } },
                            { ico: bar.brightIcon(), col: bar.brightColour(),
                              act: function (cx) { bar.requestControl("brightness", cx); } }
                        ]
                    }

                    // Battery and power -- deliberately ONE field, so hovering
                    // lights up a single continuous surface rather than two
                    // separate rectangles with a gap between them.
                    Pill {
                        items: [
                            { ico: bar.battIcon(), txt: bar.batt + "%",
                              col: bar.battState === "Charging" ? Theme.green
                                 : bar.batt <= 15 ? Theme.red
                                 : bar.batt <= 30 ? Theme.yellow : Theme.maroon },
                            { ico: 0xf0425, txt: "", col: Theme.red }
                        ]
                        onActivated: function (cx) { bar.requestQuickSettings(cx); }
                    }
                }
            }
        }
    }
}
