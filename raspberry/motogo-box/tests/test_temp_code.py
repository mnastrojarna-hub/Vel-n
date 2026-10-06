"""Krátkodobý kód z Velína (`branch_temp_codes`, rozhodnutí majitele 2026-10-06 D4, CONTRACT §32): online i offline otevře
JEN své dveře (kóje / šatna), bez rezervace → bez km, protokolu, výzvy „nejdřív šatna“, zámku přejímky a hradla vrácení."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from motogo_box import controller_codes as cc
from motogo_box import handover_locker as hl
from motogo_box import odometer as odo_mod
from motogo_box import return_gate as rg
from motogo_box.controller import BoxController
from motogo_box.models import EventKind, ResolveResult
from motogo_box.odometer import OdometerManager
from tests.handover_fakes import FakeCtrl, protocol

DOOR3 = {"id": "d3", "door_kind": "motorcycle", "box_number": 3, "label": "Kóje 3"}
DOOR8 = {"id": "d8", "door_kind": "accessories", "box_number": None, "label": "Šatna"}


def temp_rpc(door: dict, **kw) -> dict:
    return {"ok": True, "kind": door["door_kind"], "booking_id": None, "temp": True, "temp_code_id": "t1",
            "box_number": door["box_number"], "door": door, "door_configured": True, "release_at": None,
            "protocol": None, "odo": None, "return_final_from": None, **kw}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.odometer = OdometerManager(c, clock=c.clock)
    c.cache([{"code": "777777", "kind": "accessories", "booking_id": None, "door_id": "d8", "temp": True,
              "valid_until": "2099-01-01T00:00:00+00:00"},
             {"code": "888888", "kind": "accessories", "booking_id": "b2", "door_id": "d8"}],
            [protocol("b2")])
    c.handover.lock.set("b2", 8, "Jiný zákazník")         # probíhá přejímka JINÉ rezervace
    yield c
    c.close()


def test_from_rpc_and_cache_parse_temp_and_final_from():
    r = ResolveResult.from_rpc(temp_rpc(DOOR3))
    assert r.ok and r.temp and r.temp_code_id == "t1" and r.kind == "motorcycle" and r.booking_id is None
    assert (r.door_id, r.box_number, r.door_configured) == ("d3", 3, True)
    # pojistka: krátkodobý kód nikdy nenese rezervaci / hradla, ani kdyby je server poslal
    r = ResolveResult.from_rpc(temp_rpc(DOOR3, booking_id="b1", protocol=protocol("b1"), odo={"unit": "km"},
                                        release_at="2099-01-01T10:00:00Z", return_final_from="2026-10-06T22:00:00Z"))
    assert r.booking_id is None and r.protocol is None and r.odo is None and r.release_at is None
    assert r.return_final_from is None
    bad = ResolveResult.from_rpc(temp_rpc(DOOR3, kind="service"))      # nikdy servisní panel / nouzové otevření
    assert not bad.ok and bad.error == "invalid_code" and not bad.is_service
    normal = ResolveResult.from_rpc({"ok": True, "kind": "motorcycle", "booking_id": "b1", "door": DOOR3,
                                     "return_final_from": "2026-10-05T22:00:00+00:00"})
    assert not normal.temp and normal.return_final_from == "2026-10-05T22:00:00+00:00" and normal.booking_id == "b1"
    old = ResolveResult.from_rpc({"ok": True, "kind": "motorcycle", "booking_id": "b1", "door": DOOR3})
    assert not old.temp and old.return_final_from is None                  # stará DB


async def test_online_temp_moto_code_opens_only_its_bay_without_side_effects(ctrl):
    ctrl.storage.kv_set(odo_mod.KV, {"b": {}})
    ctrl.api.resolve["555555"] = temp_rpc(DOOR3)
    res = await cc.submit_code(ctrl, "555555", "ui")
    assert res["ok"] and res["zone"] == 3 and res["kind"] == "motorcycle" and res["error"] is None
    assert ctrl.zones[3].grants == [(None, "motorcycle", "ui")] and ctrl.zones[8].grants == []
    assert ctrl.zones[3].details == [{"temp": True, "temp_code_id": "t1"}]     # bez odometer_phase (žádná relace vrácení)
    assert ctrl.handover.lock.booking_id == "b2"                              # zámek jiné přejímky NEuvolněn
    assert ctrl.handover.status()["active"] is None and "PROTOCOL_SHOWN" not in ctrl.kinds()
    assert not [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert ctrl.storage.kv_get(hl.KV) is None and ctrl.storage.kv_get(odo_mod.KV) == {"b": {}}
    assert ctrl.pin_guard.failures_in_window() == 0


async def test_offline_temp_locker_code_opens_locker_without_handover(ctrl):
    ctrl.api.resolve["777777"] = None                                         # síť nejde → offline cache
    protocols = dict(ctrl.handover.protocols)
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] and res["zone"] == 8 and ctrl.zones[8].grants == [(None, "accessories", "ui")]
    assert ctrl.zones[8].details == [{"temp": True}]                          # offline bez id (cache ho nenese)
    assert ctrl.handover.protocols == protocols and ctrl.handover.lock.booking_id == "b2"
    rr = ctrl.resolver.resolve("777777", ctrl.storage.load_code_cache(), datetime.now(timezone.utc))
    assert rr.temp and rr.booking_id is None and not rg.blocks(ctrl, rr)
    # zákaznický kód jiné rezervace zámek přejímky dál blokuje (beze změny chování)
    ctrl.api.resolve["888888"] = None
    assert (await cc.submit_code(ctrl, "888888", "ui"))["ok"]                 # b2 = rezervace zámku → projde


async def test_temp_session_close_does_not_trigger_wardrobe_handover():
    calls: list = []

    async def on_wardrobe_closed(*a, **k):
        calls.append(a)
    box = SimpleNamespace(handover=SimpleNamespace(on_wardrobe_closed=on_wardrobe_closed))
    zc = SimpleNamespace(zone=SimpleNamespace(kind="accessories"), booking_id=None, number=8)
    await BoxController._session_closed(box, zc)
    assert calls == []
    zc.booking_id = "b1"
    await BoxController._session_closed(box, zc)
    assert calls == [(8, "b1")]
