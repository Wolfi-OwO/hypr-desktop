// Standalone check for the group-building logic in AltTab.qml's load handler
// (byKey[k].canonical, next to the untouched byKey[k].windows). No
// framework, no fixtures -- run with: node test-alttab-grouping.mjs
//
// Two properties, deliberately both asserted since they were once in
// conflict and each has its own regression history:
//   - canonical: a Brave PWA with a more recent focusHistoryID than the
//     actual brave-browser window must NOT become the commit target or the
//     live-thumbnail source (Task 1's bug).
//   - windows: must stay in fh order (most-recently-used first) for the
//     Down-arrow expanded row -- an earlier fix reordered this same array to
//     fix `canonical` and silently broke MRU order in the expanded row
//     (Task 4's regression). Splitting the two fields is what this test
//     would have caught.

import assert from "node:assert/strict";

// The norm() function this depends on, copied verbatim from AppGrouping.qml.
function norm(c) {
    const l = (c || "").toLowerCase();
    if (l.indexOf("brave") === 0) return "brave";
    if (l.indexOf("chromium") === 0 || l.indexOf("google-chrome") === 0) return "chromium";
    if (l.indexOf("codium") === 0) return "code";
    if (l.indexOf("code") === 0) return "code";
    if (l.indexOf("jetbrains") !== -1) return "jetbrains";
    return l;
}

// The grouping logic from AltTab.qml's load.stdout.onStreamFinished, copied
// verbatim (minus pretty-name lookup, irrelevant here).
function buildGroups(wins) {
    const byKey = {};
    const order = [];
    for (const w of wins) {
        const k = norm(w.class);
        if (!byKey[k]) { byKey[k] = { key: k, windows: [] }; order.push(k); }
        byKey[k].windows.push(w);
    }
    for (const k of order) {
        byKey[k].canonical = byKey[k].windows.reduce(
            (a, b) => b.class.length < a.class.length ? b : a);
    }
    return order.map(k => byKey[k]);
}

// Shape of the live state that reproduced the original bug: a Brave PWA
// (fh=1) focused more recently than the actual browser (fh=2), plus two more
// Brave windows stashed in special:minimized. Addresses and PWA class hashes
// below are synthetic -- only the shape (fh order, class lengths) matters
// for this check, not the real extension IDs `hyprctl clients -j` reported.
const failingState = [
    { class: "kitty", address: "A", ws: "1", fh: 0 },
    { class: "brave-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-Default", address: "B", ws: "4", fh: 1 },
    { class: "brave-browser", address: "C", ws: "4", fh: 2 },
    { class: "code", address: "D", ws: "2", fh: 3 },
    { class: "discord", address: "E", ws: "4", fh: 4 },
    { class: "brave-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-Default", address: "F", ws: "special:minimized", fh: 5 },
    { class: "brave-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-Default", address: "G", ws: "special:minimized", fh: 6 },
];

const groups = buildGroups(failingState);
const brave = groups.find(g => g.key === "brave");

// Property 1: canonical is the real browser, not a PWA.
assert.equal(brave.canonical.address, "C",
    "canonical of the brave group must be the real browser (C), not a PWA");
assert.equal(brave.canonical.class, "brave-browser");

// Property 2: windows stays in fh (most-recently-used-first) order --
// untouched by the canonical pick, exactly the order pushed from `wins`.
assert.deepEqual(brave.windows.map(w => w.address), ["B", "C", "F", "G"],
    "windows must stay in MRU (fh) order for the expanded Down-arrow row");

// No-regression: a single-class group (kitty) keeps its one window and its
// own address as canonical.
const twoKitty = [
    { class: "kitty", address: "K1", fh: 0 },
    { class: "kitty", address: "K2", fh: 1 },
];
const kg = buildGroups(twoKitty).find(g => g.key === "kitty");
assert.deepEqual(kg.windows.map(w => w.address), ["K1", "K2"],
    "equal-length classes must keep fh order (no reordering, no regression)");
assert.equal(kg.canonical.address, "K1", "canonical falls back to the MRU window when classes tie");

console.log("alttab grouping check: PASS");
