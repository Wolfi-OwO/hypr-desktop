//  Now playing, as a panel.
//
//  The media keys were already bound to playerctl, but nothing on screen said
//  what was playing -- you could pause a track without knowing which one. This
//  closes that gap.
//
//  Uses Quickshell's own MPRIS service rather than shelling out to playerctl:
//  it is a live D-Bus binding, so the title updates when the track changes
//  instead of when a timer next fires, and it costs no processes at all.
//
//  Its own file, like Clipboard.qml and SunsetSchedule.qml.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: media

    property bool panelOpen: false
    onPanelOpenChanged: {
        if (media.panelOpen) Exclusivity.claim("media");
        else Exclusivity.release("media");
    }
    Connections {
        target: Exclusivity
        function onOwnerChanged() {
            if (Exclusivity.owner !== "media" && media.panelOpen) media.panelOpen = false;
        }
    }
    readonly property int barHeight: 40
    property real anchorX: -1

    // The player to show when several are running. Preference order: the one
    // actually playing, then whichever can be controlled at all. Without this,
    // a paused browser tab could outrank the music that is audible.
    readonly property var player: {
        const ps = Mpris.players ? Mpris.players.values : [];
        if (!ps || ps.length === 0) return null;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        for (let i = 0; i < ps.length; i++) if (ps[i].canControl) return ps[i];
        return ps[0];
    }
    readonly property bool hasPlayer: media.player !== null

    IpcHandler {
        target: "media"
        function toggle(): void { media.panelOpen = !media.panelOpen; }
        function hide(): void   { media.panelOpen = false; }
        // Bound to the media keys as well, so the panel and the hardware keys
        // drive the same object rather than two different ideas of "the player".
        function playPause(): void { if (media.player) media.player.togglePlaying(); }
        function next(): void      { if (media.player) media.player.next(); }
        function previous(): void  { if (media.player) media.player.previous(); }
    }

    function openAt(x) {
        media.anchorX = (x === undefined || x === null) ? -1 : x;
        media.panelOpen = !media.panelOpen;
    }

    function fmt(us) {
        if (!us || us <= 0) return "0:00";
        const s = Math.floor(us / 1000000);
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // =======================================================================
    PanelWindow {
        id: win
        visible: media.panelOpen || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-media"
        WlrLayershell.keyboardFocus: media.panelOpen ? WlrKeyboardFocus.Exclusive
                                                     : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }

        MouseArea { anchors.fill: parent; onClicked: media.panelOpen = false }

        Item {
            anchors.fill: parent
            focus: media.panelOpen
            Keys.onEscapePressed: media.panelOpen = false
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: media.panelOpen ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card
            readonly property int animMs: 190
            readonly property int targetWidth: 400

            opacity: media.panelOpen ? 1 : 0
            scale: media.panelOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            // Centred under its trigger and clamped, computed from targetWidth
            // rather than from `width` -- see the note in Menus.qml, where a
            // width carrying its own Behavior placed the card against a stale
            // value on the first open.
            y: media.barHeight + (media.panelOpen ? 6 : -6)
            x: media.anchorX < 0
               ? parent.width - card.targetWidth - 6
               : Math.max(6, Math.min(parent.width - card.targetWidth - 6,
                                      media.anchorX - card.targetWidth / 2))
            Behavior on y { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }

            width: card.targetWidth
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
                    text: Strings.t.playback
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    leftPadding: 4
                }

                Text {
                    visible: !media.hasPlayer
                    width: parent.width
                    text: Strings.t.nothingPlaying
                    color: Theme.subtext
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    padding: 10
                }

                // ---- cover + track ----
                Row {
                    visible: media.hasPlayer
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: 72; height: 72
                        radius: 12
                        color: Qt.rgba(Theme.crust.r, Theme.crust.g, Theme.crust.b, 0.9)
                        clip: true

                        Image {
                            id: art
                            anchors.fill: parent
                            source: media.hasPlayer && media.player.trackArtUrl
                                    ? media.player.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            asynchronous: true
                            // Twice the drawn size; see #91 -- decoding cover
                            // art at its source resolution is pure waste.
                            sourceSize.width: 144
                            sourceSize.height: 144
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !art.visible
                            text: Theme.ico(0xf075a)
                            color: Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        width: parent.width - 84
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            text: media.hasPlayer ? (media.player.trackTitle || "—") : ""
                            color: Theme.text
                            font.family: Theme.uiFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: media.hasPlayer ? (media.player.trackArtist || "") : ""
                            color: Theme.subtext
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                        Text {
                            width: parent.width
                            text: media.hasPlayer ? (media.player.identity || "") : ""
                            color: Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                // ---- position ----
                Item {
                    visible: media.hasPlayer && media.player.lengthSupported
                    width: parent.width
                    height: 18

                    Rectangle {
                        id: track
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 4
                        radius: 2
                        color: Theme.surface1

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: Theme.mauve
                            width: {
                                if (!media.hasPlayer || !media.player.length) return 0;
                                const f = media.player.position / media.player.length;
                                return Math.max(0, Math.min(1, f)) * track.width;
                            }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.top: track.bottom
                        anchors.topMargin: 3
                        text: media.hasPlayer ? media.fmt(media.player.position) : ""
                        color: Theme.surface2
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.top: track.bottom
                        anchors.topMargin: 3
                        text: media.hasPlayer ? media.fmt(media.player.length) : ""
                        color: Theme.surface2
                        font.family: Theme.uiFont
                        font.pixelSize: 10
                    }
                }

                // ---- transport ----
                Row {
                    visible: media.hasPlayer
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    component Btn: Rectangle {
                        property int icon: 0
                        property bool enabled: true
                        signal pressed()
                        width: 40; height: 40
                        radius: 13
                        color: !enabled ? "transparent"
                             : (btnHover.hovered ? Theme.surface1
                                                 : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.9))
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: btnHover; enabled: parent.enabled }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.ico(parent.icon)
                            color: parent.enabled ? Theme.text : Theme.surface2
                            font.family: Theme.uiFont
                            font.pixelSize: 16
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.pressed()
                        }
                    }

                    Btn {
                        icon: 0xf04ae
                        enabled: media.hasPlayer && media.player.canGoPrevious
                        onPressed: media.player.previous()
                    }
                    Btn {
                        icon: media.hasPlayer && media.player.isPlaying ? 0xf03e4 : 0xf040a
                        enabled: media.hasPlayer && media.player.canTogglePlaying
                        onPressed: media.player.togglePlaying()
                    }
                    Btn {
                        icon: 0xf04ad
                        enabled: media.hasPlayer && media.player.canGoNext
                        onPressed: media.player.next()
                    }
                }
            }
        }
    }
}
