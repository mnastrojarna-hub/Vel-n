"""Offline hradlo dokončeného vrácení (`return_gate.py`, rozhodnutí majitele 2026-10-06, CONTRACT §32): vrácení v poslední
den = kód motorky doběhne 15 min po finálním zavření kóje, kód šatny 15 min po zavření šatny při vrácení (šatna ≤ 90 min
před kójí → od zavření kóje; bez zavření šatny platí dál). Jen OFFLINE (online rozhoduje server); odmítnutí = `code_revoked`
bez lockoutu + ACCESS_DENIED `reason: returned`; záznam přežije restart, starší než 3 dny zmizí."""
from __future__ import annotations

import asyncio
import time
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from motogo_box import controller_codes as cc
from motogo_box import return_gate as rg
from motogo_box.config import TimingsCfg
from motogo_box.controller import BoxController
from motogo_box.models import Event, EventKind, ResolveResult
from motogo_box.storage import Storage
from tests.handover_fakes import FakeCtrl, protocol
from tests.test_zone import rig_secured

M = 60
NOW = time.time()


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).isoformat(timespec="milliseconds")


def done(storage, bid: str, kind: str, at: float, phase: str | None = "in", ev=EventKind.SESSION_COMPLETED, **extra):
    detail = {"source": "ui", **({"odometer_phase": phase} if phase else {}), **extra}
    rg.observe(storage, Event(kind=ev, booking_id=bid, code_kind=kind, detail=detail, ts=iso(at)))


def rr(kind: str = "motorcycle", final: float | None = NOW - 10 * 3600, **kw) -> ResolveResult:
    base = dict(ok=True, kind=kind, booking_id="b1", offline=True, return_final_from=iso(final) if final else None)
    return ResolveResult(**{**base, **kw})


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    final = iso(NOW - 10 * 3600)                            # poslední den začal před 10 h
    c.cache([{"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3,
              "return_final_from": final},
             {"code": "888888", "kind": "accessories", "booking_id": "b1", "door_id": "d8", "return_final_from": final}],
            [protocol("b1", required=False, needs_locker=False)])   # bez výzvy „nejdřív šatna“
    c.api.resolve = {"111111": None, "888888": None}      # síť nejde → offline cache
    yield c
    c.close()


def test_observe_records_return_close_locker_and_ride_out(tmp_path):
    st = Storage(str(tmp_path / "g.db"))
    done(st, "b1", "motorcycle", NOW - 5 * 3600, phase="out")         # převzetí — žádný záznam
    assert rg.record(st, "b1") == {}
    done(st, "b1", "motorcycle", NOW - 3 * 3600)                       # zaparkováno (fáze in)
    done(st, "b1", "motorcycle", NOW - 2 * 3600)                       # znovuotevření téhož vrácení → pozdější čas (D3)
    done(st, "b1", "accessories", NOW - 90 * M, phase=None)
    assert rg.record(st, "b1") == pytest.approx({"bay": NOW - 2 * 3600, "locker": NOW - 90 * M}, abs=0.01)
    for ignored in ({"temp": True}, {"emergency": True}):               # krátkodobý kód / nouzové otevření nic nezapíše
        done(st, "b1", "motorcycle", NOW, **ignored)
    rg.observe(st, Event(kind=EventKind.SESSION_COMPLETED, booking_id="b1", code_kind="motorcycle", success=False,
                         detail={"odometer_phase": "in"}, ts=iso(NOW)))
    rg.observe(st, Event(kind=EventKind.SESSION_COMPLETED, code_kind="motorcycle", detail={"odometer_phase": "in"}))
    done(st, "b1", "motorcycle", NOW, ev=EventKind.DOOR_CLOSED)        # jen SESSION_COMPLETED
    assert rg.record(st, "b1")["bay"] == pytest.approx(NOW - 2 * 3600, abs=0.01)
    done(st, "b1", "motorcycle", NOW - M, ev=EventKind.ACCESS_GRANTED, phase="out")   # motorka znovu vyjela
    assert rg.record(st, "b1") == pytest.approx({"locker": NOW - 90 * M}, abs=0.01)
    st.close()


def test_blocks_rules(tmp_path):
    st = Storage(str(tmp_path / "g.db"))
    c = SimpleNamespace(storage=st, hardware=SimpleNamespace(timings=TimingsCfg()))
    bay = NOW - 9 * 3600                                                 # vráceno v poslední den
    done(st, "b1", "motorcycle", bay)
    assert not rg.blocks(c, rr(), bay + 14 * M) and rg.blocks(c, rr(), bay + 16 * M)
    assert not rg.blocks(c, rr(offline=False), bay + 3600)               # online rozhoduje server
    assert not rg.blocks(c, rr(final=None), bay + 3600)                  # stará cache bez klíče = bez hradla
    assert not rg.blocks(c, rr(final=bay + 60), bay + 3600)              # zaparkováno před posledním dnem = platí dál
    assert not rg.blocks(c, rr(booking_id="b2"), bay + 3600)
    assert not rg.blocks(c, rr(kind="service"), bay + 3600)
    assert not rg.blocks(c, rr(temp=True), bay + 3600)                   # krátkodobý kód (bez rezervace)
    c.hardware.timings.return_code_grace_min = 5
    assert rg.blocks(c, rr(), bay + 6 * M)
    c.hardware.timings.return_code_grace_min = 15
    acc = rr("accessories")
    assert not rg.blocks(c, acc, bay + 3600)                             # šatnu po vrácení nezavřel → platí dál
    done(st, "b1", "accessories", bay - 2 * 3600, phase=None)            # šatna ráno (převzetí) — k vrácení nepatří
    assert not rg.blocks(c, acc, bay + 3600)
    done(st, "b1", "accessories", bay - 30 * M, phase=None)              # výbava vrácena PŘED motorkou → od zavření kóje
    assert not rg.blocks(c, acc, bay + 14 * M) and rg.blocks(c, acc, bay + 16 * M)
    done(st, "b1", "accessories", bay + 10 * M, phase=None)              # šatna po motorce → od zavření šatny
    assert not rg.blocks(c, acc, bay + 24 * M) and rg.blocks(c, acc, bay + 26 * M)
    st.close()


def test_record_survives_restart_and_expires_after_3_days(tmp_path):
    path = str(tmp_path / "g.db")
    st = Storage(path)
    done(st, "b1", "motorcycle", NOW - 3600)
    done(st, "old", "motorcycle", NOW - 3 * 86400 - 60)
    st.close()
    st = Storage(path)
    c = SimpleNamespace(storage=st, hardware=SimpleNamespace(timings=TimingsCfg()))
    assert rg.blocks(c, rr()) and rg.record(st, "old") == {}
    done(st, "b2", "accessories", NOW, phase=None)                       # zápis zahodí prošlé záznamy i z kv
    assert set(st.kv_get(rg.KV)["b"]) == {"b1", "b2"}
    st.close()


async def test_submit_code_offline_refuses_without_lockout(ctrl):
    done(ctrl.storage, "b1", "motorcycle", NOW - 20 * M)
    for _ in range(7):                                                   # víc než maximum_failed_attempts
        res = await cc.submit_code(ctrl, "111111", "ui")
        assert res["ok"] is False and res["error"] == "code_revoked" and res["message"] == cc.error_text("code_revoked")
    assert ctrl.pin_guard.locked_until() is None and ctrl.pin_guard.failures_in_window() == 0
    assert ctrl.zones[3].grants == [] and "PIN_INVALID" not in ctrl.kinds()
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert len(denied) == 7 and denied[0].booking_id == "b1" and denied[0].code_kind == "motorcycle"
    assert denied[0].detail["reason"] == "returned" and denied[0].detail["error"] == "code_revoked"
    assert denied[0].detail["offline"] is True and denied[0].detail["closed_at"]
    assert (await cc.submit_code(ctrl, "888888", "ui"))["ok"]            # šatna po vrácení nezavřena → platí dál
    done(ctrl.storage, "b1", "accessories", NOW - 16 * M, phase=None)
    assert (await cc.submit_code(ctrl, "888888", "ui"))["error"] == "code_revoked"
    ctrl.api.resolve["111111"] = {"ok": True, "kind": "motorcycle", "booking_id": "b1", "box_number": 3,
                                  "door": {"id": "d3", "door_kind": "motorcycle", "box_number": 3},
                                  "protocol": protocol("b1", required=False), "return_final_from": iso(NOW - 10 * 3600)}
    assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"]            # online: rozhoduje server, hradlo neplatí


async def test_submit_code_offline_within_grace_or_parked_opens(ctrl):
    done(ctrl.storage, "b1", "motorcycle", NOW - 5 * M)                  # zapomenutá věc do 15 min
    assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"] and ctrl.zones[3].grants[-1][0] == "b1"
    done(ctrl.storage, "b1", "motorcycle", NOW - 11 * 3600)              # (přepíše) zaparkováno včera večer
    assert (await cc.submit_code(ctrl, "111111", "ui"))["ok"]


async def test_box_controller_emit_feeds_gate_and_sends_unit_ts():
    """Řetěz zóna → BoxController.emit → return_gate.observe + kiosk_log_open (detail s ts, session_id, fází)."""
    sent: list = []

    class Api:
        async def log_open(self, door_id, kind, booking_id, success, detail):
            sent.append((kind, booking_id, detail))

    with_storage = Storage(":memory:")
    box = SimpleNamespace(storage=with_storage, zones={}, api=Api(), last_error=None, ui_notice=None)
    r = await rig_secured()
    r.zc.emit = lambda ev: BoxController.emit(box, ev)
    await r.zc.grant_access(booking_id="b1", kind="motorcycle", source="ui",
                            detail={"odometer_phase": "in", "odometer_reading_id": "r1"})
    await r.zc.on_input(False)
    await r.zc.on_input(True)
    r.clock.advance(1.1)
    await r.zc.tick()
    await asyncio.sleep(0)
    events = [d["event"] for _, _, d in sent]
    assert events == ["ACCESS_GRANTED", "DOOR_OPENED", "DOOR_CLOSED", "SESSION_COMPLETED"]
    assert len({d["session_id"] for _, _, d in sent}) == 1 and all(d["odometer_phase"] == "in" for _, _, d in sent)
    closed_ts = sent[-1][2]["ts"]
    assert rg.record(with_storage, "b1")["bay"] == pytest.approx(datetime.fromisoformat(closed_ts).timestamp())
    with_storage.close()
