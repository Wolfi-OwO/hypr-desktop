pragma Singleton

//  One calendar source for the whole shell.
//
//  WHY THIS EXISTS
//  ---------------
//  There were two calendars and only one of them had any data.
//
//  The desktop widget in shell.qml loads events per month by running
//  hypr-calendar, guards against out-of-order answers, and draws event dots.
//  The calendar in the notification centre had NO data source at all -- no
//  Process, no cache read, nothing. Its month arrows re-rendered the numbers
//  and an event could never appear on it, however long you waited. That is why
//  it looked broken: it was decorative.
//
//  Rather than give the notification centre a second loader -- a second
//  process, a second cache reader, and two months of state that can disagree
//  with each other -- both now read from here. One fetch, one cache, one answer.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: cal

    // The month currently being displayed, as a year and a 0-based month, so
    // it matches JavaScript's Date.getMonth().
    property int year:  new Date().getFullYear()
    property int month: new Date().getMonth()

    // Events for the loaded month, keyed "YYYY-MM-DD".
    property var days: ({})

    // True while hypr-calendar is still refreshing behind a cached answer. The
    // script returns the cache immediately and refetches in the background, so
    // this distinguishes "no events" from "not fetched yet".
    property bool loading: false

    function pad(n) { return n < 10 ? "0" + n : String(n); }

    function dayKey(d) {
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }
    function todayKey() { return dayKey(new Date()); }

    function eventsFor(key) {
        const e = cal.days[key];
        return e === undefined ? [] : e;
    }

    // Move by whole months, rolling the year over. Callers must not do this
    // arithmetic themselves -- getting December wrong is how a calendar ends up
    // requesting month 12 of the wrong year.
    function shiftMonth(dir) {
        let m = cal.month + dir, y = cal.year;
        if (m < 0)       { m = 11; y -= 1; }
        else if (m > 11) { m = 0;  y += 1; }
        cal.year = y; cal.month = m;
        load();
    }

    function goToday() {
        const n = new Date();
        cal.year = n.getFullYear();
        cal.month = n.getMonth();
        load();
    }

    function load() {
        proc.command = ["/home/woofi/.local/bin/hypr-calendar",
                        String(cal.year), String(cal.month + 1)];
        proc.running = true;
    }

    Component.onCompleted: cal.load()

    Process {
        id: proc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text.trim());
                    // Only accept an answer that belongs to the month currently
                    // on screen. Paging quickly starts several fetches, and
                    // without this the slowest one wins and the grid shows a
                    // month nobody asked for.
                    const want = cal.year + "-" + cal.pad(cal.month + 1);
                    if (d.month !== want) return;
                    cal.days = d.days || ({});
                    cal.loading = d.loading === true;
                } catch (e) { /* keep whatever is already displayed */ }
            }
        }
    }

    Timer {
        // hypr-calendar answers from cache at once and refreshes behind it, so
        // a second call shortly after picks up the fresh events. 8 s is short
        // enough that a newly added appointment appears while you are still
        // looking at the calendar.
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: cal.load()
    }
}
