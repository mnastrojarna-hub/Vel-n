"""Výzva „nejdřív kód šatny“ (`handover_locker.py`, zadání majitele 2026-09-29) — měkké hradlo v `submit_code`."""
from __future__ import annotations

import pytest

from motogo_box import controller_codes as cc
from motogo_box import handover_locker as hl
from motogo_box.models import EventKind

from tests.handover_fakes import SIG, FakeCtrl, protocol


def _door(kind: str, zone: int, box: int | None = None) -> dict:
    return {"id": f"d{zone}", "door_kind": kind, "box_number": box}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    # b1 má v cache kód šatny (dveře d8 = zóna 8) i kód motorky (d3); protokol nepodepsaný, výbava nevyzvednutá
    c.cache([{"code": "888888", "kind": "accessories", "booking_id": "b1", "door_id": "d8"},
             {"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
            [protocol("b1")])
    yield c
    c.close()


def _online(ctrl, **proto) -> None:
    p = protocol("b1", **proto)
    ctrl.api.resolve = {
        "111111": {"ok": True, "kind": "motorcycle", "booking_id": "b1", "box_number": 3,
                   "door": _door("motorcycle", 3, 3), "protocol": p},
        "888888": {"ok": True, "kind": "accessories", "booking_id": "b1", "door": _door("accessories", 8), "protocol": p},
    }


async def test_moto_code_first_prompts_locker_then_second_entry_passes(ctrl):
    _online(ctrl)
    moto, wardrobe = ctrl.zones[3], ctrl.zones[8]
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["ok"] is False and res["error"] == "locker_first" and res["kind"] == "motorcycle"
    assert res["booking_id"] == "b1" and "kód šatny" in res["message"] and res["locked_until"] is None
    assert moto.grants == [] and wardrobe.grants == [] and ctrl.handover.status()["active"] is None
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert len(denied) == 1 and denied[0].level == "info" and denied[0].booking_id == "b1"
    assert denied[0].detail == {"source": "ui", "reason": "locker_first", "locker_zone": 8, "offline": False}
    assert ctrl.storage.pin_failures_since(0) == 0 and "PIN_INVALID" not in ctrl.kinds()
    assert "PROTOCOL_SHOWN" not in ctrl.kinds()
    ctrl.clock.advance(30)                       # „výbavu nechci“: druhé zadání pustí na protokol
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "protocol_required" and ctrl.handover.status()["active"]["then_open"] is True
    res = await ctrl.handover.submit("b1", {}, SIG, None)
    assert res["ok"] and moto.grants == [("b1", "motorcycle", "ui")]


async def test_locker_first_then_moto_code_goes_straight_to_protocol(ctrl):
    _online(ctrl)
    res = await cc.submit_code(ctrl, "888888", "ui")
    assert res["ok"] and ctrl.zones[8].grants == [("b1", "accessories", "ui")]
    assert "b1" in hl._load(ctrl.storage, ctrl.clock())["opened"]       # otevření zámku šatny stačí (ne dveřní kontakt)
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "protocol_required"
    assert not any(e.detail.get("reason") == "locker_first" for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED)


async def test_signed_in_app_still_prompts_then_second_entry_opens_bay(ctrl):
    _online(ctrl, required=False)                # podepsáno v appce před šatnou, výbava ale nevyzvednutá
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "locker_first" and ctrl.zones[3].grants == []
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["ok"] and ctrl.zones[3].grants == [("b1", "motorcycle", "ui")]


async def test_return_after_bay_opened_is_never_prompted(ctrl):
    _online(ctrl, required=False)
    await cc.submit_code(ctrl, "111111", "ui")
    assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"]           # vydáno bez výbavy
    ctrl.clock.advance(3 * 86400)                                       # vracení po 3 dnech (gear_collected_at dál NULL)
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["ok"] and len(ctrl.zones[3].grants) == 2


@pytest.mark.parametrize("proto", [{"gear_collected_at": "2026-09-29T08:00:00Z"}, {"needs_locker": False},
                                   {"absent": True, "required": False}])
async def test_no_prompt_when_gear_collected_or_not_needed(ctrl, proto):
    _online(ctrl, **proto)
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] != "locker_first"


async def test_no_prompt_without_locker_code_in_cache(ctrl):
    ctrl.cache([{"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
               [protocol("b1")])
    _online(ctrl)
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "protocol_required"


async def test_no_prompt_when_wardrobe_faulty_or_not_mapped(ctrl):
    _online(ctrl)
    ctrl.zones[8].fault = "lock_failed"
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "protocol_required"
    ctrl.zones[8].fault = None
    ctrl.zones[8].zone.door_id = "jine-dvere"                           # kód šatny nesedí na HW mapu → fail-open
    ctrl.handover.dismiss("b1")
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "protocol_required"


async def test_wardrobe_that_cannot_open_releases_moto(ctrl):
    _online(ctrl)
    ctrl.zones[8].result = (False, "lock_failed")
    res = await cc.submit_code(ctrl, "888888", "ui")
    assert res["ok"] is False
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "protocol_required"


async def test_prompt_repeats_after_window_and_survives_restart(ctrl):
    _online(ctrl)
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "locker_first"
    assert "b1" in hl._load(ctrl.storage, ctrl.clock())["prompted"]     # kv přežije restart procesu
    ctrl.clock.advance(hl.REPEAT_S + 1)                                 # po 10 min znovu výzva (dřív nechtěl → zapomenuto)
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "locker_first"


async def test_offline_cache_prompts_too(ctrl):
    ctrl.api.resolve = {"111111": None}                                 # síť nejde → offline HMAC cache + protocols[]
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "locker_first"
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert denied[-1].detail["offline"] is True
