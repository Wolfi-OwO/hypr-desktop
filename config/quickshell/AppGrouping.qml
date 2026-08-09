pragma Singleton

//  One place to turn a raw window class into the stem AltTab groups by.
//
//  AltTab used to keep its own copy of this and WindowThumb matched against
//  the RAW class with strict equality. Brave reports a different class per
//  window -- "brave-browser", "brave-<hash>-Default" per PWA -- so AltTab's
//  own copy stemmed all of them to "brave" for grouping, but WindowThumb's
//  match compared the FULL appId to that stem and never matched, leaving the
//  tile's ScreencopyView permanently unmatched and unlive. It fell to the
//  "no content" fallback, which is next to invisible: Theme.crust is close
//  enough to black that the tile just read as a dead black square.

import QtQuick

QtObject {
    function norm(c) {
        const l = (c || "").toLowerCase();
        if (l.indexOf("brave") === 0) return "brave";
        if (l.indexOf("chromium") === 0 || l.indexOf("google-chrome") === 0) return "chromium";
        if (l.indexOf("codium") === 0) return "code";
        if (l.indexOf("code") === 0) return "code";
        if (l.indexOf("jetbrains") !== -1) return "jetbrains";
        return l;
    }
}
