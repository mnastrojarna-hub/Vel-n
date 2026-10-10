"""Šatna čeká na kód motorky (2026-10-10, zadání majitele): hudba hraje bez ohledu na dveře až do kódu motorky,
dveře šatny lze libovolně otevírat a zavírat (táž relace, žádný poplach), protokol jen při zavřených dveřích."""
from __future__ import annotations

from dataclasses import replace

from motogo_box.models import EventKind, ZoneState

from tests.handover_fakes import FakeCtrl, protocol, rr_moto
from tests.test_zone import Rig


async def wardrobe_rig() -> Rig:
    r = Rig()
    r.zone = r.zc.zone = replace(r.zone, kind="accessories", hw=replace(r.zone.hw, light_until_moto_code=True))
    await r.zc.startup(True)
    assert (await r.zc.grant_access(booking_id="b", kind="accessories", source="ui")) == (True, "ok")
    r.zc.hold_until_moto_code = True             # controller_codes po kódu šatny s rezervací
    return r


async def close(r: Rig) -> None:
    await r.zc.on_input(True)
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION


async def test_music_plays_until_moto_code_regardless_of_doors():
    r = await wardrobe_rig()
    await r.zc.on_input(False)
    await close(r)
    r.clock.advance(r.hw.timings.light_after_close_s + 5)
    await r.zc.tick()                                             # dávno po doběhu hudby i světla
    assert r.audio.playing_zone == 1 and r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.zc.lock_wait
    for _ in range(3):                                            # dovnitř / ven — táž relace, bez poplachu
        await r.zc.on_input(False)
        assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b"
        await close(r)
        r.clock.advance(120)
        await r.zc.tick()
        assert r.audio.playing_zone == 1
    assert EventKind.FORCED_OPEN not in r.kinds() and r.audio.stops == 0
    await r.zc.light_off_after_moto_code()                        # kód motorky → hudba stop, světlo zhasne
    assert r.audio.playing_zone is None and r.light() is False
    r.clock.advance(1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.booking_id is None and not r.zc.hold_until_moto_code


async def test_moto_code_with_wardrobe_door_open_stops_music():
    r = await wardrobe_rig()
    await r.zc.on_input(False)
    assert await r.zc.light_off_after_moto_code() is False       # někdo uvnitř → světlo drží
    assert r.audio.playing_zone is None and r.light() is True


async def test_hold_safety_timeout_ends_session():
    r = await wardrobe_rig()
    await r.zc.on_input(False)
    await close(r)
    r.clock.advance(r.hw.timings.maximum_session_s + 1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.audio.playing_zone is None and r.light() is False


async def test_repeated_wardrobe_code_keeps_music_running():
    r = await wardrobe_rig()
    await r.zc.on_input(False)
    await close(r)
    r.clock.advance(r.hw.timings.light_after_close_s + 1)
    await r.zc.tick()
    assert (await r.zc.grant_access(booking_id="b", kind="accessories", source="ui")) == (True, "ok")
    assert r.audio.plays[0][2] is True and r.audio.plays[-1][2] is False   # bez přetáčení od začátku


async def test_motorcycle_zone_unchanged():
    r = Rig()
    await r.zc.startup(True)
    await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")
    await r.zc.on_input(False)
    await close(r)
    r.clock.advance(r.hw.timings.music_after_close_s + 1)
    await r.zc.tick()
    assert r.audio.playing_zone is None


async def test_protocol_hidden_while_wardrobe_open_and_shown_on_close(tmp_path):
    ctrl = FakeCtrl(tmp_path)
    try:
        hm = ctrl.handover
        hm.remember(rr_moto(proto=protocol("b1")))
        assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
        assert hm.status()["active"]["booking_id"] == "b1"
        assert hm.on_wardrobe_opened(8, "b1") is True
        assert hm.status()["active"] is None and "b1" in hm.items
        assert hm.on_wardrobe_opened(8, "b1") is False
        assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
        assert hm.status()["active"]["booking_id"] == "b1"
        assert len([e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SHOWN]) == 1
    finally:
        ctrl.close()


async def test_wardrobe_code_sets_hold_moto_code_does_not(tmp_path):
    from motogo_box import controller_codes as cc
    from tests.test_handover_locker import _online
    ctrl = FakeCtrl(tmp_path)
    try:
        ctrl.cache([{"code": "888888", "kind": "accessories", "booking_id": "b1", "door_id": "d8"},
                    {"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
                   [protocol("b1", required=False)])
        _online(ctrl, required=False)
        assert (await cc.submit_code(ctrl, "888888", "ui"))["ok"]
        assert ctrl.zones[8].hold_until_moto_code is True
        assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"]
        assert not getattr(ctrl.zones[3], "hold_until_moto_code", False)
    finally:
        ctrl.close()
