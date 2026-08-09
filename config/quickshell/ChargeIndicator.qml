//  Brief overlay when the laptop starts charging.
//
//  Bus.battery already carries { batt, battState, etaMin } live off the MQTT
//  topic (see Bus.qml and hypr-eventd's battery()) -- this was sitting there
//  unused for anything but the bar pill and Quick Settings. Plugging in gave
//  no feedback beyond that pill's icon quietly changing colour, which is easy
//  to miss. This mirrors what a phone does when you plug it in: centred on
//  screen, the fill and the percentage count up together over a couple of
//  seconds, the estimated charge time lands under it, and the whole thing
//  disappears on its own a few seconds later.
//
//  Only fires on a genuine transition into "Charging" -- not on every
//  battery reading while already plugged in, and not just because the shell
//  happened to start while the charger was already connected.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: chg

    // "" means "no reading yet" -- distinct from any real battState, so the
    // very first message the shell ever sees cannot look like a transition.
    property string prevState: ""
    property int    shownPct: 0
    property var    shownEta: null
    property bool   show: false

    Connections {
        target: Bus
        function onBatteryChanged() {
            const s = Bus.battery.battState;
            const p = Bus.battery.batt;
            const e = Bus.battery.etaMin;
            if (s === "Charging" && chg.prevState !== "" && chg.prevState !== "Charging")
                chg.trigger(p !== undefined ? p : 0, e !== undefined ? e : null);
            chg.prevState = s;
        }
    }

    // There is no way to actually unplug and replug a laptop on demand, so
    // this is what verification runs through:
    // `qs ipc call charge test 63 75`  (percent, eta minutes -- eta optional)
    IpcHandler {
        target: "charge"
        function test(pct: int, etaMin: int): void {
            chg.trigger(pct, etaMin > 0 ? etaMin : null);
        }
    }

    function trigger(pct, etaMin) {
        chg.shownPct = pct;
        chg.shownEta = etaMin;
        // Force a real false->true edge even if a previous animation is
        // still showing, so replugging quickly restarts it cleanly instead
        // of being a no-op against an already-true `show`.
        chg.show = false;
        restartTimer.start();
    }

    // "Noch 1 Std 15 Min" / "Noch 40 Min" -- omitted entirely when the kernel
    // has not settled on a power reading yet (etaMin null right after plug-in).
    function etaLabel(min) {
        if (min === null || min === undefined) return "";
        if (min < 60) return "Noch " + min + " Min";
        const h = Math.floor(min / 60), m = min % 60;
        return "Noch " + h + " Std" + (m > 0 ? " " + m + " Min" : "");
    }

    Timer {
        id: restartTimer
        interval: 1
        onTriggered: chg.show = true
    }

    // Fill takes ~2 s (fillAnim below) plus this hold, so the card is never
    // dismissed mid-count -- then a further ~350 ms to fade out, landing on
    // the same 3-4 s a phone's plug-in animation stays up for.
    Timer {
        id: hideTimer
        interval: 3700
        running: chg.show
        onTriggered: chg.show = false
    }

    PanelWindow {
        id: panel
        visible: chg.show || card.opacity > 0.01

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-charge-indicator"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        Rectangle {
            id: card
            readonly property int animMs: 380
            property real animPct: 0

            // Centred on screen, phone-style, rather than dropping from the
            // bar like a toast -- this is a celebratory one-off, not routine
            // notification chrome, and reads better as its own moment.
            anchors.centerIn: parent
            width: 196
            // Grows from the content itself instead of a guessed constant:
            // a fixed height here previously ran a few px short and let the
            // eta line overlap the percentage instead of sitting under it.
            height: subtitle.y + subtitle.height + 22
            radius: 28

            opacity: chg.show ? 1 : 0
            scale: chg.show ? 1 : 0.85
            // OutBack gives the pop-in a slight overshoot rather than a flat
            // ease -- the "nicely animated" ask, and the same trick phones'
            // own charge animations use to feel alive rather than mechanical.
            Behavior on opacity { NumberAnimation { duration: card.animMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: card.animMs; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.98)
            border.width: 2
            border.color: Theme.surface1

            // Counts up in step with the fill -- both driven off the same
            // animated value, so they can never drift apart the way two
            // separately-timed animations could. 1-3 s, per spec: 2 s.
            NumberAnimation {
                target: card
                property: "animPct"
                from: 0
                to: chg.shownPct
                duration: 2000
                easing.type: Easing.OutCubic
                running: chg.show
            }

            // ---- battery outline -------------------------------------
            Item {
                id: battOutline
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 26
                width: 64; height: 98

                Rectangle {
                    id: nub
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 24; height: 7
                    radius: 3
                    color: Theme.surface2
                }
                Rectangle {
                    id: body
                    anchors.top: nub.bottom
                    anchors.topMargin: 2
                    width: parent.width
                    height: parent.height - nub.height - 2
                    radius: 11
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.surface2
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        height: (body.height - 8) * (card.animPct / 100)
                        radius: 6
                        color: Theme.green
                    }

                    // Small charging bolt, sitting on top of the fill -- the
                    // same glyph the bar and Quick Settings already use for
                    // "Charging" (0xf0084), so the icon language matches.
                    // Pulses gently while the card is up: a subtle "still
                    // charging" heartbeat rather than a static glyph.
                    Text {
                        id: bolt
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xf0084)
                        font.family: Theme.uiFont
                        font.pixelSize: 21
                        color: Theme.crust

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: chg.show
                            NumberAnimation { from: 0.7; to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 1.0; to: 0.7; duration: 1000; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }

            Text {
                id: pct
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: battOutline.bottom
                anchors.topMargin: 14
                text: Math.round(card.animPct) + "%"
                color: Theme.text
                font.family: Theme.uiFont
                font.pixelSize: 22
                font.weight: Font.Bold
            }

            Text {
                id: subtitle
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: pct.bottom
                anchors.topMargin: 4
                text: chg.etaLabel(chg.shownEta) || "Wird geladen"
                color: Theme.subtext
                font.family: Theme.uiFont
                font.pixelSize: 12
            }
        }
    }
}
