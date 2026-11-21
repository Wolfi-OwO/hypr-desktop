#!/usr/bin/env bash
# Self-check for hypr-faillock-countdown against fake faillock tally
# directories (never the real account -- see FAILLOCK_DIR in that script).
# Fake records use the tally-file layout confirmed by writing one and
# reading it back with the real `faillock` binary: each record is
# struct.pack('<52sHHQ', source, status, flags, timestamp), flags=1 marks a
# failed (not successful) attempt, which is what makes faillock print "V".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/bin/hypr-faillock-countdown"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0

make_tally() {
    # make_tally <dir> <count> <age-seconds>
    local dir="$1" count="$2" age="$3"
    mkdir -p "$dir"
    local now
    now=$(date +%s)
    python3 -c "
import struct
now = $now
count = $count
age = $age
with open('$dir/woofi', 'wb') as f:
    for i in range(count):
        ts = now - age - i
        f.write(struct.pack('<52sHHQ', b'test'.ljust(52, b'\0'), 0, 1, ts))
"
}

check() {
    local name="$1" dir="$2" pattern="$3"
    local out
    out="$(FAILLOCK_DIR="$dir" "$SCRIPT")"
    if [ -z "$pattern" ]; then
        if [ -z "$out" ]; then
            echo "PASS: $name"
        else
            echo "FAIL: $name -- expected empty output, got '$out'"
            fail=1
        fi
    else
        if printf '%s' "$out" | grep -Eq "$pattern"; then
            echo "PASS: $name"
        else
            echo "FAIL: $name -- '$out' did not match /$pattern/"
            fail=1
        fi
    fi
}

# (a) empty dir -> no output
mkdir -p "$WORK/a"
check "empty tally dir" "$WORK/a" ""

# (b) 3 records at now-60s -> locked, ~9:00 left (600-60=540s)
make_tally "$WORK/b" 3 60
check "3 fails 60s ago" "$WORK/b" '^Gesperrt – entsperrt in [89]:[0-5][0-9]$'

# (c) 3 records at now-700s -> lockout window (600s) already expired
make_tally "$WORK/c" 3 700
check "3 fails 700s ago (expired)" "$WORK/c" ""

# (d) 2 records at now-10s -> below deny threshold of 3
make_tally "$WORK/d" 2 10
check "2 fails 10s ago (below deny)" "$WORK/d" ""

# (e) command-injection PoC: a Source field carrying a newline followed by a
# command-substitution-looking string, reproducing the security review's PoC
# shape. With the shell-call-free fix, the crafted row's time column never
# matches the HH:MM:SS validation regex, so it's dropped by `next` -- no
# subshell is ever built from this data to begin with. Assert both that the
# script's output stays safe/empty (it falls below the deny threshold once
# the poisoned row is dropped) and that no PWNED-style file appears anywhere
# a shell could have written one.
make_tally_injection() {
    local dir="$1"
    mkdir -p "$dir"
    local now
    now=$(date +%s)
    python3 -c "
import struct
now = $now
src = b'x\n2026-10-01 \$(id>$WORK/PWNED) X'.ljust(52, b'\0')[:52]
with open('$dir/woofi', 'wb') as f:
    f.write(struct.pack('<52sHHQ', src, 0, 1, now - 60))
    f.write(struct.pack('<52sHHQ', b'test'.ljust(52, b'\0'), 0, 1, now - 61))
"
}
make_tally_injection "$WORK/e"
check "injection PoC in Source field" "$WORK/e" ""
# The crafted payload targets "$WORK/PWNED" specifically (and the PoC command
# would otherwise run in the test's own cwd), so both are checked.
if find "$WORK" "$REPO_ROOT" -maxdepth 1 -name 'PWNED*' 2>/dev/null | grep -q .; then
    echo "FAIL: injection PoC -- a PWNED file was created"
    fail=1
else
    echo "PASS: injection PoC -- no PWNED file created"
fi

# (f) unlock_time=never (faillock.conf(5): permanent lock, cleared only by
# `faillock --reset`) must not crash the countdown and must still print the
# bare "Gesperrt" label with no stray stderr and exit 0. The script only
# reads $FAILLOCK_CONF at all when $FAILLOCK_DIR is unset (see the dir-read
# condition in the script), so this test points "dir" at the scratch tally
# directory from inside the fake conf file itself, same as a real override.
make_tally "$WORK/f" 3 10
printf 'dir = %s\nunlock_time = never\n' "$WORK/f" > "$WORK/f.conf"
out="$(FAILLOCK_CONF="$WORK/f.conf" "$SCRIPT" 2>"$WORK/f.err")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "Gesperrt" ] && [ ! -s "$WORK/f.err" ]; then
    echo "PASS: unlock_time=never"
else
    echo "FAIL: unlock_time=never -- rc=$rc out='$out' err='$(cat "$WORK/f.err")'"
    fail=1
fi

exit "$fail"
