//  Makes an app's OWN titlebar minimize button do the same thing SUPER+H
//  does (hyprland.lua): stash the window on the hidden `special:minimized`
//  workspace, instead of nothing at all.
//
//  Hyprland has no event for a client's own minimize request -- checked by
//  probing `hl.on()`'s full event list (window.active, window.close,
//  window.fullscreen, workspace.created, ... 30 total): there is no
//  window.minimized among them. A window asking Hyprland to minimize itself
//  (its CSD titlebar's own "_" button, xdg_toplevel.set_minimized under the
//  hood) is a request Hyprland's compositor core does not act on and gives
//  nothing anywhere a chance to react to -- the window just stays exactly as
//  it was, which is what "minimize doesn't do anything" turned out to be.
//
//  Quickshell's own Wayland.ToplevelManager sees that SAME request through a
//  separate protocol (wlr-foreign-toplevel-management) that Hyprland does
//  implement enough of to report state through, even though it does not act
//  on it: Toplevel.minimized flips true the instant the app asks, with a
//  real minimizedChanged signal. That is the hook Hyprland itself doesn't
//  have. This watches every toplevel for that signal and, the moment one
//  flips minimized true, cancels the flag right back (Hyprland was never
//  going to do anything with it, and leaving it true would tell the app --
//  and anything else watching this protocol -- that it succeeded) and runs
//  the real minimize through hyprctl instead.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: mb

    Instantiator {
        model: ToplevelManager.toplevels

        // Scope, NOT QtObject: QtObject declares no default property, so the
        // nested Connections below (a plain child, no property name given)
        // fails to attach with "Cannot assign to non-existent default
        // property" -- caught live, this exact error, the first reload after
        // the file existed. Scope's default property is "children", same as
        // every other Instantiator delegate in this file's siblings.
        delegate: Scope {
            id: watcher
            required property var modelData

            Connections {
                target: watcher.modelData
                function onMinimizedChanged() {
                    if (!watcher.modelData.minimized) return;
                    // NOT .setMinimized(false) as a call: the qmltypes only
                    // lists setMinimized as the "minimized" property's WRITE
                    // accessor, not as an invokable Method -- calling it as a
                    // function throws "is not a function" the first time a
                    // real minimize request ever arrives. Plain property
                    // assignment goes through the same C++ setter.
                    watcher.modelData.minimized = false;
                    mb.pendingAppId = watcher.modelData.appId || "";
                    mb.pendingTitle = watcher.modelData.title || "";
                    lookup.running = true;
                }
            }
        }
    }

    property string pendingAppId: ""
    property string pendingTitle: ""

    // MATCHING, NOT ADDRESSING, same limitation and same fix as
    // WindowThumb.qml: the toplevel-management protocol exposes appId and
    // title, never a Hyprland window address, so the real hyprctl client has
    // to be found by comparing those -- mirrors hypr-launch's own
    // class/initialClass substring match (bin/hypr-launch), not
    // AppGrouping's GROUPED key, because this needs the exact window, not a
    // display stem.
    Process {
        id: lookup
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = [];
                try { clients = JSON.parse(this.text.trim()); } catch (e) { return; }

                const needle = mb.pendingAppId.toLowerCase();
                if (needle === "") return;

                let addr = null;
                for (const c of clients) {
                    if (!c.mapped) continue;
                    const cl = (c.class || "").toLowerCase();
                    const ic = (c.initialClass || "").toLowerCase();
                    if (cl !== needle && ic !== needle
                        && cl.indexOf(needle) === -1 && ic.indexOf(needle) === -1) continue;
                    if (c.title === mb.pendingTitle) { addr = c.address; break; }
                    if (addr === null) addr = c.address;
                }
                if (!addr) return;

                // Identical to the SUPER+H bind in hyprland.lua: move it in,
                // then check whether that left the special workspace visible
                // (it was already toggled on for some other reason) and close
                // it if so -- minimize must always make the window disappear,
                // regardless of what SUPER+SHIFT+H was left at.
                Quickshell.execDetached(["sh", "-c",
                    "hyprctl dispatch \"hl.dsp.window.move({ window = 'address:" + addr
                    + "', workspace = 'special:minimized', silent = true })\" && "
                    + "hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name == \"special:minimized\")' >/dev/null && "
                    + "hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"minimized\")'"
                ]);
            }
        }
    }
}
