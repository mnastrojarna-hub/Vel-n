"""Zámek bez paměti drží po zadání kódu aspoň `timings.lock_hold_min_s` (výchozí 60 s; zadání majitele 2026-10-06:
„kiosek musí držet magnet dveří po zadání kódu alespoň 1 min“). Jen režim `lock_hold_until_open`; impulzní zámek beze změny."""
from __future__ import annotations

from motogo_box import diag_protocol as dp, diag_steps, lock_hold, zone_access
from motogo_box.config import HardwareConfig, validate_hardware
from motogo_box.models import EventKind, Signal, ZoneState

from tests.test_diag_protocol import full_ctrl, httpsrv  # noqa: F401 — fixture
from tests.test_diagnostics import sim  # noqa: F401 — fixture
from tests.test_zone import Rig, rig_secured


async def rig_hold(min_s: int = 60, **timings) -> Rig:
    r = await rig_secured()
    r.hw.timings.lock_hold_until_open, r.hw.timings.lock_hold_min_s = True, min_s
    for k, v in timings.items():
        setattr(r.hw.timings, k, v)
    r.zc._timings_cache = None
    return r


def lock_on(r: Rig) -> bool | None:
    ref = r.zone.hw.lock
    return r.io.coils.get((ref.dev, ref.idx))


async def grant(r: Rig, booking: str = "b-1") -> None:
    assert (await r.zc.grant_access(booking_id=booking, kind="motorcycle", source="ui")) == (True, "ok")


async def test_door_opened_early_lock_held_until_minimum():
    r = await rig_hold()
    await grant(r)
    assert r.io.pulses[-1] == (r.zone.hw.lock, 61000)          # HW časovač = max(30, 60) + 1 s
    assert zone_access.hold_lock_ms(r.zc) == 61000 and zone_access.open_timeout_s(r.zc) == 60
    assert lock_on(r) is True and r.zc.lock_held and r.zc.lock_held_since == 1000.0
    r.clock.advance(5)
    await r.zc.on_input(False)                                  # otevřeno v 5. s → zámek drží dál
    assert r.zc.state == ZoneState.DOOR_OPEN and lock_on(r) is True and r.zc.lock_held
    r.clock.advance(54.5)
    await r.zc.tick()
    assert lock_on(r) is True and r.zc.lock_held                # 59,5 s
    r.clock.advance(0.5)
    await r.zc.tick()                                           # 60 s → vypnout (min_hold)
    assert lock_on(r) is False and not r.zc.lock_held and r.zc.lock_held_since is None
    assert r.zc.state == ZoneState.DOOR_OPEN and EventKind.FORCED_OPEN not in r.kinds()


async def _open_close(r: Rig) -> None:
    """Otevřeno v 5. s, zavřeno ve 20. s (debounce 1 s) → CLOSED_CONFIRMATION od 21. s."""
    await grant(r)
    r.clock.advance(5)
    await r.zc.on_input(False)
    r.clock.advance(15)
    await r.zc.on_input(True)
    r.clock.advance(1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and lock_on(r) is True


async def test_quick_close_stays_closed_confirmation_and_reopen_is_same_session():
    r = await rig_hold(light_after_close_s=10, music_after_close_s=5)
    await _open_close(r)
    r.clock.advance(10)
    await r.zc.tick()                                           # 31 s: světlo po zavření vypršelo, zámek drží
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.zc.booking_id == "b-1"
    assert lock_on(r) is True and r.light() is False and r.audio.playing_zone is None
    r.clock.advance(14)
    await r.zc.on_input(False)                                  # 45 s: znovu otevřeno = stejná relace
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b-1" and r.light() is True
    assert r.kinds()[-1] == EventKind.DOOR_OPENED and EventKind.FORCED_OPEN not in r.kinds()
    assert r.signals.current(1) == Signal.GREEN and r.zc.fault is None
    r.clock.advance(15)
    await r.zc.tick()                                           # 60 s: zámek vypnut, dveře pořád otevřené
    assert lock_on(r) is False and r.zc.state == ZoneState.DOOR_OPEN
    await r.zc.on_input(True)
    r.clock.advance(1)
    await r.zc.tick()
    r.clock.advance(10)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.light() is False and r.zc.booking_id is None


async def test_quick_close_secured_only_after_lock_release_then_open_is_forced():
    r = await rig_hold(light_after_close_s=10, music_after_close_s=5)
    await _open_close(r)
    r.clock.advance(38.5)
    await r.zc.tick()                                           # 59,5 s
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and lock_on(r) is True
    r.clock.advance(0.5)
    await r.zc.tick()                                           # 60 s: zámek vypnut, relace ještě dozvuk (poll+debounce)
    assert lock_on(r) is False and r.zc.state == ZoneState.CLOSED_CONFIRMATION
    assert abs(lock_hold.release_grace_s(r.zc) - 0.9) < 1e-9  # 100 ms poll + 300 ms SW debounce + 0,5 s
    r.clock.advance(0.9)
    await r.zc.tick()                                           # 60,9 s: SECURED
    assert r.zc.state == ZoneState.SECURED and r.signals.current(1) == Signal.RED
    await r.zc.on_input(False)                                  # zamčeno → otevření je násilné
    r.clock.advance(0.6)
    await r.zc.tick()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "forced_open"


async def test_no_open_timeout_after_minimum():
    r = await rig_hold()                                        # door_open_timeout_s 30 < 60
    await grant(r)
    r.clock.advance(59.5)
    await r.zc.tick()
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN and lock_on(r) is True
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and lock_on(r) is False and not r.zc.lock_held
    assert r.kinds()[-1] == EventKind.OPEN_TIMEOUT and "do 60 s" in r.events[-1].message


async def test_longer_open_timeout_keeps_hold_until_open():
    r = await rig_hold(door_open_timeout_s=90)
    await grant(r)
    assert r.io.pulses[-1][1] == 91000
    r.clock.advance(70)
    await r.zc.tick()
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN and lock_on(r) is True   # čeká dál na otevření
    await r.zc.on_input(False)                                  # minimum dávno uplynulo → vypnout hned
    assert r.zc.state == ZoneState.DOOR_OPEN and lock_on(r) is False


async def test_min_zero_is_old_behaviour():
    r = await rig_hold(min_s=0)
    await grant(r)
    assert r.io.pulses[-1][1] == 31000
    await r.zc.on_input(False)
    assert lock_on(r) is False and not r.zc.lock_held
    await r.zc.on_input(True)
    r.clock.advance(1)
    await r.zc.tick()
    r.clock.advance(30)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED


async def test_pulse_mode_unchanged():
    r = await rig_secured()
    assert r.hw.timings.lock_hold_min_s == 60 and not r.hw.timings.lock_hold_until_open
    assert zone_access.lock_hold_min_s(r.zc) == 0 and zone_access.open_timeout_s(r.zc) == 30
    await grant(r)
    assert r.io.pulses == [(r.zone.hw.lock, 10)] and not r.lock_coil_touched() and not r.zc.lock_held
    r.clock.advance(31)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and "do 30 s" in r.events[-1].message and not r.lock_coil_touched()


async def test_all_off_io_fault_and_failed_regrant_release_lock():
    r = await rig_hold()
    await grant(r)
    await r.zc.force_secure()
    assert lock_on(r) is False and not r.zc.lock_held
    r2 = await rig_hold()
    await grant(r2)
    await r2.zc.on_input(None)                                  # kontakt offline → FAULT io_offline
    assert r2.zc.state == ZoneState.FAULT and lock_on(r2) is False and not r2.zc.lock_held
    r3 = await rig_hold(light_after_close_s=10)
    await _open_close(r3)
    r3.io.pulse_ok = False                                      # nový kód v doběhu, zámek nepotvrdí
    assert (await r3.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui")) == (False, "lock_failed")
    assert r3.zc.state == ZoneState.SECURED and lock_on(r3) is False and not r3.zc.lock_held


async def test_second_code_in_hold_window_restarts_minimum():
    r = await rig_hold(light_after_close_s=10)
    await _open_close(r)
    r.clock.advance(19)                                         # 40 s
    await grant(r, "b-2")
    assert r.zc.lock_held_since == 1040.0 and r.zc.state == ZoneState.WAITING_FOR_OPEN
    await r.zc.on_input(False)
    r.clock.advance(59.5)
    await r.zc.tick()
    assert lock_on(r) is True
    r.clock.advance(0.5)
    await r.zc.tick()
    assert lock_on(r) is False


async def test_lock_hold_min_range_validated_and_reported():
    base = {"devices": {"wav645": {"type": "wav645", "host": "a"}, "wav617a": {"type": "wav617", "host": "b"}},
            "zones": [{"zone": 1, "lock": {"dev": "wav645", "coil": 0}, "contact": {"dev": "wav617a", "input": 0}}]}
    assert validate_hardware(HardwareConfig.from_dict(base)) == []
    for bad in (601, -1):
        problems = validate_hardware(HardwareConfig.from_dict(dict(base, timings={"lock_hold_min_s": bad})))
        assert any("lock_hold_min_s" in p for p in problems)
    assert HardwareConfig.from_dict(dict(base, timings={"lock_hold_min_s": "90"})).timings.lock_hold_min_s == 90
    cfg = {"zones": [], "timings": {"lock_hold_until_open": True, "lock_hold_min_s": 60, "door_open_timeout_s": 30},
           "timings_problems": []}
    sec = dp._config({"config": cfg, "steps": {"config": {"ok": True}}})
    line = next(i for i in sec["items"] if i["id"] == "config.timings")
    assert "min. 60 s" in str(line["value"])


async def test_diag_held_lock_coil_is_not_an_alarm(tmp_path, sim, httpsrv):  # noqa: F811 — fixtures
    """Diagnostika: sepnuté relé zámku, který právě drží po kódu (`lock_held`), není „SEPNUTÉ v klidu — NEBEZPEČÍ“."""
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ctrl.zones[4].lock_held = True
    zones = {z["zone"]: z for z in await diag_steps.zones(ctrl.diagnostics, {})}
    assert zones[4]["lock"]["coil_off"] is False and zones[4]["lock"]["held"] is True
    assert not any("SEPNUTÉ" in p for p in zones[4]["problems"]) and not ctrl.io.pulses
