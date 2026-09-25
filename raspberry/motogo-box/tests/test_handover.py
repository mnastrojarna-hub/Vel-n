"""Stavový automat předávacího protokolu na displeji (`handover.py`, DESIGN §4)."""
from __future__ import annotations

import pytest

from motogo_box.handover import DONE_TTL_S, ITEM_MAX_AGE_S, HandoverManager
from motogo_box.models import EventKind
from motogo_box.pins import LocalResolver

from tests.handover_fakes import FakeCtrl, protocol, rr_moto


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
    assert a["stage"] == "done" and a["booking_id"] == "b1" and hm.busy() is False
    ctrl.clock.advance(DONE_TTL_S + 1)
    hm.tick()
    assert hm.status()["active"] is None and hm.items == {}
    assert ctrl.kinds() == []                                       # bez PROTOCOL_SHOWN


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
    assert opened == {"zone": 3, "kind": "motorcycle", "message": "Otevřeno — Kóje 3. Příjemnou cestu! 🏍️"}
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
    assert st == {"active": None, "pending": [], "failed": [], "waiting": []}
