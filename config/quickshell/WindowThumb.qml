//  A live window thumbnail, or the app glyph if no live source can be found.
//
//  Backed by Quickshell.Wayland's ScreencopyView + ToplevelManager -- unlike
//  Quickshell.Hyprland (empty qmltypes, runtime-registered, unverifiable
//  before use), this module ships a real static qmltypes file, so the API
//  below is read from that file, not guessed.
//
//  MATCHING, NOT ADDRESSING: the toplevel-management protocol exposes appId
//  and title, never a Hyprland window address, so a hyprctl window (which is
//  what Overview and AltTab otherwise key everything by) is matched to a
//  Toplevel by (appId, title). Two windows of the same app sharing an exact
//  title -- two blank terminals, say -- are genuinely indistinguishable this
//  way, and the second one falls back to a wrong-but-plausible match rather
//  than none. That is an acceptable trade for not being able to switch to a
//  window at all, which is the only thing the address was ever used for here.
//
//  COST: `live` is bound to `active` by the caller, which in turn is bound to
//  the panel actually being open. A ScreencopyView with live=false does not
//  keep decoding frames -- this is what keeps Overview and AltTab at zero
//  extra GPU cost while closed, the exact concern that ruled thumbnails out
//  here originally.

import Quickshell
import Quickshell.Wayland
import QtQuick

Item {
    id: thumb

    required property string cls
    required property string winTitle
    property bool active: false
    property int fallbackIcon: 0xf0349
    property color fallbackColour: Theme.subtext
    property real radius: 8

    readonly property var matched: {
        const cl = (thumb.cls || "").toLowerCase();
        if (cl === "") return null;
        const list = ToplevelManager.toplevels.values;
        // Exact title match wins; otherwise the first window of the same app,
        // for the reason in the header comment above.
        let byClass = null;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if ((t.appId || "").toLowerCase() !== cl) continue;
            if (t.title === thumb.winTitle) return t;
            if (byClass === null) byClass = t;
        }
        return byClass;
    }

    Rectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: Theme.crust
        visible: !view.hasContent

        Text {
            anchors.centerIn: parent
            text: Theme.ico(thumb.fallbackIcon)
            color: thumb.fallbackColour
            font.family: Theme.uiFont
            font.pixelSize: Math.min(parent.width, parent.height) * 0.42
        }
    }

    Item {
        anchors.fill: parent
        clip: true

        ScreencopyView {
            id: view
            anchors.fill: parent
            captureSource: thumb.matched
            live: thumb.active && thumb.matched !== null
            paintCursor: false
            constraintSize: Qt.size(thumb.width, thumb.height)
        }
    }
}
