//  Rounded group on the right-hand side of the bar.
//
//  The pill deliberately keeps air above and below it inside the 40 px bar
//  (40 - 2*7 = 26 px), so it reads as an element of its own rather than as a
//  band running the full height.
//
//  Three modes, depending on which property is set:
//
//    content   a single piece of text, or a single glyph
//    items     icon and value pairs (battery 83 %, 57 C ...); the whole pill
//              is ONE click target and lights up as a single surface
//    icons     several individually clickable icons; here only the icon under
//              the pointer lights up
//
//  -------------------------------------------------------------------------
//  IMPORTANT: there is deliberately NO `Behavior on color` here.
//
//  Every surface used to carry its own colour animation (80 ms here, 90 ms on
//  the workspaces, 120 ms on the icons). It was meant as hover feedback -- but
//  it fired on the light/dark switch just the same, and then ran ON TOP OF the
//  theme animation. Each island therefore took a different amount of time and
//  they visibly arrived one after another instead of together.
//
//  The theme colours are bound directly for that reason -- Theme already
//  animates them, for everything at once, from a single source. Hover feedback
//  lives in a separate surface instead, of which only the OPACITY is animated.
//  Opacity and colour do not interfere with each other.

import QtQuick

Item {
    id: pill

    property string content: ""
    property var    items: []
    property var    icons: []
    property bool   mono: false
    // Diagonal stroke across the content -- for "do not disturb".
    property bool   strike: false
    property int    pixel: 13
    property color  colour: Theme.text

    signal activated()

    // The list is not set yet the first time the binding is evaluated, hence
    // the undefined check -- without it this throws "Cannot read property
    // 'length' of undefined".
    readonly property bool perIcon: pill.icons !== undefined
                                    && pill.icons.length > 0

    implicitWidth: body.implicitWidth + 16
    implicitHeight: 40

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 10
        height: 26
        radius: 13
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.75)
        border.width: 1
        border.color: Qt.rgba(Theme.surface0.r, Theme.surface0.g,
                              Theme.surface0.b, 0.7)

        // Hover surface for the WHOLE pill. Only the opacity is animated.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.surface1
            opacity: (!pill.perIcon && groupMa.containsMouse) ? 0.85 : 0
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }

        Row {
            id: body
            anchors.centerIn: parent
            spacing: 0

            // ---- single content ----
            Text {
                visible: pill.content.length > 0
                text: pill.content
                color: pill.colour
                // Monospaced, so every glyph gets the same advance width.
                // Without it, glyphs with a narrow counter sat visibly off the
                // centre of their cell.
                font.family: pill.mono ? "Symbols Nerd Font Mono" : Theme.uiFont
                font.pixelSize: pill.pixel
                font.weight: Font.DemiBold
                leftPadding: 8
                rightPadding: 8
            }

            // ---- strike-through ----
            // A surface of its own rather than a different glyph: that keeps
            // it the same bell, only struck through, and does not make the
            // whole thing depend on a second glyph existing in the font.

            // ---- icon and value ----
            Repeater {
                model: pill.items
                delegate: Row {
                    required property var modelData
                    spacing: 5
                    leftPadding: 8
                    rightPadding: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.ico(modelData.ico)
                        color: modelData.col
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (modelData.txt || "").length > 0
                        text: modelData.txt || ""
                        color: modelData.col
                        font.family: Theme.uiFont
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
            }

            // ---- individually clickable icons ----
            Repeater {
                model: pill.icons
                delegate: Item {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Theme.surface1
                        opacity: iconMa.containsMouse ? 0.85 : 0
                        Behavior on opacity { NumberAnimation { duration: 80 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Theme.ico(modelData.ico)
                        color: modelData.col
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: iconMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (modelData.act) modelData.act()
                    }
                }
            }
        }
    }

    Rectangle {
        visible: pill.strike
        anchors.centerIn: parent
        width: 21
        height: 2
        radius: 1
        rotation: -30
        color: pill.colour
    }

    // One click target for the whole pill -- only when the icons are not
    // meant to respond individually.
    MouseArea {
        id: groupMa
        anchors.fill: parent
        enabled: !pill.perIcon
        hoverEnabled: !pill.perIcon
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.activated()
    }
}
