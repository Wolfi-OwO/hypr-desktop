// Standalone check for the "first press stays on the current app" behaviour
// in AltTab.qml (step()'s opening branch + the pendingStep replay in
// onStreamFinished). No framework, no fixtures -- run with:
//   node test-alttab-stepping.mjs
//
// Simulates just the index arithmetic; the actual `hyprctl clients | jq`
// load and the grouping/sort fix are covered separately in
// test-alttab-grouping.mjs and need a live compositor, which this does not.

import assert from "node:assert/strict";

function makeState() {
    return { shown: false, index: 0, subIndex: -1, groups: [], pendingStep: 0, loading: false };
}

// Mirrors step() in AltTab.qml.
function step(s, dir) {
    if (!s.shown) {
        s.shown = true;
        s.index = 0;
        s.subIndex = -1;
        s.groups = [];
        s.pendingStep = 0;   // the opening press itself never steps
        s.loading = true;
        return;
    }
    if (s.loading) {
        s.pendingStep += dir;
        return;
    }
    if (s.groups.length === 0) return;
    s.index = ((s.index + dir) % s.groups.length + s.groups.length) % s.groups.length;
    s.subIndex = -1;
}

// Mirrors the tail of load.stdout.onStreamFinished in AltTab.qml.
function finishLoad(s, groupCount) {
    s.groups = new Array(groupCount).fill(0);
    s.loading = false;
    if (s.index >= s.groups.length) s.index = 0;
    if (s.pendingStep !== 0 && s.groups.length > 0) {
        const d = s.pendingStep;
        const n = s.groups.length;
        s.index = ((d % n) + n) % n;
    }
    s.pendingStep = 0;
}

// One tap opens the overlay and must land on the current app (index 0),
// once the async load comes back -- this is the whole point of the task.
{
    const s = makeState();
    step(s, 1);
    finishLoad(s, 4);
    assert.equal(s.index, 0, "single ALT+TAB tap must stay on the current app");
}

// Two taps that both land BEFORE the load finishes (fast double-tap, the
// exact async window pendingStep exists for): first stays, second moves --
// net one step, not two.
{
    const s = makeState();
    step(s, 1);
    step(s, 1);
    finishLoad(s, 4);
    assert.equal(s.index, 1, "second queued tap before load finishes must move exactly one step");
}

// Normal case: load finishes between taps (the common real-world timing).
// Second tap after the overlay is already showing must move forward.
{
    const s = makeState();
    step(s, 1);
    finishLoad(s, 4);
    step(s, 1);
    assert.equal(s.index, 1, "second tap after the overlay is up must move to the next app");
}

// ALT+SHIFT+TAB: same rule, opposite direction.
{
    const s = makeState();
    step(s, -1);
    finishLoad(s, 4);
    step(s, -1);
    assert.equal(s.index, 3, "second ALT+SHIFT+TAB tap must move to the previous app");
}

// Full cycle must still be reachable: taps 1..4 (n=4) visit every index once.
{
    const s = makeState();
    step(s, 1);
    finishLoad(s, 4);
    const seen = [s.index];
    for (let i = 0; i < 3; i++) { step(s, 1); seen.push(s.index); }
    assert.deepEqual(seen, [0, 1, 2, 3], "four taps over four groups must visit every index once");
}

console.log("alttab stepping check: PASS");
