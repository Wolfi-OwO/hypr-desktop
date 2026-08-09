pragma Singleton

//  Makes sure only one overlay ever holds exclusive keyboard focus.
//
//  WHY THIS EXISTS
//  ---------------
//  Nothing closed a panel when another one opened -- notifCentre.panelOpen,
//  quickSettings.panelOpen, menus.active, controls.active, altTab.shown,
//  sunsetSchedule.panelOpen, clipboard.panelOpen, mediaPanel.panelOpen,
//  overview.panelOpen were all independent booleans. Two of them could be
//  true at once, and each one individually requests
//  WlrKeyboardFocus.Exclusive while open. With two surfaces both holding an
//  exclusive keyboard grab, a single Escape press was not going to one --
//  it was reaching both, so both closed. That is what "pressing Escape
//  closes everything" actually was: not one Escape handler misfiring, but
//  two live at once.
//
//  One flag, set by whichever panel opened last. Every panel closes itself
//  the moment it is no longer that flag's value.

import Quickshell.Io
import QtQuick

QtObject {
    id: excl

    property string owner: ""

    function claim(name) {
        excl.owner = name;
    }

    function release(name) {
        if (excl.owner === name) excl.owner = "";
    }

    // For external tools (hypr-screenshot: slurp/swappy need the keyboard
    // themselves, and a panel left open behind them was fighting them for it).
    property var ipc: IpcHandler {
        target: "panels"
        function closeAll(): void { excl.owner = ""; }
    }
}
