//  Alt+Tab switcher: application tiles with grouped windows behind them.
//
//  Behaviour:
//    Alt+Tab (1st tap)  open the overlay, highlight stays on the CURRENT app
//    Alt+Tab (further)  forward through the other applications
//    Alt+Shift+Tab      same, backward -- 1st tap also stays on the current app
//    release Alt        the highlighted application is raised
//    Enter              the same, without waiting for the release
//    click on a tile    switches there immediately
//    Escape             cancel
//    click beside it    cancel
//    Down arrow         expand the grouped windows of an application
//    Left/Right         choose among the expanded windows, most recently used first
//
//  Windows of the same application are collapsed into one tile; an arrow below
//  the tile shows that there is more than one window behind it. Not GNOME
//  parity any more: GNOME's first press already jumps to the most recently
//  used app, which the user explicitly did not want here -- see the
//  `pendingStep` handling below for why that costs an extra tap to reach it.
//
//  The release of Alt does NOT come from Hyprland. A `bindr` on Alt_L never
//  fires there -- Alt_L is processed as a modifier and does not appear in the
//  bind system as a key event of its own. Instead the overlay takes the
//  keyboard focus and evaluates the events itself; details in the PanelWindow
//  further down.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: at

    property bool shown: false
    onShownChanged: {
        if (at.shown) Exclusivity.claim("alttab");
        else Exclusivity.release("alttab");
    }
    Connections {
        target: Exclusivity
        function onOwnerChanged() {
            if (Exclusivity.owner !== "alttab" && at.shown) at.shown = false;
        }
    }
    property int index: 0
    property int subIndex: -1        // -1 = the group, otherwise a window in it
    property var groups: []          // [{ key, name, icon, windows:[...] }]

    // Direction of the first key press while the window list is still loading.
    // `hyprctl clients` runs asynchronously, so step() always used to see the
    // list from the PREVIOUS call -- on the first Alt+Tab none at all, and a
    // stale one after that. The step is now replayed as soon as the data has
    // actually arrived.
    property int pendingStep: 0

    IpcHandler {
        target: "alttab"
        function next(): void   { at.step(1); }
        function prev(): void   { at.step(-1); }
        function expand(): void { at.toggleExpand(); }
        function left(): void   { at.stepSub(-1); }
        function right(): void  { at.stepSub(1); }
        function commit(): void { at.confirm(); }
        function cancel(): void { at.cancel(); }
    }

    Process {
        id: load
        command: ["sh", "-c",
            "hyprctl clients -j | jq -c '" +
            "[ .[] | select(.mapped == true) " +
            "  | select((.class // \"\") != \"\") " +
            "  | { class, title, address, ws: .workspace.name, fh: .focusHistoryID } ] " +
            "| sort_by(.fh)'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let wins = [];
                try { wins = JSON.parse(this.text.trim()); } catch (e) { wins = []; }

                // Collapse windows of the same application. Brave reports a
                // separate class per PWA (brave-mjoklpl...), so shorten to the
                // stem. Shared with WindowThumb's match, in AppGrouping.qml --
                // it used to be a local copy here that WindowThumb's strict
                // equality check against the RAW appId could never satisfy,
                // so grouped tiles never got a live thumbnail at all.
                const norm = AppGrouping.norm;

                // Display name from the normalised key, not from the raw
                // window class: Brave reports something like
                // "brave-ejjefgnohzmgkmkilnr..." per PWA, and that used to be
                // the caption under the tile.
                const PRETTY = {
                    brave: "Brave", chromium: "Chromium", code: "VS Code",
                    jetbrains: "JetBrains", kitty: "Terminal",
                    nautilus: Strings.t.appFiles, org: "System"
                };
                const pretty = k => PRETTY[k]
                    || k.split(/[-_.]/)[0].replace(/^./, c => c.toUpperCase());

                const byKey = {};
                const order = [];
                for (const w of wins) {
                    const k = norm(w.class);
                    if (!byKey[k]) { byKey[k] = { key: k, name: pretty(k), windows: [] }; order.push(k); }
                    byKey[k].windows.push(w);
                }

                // `windows` keeps the fh order `wins` arrived in (most
                // recently focused first) -- that is what the Down-arrow
                // expanded row wants: pick one of this app's windows, most
                // recently used first. `canonical` is a SEPARATE field for
                // the other two readers -- confirm() with nothing expanded,
                // and the main tile's WindowThumb/caption -- which both want
                // "the app", not "whichever window of it was touched last".
                //
                // Brave/Chromium report one class per PWA -- a hash-suffixed
                // variant of the base "brave-browser"/"chromium" class -- and
                // norm() above folds all of them into one group. Without this
                // split, a Brave PWA focused more recently than the actual
                // browser became windows[0] and both readers used it --
                // measured with hyprctl -j activewindow before/after a real
                // commit: releasing Alt on the tile captioned "Brave" focused
                // the PWA, not the browser. Reordering `windows` itself fixed
                // that but broke the expanded row's MRU order, a second, real
                // requirement -- hence two fields instead of one array
                // serving both.
                // ponytail: string-length is a proxy for "base app vs. PWA
                // derivative", not a real check -- correct as long as PWA
                // classes stay longer than the class they derive from (true
                // for Brave/Chromium now). If another app needs the same
                // distinction under a class scheme where that stops holding,
                // replace this with an explicit AppGrouping.isCanonical(cls)
                // instead of guessing from length.
                for (const k of order) {
                    byKey[k].canonical = byKey[k].windows.reduce(
                        (a, b) => b.class.length < a.class.length ? b : a);
                }

                at.groups = order.map(k => byKey[k]);
                if (at.index >= at.groups.length) at.index = 0;

                // Replay any presses that queued up WHILE this load was in
                // flight (see the `load.running` branch in step()). The very
                // first press that opens the overlay does not go through
                // here at all any more -- step() now leaves it out of
                // `pendingStep` on purpose, so index 0 (the currently focused
                // application) survives untouched. Deliberate departure from
                // GNOME's "first press already jumps to the MRU app": the
                // user asked for the highlight to start on the app already
                // focused and only move on a press after that.
                if (at.pendingStep !== 0 && at.groups.length > 0) {
                    const d = at.pendingStep;
                    const n = at.groups.length;
                    at.index = ((d % n) + n) % n;
                }
                at.pendingStep = 0;
            }
        }
    }

    function step(dir) {
        stuckGuard.restart();
        if (!at.shown) {
            at.shown = true;
            at.index = 0;
            at.subIndex = -1;
            // Drop the previous session's tiles rather than leaving them
            // displayed while the fresh list loads -- Alt+Tab is bound
            // through Hyprland's `bind` (fires once per keypress, not held),
            // so each press re-runs `hyprctl clients | jq`. Leaving the last
            // session's groups around let that stale list render, and its
            // group order/positions rarely match the fresh one -- THAT was
            // the "twitches / jumps over Brave" report: a flash of the wrong
            // tile before the real data replaced it a few ms later.
            at.groups = [];
            // Not `dir`: the press that OPENS the overlay must land on
            // index 0 (the current application), not step away from it --
            // see the reasoning in onStreamFinished. `dir` is deliberately
            // dropped here; only presses that queue up below, while the
            // list is still loading, accumulate into pendingStep.
            at.pendingStep = 0;
            load.running = true;
            return;
        }
        if (load.running) {
            // The fetch from opening the overlay hasn't come back yet.
            // Pressing Tab again in this window used to either do nothing
            // (groups still empty) or step through the just-cleared/stale
            // array, corrupting `index` before onStreamFinished had a
            // chance to apply pendingStep to it -- a second real keypress
            // could get silently dropped or land on the wrong tile
            // depending on how fast `hyprctl clients | jq` happened to run
            // (a whole process pipeline, not free) relative to it. Queue it
            // instead; it's applied together with the opening step once the
            // fresh list is in.
            at.pendingStep += dir;
            return;
        }
        if (at.groups.length === 0) return;
        at.index = ((at.index + dir) % at.groups.length + at.groups.length) % at.groups.length;
        at.subIndex = -1;
    }

    // Emergency brake: under no circumstances may the overlay stay up
    // permanently. If nothing happens for 4 seconds, the current selection is
    // committed and the overlay closes.
    Timer {
        id: stuckGuard
        interval: 4000
        repeat: false
        onTriggered: if (at.shown) at.confirm()
    }

    function toggleExpand() {
        if (!at.shown) return;
        const g = at.groups[at.index];
        if (!g || g.windows.length < 2) return;
        at.subIndex = at.subIndex === -1 ? 0 : -1;
    }

    function stepSub(dir) {
        if (!at.shown || at.subIndex === -1) { at.step(dir); return; }
        const g = at.groups[at.index];
        if (!g) return;
        at.subIndex = ((at.subIndex + dir) % g.windows.length + g.windows.length) % g.windows.length;
    }

    function cancel() {
        stuckGuard.stop();
        at.shown = false;
        at.subIndex = -1;
        at.pendingStep = 0;
    }

    function confirm() {
        stuckGuard.stop();
        if (!at.shown) return;
        const g = at.groups[at.index];
        at.shown = false;
        const sub = at.subIndex;
        at.subIndex = -1;
        at.pendingStep = 0;
        if (!g) return;
        // Nothing expanded -> the canonical (base-app) window, never a PWA.
        // A specific sub-window was picked -> exactly that one, from the
        // same MRU-ordered `windows` array the expanded row displays, so
        // `sub` always indexes the window the user actually saw highlighted.
        const w = sub === -1 ? g.canonical : g.windows[sub];
        // Cheap and permanent: the group-vs-chosen mismatch that caused the
        // "Alt+Tab can't reach Brave" report only showed up by comparing this
        // line against `hyprctl -j activewindow` after the fact. Left in so
        // a future recurrence is diagnosable from `qs log` alone.
        console.log("alttab confirm: group=" + g.key + " windows=" +
                     JSON.stringify(g.windows.map(x => x.address + "/" + x.ws)) +
                     " canonical=" + (g.canonical ? g.canonical.address : "none") +
                     " chosen=" + (w ? w.address + "/" + w.ws : "none"));
        if (!w) return;
        // Through hypr-focus-window, NOT a raw focuswindow of our own. The
        // candidate query above deliberately has no workspace filter, so a
        // minimized app is still an Alt+Tab tile -- and focusing one directly
        // did not switch to it, it opened the special:minimized stash over the
        // current workspace, which then followed the user across workspaces.
        // Measured; the helper carries the numbers. One owner for focus.
        //
        // argv form, no sh -c: nothing window-derived is interpolated into a
        // shell command.
        Quickshell.execDetached(["hypr-focus-window", w.address]);
    }

    function iconFor(cls) {
        const c = (cls || "").toLowerCase();
        if (c.indexOf("kitty") === 0 || c.indexOf("alacritty") === 0) return 0xf018d;
        if (c.indexOf("brave") === 0 || c.indexOf("chrom") === 0 || c.indexOf("firefox") === 0) return 0xf059f;
        if (c.indexOf("code") === 0 || c.indexOf("jetbrains") !== -1) return 0xf0169;
        if (c.indexOf("nautilus") !== -1) return 0xf0770;
        if (c.indexOf("discord") !== -1 || c.indexOf("teams") !== -1) return 0xf0b79;
        if (c.indexOf("outlook") !== -1 || c.indexOf("mail") !== -1) return 0xf01f0;
        return 0xf0349;
    }

    // =======================================================================
    PanelWindow {
        id: panel
        visible: at.shown

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-alttab"
        // While the overlay is up it takes the keyboard focus. That is the
        // only way it sees Alt being RELEASED.
        //
        // Going through Hyprland (a `bindr` on Alt_L) does not work here:
        // Alt_L is processed as a modifier and never shows up in the bind
        // system as a key event of its own. With the modifier in the bind
        // (modmask 8) it never fired, because the ALT bit is already cleared on
        // release -- and without the modifier it did not fire either. The
        // overlay therefore stayed up until the emergency brake hit.
        WlrLayershell.keyboardFocus: at.shown ? WlrKeyboardFocus.Exclusive
                                              : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        anchors { top: true; left: true; right: true; bottom: true }

        // Keyboard. ALL navigation lives HERE, not in the Hyprland binds.
        //
        // Measured: as long as this overlay holds the exclusive keyboard
        // focus, Hyprland binds stop firing entirely. The test -- open the
        // overlay, then send CTRL+ALT+Right with wtype: the workspace did not
        // change. That is exactly why "Down arrow" did nothing even though the
        // bind existed and the IPC function worked perfectly.
        //
        // Because binds do not arrive here, handling Tab cannot double-count
        // either. The binds in hyprland.lua now only serve to OPEN the overlay,
        // while it is not yet up.
        Item {
            id: keys
            anchors.fill: parent
            focus: at.shown

            Keys.onReleased: function (e) {
                if (e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) {
                    at.confirm();
                    e.accepted = true;
                }
            }
            Keys.onPressed: function (e) {
                switch (e.key) {
                case Qt.Key_Escape:
                    at.cancel(); break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    at.confirm(); break;
                case Qt.Key_Tab:
                case Qt.Key_Backtab:
                    // Backtab is Shift+Tab, but some layouts report plain Tab
                    // with the Shift modifier set.
                    at.step((e.key === Qt.Key_Backtab
                             || (e.modifiers & Qt.ShiftModifier)) ? -1 : 1);
                    break;
                case Qt.Key_Down:
                    at.toggleExpand(); break;
                case Qt.Key_Up:
                    if (at.subIndex !== -1) at.subIndex = -1;
                    break;
                case Qt.Key_Left:
                    at.stepSub(-1); break;
                case Qt.Key_Right:
                    at.stepSub(1); break;
                default:
                    return;     // do not claim what is none of our business
                }
                e.accepted = true;
            }
        }

        // A click anywhere beside it cancels, as in every other menu.
        MouseArea {
            anchors.fill: parent
            onClicked: at.cancel()
        }

        Rectangle {
            id: panelBox
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, Math.max(260, row.implicitWidth + 40))
            // The height follows the application tiles ONLY. The expanded
            // windows deliberately sit outside this frame; see below.
            height: row.implicitHeight + 40 + (hintText.visible ? hintText.height + 14 : 0)
            radius: 24
            color: Qt.rgba(Theme.mantle.r, Theme.mantle.g, Theme.mantle.b, 0.96)
            border.width: 2
            border.color: Theme.surface1

            opacity: at.shown ? 1 : 0
            scale: at.shown ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            Column {
                anchors.centerIn: parent
                spacing: 14

                // ---- application tiles ----
                // Grid rather than Row: as a Row the line grew to the right
                // without limit while the frame was capped at parent.width - 80
                // -- the outermost tiles then visibly stuck out past the edge.
                // Now it wraps and the frame grows downwards with it.
                Grid {
                    id: row
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    readonly property int cell: 150 + spacing
                    columns: Math.max(1, Math.min(at.groups.length,
                                 Math.floor((panel.width - 120 + spacing) / cell)))

                    Repeater {
                        model: at.groups
                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            width: 150; height: 150
                            radius: 22
                            // The currently selected tile is set off in colour,
                            // so it is clear what will be raised on release.
                            color: index === at.index ? Theme.mauve
                                 : Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.85)
                            border.width: index === at.index ? 2 : 1
                            border.color: index === at.index ? Theme.lavender : Theme.surface0
                            Behavior on color { ColorAnimation { duration: 90 } }

                            // Live thumbnail of the group's first/active
                            // window, underneath everything else. `active` is
                            // tied to the overlay being shown at all, not to
                            // being the selected tile -- Alt+Tab is a rapid
                            // keyboard cycle (see the header comment: no
                            // animation on the cycle itself), and re-starting
                            // a capture stream on every step would show a
                            // blank tile for a frame each time instead of
                            // already having the picture.
                            WindowThumb {
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                radius: 20
                                cls: modelData.key
                                winTitle: modelData.canonical ? modelData.canonical.title : ""
                                active: at.shown
                                fallbackIcon: at.iconFor(modelData.key)
                                // Always readable: the tile behind it is
                                // Theme.crust regardless of selection (the
                                // border carries the selected look), so tying
                                // this to `index === at.index` used to put
                                // Theme.crust text on a Theme.crust tile --
                                // invisible on exactly the selected tile,
                                // which is what made the Brave group look
                                // like a dead black square.
                                fallbackColour: Theme.text
                            }

                            // Name scrim at the bottom, over the thumbnail.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: parent.border.width
                                height: 28
                                radius: 20
                                color: index === at.index
                                       ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.9)
                                       : Qt.rgba(0, 0, 0, 0.55)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: parent.radius
                                    color: parent.color
                                }
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 14
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.name
                                    color: index === at.index ? Theme.crust : "white"
                                    font.family: Theme.uiFont
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            // Arrow when more than one window is behind it
                            Text {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 7
                                visible: modelData.windows.length > 1
                                text: Theme.ico(0xf0140) + " " + modelData.windows.length
                                color: index === at.index ? Theme.crust : "white"
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                style: Text.Outline
                                styleColor: Qt.rgba(0, 0, 0, 0.5)
                            }

                            // With the mouse: hovering selects, clicking
                            // switches immediately and closes the overlay.
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: { at.index = index; at.subIndex = -1; }
                                onClicked: at.confirm()
                            }
                        }
                    }

                    Text {
                        visible: at.groups.length === 0
                        text: Strings.t.noWindows
                        color: Theme.subtext
                        font.family: Theme.uiFont
                        font.pixelSize: 13
                    }
                }

                Text {
                    id: hintText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: at.groups.length > 0 &&
                             at.groups[at.index] &&
                             at.groups[at.index].windows.length > 1 &&
                             at.subIndex === -1
                    text: Theme.ico(0xf0140) + "  " + Strings.t.altTabHint
                    color: Theme.surface2
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }
            }
        }

        // ---- expanded windows of one application -------------------------
        //
        // Deliberately OUTSIDE the frame: they used to sit inside the panel and
        // made it grow downwards, which made them look like part of the tile.
        // Now they float below it as elements of their own -- each with its own
        // border and its own shadow, so the grouping comes from position rather
        // than from a shared frame.
        Grid {
            id: subRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: panelBox.bottom
            anchors.topMargin: 16
            spacing: 14
            visible: at.subIndex !== -1 && at.groups.length > 0

            readonly property int cell: 220 + spacing
            readonly property int count: (at.subIndex !== -1 && at.groups[at.index])
                                         ? at.groups[at.index].windows.length : 0
            columns: Math.max(1, Math.min(count,
                         Math.floor((panel.width - 120 + spacing) / cell)))

            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

            Repeater {
                model: subRow.visible && at.groups[at.index]
                       ? at.groups[at.index].windows : []

                // Item rather than Rectangle: it holds the shadow and the tile
                // getrennt uebereinander.
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool picked: index === at.subIndex

                    width: 220; height: 140

                    // Drop shadow. Not DropShadow from Qt5Compat: that would be
                    // an extra dependency for an effect a slightly offset, soft
                    // rectangle delivers just as well.
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 2
                        anchors.leftMargin: 1
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0.35)
                    }

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        radius: 16
                        color: Theme.crust
                        border.width: parent.picked ? 2 : 1
                        border.color: parent.picked ? Theme.mauve : Theme.surface1
                        Behavior on border.color { ColorAnimation { duration: 90 } }

                        WindowThumb {
                            anchors.fill: parent
                            anchors.margins: tile.border.width
                            radius: 14
                            // Same app for every tile in this row, so the
                            // group's own key is the class; only the title
                            // distinguishes one window from the next.
                            cls: at.groups[at.index] ? at.groups[at.index].key : ""
                            winTitle: modelData.title
                            active: at.shown && at.subIndex !== -1
                            fallbackIcon: at.iconFor(cls)
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: tile.border.width
                            height: 26
                            radius: 14
                            color: parent.picked
                                   ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.9)
                                   : Qt.rgba(0, 0, 0, 0.55)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: parent.radius
                                color: parent.color
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 14
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.title
                                color: "white"
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: at.subIndex = index
                        onClicked: at.confirm()
                    }
                }
            }
        }
    }
}
