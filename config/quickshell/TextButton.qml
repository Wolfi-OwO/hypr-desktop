//  Labelled button for the left-hand side of the bar ("Apps", "Places").
//  Its own file so both look and behave exactly alike.
//
//  As in Pill.qml, there is deliberately NO animation on a colour here.
//  A `Behavior on color` would sit on top of the theme animation when
//  switching between light and dark, and this button would lag behind every
//  other element. Hover feedback therefore runs on opacity: the surface fades
//  in, and the text is cross-faded between two labels stacked on top of each
//  other.

import QtQuick

Item {
    id: btn

    property string text: ""
    property bool   bold: false
    signal activated()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        color: Theme.surface1
        opacity: ma.containsMouse ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    // Resting state
    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: Theme.subtext
        font.family: Theme.uiFont
        font.pixelSize: 13
        font.weight: btn.bold ? Font.Bold : Font.DemiBold
    }

    // Highlighted — sits exactly on top of the label above and fades in.
    Text {
        anchors.centerIn: parent
        text: btn.text
        color: Theme.text
        font.family: Theme.uiFont
        font.pixelSize: 13
        font.weight: btn.bold ? Font.Bold : Font.DemiBold
        opacity: ma.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
