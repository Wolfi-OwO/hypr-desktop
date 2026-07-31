//  GNOME-style Quick Settings -- replaces the rofi dropdowns for battery and
//  power.
//
//  Why not stay with rofi: under Wayland, rofi never receives clicks outside
//  its own surface, so -click-to-exit does not close it there. On top of that
//  the position could not be placed cleanly under the bar (the menus ended up
//  far too low). As a Quickshell panel both are directly controllable: a
//  full-screen MouseArea closes on a click beside it, and the card hangs
//  exactly below the bar.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: qs

    property bool panelOpen: false
    property string profile: "balanced"
    property string scheme: "prefer-dark"
    property string battPct: "—"
    property string battState: ""

    readonly property int barHeight: 40

    // ---- Palette ----------------------------------------------------------
    // Bound to Theme instead of hard-wired. This used to hold literals, which
    // is why these surfaces stayed dark in light mode while the bar and the GTK
    // apps had already switched.
    readonly property color cBase:     Theme.base
    readonly property color cMantle:   Theme.mantle
    readonly property color cCrust:    Theme.crust
    readonly property color cSurface0: Theme.surface0
    readonly property color cSurface1: Theme.surface1
    readonly property color cSurface2: Theme.surface2
    readonly property color cText:     Theme.text
    readonly property color cSubtext:  Theme.subtext
    readonly property color cMauve:    Theme.mauve
    readonly property color cGreen:    Theme.green
    readonly property color cRed:      Theme.red
    readonly property string uiFont: Theme.uiFont

    // Build Nerd Font characters from code points: literal glyphs get lost
    // when this file is written out.
    function ico(cp) { return String.fromCodePoint(cp); }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { qs.panelOpen = !qs.panelOpen; if (qs.panelOpen) qs.refresh(); }
        function show(): void { qs.panelOpen = true; qs.refresh(); }
        function hide(): void { qs.panelOpen = false; }
    }

    // Nothing to refresh on demand any more: every value below arrives on the
    // bus as it changes, and the retained messages mean the panel already holds
    // the current state before it is opened. Kept as an empty function because
    // the IPC handlers above call it.
    function refresh() {}

    // One subscription for all three values that used to be polled every 30 s:
    // the power profile (was `powerprofilesctl get`), the colour scheme (was
    // `gsettings get`) and the battery (was a shell reading two sysfs files).
    //
    // 30 s was slow enough that the panel regularly opened showing a stale
    // battery percentage and then corrected itself a moment later. These are
    // retained topics, so the values are already current when the panel opens
    // and there is nothing to wait for.
    Process {
        id: busSub
        running: true
        command: ["mosquitto_sub",
                  "--unix", "/run/user/1000/mosquitto.sock",
                  "-t", "hypr/power", "-t", "hypr/theme", "-t", "hypr/battery",
                  "-q", "0"]
        stdout: SplitParser {
            onRead: function (line) {
                try {
                    const d = JSON.parse(line.trim());
                    // Each message carries only its own topic's keys, so an
                    // absent field means "unchanged", not "empty".
                    if (d.profile !== undefined)   qs.profile   = d.profile;
                    if (d.dark !== undefined)      qs.scheme    = d.dark ? "prefer-dark" : "prefer-light";
                    if (d.batt !== undefined)      qs.battPct   = "" + d.batt;
                    if (d.battState !== undefined) qs.battState = d.battState;
                } catch (e) { /* keep the previous values */ }
            }
        }
    }

    Process { id: runner }
    function run(cmd) {
        runner.command = ["sh", "-c", cmd];
        runner.running = true;
    }


    // =======================================================================
    PanelWindow {
        id: qsWin

        // Tied to the card's opacity rather than straight to `panelOpen`, so
        // the layer surface outlives the closing fade. With
        // `visible: qs.panelOpen` the surface disappeared in the same frame the
        // state flipped, and the close animation was never seen — it opened
        // with a transition and vanished instantly. Same fix as in Menus.qml.
        visible: qs.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-quick-settings"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        // A click anywhere beside it closes -- rofi could not do that here.
        MouseArea {
            anchors.fill: parent
            onClicked: qs.panelOpen = false
        }

        // Escape closes as well, not just the click beside it (#50).
        Item {
            anchors.fill: parent
            focus: qs.panelOpen
            Keys.onEscapePressed: qs.panelOpen = false
        }


        // Scrim, identical to the one behind the applications menu.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: qs.panelOpen ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card

            // Same transition as every other panel: opacity, scale from the
            // corner under its button, and a short slide out from beneath the
            // bar — all on one duration and one curve so it reads as a single
            // movement. 190 ms; the previous 110 was short enough to read as a
            // flicker rather than a transition.
            readonly property int animMs: 190

            opacity: qs.panelOpen ? 1 : 0
            scale: qs.panelOpen ? 1 : 0.94
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.top: parent.top
            anchors.topMargin: qs.barHeight + (qs.panelOpen ? 4 : -6)   // just below the bar
            Behavior on anchors.topMargin { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            width: 340
            height: content.implicitHeight + 24
            radius: 20
            color: Qt.rgba(qs.cMantle.r, qs.cMantle.g, qs.cMantle.b, 0.98)
            border.width: 2
            border.color: qs.cSurface1

            MouseArea { anchors.fill: parent }   // do not pass clicks through

            Column {
                id: content
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 10

                // ---------- header: battery ----------
                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 14
                    color: Qt.rgba(qs.cBase.r, qs.cBase.g, qs.cBase.b, 0.9)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: qs.battState === "Charging" ? qs.ico(0xf0084) : qs.ico(0xf0079)
                            color: qs.battState === "Charging" ? qs.cGreen : qs.cMauve
                            font.family: qs.uiFont
                            font.pixelSize: 20
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Text {
                                text: "Akku " + qs.battPct + "%"
                                color: qs.cText
                                font.family: qs.uiFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }
                            Text {
                                text: qs.battState === "Charging" ? "Wird geladen"
                                    : (qs.battState === "Full" ? "Voll" : "Akkubetrieb")
                                color: qs.cSubtext
                                font.family: qs.uiFont
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ---------- Gruppe: Energiemodus ----------
                Text {
                    text: "ENERGIEMODUS"
                    color: qs.cSurface2
                    font.family: qs.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                Rectangle {
                    width: parent.width
                    height: profCol.implicitHeight + 8
                    radius: 14
                    color: Qt.rgba(qs.cBase.r, qs.cBase.g, qs.cBase.b, 0.9)

                    Column {
                        id: profCol
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 0

                        component Choice: Rectangle {
                            property string label
                            property int icon
                            property string value
                            width: profCol.width
                            height: 36
                            radius: 11
                            color: ma.containsMouse ? qs.cSurface1 : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: qs.ico(parent.icon)
                                color: qs.cSubtext
                                font.family: qs.uiFont
                                font.pixelSize: 15
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.label
                                color: qs.cText
                                font.family: qs.uiFont
                                font.pixelSize: 13
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: qs.profile === parent.value ? qs.ico(0xf012c) : ""
                                color: qs.cMauve
                                font.family: qs.uiFont
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    qs.run("powerprofilesctl set " + parent.value);
                                    qs.profile = parent.value;
                                }
                            }
                        }

                        Choice { label: "Leistung";    icon: 0xf0e31; value: "performance" }
                        Choice { label: "Ausgeglichen"; icon: 0xf0595; value: "balanced" }
                        Choice { label: "Energiesparen"; icon: 0xf0084; value: "power-saver" }
                    }
                }

                // ---------- Gruppe: Erscheinungsbild ----------
                Text {
                    text: "ERSCHEINUNGSBILD"
                    color: qs.cSurface2
                    font.family: qs.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                // On hover the two halves behave as ONE element: the hover
                // sits on the container and both sides light up together.
                // Clicks still land specifically on the left or the right, so
                // either can be picked directly.
                Rectangle {
                    id: appearanceGroup
                    property bool hovered: groupHover.hovered

                    width: parent.width
                    height: 44
                    radius: 14
                    color: hovered
                           ? Qt.rgba(qs.cSurface1.r, qs.cSurface1.g, qs.cSurface1.b, 0.55)
                           : Qt.rgba(qs.cBase.r, qs.cBase.g, qs.cBase.b, 0.9)

                    Behavior on color { ColorAnimation { duration: 110 } }

                    HoverHandler { id: groupHover }

                    Row {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 4

                        component Mode: Rectangle {
                            property string label
                            property int icon
                            property string value
                            readonly property bool active: qs.scheme === value

                            width: (parent.width - 4) / 2
                            height: 36
                            radius: 11
                            color: active
                                   ? qs.cMauve
                                   : (appearanceGroup.hovered
                                      ? Qt.rgba(qs.cSurface2.r, qs.cSurface2.g, qs.cSurface2.b, 0.55)
                                      : "transparent")

                            Behavior on color { ColorAnimation { duration: 110 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    text: qs.ico(parent.parent.icon)
                                    color: parent.parent.active ? qs.cCrust : qs.cText
                                    font.family: qs.uiFont
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: parent.parent.label
                                    color: parent.parent.active ? qs.cCrust : qs.cText
                                    font.family: qs.uiFont
                                    font.pixelSize: 12
                                    font.weight: parent.parent.active ? Font.Bold : Font.Normal
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    // hypr-appearance rather than gsettings alone: color-scheme by
                                    // itself changes nothing, because settings.ini overrode the portal
                                    // and Catppuccin-GnomeTheme has no light variant.
                                    qs.run("/home/woofi/.local/bin/hypr-appearance "
                                           + (parent.value === "prefer-dark" ? "dark" : "light"));
                                    qs.scheme = parent.value;
                                }
                            }
                        }

                        Mode { label: "Dunkel"; icon: 0xf0594; value: "prefer-dark" }
                        Mode { label: "Hell";   icon: 0xf0599; value: "prefer-light" }
                    }
                }

                // ---------- Gruppe: System ----------
                Text {
                    text: "SYSTEM"
                    color: qs.cSurface2
                    font.family: qs.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                Rectangle {
                    width: parent.width
                    height: sysCol.implicitHeight + 8
                    radius: 14
                    color: Qt.rgba(qs.cBase.r, qs.cBase.g, qs.cBase.b, 0.9)

                    Column {
                        id: sysCol
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 0

                        component Act: Rectangle {
                            property string label
                            property int icon
                            property string cmd
                            property bool danger: false
                            width: sysCol.width
                            height: 36
                            radius: 11
                            color: aa.containsMouse ? (danger ? qs.cRed : qs.cSurface1) : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: qs.ico(parent.icon)
                                color: aa.containsMouse && parent.danger ? qs.cCrust : qs.cSubtext
                                font.family: qs.uiFont
                                font.pixelSize: 15
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.label
                                color: aa.containsMouse && parent.danger ? qs.cCrust : qs.cText
                                font.family: qs.uiFont
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: aa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { qs.panelOpen = false; qs.run(parent.cmd); }
                            }
                        }

                        Act { label: "Sperren";     icon: 0xf033e; cmd: "hyprlock" }
                        Act { label: "Abmelden";    icon: 0xf0343; cmd: "hyprctl dispatch 'hl.dsp.exit()'" }
                        Act { label: "Bereitschaft"; icon: 0xf04b2; cmd: "systemctl suspend" }
                        Act { label: "Neu starten"; icon: 0xf0709; cmd: "systemctl reboot" }
                        Act { label: "Herunterfahren"; icon: 0xf0425; cmd: "systemctl poweroff"; danger: true }
                        Act { label: "Einstellungen"; icon: 0xf0493; cmd: "/home/woofi/.local/bin/hypr-settings" }
                    }
                }
            }
        }
    }
}
