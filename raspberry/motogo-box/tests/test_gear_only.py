"""Výpůjčka výbavy bez motorky na kiosku — převzetí (1.3.0, CONTRACT §33): kód šatny → šatna bez držení „do kódu motorky“ →
zavření → protokol jen s výbavou (velikosti z `sizes_catalog`) → podpis s KÓDEM ŠATNY téže rezervace, kóje se neotvírá,
zámek přejímky končí podpisem. Motorkový tok beze změny (regrese na konci)."""
from __future__ import annotations

import pytest

from motogo_box import controller_codes as cc
from motogo_box import handover_gear as hg
from motogo_box.handover import HandoverManager
from motogo_box.models import EventKind, ResolveResult

from tests.handover_fakes import SIG, FakeCtrl, protocol

GEAR = [{"key": "helmet", "who": "rider", "field": "helmet_size", "size": "M"},
        {"key": "jacket", "who": "rider", "field": "jacket_size", "size": "L"}]
CATALOG = {"helmet": ["XS", "S", "M", "L"], "jacket": ["M", "L", "5XL"], "gloves": ["L"]}
FORM = {"accessories": [{"key": "helmet", "who": "rider", "field": "helmet_size", "size": "L", "checked": True},
                        {"key": "jacket", "who": "rider", "field": "jacket_size", "size": "L", "checked": False}],
        "gear_add": True, "moto_equipment": [{"key": "luggage", "qty": 1, "checked": True}], "mileage": "5"}


def gear_proto(bid: str = "g1", required: bool = True, **extra) -> dict:
    return {"booking_id": bid, "required": required, "filled_at": None if required else "2026-10-23T08:00:00Z",
            "needs_locker": True, "is_child": False, "prompted_at": None, "gear_collected_at": None, "moto_id": None,
            "gear_only": True, "sizes_catalog": CATALOG,
            "data": {"customer_name": "Jana N.", "moto_model": None, "moto_spz": None, "start_date": "2026-10-23",
                     "end_date": "2026-10-25", "mileage": None, "gear": [dict(g) for g in GEAR]}, **extra}


def rpc_gear(bid: str = "g1", **pk) -> dict:
    return {"ok": True, "kind": "accessories", "booking_id": bid, "gear_only": True,
            "door": {"id": "d8", "door_kind": "accessories", "box_number": None}, "protocol": gear_proto(bid, **pk)}


def rpc_moto(bid: str = "b2", code_kind: str = "motorcycle") -> dict:
    door = {"id": "d3", "door_kind": "motorcycle", "box_number": 3} if code_kind == "motorcycle" else \
        {"id": "d8", "door_kind": "accessories", "box_number": None}
    return {"ok": True, "kind": code_kind, "booking_id": bid, "box_number": door["box_number"], "door": door,
            "protocol": protocol(bid)}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "777777", "kind": "accessories", "booking_id": "g1", "door_id": "d8", "gear_only": True},
             {"code": "222222", "kind": "motorcycle", "booking_id": "b2", "door_id": "d3", "box_number": 3}],
            [gear_proto("g1"), protocol("b2")])
    c.api.resolve = {"777777": rpc_gear(), "222222": rpc_moto("b2")}
    yield c
    c.close()


def test_resolve_result_gear_only_flags(ctrl):
    assert ResolveResult.from_rpc(rpc_gear()).gear_only is True
    only_proto = {k: v for k, v in rpc_gear().items() if k != "gear_only"}
    assert ResolveResult.from_rpc(only_proto).gear_only is True                 # z protocol.gear_only
    assert ResolveResult.from_rpc(rpc_moto()).gear_only is False                # běžná rezervace / stará DB
    assert ResolveResult.from_rpc({**rpc_gear(), "temp": True}).gear_only is False   # krátkodobý kód nikdy
    from datetime import datetime, timezone
    rr = ctrl.resolver.resolve("777777", ctrl.storage.load_code_cache(), datetime.now(timezone.utc))
    assert rr.ok and rr.offline and rr.gear_only and rr.kind == "accessories"   # codes[].gear_only (offline)


async def test_pickup_opens_locker_without_moto_hold_and_shows_gear_protocol(ctrl):
    hm, wz = ctrl.handover, ctrl.zones[8]
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] and res["kind"] == "accessories" and res["zone"] == 8 and wz.grants == [("g1", "accessories", "ui")]
    assert getattr(wz, "hold_until_moto_code", False) is False and wz.light_off_on_secure is True   # kód motorky nepřijde
    assert hm.gear.visits["g1"]["returning"] is False
    assert await hm.on_wardrobe_closed(8, "g1") == "protocol"
    st = hm.status()
    a = st["active"]
    assert a["gear_only"] is True and a["needs_code"] is True and a["then_open"] is False and a["kind_origin"] == "accessories"
    assert a["sizes"]["helmet"] == ["S", "M", "L"] and a["sizes"]["jacket"] == ["M", "L"]   # katalog ∩ meze samoobsluhy
    assert a["sizes"]["gloves"] == ["L"] and a["sizes"]["boots"] == []
    assert [g["size"] for g in a["data"]["gear"]] == ["M", "L"]
    assert st["lock"] == {**st["lock"], "booking_id": "g1", "zone": 8, "gear_only": True}
    assert st["gear"] == {"return": None, "visits": {"g1": "pickup"}}
    shown = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SHOWN]
    assert len(shown) == 1 and shown[0].code_kind == "accessories" and shown[0].zone == 8


async def test_other_customer_waits_with_gear_lock_text(ctrl):
    await cc.submit_code(ctrl, "777777", "ui")
    await ctrl.handover.on_wardrobe_closed(8, "g1")
    res = await cc.submit_code(ctrl, "222222", "ui")
    assert res["error"] == "handover_in_progress" and res["message"] == hg.LOCK_TEXT
    assert ctrl.zones[3].grants == [] and ctrl.storage.pin_failures_since(0) == 0


async def test_sign_with_locker_code_no_bay_and_lock_released(ctrl):
    hm = ctrl.handover
    await cc.submit_code(ctrl, "777777", "ui")
    await hm.on_wardrobe_closed(8, "g1")
    assert (await hm.submit("g1", FORM, SIG, None))["error"] == "code_mismatch"       # kód povinný
    assert (await hm.submit("g1", FORM, SIG, "222222"))["error"] == "code_mismatch"   # kód jiné rezervace = hádání
    assert ctrl.storage.pin_failures_since(0) == 1 and ctrl.kinds().count("PIN_INVALID") == 1
    assert "šatny" in [e for e in ctrl.events if e.kind == EventKind.PIN_INVALID][0].message
    res = await hm.submit("g1", FORM, SIG, "777 777")
    assert res == {"ok": True, "status": "saved", "opened": None, "error": None, "gear_only": True}
    assert ctrl.zones[3].grants == [] and ctrl.zones[8].grants == [("g1", "accessories", "ui")]   # žádné další otevření
    sent = ctrl.api.submits[-1]
    assert sent["gear_only"] is True and sent["form"]["gear_add"] is False
    assert "moto_equipment" not in sent["form"] and "mileage" not in sent["form"]
    assert sent["form"]["accessories"][1]["checked"] is False and sent["form"]["accessories"][1]["size"] == "L"
    signed = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SIGNED]
    assert len(signed) == 1 and signed[0].code_kind == "accessories" and signed[0].zone == 8
    assert hm.lock.status() is None and hm.status()["active"] is None and hm.signed_local("g1")
    res2 = await cc.submit_code(ctrl, "222222", "ui")                                   # další zákazník na řadě
    assert res2["error"] != "handover_in_progress"


async def test_sign_offline_with_cached_locker_code(ctrl):
    hm = ctrl.handover
    await cc.submit_code(ctrl, "777777", "ui")
    await hm.on_wardrobe_closed(8, "g1")
    ctrl.api.resolve = {"777777": None}                                                 # síť dole → offline cache
    res = await hm.submit("g1", FORM, SIG, "777777")
    assert res["ok"] and res["gear_only"] and res["opened"] is None


async def test_upload_failure_event_is_accessories(ctrl):
    hm = ctrl.handover
    await cc.submit_code(ctrl, "777777", "ui")
    await hm.on_wardrobe_closed(8, "g1")
    ctrl.api.results.append({"ok": False, "permanent": True, "error": "not_self_service", "already_filled": False})
    res = await hm.submit("g1", FORM, SIG, "777777")
    assert res["ok"] and res["status"] == "queued"                                      # podpis se neztratí (failed[])
    failed = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_UPLOAD_FAILED]
    assert len(failed) == 1 and failed[0].code_kind == "accessories"
    assert hm.status()["failed"] == ["g1"]


async def test_remote_signature_releases_gear_lock_and_shows_gear_toast(ctrl):
    hm = ctrl.handover
    await cc.submit_code(ctrl, "777777", "ui")
    await hm.on_wardrobe_closed(8, "g1")
    assert hm.lock.active()
    assert await hm.mark_signed_remote("g1", may_open=True) is None                    # žádná kóje k otevření
    a = hm.status()["active"]
    assert hm.lock.status() is None and a["stage"] == "done" and a["gear_only"] is True
    assert ctrl.zones[3].grants == []


async def test_gear_item_persists_flags(ctrl, tmp_path):
    hm = ctrl.handover
    await cc.submit_code(ctrl, "777777", "ui")
    await hm.on_wardrobe_closed(8, "g1")
    hm2 = HandoverManager(ctrl, clock=ctrl.clock)                                       # restart procesu
    item = hm2.items["g1"]
    assert item.gear_only is True and item.sizes_catalog == CATALOG and item.visible is False
    assert hm2.lock.booking_id == "g1"


async def test_moto_booking_flow_unchanged(ctrl):
    """Regrese: šatna rezervace s motorkou dál drží hudbu do kódu motorky, protokol bez `gear_only`, snapshot bez `gear`."""
    ctrl.api.resolve["888888"] = rpc_moto("b2", "accessories")
    hm, wz = ctrl.handover, ctrl.zones[8]
    res = await cc.submit_code(ctrl, "888888", "ui")
    assert res["ok"] and wz.hold_until_moto_code is True and not getattr(wz, "light_off_on_secure", False)
    assert await hm.on_wardrobe_closed(8, "b2") == "protocol"
    st = hm.status()
    assert "gear_only" not in st["active"] and "gear" not in st and "gear_only" not in st["lock"]
    assert st["active"]["sizes"]["pants"] == ["S", "M", "L", "XL", "2XL", "3XL", "4XL"]   # číselník ze syncu (+ záloha)
    assert (await hm.submit("b2", FORM, SIG, "888888"))["error"] == "code_mismatch"     # identita = kód MOTORKY
    res = await hm.submit("b2", FORM, SIG, "222222")
    assert res["ok"] and "gear_only" not in res and res["opened"]["zone"] == 3
    sent = ctrl.api.submits[-1]
    assert "gear_only" not in sent and sent["form"]["gear_add"] is True and "moto_equipment" in sent["form"]
