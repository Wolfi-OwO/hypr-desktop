pragma Singleton

//  One connection to the event broker, for the whole shell.
//
//  WHY THIS EXISTS
//  ---------------
//  Six files each spawned their own `mosquitto_sub`, so the shell ran seven
//  subscriber processes against one broker. Measured: 7.2 MB of PSS and seven
//  broker connections to carry a few hundred bytes a second.
//
//  Worse than the cost was the duplication. `hypr/theme` was subscribed twice
//  and `hypr/battery` twice, so those payloads were parsed and applied twice
//  per message by two different files, each unaware of the other.
//
//  And each of the seven carried its own copy of a reconnect Timer, because
//  Quickshell does not restart a Process that exits. That reconnect racing
//  shell teardown is what stranded mosquitto_sub processes on init: `pkill` took
//  the parent, and a subscriber that happened to be mid-restart was re-exec'd
//  after its parent was gone. Three were found orphaned after a single restart.
//
//  One subscription over `hypr/#` replaces all of it. `-v` prefixes each line
//  with its topic, which is what makes a single stream demultiplexable.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: bus

    // Last payload seen per topic, already parsed. Consumers bind to these
    // rather than parsing anything themselves.
    property var state:      ({})
    property var audio:      ({})
    property var brightness: ({})
    property var bluetooth:  ({})
    property var battery:    ({})
    property var system:     ({})
    property var network:    ({})
    property var power:      ({})
    property var theme:      ({})
    property var weather:    ({})
    property var apps:       ({})

    // Emitted for every message, after the matching property is updated. For
    // consumers that need to act on arrival rather than on a value changing --
    // a payload identical to the previous one produces no property change but
    // is still a real event.
    signal message(string topic, var data)

    Process {
        id: sub
        running: true

        // `hypr/#` is every topic under hypr/ in ONE subscription. -v prefixes
        // each line with the topic name, without which a single stream could
        // not be told apart. -q 0 matches the publisher: these are current-state
        // messages, and a redelivered stale one is worse than a dropped one.
        command: ["mosquitto_sub",
                  "--unix", "/run/user/1000/mosquitto.sock",
                  "-t", "hypr/#",
                  "-v", "-q", "0"]

        // A subscription that exits must come back: Quickshell does not restart
        // a Process on its own, so when the broker restarts -- or when the shell
        // simply wins the race against it at login -- the subscription stays
        // dead for the rest of the session. The panels then show their last
        // received values forever with no error anywhere.
        onExited: reconnect.start()

        stdout: SplitParser {
            onRead: function (line) {
                const s = line.trim();
                const sp = s.indexOf(" ");
                if (sp <= 0) return;

                const topic = s.substring(0, sp);
                const rest  = s.substring(sp + 1);

                let d;
                try {
                    d = JSON.parse(rest);
                } catch (e) {
                    return;         // keep whatever is already displayed
                }

                switch (topic) {
                case "hypr/state":      bus.state = d;      break;
                case "hypr/audio":      bus.audio = d;      break;
                case "hypr/brightness": bus.brightness = d; break;
                case "hypr/bluetooth":  bus.bluetooth = d;  break;
                case "hypr/battery":    bus.battery = d;    break;
                case "hypr/system":     bus.system = d;     break;
                case "hypr/network":    bus.network = d;    break;
                case "hypr/power":      bus.power = d;      break;
                case "hypr/theme":      bus.theme = d;      break;
                case "hypr/weather":    bus.weather = d;    break;
                case "hypr/apps":       bus.apps = d;       break;
                default: break;
                }

                bus.message(topic, d);
            }
        }
    }

    Timer {
        id: reconnect
        interval: 1000
        repeat: false
        onTriggered: sub.running = true
    }
}
