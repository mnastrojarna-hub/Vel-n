"""Výpůjčka výbavy bez motorky — vrácení na kiosku (1.3.0, CONTRACT §33, varianta B): zavření šatny PODEPSANÉ rezervace →
dotaz „Vracíš všechnu výbavu?“; Ano → GEAR_RETURN_CONFIRMED (kiosk_log_open, kind accessories, session_id návštěvy) a offline
hradlo kódu šatny 15 min po zavření; Ne / bez odpovědi → nic. Bez zámku přejímky. + endpoint `/api/gear/return` a statika UI."""
from __future__ import annotations

import asyncio
import time
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from aiohttp.test_utils import TestClient, TestServer

from motogo_box import controller_codes as cc
from motogo_box import handover_gear as hg
from motogo_box import return_gate as rg
from motogo_box.config import LocalConfig
from motogo_box.controller import BoxController
from motogo_box.models import Event, EventKind, ResolveResult
from motogo_box.storage import Storage
from motogo_box.webserver import WebServer

from tests.handover_fakes import FakeCtrl
from tests.test_gear_only import rpc_gear

M = 60


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).isoformat(timespec="milliseconds")


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "777777", "kind": "accessories", "booking_id": "g1", "door_id": "d8", "gear_only": True}], [])
    c.api.resolve = {"777777": rpc_gear(required=False, gear_collected_at="2026-10-23T08:05:00Z")}
    c.zones[8].session_ctx = {"session_id": "a" * 32}
    yield c
    c.close()


async def _return_visit(ctrl) -> str | None:
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] and res["zone"] == 8
    return await ctrl.handover.on_wardrobe_closed(8, "g1")


async def test_signed_booking_close_asks_return_without_lock(ctrl):
    hm = ctrl.handover
    assert await _return_visit(ctrl) == "return_ask"
    assert hm.lock.status() is None and hm.status()["active"] is None              # žádný zámek ani protokol
    st = hm.status()["gear"]
    assert st["visits"] == {"g1": "return"}
    r = st["return"]
    assert r["booking_id"] == "g1" and r["zone"] == 8 and r["grace_min"] == 15 and r["expires_at"]
    assert r["data"] == {"customer_name": "Jana N.", "start_date": "2026-10-23", "end_date": "2026-10-25"}
    assert hm.busy() is True                                                       # aktualizace počká na odpověď


async def test_yes_emits_gear_return_confirmed_once(ctrl):
    hm = ctrl.handover
    await _return_visit(ctrl)
    assert await hm.gear.answer("g1", True) == {"ok": True, "confirmed": True, "error": None}
    ev = [e for e in ctrl.events if e.kind == EventKind.GEAR_RETURN_CONFIRMED]
    assert len(ev) == 1
    e = ev[0]
    assert (e.booking_id, e.code_kind, e.door_id, e.zone, e.success) == ("g1", "accessories", "d8", 8, True)
    assert e.detail["source"] == "kiosk" and e.detail["session_id"] == "a" * 32 and e.detail["offline"] is False
    assert datetime.fromisoformat(e.detail["closed_ts"]).tzinfo is not None
    d = cc.open_detail(e)                                                          # tělo kiosk_log_open
    assert d["event"] == "GEAR_RETURN_CONFIRMED" and d["ts"] == e.ts and d["zone"] == 8 and d["source"] == "kiosk"
    assert e.kind in cc.LOG_OPEN_KINDS and cc.log_open_kind(e) == "accessories"
    assert hm.status().get("gear", {}).get("return") is None and hm.busy() is False
    assert (await hm.gear.answer("g1", True))["error"] == "not_pending"           # dotaz se spotřeboval
    assert len([e for e in ctrl.events if e.kind == EventKind.GEAR_RETURN_CONFIRMED]) == 1


async def test_no_and_timeout_do_nothing(ctrl):
    hm = ctrl.handover
    await _return_visit(ctrl)
    assert await hm.gear.answer("g1", False) == {"ok": True, "confirmed": False, "error": None}
    await _return_visit(ctrl)
    ctrl.clock.advance(hg.ASK_S + 1)
    hm.tick()
    assert hm.status()["gear"]["return"] is None and hm.busy() is False
    assert (await hm.gear.answer("g1", True))["error"] == "not_pending"
    assert EventKind.GEAR_RETURN_CONFIRMED.value not in ctrl.kinds()


async def test_reopen_hides_question_and_next_close_asks_again(ctrl):
    hm = ctrl.handover
    await _return_visit(ctrl)
    assert hm.on_wardrobe_opened(8, "g1") is True and hm.status()["gear"]["return"] is None
    assert await hm.on_wardrobe_closed(8, "g1") == "return_ask"


async def test_offline_flag_and_signed_on_this_display(ctrl):
    hm = ctrl.handover
    ctrl.api.resolve = {"777777": None}                                            # offline: cache bez protocols[] záznamu
    hm.signed["g1"] = ctrl.clock()                                                 # podepsáno dřív na tomto displeji
    assert await _return_visit(ctrl) == "return_ask"
    await hm.gear.answer("g1", True)
    assert [e for e in ctrl.events if e.kind == EventKind.GEAR_RETURN_CONFIRMED][0].detail["offline"] is True


async def test_first_pickup_signed_elsewhere_is_not_a_return(ctrl):
    """Podepsáno ve Velíně / appce a výbava ještě nevyzvednutá (gear_collected_at null) → zavření = převzetí: jen toast."""
    ctrl.api.resolve = {"777777": rpc_gear(required=False)}
    assert await _return_visit(ctrl) == "done"
    st = ctrl.handover.status()
    assert st["active"]["stage"] == "done" and st["active"]["gear_only"] is True and st["gear"]["return"] is None
    assert st["gear"]["visits"] == {"g1": "pickup"} and ctrl.handover.lock.status() is None


async def test_unknown_state_without_protocol_does_nothing(ctrl):
    hm = ctrl.handover
    ctrl.cache([{"code": "999999", "kind": "accessories", "booking_id": "g9", "door_id": "d8", "gear_only": True}], None)
    hm.gear.visits["g9"] = {"returning": False, "offline": True, "at": ctrl.clock()}
    assert await hm.on_wardrobe_closed(8, "g9") is None             # stará cache bez protocols[] → bez protokolu i dotazu
    assert hm.lock.status() is None and hm.status()["gear"]["return"] is None


# ─── offline hradlo (return_gate) ──────────────────────────────────────────────────────────────────
def _confirm(storage, closed: float, at: float, code_kind: str = "accessories") -> None:
    rg.observe(storage, Event(kind=EventKind.GEAR_RETURN_CONFIRMED, booking_id="g1", code_kind=code_kind,
                              detail={"source": "kiosk", "closed_ts": iso(closed), "session_id": "s"}, ts=iso(at)))


def _rr(**kw) -> ResolveResult:
    return ResolveResult(**{"ok": True, "kind": "accessories", "booking_id": "g1", "offline": True, "gear_only": True, **kw})


def test_gate_blocks_locker_code_15_min_after_confirmed_close(tmp_path):
    st = Storage(str(tmp_path / "g.db"))
    c = SimpleNamespace(storage=st, hardware=None)
    now = time.time()
    _confirm(st, closed=now - 10 * M, at=now - 9 * M)
    assert rg.record(st, "g1")["gear"] == pytest.approx(now - 10 * M, abs=0.01)    # čas ZAVŘENÍ šatny, ne potvrzení
    assert rg.blocks(c, _rr(), now) is False                                        # v okně 15 min
    assert rg.blocks(c, _rr(), now + 6 * M) is True                                 # po doběhu
    assert rg.blocks(c, _rr(offline=False), now + 6 * M) is False                   # online rozhoduje server
    assert rg.blocks(c, _rr(gear_only=False), now + 6 * M) is False                 # bez flagu = pravidla §32 (bez final)
    rg.observe(st, Event(kind=EventKind.SESSION_COMPLETED, booking_id="g1", code_kind="accessories",
                         detail={"source": "ui"}, ts=iso(now + 5 * M)))             # znovu zavřeno v okně → posun
    assert rg.blocks(c, _rr(), now + 6 * M) is False and rg.blocks(c, _rr(), now + 21 * M) is True
    st.close()


def test_gate_ignores_moto_kind_and_unconfirmed(tmp_path):
    st = Storage(str(tmp_path / "g.db"))
    c = SimpleNamespace(storage=st, hardware=None)
    now = time.time()
    rg.observe(st, Event(kind=EventKind.SESSION_COMPLETED, booking_id="g1", code_kind="accessories",
                         detail={"source": "ui"}, ts=iso(now - 60 * M)))            # jen zavření, bez potvrzení
    assert rg.blocks(c, _rr(), now) is False
    _confirm(st, closed=now - 60 * M, at=now - 59 * M, code_kind="motorcycle")     # cizí druh se nezapíše
    assert "gear" not in rg.record(st, "g1")
    st.close()


async def test_submit_code_offline_refuses_after_confirmed_return(ctrl):
    ctrl.api.resolve = {"777777": None}
    _confirm(ctrl.storage, closed=time.time() - 20 * M, at=time.time() - 19 * M)
    res = await cc.submit_code(ctrl, "777777", "ui")
    assert res["ok"] is False and res["error"] == "code_revoked" and ctrl.zones[8].grants == []
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED][-1]
    assert denied.detail["reason"] == "returned" and "výbava" in denied.message
    assert ctrl.storage.pin_failures_since(0) == 0                                  # bez lockoutu


async def test_box_controller_emit_sends_log_open_and_feeds_gate():
    sent: list = []

    class Api:
        async def log_open(self, door_id, kind, booking_id, success, detail):
            sent.append((door_id, kind, booking_id, success, detail))

    st = Storage(":memory:")
    box = SimpleNamespace(storage=st, zones={}, api=Api(), last_error=None, ui_notice=None)
    closed = time.time() - 30
    ev = Event(kind=EventKind.GEAR_RETURN_CONFIRMED, zone=8, door_id="d8", booking_id="g1", box_number=None,
               code_kind="accessories", detail={"source": "kiosk", "session_id": "s1", "closed_ts": iso(closed), "offline": False})
    await BoxController.emit(box, ev)
    await asyncio.sleep(0)
    door, kind, bid, ok, detail = sent[0]
    assert (door, kind, bid, ok) == ("d8", "accessories", "g1", True)
    assert detail["event"] == "GEAR_RETURN_CONFIRMED" and detail["session_id"] == "s1" and detail["ts"] == ev.ts
    assert detail["offline"] is False and detail["closed_ts"] == iso(closed) and detail["source"] == "kiosk"
    assert rg.record(st, "g1")["gear"] == pytest.approx(closed, abs=0.01)
    st.close()


# ─── webserver: /api/gear/return + statika UI ─────────────────────────────────────────────────────
@pytest.fixture
async def web(ctrl):
    server = WebServer(ctrl, SimpleNamespace(paired=True), SimpleNamespace(), LocalConfig())
    client = TestClient(TestServer(server.app))
    await client.start_server()
    try:
        yield client
    finally:
        await client.close()


async def test_http_gear_return_endpoint(web, ctrl):
    assert (await web.post("/api/gear/return", json={"answer": "yes"})).status == 400
    r = await web.post("/api/gear/return", json={"booking_id": "g1", "answer": "maybe"})
    assert r.status == 400 and (await r.json())["error"] == "bad_answer"
    assert (await (await web.post("/api/gear/return", json={"booking_id": "g1", "answer": "yes"})).json())["error"] == "not_pending"
    await _return_visit(ctrl)
    body = await (await web.post("/api/gear/return", json={"booking_id": "g1", "answer": "yes"})).json()
    assert body == {"ok": True, "confirmed": True, "error": None}
    assert EventKind.GEAR_RETURN_CONFIRMED.value in ctrl.kinds()


async def test_ui_static_and_order(web):
    for f in ("handover-gear.js", "i18n-gear.js", "i18n-gear-return.js", "style-gear.css"):
        assert (await web.get(f"/static/{f}")).status == 200, f
    html = await (await web.get("/")).text()
    assert 'id="gear-return"' in html and 'id="gr-yes"' in html and 'id="gr-no"' in html and "style-gear.css" in html
    assert html.index("i18n-codes.js") < html.index("i18n-gear.js") < html.index("i18n-gear-return.js") < html.index("keyboard.js")
    assert html.index("/static/handover-gear.js") < html.index("/static/handover.js") < html.index("/static/app.js")


@pytest.mark.parametrize("name, must", [("i18n-gear.js", {"code", "codeHint", "codeMismatch", "lockTitle", "pickOne"}),
                                         ("i18n-gear-return.js", {"title", "yes", "no", "close", "closeNo", "closeSub"})])
def test_i18n_gear_has_all_languages_and_keys(name, must):
    import os
    import re
    src = open(os.path.join(os.path.dirname(hg.__file__), "ui", name), encoding="utf-8").read()
    blocks = re.split(r"\n  (cs|en|de|es|fr|nl|pl|uk): \{", src)[1:]
    langs = blocks[0::2]
    assert langs == ["cs", "en", "de", "es", "fr", "nl", "pl", "uk"]
    key_sets = [set(re.findall(r"(\w+): '", body)) for body in blocks[1::2]]
    assert all(k == key_sets[0] for k in key_sets) and must <= key_sets[0]
    if name == "i18n-gear-return.js":
        assert "Vracíš všechnu výbavu?" in src           # znění zadání majitele


async def test_real_zone_session_id_and_no_wardrobe_hold(tmp_path):
    """Skutečná zóna šatny (světlo „do kódu motorky“ zapnuté): výpůjčka výbavy relaci nedrží — po doběhu SECURED, světlo
    zhasne, hudba stop; potvrzení vrácení nese session_id TÉŽE návštěvy jako její DOOR_CLOSED."""
    from dataclasses import replace

    from motogo_box.models import ZoneState
    from tests.test_zone import Rig

    c = FakeCtrl(tmp_path)
    r = Rig()
    r.zone = r.zc.zone = replace(r.zone, kind="accessories", door_id="d8", hw=replace(r.zone.hw, light_until_moto_code=True))
    c.zones = {1: r.zc}
    await r.zc.startup(True)
    hm = c.handover
    hm.signed["g1"] = c.clock()                                   # podepsáno při převzetí
    r.zc.on_session_closed = lambda zc: hm.on_wardrobe_closed(zc.number, zc.booking_id)
    assert (await r.zc.grant_access(booking_id="g1", kind="accessories", source="ui")) == (True, "ok")
    r.zc.light_off_on_secure = True                               # = controller_codes.submit_code pro rr.gear_only
    hm.gear.visit(ResolveResult(ok=True, kind="accessories", booking_id="g1", gear_only=True,
                                protocol=gear_proto_signed()))
    await r.zc.on_input(False)
    await r.zc.on_input(True)
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    ask = hm.gear.ask
    closed = [e for e in r.events if e.kind == EventKind.DOOR_CLOSED][-1]
    assert ask is not None and ask["session_id"] == closed.detail["session_id"] and ask["door_id"] == "d8"
    r.clock.advance(r.hw.timings.light_after_close_s + 1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.light() is False and r.audio.playing_zone is None
    assert r.zc.light_hold_since is None
    await hm.gear.answer("g1", True)
    ev = [e for e in c.events if e.kind == EventKind.GEAR_RETURN_CONFIRMED][0]
    assert ev.detail["session_id"] == closed.detail["session_id"] and ev.zone == 1
    c.close()


def gear_proto_signed() -> dict:
    from tests.test_gear_only import gear_proto
    return gear_proto(required=False, gear_collected_at="2026-10-23T08:05:00Z")
