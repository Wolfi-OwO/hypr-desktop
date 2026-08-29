#!/usr/bin/env bash
# Self-check for the lockdead-screen bug fixed 2026-08-26: hypr-dpms-ensure-on's
# modeset_cycle() used to disable+re-enable eDP-1 unconditionally once DPMS
# checks missed 3 times in a row -- including while hyprlock's lock surface
# was bound to that same output. Reproduced live and confirmed with grim:
# that disable is what put Hyprland into its lockdead ("it looks like you
# locked your screen but the lockscreen ... crashed") recovery screen, not a
# benign flash. The fix: modeset_cycle must skip the disable/re-enable
# entirely whenever a real hyprlock process is running.
#
# This sources modeset_cycle() out of the real script (never runs the real
# thing against the real display) with `hyprctl`/`pgrep` stubbed on PATH, and
# asserts hyprctl's "disabled = true" eval is never called while the pgrep
# stub reports hyprlock running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
CALL_LOG="$WORK/hyprctl-calls"
touch "$CALL_LOG"

cat > "$STUB_BIN/pgrep" <<'INNER'
#!/usr/bin/env bash
# Simulates hyprlock currently running, regardless of args asked for.
exit 0
INNER

cat > "$STUB_BIN/hyprctl" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$CALL_LOG"
if [ "\$1" = "monitors" ]; then
    echo '[{"name":"eDP-1","width":2880,"height":1800,"refreshRate":90.0,"x":0,"y":0,"scale":2,"dpmsStatus":true}]'
fi
EOF2

chmod +x "$STUB_BIN/pgrep" "$STUB_BIN/hyprctl"

# Pull in only modeset_cycle()/log()/modeline() from the real script, stubbed
# PATH first so `pgrep -x hyprlock` and `hyprctl` hit the fakes above.
LOG="$WORK/dpms.log"
log() { printf '%(%H:%M:%S)T %s\n' -1 "$1" >> "$LOG"; }

PATH="$STUB_BIN:$PATH"
export PATH

source <(grep -A 20 '^modeline()' "$REPO_ROOT/bin/hypr-dpms-ensure-on" | sed -n '/^modeline()/,/^}/p')
source <(grep -A 20 '^modeset_cycle()' "$REPO_ROOT/bin/hypr-dpms-ensure-on" | sed -n '/^modeset_cycle()/,/^}/p')

modeset_cycle

if grep -q "disabled = true" "$CALL_LOG"; then
    echo "FAIL: modeset_cycle disabled eDP-1 while hyprlock (stubbed) was running -- regression of the 2026-08-26 fix"
    exit 1
fi

echo "PASS: modeset_cycle skipped the disable while hyprlock was running"
