"""Stavový automat předávacího protokolu na displeji (`handover.py`, DESIGN §4)."""
from __future__ import annotations

import pytest

from motogo_box import controller_codes as cc
from motogo_box.handover import DONE_TTL_S, ITEM_MAX_AGE_S, HandoverItem, HandoverManager
from motogo_box.handover_lock import iso_ts
from motogo_box.models import EventKind
from motogo_box.pins import LocalResolver

from tests.handover_fakes import SIG, FakeCtrl, protocol, rr_moto


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "123456", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
            [protocol("b1")])
    yield c
    c.close()


async def test_wardrobe_closed_shows_protocol_once(ctrl):
    hm = ctrl.handover
    hm.remember(rr_moto(proto=protocol("b1")))
    assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
    a = hm.status()["active"]
    assert a["booking_id"] == "b1" and a["stage"] == "protocol" and a["zone"] == 8 and a["zone_label"] == "Šatna"
    assert a["kind"] == "accessories" and a["then_open"] is False and a["needs_code"] is True
    assert a["data"]["customer_name"] == "Petra S." and a["sizes"]["helmet"] == ["S", "M", "L"]
    assert a["expires_at"] and a["shown_at"] and a["saving"] is False
    shown = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SHOWN]
    assert len(shown) == 1 and shown[0].booking_id == "b1" and shown[0].code_kind == "accessories" and shown[0].zone == 8
    assert shown[0].door_id == "d8"
    assert await hm.on_wardrobe_closed(8, "b1") == "protocol"       # další zavření šatny = znovu vidět, bez 2. události
    assert len([e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SHOWN]) == 1
    # servisní relace (bez rezervace) protokol nespouští
    assert await hm.on_wardrobe_closed(8, None) is None


async def test_wardrobe_closed_signed_elsewhere_shows_done_toast(ctrl):
    hm = ctrl.handover
    hm.remember(rr_moto(proto=protocol("b1", required=False)))
    assert await hm.on_wardrobe_closed(8, "b1") == "done"
    a = hm.status()["active"]
    assert a["stage"] == "done" and a["booking_id"] == "b1"
    assert hm.busy() is True and hm.lock.booking_id == "b1"         # toast neblokuje, zámek přejímky ano (2026-09-28)
    ctrl.clock.advance(DONE_TTL_S + 1)
    hm.tick()
    assert hm.status()["active"] is None and hm.items == {}
    assert ctrl.kinds() == []                                       # bez PROTOCOL_SHOWN
    hm.lock.release("b1")
    assert hm.busy() is False


async def test_wardrobe_closed_from_cache_and_fail_open(tmp_path):
    ctrl = FakeCtrl(tmp_path)
    try:
        hm = ctrl.handover
        ctrl.cache([], None)                                        # stará cache bez protocols → stav neznámý
        assert await hm.on_wardrobe_closed(8, "b1") is None and hm.items == {}
        ctrl.cache([], [protocol("b1")])                            # protokol z offline cache
        assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
        hm.dismiss("b1")
        ctrl.cache([], [])                                          # seznam přítomen, rezervace v něm není = podepsáno
        assert await hm.on_wardrobe_closed(8, "b2") == "done"
    finally:
        ctrl.close()


async def test_require_before_open_gate(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    assert await hm.require_before_open(rr_moto(proto=None), zc, "ui") is False      # fail-open
    assert await hm.require_before_open(rr_moto(proto=protocol("b1", required=False)), zc, "ui") is False
    assert hm.items == {}
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is True
    a = hm.status()["active"]
    assert a["then_open"] is True and a["needs_code"] is False and a["zone"] == 3 and a["zone_label"] == "Kóje 3"
    assert a["kind"] == "motorcycle" and zc.grants == [] and hm.busy() is True
    # 2026-10-05: nárok na šatnu z protokolu → UI nabídne zápis výbavy i po kódu motorky; dětská = jen řidič
    assert a["needs_locker"] is True and a["is_child"] is False
    assert HandoverItem.from_dict(hm.items["b1"].persisted()).needs_locker is True
    assert [e.code_kind for e in ctrl.events if e.kind == EventKind.PROTOCOL_SHOWN] == ["motorcycle"]
    # podepsáno u displeje (čeká ve frontě) → hradlo se neuplatní ani při zastaralém required=true
    ctrl.storage.protocol_queue_put("b1", {"x": 1})
    hm.refresh_queue()
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is False


async def test_dismiss_then_remote_sign_does_not_open(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    assert hm.dismiss("b1") is True and hm.active() is None and hm.items["b1"].then_open is None
    assert hm.busy() is False and hm.status()["waiting"] == ["b1"]
    assert await hm.mark_signed_remote("b1", may_open=True) is None
    assert zc.grants == [] and hm.items == {} and hm.status()["active"] is None
    assert hm.dismiss("b1") is False


async def test_idle_hides_and_clears_then_open(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    ctrl.clock.advance(100)
    assert hm.touch("b1") is True                                  # dotyk prodlužuje
    ctrl.clock.advance(100)
    hm.tick()
    assert hm.active() is not None
    ctrl.clock.advance(hm.idle_s)
    hm.tick()
    assert hm.active() is None and hm.items["b1"].then_open is None and hm.touch("b1") is False
    assert await hm.mark_signed_remote("b1", may_open=True) is None and zc.grants == []


async def test_remote_sign_with_visible_then_open_opens_once(ctrl):
    """Jen příkaz `protocol_signed` (may_open=True) smí otevřít; výchozí volání (sync) nikdy."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    assert await hm.mark_signed_remote("b1") is None and zc.grants == []      # bez may_open → jen toast DONE
    assert hm.status()["active"]["stage"] == "done" and "b1" in hm.signed
    ctrl.clock.advance(DONE_TTL_S + 1)
    hm.tick()
    del hm.signed["b1"]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    opened = await hm.mark_signed_remote("b1", may_open=True)
    assert opened == {"zone": 3, "kind": "motorcycle", "message": "Dveře č. 3 otevřeny — běžte ke dveřím č. 3."}
    assert zc.grants == [("b1", "motorcycle", "ui")] and hm.items == {}
    assert await hm.mark_signed_remote("b1", may_open=True) is None and len(zc.grants) == 1   # idempotentní
    assert "b1" in hm.signed


async def test_remote_sign_visible_without_then_open_shows_done(ctrl):
    hm = ctrl.handover
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    assert await hm.mark_signed_remote("b1", may_open=True) is None
    assert hm.status()["active"]["stage"] == "done" and ctrl.zones[3].grants == []


async def test_restart_clears_visibility_and_then_open(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    hm2 = HandoverManager(ctrl, clock=ctrl.clock)
    assert "b1" in hm2.items and hm2.items["b1"].visible is False and hm2.items["b1"].then_open is None
    assert hm2.active() is None and hm2.items["b1"].shown_logged is True
    assert hm2.gear_sizes["adult"]["helmet"] == ["S", "M", "L"]
    assert await hm2.mark_signed_remote("b1", may_open=True) is None and zc.grants == []


async def test_new_item_hides_other_and_items_expire(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    await hm.require_before_open(rr_moto("b2", protocol("b2")), zc, "ui")
    assert hm.active().booking_id == "b2" and hm.items["b1"].visible is False
    assert sorted(hm.status()["waiting"]) == ["b1", "b2"]
    ctrl.clock.advance(ITEM_MAX_AGE_S + 1)
    hm.tick()
    assert hm.items == {}


async def test_reconcile_after_sync(ctrl):
    hm = ctrl.handover
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    fresh = protocol("b1")
    fresh["data"]["gear"][0]["size"] = "L"
    await hm.reconcile([fresh], {"adult": {"helmet": ["L"]}})
    assert hm.items["b1"].data["gear"][0]["size"] == "L" and hm.status()["active"]["sizes"]["helmet"] == ["L"]
    await hm.reconcile(None)                                        # stará DB bez seznamu → beze změny
    assert hm.items["b1"].stage == "protocol"
    await hm.reconcile([])                                          # rezervace v seznamu chybí (nejspíš podepsána jinde)
    assert hm.status()["active"]["stage"] == "done" and hm.protocols == {} and "b1" not in hm.signed
    hm.remember(rr_moto("b9", protocol("b9")))
    await hm.reconcile([])
    assert hm.protocols["b9"] == {"booking_id": "b9", "required": False, "absent": True}


async def test_reconcile_absent_never_opens_nor_marks_signed(ctrl):
    """Sync neumí rozlišit „podepsáno jinde“ od „kód odebrán / rezervace zrušena“ (CONTRACT §28 pravidlo 1):
    chybějící rezervace → jen skrýt (toast DONE), then_open se NEspotřebuje a `signed` se NEzapíše."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    assert hm.status()["active"]["then_open"] is True
    await hm.reconcile([])
    assert zc.grants == [] and hm.status()["active"]["stage"] == "done" and hm.signed == {}
    ctrl.clock.advance(DONE_TTL_S + 1)
    hm.tick()
    await hm.reconcile([protocol("b1")])                            # kód znovu aktivován → hradlo platí dál
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is True and zc.grants == []
    hm.dismiss("b1")                                                # skrytá položka: absence ji smaže bez toastu
    await hm.reconcile([])
    assert hm.items == {} and hm.status()["active"] is None and hm.signed == {}


async def test_reconcile_filled_marks_signed_but_never_opens(ctrl):
    """Explicitní `required=false` ze sync = potvrzený podpis, kóje se ale z cesty sync nikdy neotevře."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    await hm.reconcile([protocol("b1", required=False)])
    assert zc.grants == [] and hm.status()["active"]["stage"] == "done" and "b1" in hm.signed
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is False   # zastaralé required


async def test_reconcile_required_clears_stale_local_signed(ctrl):
    """Server je zdroj pravdy: `required=true` v syncu ruší lokální „podepsáno“ (např. vrácený claim edge);
    podpis čekající ve frontě hradlo dál obchází."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.mark_signed_remote("b1", may_open=True)
    assert "b1" in hm.signed
    await hm.reconcile([protocol("b1")])
    assert "b1" not in hm.signed and HandoverManager(ctrl, clock=ctrl.clock).signed == {}   # i persist
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is True
    hm.dismiss("b1")
    ctrl.storage.protocol_queue_put("b1", {"x": 1})
    hm.refresh_queue()
    await hm.reconcile([protocol("b1")])
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is False


async def test_absent_in_cache_is_fail_open_without_memory(ctrl):
    """Offline cache bez záznamu rezervace (podepsáno jinde / cache mimo okno) → otevřít bez hradla, ale nic si
    nepamatovat: další protokol s `required=true` hradlo obnoví."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    ctrl.cache([{"code": "123456", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}], [])
    p = LocalResolver.protocol_for(ctrl.storage.load_code_cache(), "b1")
    assert p == {"booking_id": "b1", "required": False, "absent": True}
    assert await hm.require_before_open(rr_moto(proto=p), zc, "ui") is False
    assert hm.signed == {} and hm.items == {}
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is True


async def test_status_shape_when_idle(ctrl):
    st = ctrl.handover.status()
    assert st == {"active": None, "pending": [], "failed": [], "waiting": [], "lock": None}


# ─── Zámek přejímky (rozhodnutí majitele 2026-09-28, handover_lock.py) ──────────────────────────────
def _door(kind: str, zone: int, box: int | None = None) -> dict:
    return {"id": f"d{zone}", "door_kind": kind, "box_number": box}


def _online(ctrl, b1_required: bool = True, b2_required: bool = True) -> None:
    """Online RPC pro `submit_code`: b1 = šatna 888888 + motorka 111111, b2 = šatna 999999 + motorka 222222, servisní heslo."""
    ctrl.api.resolve = {
        "111111": {"ok": True, "kind": "motorcycle", "booking_id": "b1", "box_number": 3, "door": _door("motorcycle", 3, 3),
                   "protocol": protocol("b1", required=b1_required)},
        "888888": {"ok": True, "kind": "accessories", "booking_id": "b1", "door": _door("accessories", 8),
                   "protocol": protocol("b1", required=b1_required)},
        "222222": {"ok": True, "kind": "motorcycle", "booking_id": "b2", "box_number": 3, "door": _door("motorcycle", 3, 3),
                   "protocol": protocol("b2", required=b2_required)},
        "999999": {"ok": True, "kind": "accessories", "booking_id": "b2", "door": _door("accessories", 8),
                   "protocol": protocol("b2", required=b2_required)},
        "SERVIS1": {"ok": True, "kind": "service", "doors": []},
    }


async def test_lock_set_on_every_customer_wardrobe_close_and_persisted(ctrl):
    hm = ctrl.handover
    assert hm.lock.state is None and hm.status()["lock"] is None and hm.lock_s == 600
    hm.remember(rr_moto(proto=protocol("b1")))
    assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
    st = hm.status()["lock"]
    assert st == {"booking_id": "b1", "zone": 8, "until": iso_ts(ctrl.clock() + 600), "customer_name": "Petra S."}
    assert hm.lock.state["since"] == hm.lock.state["last_activity"] == ctrl.clock()
    assert hm.lock.active() and hm.lock.blocks("b2") and not hm.lock.blocks("b1") and hm.busy() is True
    hm2 = HandoverManager(ctrl, clock=ctrl.clock)                   # restart procesu: zámek z kv přežije
    assert hm2.lock.state == hm.lock.state and hm2.status()["lock"] == st
    ctrl.clock.advance(10)
    ctrl.cache([], [])                                              # b2 v cache chybí → podepsáno jinde (toast DONE)
    assert await hm.on_wardrobe_closed(8, "b2") == "done" and hm.lock.booking_id == "b2"
    assert hm.lock.state["since"] == ctrl.clock() and hm.status()["lock"]["customer_name"] is None
    ctrl.cache([], None)                                            # stará cache → stav protokolu neznámý (fail-open)
    assert await hm.on_wardrobe_closed(8, "b3") is None and hm.lock.booking_id == "b3"
    assert await hm.on_wardrobe_closed(8, None) is None and hm.lock.booking_id == "b3"   # servisní relace zámek nemění


async def test_lock_refuses_foreign_codes_until_own_bay_opens(ctrl):
    hm, moto, wardrobe = ctrl.handover, ctrl.zones[3], ctrl.zones[8]
    _online(ctrl, b2_required=False)
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    hm.dismiss("b1")
    for code, kind in (("222222", "motorcycle"), ("999999", "accessories")):
        res = await cc.submit_code(ctrl, code, "ui")
        assert res["ok"] is False and res["error"] == "handover_in_progress" and res["kind"] == kind
        assert res["booking_id"] == "b2" and res["locked_until"] is None and "předchozí přejímka" in res["message"]
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert [e.code_kind for e in denied] == ["motorcycle", "accessories"] and denied[0].booking_id == "b2"
    assert denied[0].level == "warn" and denied[0].success is False
    assert denied[0].detail == {"source": "ui", "reason": "handover_in_progress", "locked_booking_id": "b1", "offline": False}
    assert ctrl.storage.pin_failures_since(0) == 0 and "PIN_INVALID" not in ctrl.kinds()   # platný kód, žádný lockout
    assert moto.grants == [] and wardrobe.grants == []
    ctrl.clock.advance(100)                                         # vlastní kód šatny znovu projde + obnoví aktivitu
    res = await cc.submit_code(ctrl, "888888", "ui")
    assert res["ok"] and wardrobe.grants == [("b1", "accessories", "ui")] and hm.lock.state["last_activity"] == ctrl.clock()
    res = await cc.submit_code(ctrl, "111111", "ui")                # vlastní kód motorky: protokol → then_open, zámek trvá
    assert res["error"] == "protocol_required" and hm.lock.active() and hm.status()["active"]["then_open"] is True
    res = await hm.submit("b1", {}, SIG, None)                      # podpis → kóje otevřena → zámek pryč
    assert res["ok"] and res["opened"]["zone"] == 3 and moto.grants == [("b1", "motorcycle", "ui")]
    assert hm.lock.state is None and hm.status()["lock"] is None and hm.busy() is False
    assert (await cc.submit_code(ctrl, "222222", "ui"))["ok"] is True      # další zákazník na řadě
    assert moto.grants[-1] == ("b2", "motorcycle", "ui")


async def test_lock_released_by_motorcycle_grant_and_remote_signature(ctrl):
    hm, moto = ctrl.handover, ctrl.zones[3]
    _online(ctrl, b1_required=False)
    hm.remember(rr_moto(proto=protocol("b1", required=False)))
    assert await hm.on_wardrobe_closed(8, "b1") == "done" and hm.lock.active()
    assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"] is True       # podepsáno jinde → kóje rovnou
    assert moto.grants == [("b1", "motorcycle", "ui")] and hm.lock.state is None
    hm.remember(rr_moto(proto=protocol("b1")))                      # příkaz protocol_signed s viditelným then_open
    await hm.on_wardrobe_closed(8, "b1")
    await hm.require_before_open(rr_moto(proto=protocol("b1")), moto, "ui")
    assert hm.lock.active()
    assert (await hm.mark_signed_remote("b1", may_open=True))["zone"] == 3 and hm.lock.state is None
    del hm.signed["b1"]
    moto.result = (False, "busy")                                   # kóje se neotevřela → zámek zůstává (kód znovu)
    await hm.on_wardrobe_closed(8, "b1")
    await hm.require_before_open(rr_moto(proto=protocol("b1")), moto, "ui")
    res = await hm.submit("b1", {}, SIG, None)
    assert res["ok"] and res["opened"] is None and res["error"] == "busy" and hm.lock.active()


async def test_lock_expires_without_activity_and_touch_extends(ctrl):
    hm = ctrl.handover
    _online(ctrl, b2_required=False)
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    ctrl.clock.advance(hm.lock_s - 1)
    assert hm.touch("b1") is True                                   # dotyk v protokolu = aktivita zámku
    ctrl.clock.advance(hm.lock_s - 1)
    hm.tick()
    assert hm.lock.active() and (await cc.submit_code(ctrl, "222222", "ui"))["error"] == "handover_in_progress"
    ctrl.clock.advance(1)
    hm.tick()
    assert hm.lock.state is None and hm.status()["lock"] is None and hm.busy() is False
    assert HandoverManager(ctrl, clock=ctrl.clock).lock.state is None      # vypršení se persistuje
    assert (await cc.submit_code(ctrl, "222222", "ui"))["ok"] is True


async def test_lock_never_blocks_service_or_fixed_codes(ctrl):
    hm = ctrl.handover
    _online(ctrl)
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    res = await cc.submit_code(ctrl, "SERVIS1", "ui")
    assert res["ok"] and res["kind"] == "service" and res["service_token"] in ctrl.service_tokens
    res = await cc.submit_code(ctrl, "39301H", "ui")                # pevný servisní kód šatny
    assert res["ok"] and res["kind"] == "service_door" and ctrl.zones[8].grants == [(None, "service", "fixed_service_code")]
    assert hm.lock.active() and "ACCESS_DENIED" not in ctrl.kinds()   # servis zámek nemění a nic neodmítá
    assert hm.lock.release(None, "all_off") is True and hm.lock.state is None   # servisní „Vše vypnout“ (controller.all_off)
    assert hm.lock.release("b1") is False
