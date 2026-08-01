//  Workspace overview -- the biggest thing lost leaving GNOME.
//
//  Shows every workspace as a card with the windows on it, which one is
//  focused, and lets you jump to a workspace or straight to a window.
//
//  NO live thumbnails. Those need wlr-screencopy per window per frame, and
//  getting that wrong costs GPU time continuously rather than once. Titles and
//  application names identify a window well enough to switch to it, which is
//  what a switcher is for. Thumbnails can come later without changing this.
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

    function goWorkspace(id) {
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(id)]);
        ov.close();
    }
    function goWindow(addr) {
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow",
                                 "address:" + addr]);
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
                text: "ARBEITSFLÄCHEN"
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

                        width: 230
                        height: 150
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
                                  ? "leer" : modelData.windows.length + ""
                            color: Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                        }

                        Column {
                            anchors.top: wsNum.bottom
                            anchors.topMargin: 6
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 10
                            spacing: 3

                            Repeater {
                                // Four fit; beyond that the card would grow and
                                // the grid would jump between workspaces.
                                model: modelData.windows.slice(0, 4)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: 22
                                    radius: 7
                                    color: modelData.focused
                                           ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.22)
                                           : (winHov.hovered ? Theme.surface1 : "transparent")
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    HoverHandler { id: winHov; cursorShape: Qt.PointingHandCursor }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 7
                                        anchors.rightMargin: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.title !== ""
                                              ? modelData.title : modelData.class
                                        color: modelData.focused ? Theme.text : Theme.subtext
                                        font.family: Theme.uiFont
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: ov.goWindow(modelData.address)
                                    }
                                }
                            }
                            Text {
                                visible: modelData.windows.length > 4
                                text: "+ " + (modelData.windows.length - 4) + " weitere"
                                color: Theme.surface2
                                font.family: Theme.uiFont
                                font.pixelSize: 10
                                leftPadding: 7
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
