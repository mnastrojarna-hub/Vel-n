"""Držený zámek bez paměti se vypne `timings.lock_release_after_open_s` (výchozí 2 s) po skutečném otevření dveří
(kontakt), i když minimum `lock_hold_min_s` od kódu ještě neuplynulo — zadání majitele 2026-10-10: magnet pod napětím
nešel zavřít. Na otevření se dál čeká až minimum (60 s)."""
from __future__ import annotations

from motogo_box import zone_access
from motogo_box.config import HardwareConfig, TimingsCfg, validate_hardware
from motogo_box.models import EventKind, ZoneState

from tests.test_lock_hold import grant, lock_on, rig_hold


async def test_default_is_two_seconds():
    assert TimingsCfg().lock_release_after_open_s == 2


async def test_lock_released_two_seconds_after_door_opens():
    r = await rig_hold(after_open_s=2)
    await grant(r)
    r.clock.advance(40)
    await r.zc.tick()
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN and lock_on(r) is True   # na otevření čeká dál (minimum 60 s)
    await r.zc.on_input(False)                                  # 40 s: otevřeno → ještě drží
    assert r.zc.state == ZoneState.DOOR_OPEN and lock_on(r) is True
    r.clock.advance(1.75)
    await r.zc.tick()
    assert lock_on(r) is True and r.zc.lock_held
    r.clock.advance(0.25)
    await r.zc.tick()                                           # 2 s po otevření → proud vypnut
    assert lock_on(r) is False and not r.zc.lock_held and r.zc.lock_opened_at is None
    assert r.zc.state == ZoneState.DOOR_OPEN and EventKind.FORCED_OPEN not in r.kinds()


async def test_closed_within_two_seconds_still_released_and_session_closes():
    r = await rig_hold(after_open_s=2, light_after_close_s=10, door_close_debounce_ms=500)
    await grant(r)
    r.clock.advance(5)
    await r.zc.on_input(False)                                  # otevřeno v 5. s
    r.clock.advance(1)
    await r.zc.on_input(True)
    r.clock.advance(0.5)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and lock_on(r) is True
    r.clock.advance(0.5)
    await r.zc.tick()                                           # 7 s = 2 s od otevření → vypnuto
    assert lock_on(r) is False and not r.zc.lock_held
    r.clock.advance(10)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.booking_id is None


async def test_reopen_counts_from_first_opening():
    r = await rig_hold(after_open_s=2, door_close_debounce_ms=100)
    await grant(r)
    await r.zc.on_input(False)
    r.clock.advance(0.5)
    await r.zc.on_input(True)
    r.clock.advance(0.2)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(0.8)
    await r.zc.on_input(False)                                  # znovu otevřeno v 1,5 s — odpočet neresetovat
    r.clock.advance(0.5)
    await r.zc.tick()
    assert lock_on(r) is False and r.zc.state == ZoneState.DOOR_OPEN


async def test_zero_releases_on_open_and_range_validated():
    r = await rig_hold(after_open_s=0)
    await grant(r)
    await r.zc.on_input(False)
    assert lock_on(r) is False
    base = {"devices": {"wav645": {"type": "wav645", "host": "a"}, "wav617a": {"type": "wav617", "host": "b"}},
            "zones": [{"zone": 1, "lock": {"dev": "wav645", "coil": 0}, "contact": {"dev": "wav617a", "input": 0}}]}
    for bad in (31, -1):
        problems = validate_hardware(HardwareConfig.from_dict(dict(base, timings={"lock_release_after_open_s": bad})))
        assert any("lock_release_after_open_s" in p for p in problems)
    assert zone_access.lock_hold_min_s(r.zc) == 60
