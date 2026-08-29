#!/usr/bin/env bash
# Self-check for the flock-fd-leak bug fixed 2026-08-26: hypr-lock's
# backgrounded hypr-dpms-ensure-on child used to inherit fd 9 (the flock on
# hypr-lock.flock) because `setsid ... &` doesn't close inherited descriptors
# on its own. That let the recovery script hold the lock long after hyprlock
# itself had exited, so a later lock attempt saw `flock -n 9` fail and
# silently no-op'd -- confirmed live: an idle-triggered lock (pid 111267,
# 2026-08-26 21:34:00) produced zero hyprlock output and no coredump, the
# only path through the script that's completely silent.
#
# Runs an isolated COPY of hypr-lock (never the live one, never the live
# ~/.local/bin/hypr-dpms-ensure-on) with `hyprlock` and `hypr-dpms-ensure-on`
# stubbed via PATH, then asserts the dpms-ensure-on stub does NOT see fd 9.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export XDG_RUNTIME_DIR="$WORK/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"

RESULT_FILE="$WORK/fd9-result"

cat > "$STUB_BIN/hyprlock" <<'EOF'
#!/usr/bin/env bash
sleep 0.3
EOF

cat > "$STUB_BIN/hypr-dpms-ensure-on" <<EOF
#!/usr/bin/env bash
if [ -e /proc/self/fd/9 ]; then
    echo "LEAKED" > "$RESULT_FILE"
else
    echo "CLOSED" > "$RESULT_FILE"
fi
EOF

chmod +x "$STUB_BIN/hyprlock" "$STUB_BIN/hypr-dpms-ensure-on"

# hypr-lock hardcodes the absolute path to hypr-dpms-ensure-on -- test an
# isolated copy with that path swapped to the stub, never the live script or
# the live ~/.local/bin/hypr-dpms-ensure-on.
TEST_SCRIPT="$WORK/hypr-lock-under-test"
sed "s#/home/woofi/.local/bin/hypr-dpms-ensure-on#$STUB_BIN/hypr-dpms-ensure-on#" \
    "$REPO_ROOT/bin/hypr-lock" > "$TEST_SCRIPT"
chmod +x "$TEST_SCRIPT"

PATH="$STUB_BIN:$PATH" bash "$TEST_SCRIPT"

# Give the backgrounded stub a moment to write its result.
for _ in 1 2 3 4 5; do
    [ -f "$RESULT_FILE" ] && break
    sleep 0.1
done

if [ ! -f "$RESULT_FILE" ]; then
    echo "FAIL: hypr-dpms-ensure-on stub never ran"
    exit 1
fi

result="$(cat "$RESULT_FILE")"
if [ "$result" = "LEAKED" ]; then
    echo "FAIL: hypr-dpms-ensure-on inherited fd 9 (the hypr-lock flock) -- regression of the 2026-08-26 fix"
    exit 1
fi

echo "PASS: hypr-dpms-ensure-on did not inherit fd 9"
