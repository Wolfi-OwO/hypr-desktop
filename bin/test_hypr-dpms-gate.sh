#!/usr/bin/env bash
# Self-check for the gate in hypr-dpms-ensure-on that decides whether a resume
# needs the DPMS off/on toggle (which blanks the lock screen for ~1.3 s).
# Sources resume_epoch() and ec_fault_seen() out of the real script with
# `journalctl` stubbed on PATH, and asserts: the resume timestamp is read from
# the LAST "PM: suspend exit" line, and the EC WM00 fault is reported only when
# the stubbed kernel log contains it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/journalctl" <<'INNER'
#!/usr/bin/env bash
case "$*" in
    *short-unix*)
        echo "1000.100000 host kernel: PM: suspend exit"
        echo "2000.200000 host kernel: PM: suspend entry (s2idle)"
        echo "2500.300000 host kernel: PM: suspend exit" ;;
    *) [ "${FAKE_FAULT:-0}" = 1 ] && echo "ACPI BIOS Error (bug): Could not resolve symbol [\\_SB.PC00.LPCB.EC0._Q12.WM00], AE_NOT_FOUND"
       echo "ACPI Error: Aborting method \\_SB.PC00.LPCB.EC0._Q70 (AE_NOT_FOUND)" ;;
esac
exit 0
INNER
chmod +x "$WORK/bin/journalctl"
export PATH="$WORK/bin:$PATH"

set +u
source <(sed -n '/^resume_epoch()/,/^}/p' "$REPO_ROOT/bin/hypr-dpms-ensure-on")
source <(sed -n '/^ec_fault_seen()/,/^}/p' "$REPO_ROOT/bin/hypr-dpms-ensure-on")
set -u

RESUME_AT="$(resume_epoch)"
[ "$RESUME_AT" = 2500 ] || { echo "FAIL: resume_epoch gave '$RESUME_AT', expected 2500"; exit 1; }

FAKE_FAULT=0 ec_fault_seen && { echo "FAIL: fault reported with none logged (_Q70 noise must not count)"; exit 1; }
FAKE_FAULT=1 ec_fault_seen || { echo "FAIL: WM00 fault logged but not reported"; exit 1; }
RESUME_AT="" ec_fault_seen && { echo "FAIL: fault reported with unknown resume time"; exit 1; }

echo "PASS: resume_epoch and ec_fault_seen behave"
