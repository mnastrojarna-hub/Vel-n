"""Výpůjčka výbavy bez motorky — převzetí, nebo vrácení? (1.3.0, CONTRACT §33). Dotaz „Vracíš všechnu výbavu?“ jen když byla
výbava vyzvednutá PŘED touto návštěvou: zavření šatny na jednotce (`picked`, persist), podpis z displeje ve frontě, nebo server
`gear_collected_at`. Podpis ve Velíně před převzetím (příkaz `protocol_signed` → `hm.signed`), sync během návštěvy, znovuzavření
v téže relaci ani offline cache bez záznamu dotaz NEvyvolají (Ano by výpůjčku omylem ukončilo)."""
from __future__ import annotations

from datetime import datetime, timezone

import pytest

from motogo_box import controller_codes as cc
from motogo_box import handover_gear as hg
from motogo_box.handover import HandoverManager
from motogo_box.models import EventKind

from tests.handover_fakes import SIG, FakeCtrl
from tests.test_gear_only import FORM, rpc_gear


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "777777", "kind": "accessories", "booking_id": "g1", "door_id": "d8", "gear_only": True}], [])
    c.zones[8].session_ctx = {"session_id": "a" * 32}
    yield c
    c.close()


async def _return_visit(ctrl) -> str | None:
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] and res["zone"] == 8
    return await ctrl.handover.on_wardrobe_closed(8, "g1")


async def test_offline_return_after_pickup_signed_on_this_display(ctrl):
    """Převzetí a podpis na tomto displeji, vrácení po 2 dnech OFFLINE (cache: podepsaná rezervace v protocols[] chybí =
    absent) a po restartu procesu: důkaz převzetí drží jednotka (`picked`, kv) → dotaz; Ano → `offline: true`."""
    ctrl.api.resolve = {"777777": rpc_gear()}                                      # nepodepsáno, gear_collected_at null
    assert await _return_visit(ctrl) == "protocol"
    assert (await ctrl.handover.submit("g1", FORM, SIG, "777777"))["ok"]
    ctrl.clock.advance(2 * 86400)
    ctrl.handover.tick()                                                           # signed / visits po 24 h pryč
    assert "g1" not in ctrl.handover.signed and not ctrl.handover.gear.visits
    ctrl.handover = hm = HandoverManager(ctrl, clock=ctrl.clock)                   # restart procesu
    assert "g1" in hm.gear.picked
    ctrl.api.resolve = {"777777": None}                                            # offline
    assert await _return_visit(ctrl) == "return_ask" and hm.status()["gear"]["visits"] == {"g1": "return"}
    await hm.gear.answer("g1", True)
    assert [e for e in ctrl.events if e.kind == EventKind.GEAR_RETURN_CONFIRMED][0].detail["offline"] is True


def _pickup_only(ctrl) -> None:
    st = ctrl.handover.status()
    assert st["active"]["stage"] == "done" and st["active"]["gear_only"] is True and st["gear"]["return"] is None
    assert st["gear"]["visits"] == {"g1": "pickup"} and ctrl.handover.lock.status() is None
    assert EventKind.GEAR_RETURN_CONFIRMED.value not in ctrl.kinds()


async def test_first_pickup_signed_elsewhere_is_not_a_return(ctrl):
    """Podepsáno ve Velíně / appce a výbava ještě nevyzvednutá (gear_collected_at null) → zavření = převzetí: jen toast."""
    ctrl.api.resolve = {"777777": rpc_gear(required=False)}
    assert await _return_visit(ctrl) == "done"
    _pickup_only(ctrl)


async def test_velin_signature_command_before_first_pickup_is_not_a_return(ctrl):
    """Podpis ve Velíně PŘED převzetím pošle jednotce příkaz `protocol_signed` (→ `hm.signed`); sync během návštěvy udělá
    z protokolu `absent` a zákazník šatnu v téže relaci znovu otevře a zavře — pořád převzetí, žádný dotaz. Další návštěva
    (nový kód šatny) už je vrácení, i když server o zavření ještě neví (událost čeká ve frontě)."""
    hm = ctrl.handover
    ctrl.api.resolve = {"777777": rpc_gear(required=False)}                       # gear_collected_at null
    await hm.mark_signed_remote("g1", may_open=True)                              # commands.py protocol_signed
    assert "g1" in hm.signed
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] and hm.status()["gear"]["visits"] == {"g1": "pickup"}       # šatna: „vezměte si výbavu“
    await hm.reconcile([])                                                         # sync: podepsaná rezervace chybí
    assert await hm.on_wardrobe_closed(8, "g1") == "done"
    _pickup_only(ctrl)
    assert hm.on_wardrobe_opened(8, "g1") is False                                # znovuotevření v téže relaci
    assert await hm.on_wardrobe_closed(8, "g1") == "done" and hm.gear.ask is None
    ctrl.clock.advance(3600)
    assert await _return_visit(ctrl) == "return_ask"                              # vrácení: šatna už byla zavřena


async def test_offline_first_pickup_absent_or_stale_cache_is_not_a_return(ctrl):
    """Offline a v cache žádný záznam protokolu (podepsáno jinde před převzetím / zastaralá cache mimo okno protocols[]),
    na jednotce žádné předchozí zavření → převzetí s toastem, nikdy dotaz (Ano by výpůjčku omylem ukončilo)."""
    ctrl.api.resolve = {"777777": None}
    assert await _return_visit(ctrl) == "done"
    _pickup_only(ctrl)


async def test_online_return_after_pickup_on_this_display_and_forgotten_item_grace(ctrl):
    """Převzetí s podpisem na displeji; za 5 min znovu kód šatny (zapomenutý kus) = pořád převzetí (toast, bez dotazu);
    po `PICKUP_GRACE_S` je další návštěva vrácení (server: podepsáno, gear_collected_at vyplněné) → dotaz."""
    hm = ctrl.handover
    ctrl.api.resolve = {"777777": rpc_gear()}
    assert await _return_visit(ctrl) == "protocol"
    assert (await hm.submit("g1", FORM, SIG, "777777"))["ok"]
    ctrl.api.resolve = {"777777": rpc_gear(required=False, gear_collected_at="2023-11-14T22:13:20Z")}
    ctrl.clock.advance(5 * 60)
    assert await _return_visit(ctrl) == "done" and hm.status()["gear"]["visits"] == {"g1": "pickup"}
    ctrl.clock.advance(hg.PICKUP_GRACE_S)
    assert await _return_visit(ctrl) == "return_ask" and hm.status()["gear"]["visits"] == {"g1": "return"}


async def test_first_close_here_is_a_return_no_grace(ctrl):
    """Převzetí jinde / před záznamem jednotky, první zavření na jednotce je už vrácení (server: vyzvednuto) a zákazník dá
    „Ne“ → za 10 min znovu: pořád vrácení (grace platí jen po zavření při převzetí)."""
    hm = ctrl.handover
    ctrl.api.resolve = {"777777": rpc_gear(required=False, gear_collected_at="2023-11-10T08:00:00Z")}
    assert await _return_visit(ctrl) == "return_ask"
    assert hm.gear.picked["g1"]["at"] == 0.0
    await hm.gear.answer("g1", False)
    ctrl.clock.advance(10 * 60)
    assert await _return_visit(ctrl) == "return_ask"


def test_picked_record_persists_until_end_of_rental(ctrl):
    hm = ctrl.handover
    hm.gear._mark_closed("g1", rpc_gear()["protocol"], pickup=True)               # konec výpůjčky 2026-10-25
    until = datetime(2026, 10, 27, tzinfo=timezone.utc).timestamp()
    rec = hm.gear.picked["g1"]
    assert rec["at"] == ctrl.clock() and rec["until"] == pytest.approx(max(until, ctrl.clock() + hg.PICKED_KEEP_S))
    assert ctrl.storage.kv_get(hg.KV)["picked"]["g1"] == rec
    assert HandoverManager(ctrl, clock=ctrl.clock).gear.picked == {"g1": rec}     # restart
    ctrl.clock.t = rec["until"] + 1
    hm.tick()
    assert hm.gear.picked == {} and ctrl.storage.kv_get(hg.KV)["picked"] == {}
