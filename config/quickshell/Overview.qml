//  Workspace overview -- the biggest thing lost leaving GNOME.
//
//  Shows every workspace as a card with the windows on it, which one is
//  focused, and lets you jump to a workspace or straight to a window.
//
//  Live thumbnails via WindowThumb.qml (Quickshell.Wayland's ScreencopyView +
//  ToplevelManager -- a real, statically-typed module, unlike the empty
//  runtime-registered Quickshell.Hyprland one). Only decode while this panel
//  is actually open (`active: ov.panelOpen`), so a closed overview costs
//  nothing -- the GPU concern that ruled thumbnails out originally is what
//  that gate exists to answer.
//
//  Data comes from hypr-overview (hyprctl JSON), not from the Quickshell
//  Hyprland module: that module registers its types at runtime, so its API
//  cannot be verified before writing against it. Guessing property names is
//  where the last few panels acquired their bugs.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: ov

    property bool panelOpen: false
    onPanelOpenChanged: {
        if (ov.panelOpen) Exclusivity.claim("overview");
        else Exclusivity.release("overview");
    }
    Connections {
        target: Exclusivity
        function onOwnerChanged() {
            if (Exclusivity.owner !== "overview" && ov.panelOpen) ov.panelOpen = false;
        }
    }
    property var workspaces: []
    property int activeWs: 1
    property int selIndex: 0

    IpcHandler {
        target: "overview"
        function toggle(): void { ov.panelOpen ? ov.close() : ov.open(); }
        function hide(): void   { ov.close(); }
    }

    function open() {
        ov.panelOpen = true;
        load.running = true;    // always fresh: windows move constantly
    }
    function close() { ov.panelOpen = false; }

    Process {
        id: load
        running: false
        command: ["/home/woofi/.local/bin/hypr-overview"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text.trim());
                    ov.workspaces = d.workspaces || [];
                    ov.activeWs = d.active || 1;
                    // Start on the workspace you are actually on, so Enter
                    // without any arrow press is a no-op rather than a jump.
                    for (let i = 0; i < ov.workspaces.length; i++)
                        if (ov.workspaces[i].id === ov.activeWs) ov.selIndex = i;
                } catch (e) { /* keep whatever is displayed */ }
            }
        }
    }

    // NOT the plain "workspace"/"focuswindow" dispatcher strings: this machine
    // runs the Hyprland Lua config plugin, which evaluates every dispatch
    // argument as Lua. "hyprctl dispatch workspace 2" fails with
    //     [string "return hl.dispatch(workspace 2)"]:1: ')' expected near '2'
    // The object form below is what every keybind in hyprland.lua already
    // uses, and is what actually works on this Hyprland.
    function goWorkspace(id) {
        Quickshell.execDetached(["hyprctl", "dispatch",
            "hl.dsp.focus({ workspace = " + String(id) + " })"]);
        ov.close();
    }
    function goWindow(addr) {
        Quickshell.execDetached(["hyprctl", "dispatch",
            "hl.dsp.focus({ window = \"address:" + addr + "\" })"]);
        ov.close();
    }
    function move(d) {
        const n = ov.workspaces.length;
        if (n === 0) return;
        ov.selIndex = Math.max(0, Math.min(n - 1, ov.selIndex + d));
    }

    // =======================================================================
    PanelWindow {
        id: win
        visible: ov.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-overview"
        WlrLayershell.keyboardFocus: ov.panelOpen ? WlrKeyboardFocus.Exclusive
                                                  : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }

        MouseArea { anchors.fill: parent; onClicked: ov.close() }

        Item {
            anchors.fill: parent
            focus: ov.panelOpen
            Keys.onEscapePressed: ov.close()
            Keys.onLeftPressed:  ov.move(-1)
            Keys.onRightPressed: ov.move(1)
            Keys.onReturnPressed: {
                const w = ov.workspaces[ov.selIndex];
                if (w) ov.goWorkspace(w.id);
            }
            // Number keys jump straight to a workspace, as they do in the bar.
            Keys.onPressed: function (e) {
                if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                    ov.goWorkspace(e.key - Qt.Key_0);
                    e.accepted = true;
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: ov.panelOpen ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card
            readonly property int animMs: 190

            opacity: ov.panelOpen ? 1 : 0
            scale: ov.panelOpen ? 1 : 0.96
            transformOrigin: Item.Center
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            anchors.centerIn: parent
            width: Math.min(parent.width - 80, grid.implicitWidth + 40)
            height: grid.implicitHeight + 70
            radius: 22
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.98)
            border.width: 2
            border.color: Theme.surface1

            MouseArea { anchors.fill: parent }

            Text {
                id: heading
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.leftMargin: 20
                text: Strings.t.desktops
                color: Theme.surface2
                font.family: Theme.uiFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Grid {
                id: grid
                anchors.top: heading.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                spacing: 10

                Repeater {
                    model: ov.workspaces
                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        readonly property bool isActive: modelData.id === ov.activeWs
                        readonly property bool isSelected: index === ov.selIndex

                        width: 260
                        height: 196
                        radius: 14
                        color: isActive
                               ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.16)
                               : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9)
                        border.width: 2
                        // Selection and active are DIFFERENT things: one is
                        // where you are, the other is what Enter would do.
                        // Showing them identically hides which is which.
                        border.color: isSelected ? Theme.mauve
                                    : (isActive ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.5)
                                                : Theme.surface0)
                        Behavior on border.color { ColorAnimation { duration: 110 } }

                        Text {
                            id: wsNum
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 10
                            text: modelData.name
                            color: parent.isActive ? Theme.mauve : Theme.subtext
                            font.family: Theme.uiFont
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 10
                            text: modelData.windows.length === 0
                                  ? Strings.t.workspaceEmpty : modelData.windows.length + ""
                            color: Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                        }

                        Grid {
                            anchors.top: wsNum.bottom
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            columns: 2
                            spacing: 6

                            Repeater {
                                // Four fit as a 2x2 grid; beyond that the card
                                // would grow and the grid would jump between
                                // workspaces.
                                model: modelData.windows.slice(0, 4)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 113
                                    height: 76
                                    radius: 9
                                    color: Theme.crust
                                    border.width: modelData.focused ? 2 : 1
                                    border.color: modelData.focused ? Theme.mauve : Theme.surface0
                                    Behavior on border.color { ColorAnimation { duration: 90 } }

                                    WindowThumb {
                                        anchors.fill: parent
                                        anchors.margins: parent.border.width
                                        radius: 7
                                        cls: modelData.class
                                        winTitle: modelData.title
                                        // Only THIS workspace's thumbnails
                                        // actually decode frames, and only
                                        // while the panel is open -- an
                                        // off-screen workspace's windows cost
                                        // nothing to show here either.
                                        active: ov.panelOpen
                                        fallbackColour: modelData.focused ? Theme.mauve : Theme.subtext
                                    }

                                    // Title scrim, Windows-Task-View style:
                                    // overlaid on the thumbnail rather than a
                                    // separate row, so four windows still fit
                                    // in the same card.
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 18
                                        radius: 7
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                        // Square off the top corners of the
                                        // scrim so only the bottom stays
                                        // rounded with the tile.
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: parent.radius
                                            color: parent.color
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            text: modelData.title !== ""
                                                  ? modelData.title : modelData.class
                                            color: "white"
                                            font.family: Theme.uiFont
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }
                                    }

                                    HoverHandler { id: winHov; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: ov.goWindow(modelData.address)
                                    }
                                }
                            }
                        }

                        // Below the window rows, so clicking a window wins.
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: ov.goWorkspace(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
