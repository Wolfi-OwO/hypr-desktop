#!/usr/bin/env python3
"""Hermetic self-check for hypr-lock-sleep-gate's release decision.

Drives Gate.tick / Gate.on_sleep bound to a stub instance against a
hand-set lock_state/req_t - no D-Bus, no real fd, no journalctl, no GLib
main loop. Gate.__init__ is never called (that's the only place touching
Gio.bus_get_sync), so importing the module has no side effects.
"""
import importlib.machinery
import importlib.util
import os
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE_PATH = os.path.join(REPO_ROOT, "bin", "hypr-lock-sleep-gate")

# spec_from_file_location can't infer a loader for a file with no ".py"
# suffix, so name the loader explicitly.
loader = importlib.machinery.SourceFileLoader("hypr_lock_sleep_gate", GATE_PATH)
spec = importlib.util.spec_from_loader(loader.name, loader)
hlsg = importlib.util.module_from_spec(spec)
loader.exec_module(hlsg)


class FakeGLib:
    """Stands in for the real GLib so a timer id being removed twice is
    caught directly, instead of relying on a real main loop's critical log."""

    def __init__(self):
        self.removed = []
        self.double_remove = False
        self._next_id = 1

    def timeout_add(self, _ms, _fn):
        tid = self._next_id
        self._next_id += 1
        return tid

    def source_remove(self, tid):
        if tid in self.removed:
            self.double_remove = True
        self.removed.append(tid)


class FakeParams:
    """Fakes the GVariant tuple on_sleep pulls the sleep-direction bool out of."""

    def __init__(self, going_to_sleep):
        self._value = going_to_sleep

    def get_child_value(self, _i):
        return self

    def get_boolean(self):
        return self._value


class StubGate:
    """Same instance shape as Gate, minus __init__'s D-Bus call."""

    def __init__(self):
        self.timer = None
        self.req_t = 0.0
        self.fd = None
        self.released = []

    def release(self, why):
        if self.timer is not None:
            hlsg.GLib.source_remove(self.timer)
            self.timer = None
        self.released.append(why)

    tick = hlsg.Gate.tick
    on_sleep = hlsg.Gate.on_sleep


def fail(msg):
    print(f"FAIL: {msg}")
    raise SystemExit(1)


def set_lock_state(phase, seconds_ago):
    hlsg.lock_state["phase"] = phase
    hlsg.lock_state["t"] = time.monotonic() - seconds_ago


def sleep_signal(gate):
    gate.on_sleep(None, None, None, None, None, FakeParams(True), None)


def test_locked_long_ago_releases_immediately():
    hlsg.GLib = FakeGLib()
    gate = StubGate()
    set_lock_state("locked", hlsg.SETTLE_S + 0.05)
    sleep_signal(gate)
    if gate.released != ["already locked"]:
        fail(f"locked-long-ago: released={gate.released!r}")
    if gate.timer is not None:
        fail("locked-long-ago: timer should stay unset on the early-release path")


def test_locked_just_now_waits_for_settle():
    hlsg.GLib = FakeGLib()
    gate = StubGate()
    set_lock_state("locked", 0.0)
    sleep_signal(gate)
    if gate.released:
        fail(f"locked-just-now: released too early: {gate.released!r}")
    if not gate.tick():
        fail("locked-just-now: tick released before SETTLE_S elapsed")
    set_lock_state("locked", hlsg.SETTLE_S + 0.05)
    if gate.tick():
        fail("locked-just-now: tick did not release once SETTLE_S elapsed")
    if gate.released != ["hyprlock onLockLocked + settle"]:
        fail(f"locked-just-now: released={gate.released!r}")


def test_no_lock_started_releases_at_appear():
    hlsg.GLib = FakeGLib()
    gate = StubGate()
    set_lock_state("unlocked", 0.0)
    sleep_signal(gate)
    gate.req_t = time.monotonic() - hlsg.APPEAR_S / 2
    if not gate.tick():
        fail("no-lock-started: released before APPEAR_S elapsed")
    gate.req_t = time.monotonic() - (hlsg.APPEAR_S + 0.05)
    if gate.tick():
        fail("no-lock-started: tick did not release once APPEAR_S elapsed")
    if gate.released != ["no lock started"]:
        fail(f"no-lock-started: released={gate.released!r}")


def test_stuck_locking_releases_at_max_wait():
    hlsg.GLib = FakeGLib()
    gate = StubGate()
    set_lock_state("locking", 0.0)
    sleep_signal(gate)
    gate.req_t = time.monotonic() - (hlsg.MAX_WAIT_S + 0.05)
    if gate.tick():
        fail("stuck-locking: tick did not release once MAX_WAIT_S elapsed")
    if gate.released != ["bound reached, phase=locking"]:
        fail(f"stuck-locking: released={gate.released!r}")


def test_second_on_sleep_does_not_double_remove_pending_timer():
    """Regression test for the Task 1 fix: a second PrepareForSleep(true)
    arriving while a tick timer is still pending must not call
    GLib.source_remove on the same id twice."""
    hlsg.GLib = FakeGLib()
    gate = StubGate()
    gate.timer = hlsg.GLib.timeout_add(hlsg.TICK_MS, gate.tick)
    set_lock_state("locked", hlsg.SETTLE_S + 0.1)
    sleep_signal(gate)
    if hlsg.GLib.double_remove:
        fail("double-remove: same timer id removed twice")
    if gate.timer is not None:
        fail("double-remove: timer should be cleared after the early release")
    if gate.released != ["already locked"]:
        fail(f"double-remove: released={gate.released!r}")


def main():
    test_locked_long_ago_releases_immediately()
    test_locked_just_now_waits_for_settle()
    test_no_lock_started_releases_at_appear()
    test_stuck_locking_releases_at_max_wait()
    test_second_on_sleep_does_not_double_remove_pending_timer()
    print("PASS: hypr-lock-sleep-gate release decisions and the timer double-remove fix")


if __name__ == "__main__":
    main()
