"""Události relace zóny pro server (1.2.8, 2026-10-06, CONTRACT §15/§32): `detail.ts` = čas události na jednotce (ISO UTC
s ms) u každé události kiosk_log_open, `session_id` (32 hex, nový při každém grantu) na všech událostech relace a fáze
tachometru grantu (`odometer_phase`, `odometer_reading_id`) i na DOOR_OPENED / DOOR_CLOSED / SESSION_COMPLETED / OPEN_TIMEOUT."""
from __future__ import annotations

import re

from motogo_box import controller_codes as cc
from motogo_box.models import Event, EventKind, ZoneState
from tests.test_zone import rig_secured

RETURN = {"odometer_phase": "in", "odometer_km": 10450, "odometer_reading_id": "r1"}
TS_RE = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}\+00:00$")
SESSION = (EventKind.ACCESS_GRANTED, EventKind.DOOR_OPENED, EventKind.DOOR_CLOSED, EventKind.SESSION_COMPLETED)


async def _close(r) -> None:
    await r.zc.on_input(True)
    r.clock.advance(1.1)
    await r.zc.tick()


async def test_return_session_carries_session_id_and_phase_on_every_event():
    r = await rig_secured()
    ok, _ = await r.zc.grant_access(booking_id="b1", kind="motorcycle", source="ui", detail=dict(RETURN))
    await r.zc.on_input(False)
    await _close(r)
    assert ok and [e.kind for e in r.events[-4:]] == list(SESSION)
    sid = r.events[-4].detail["session_id"]
    assert re.fullmatch(r"[0-9a-f]{32}", sid)
    for ev in r.events[-4:]:
        d = cc.open_detail(ev)
        assert (d["session_id"], d["odometer_phase"], d["odometer_reading_id"]) == (sid, "in", "r1")
        assert d["event"] == ev.kind.value and ev.booking_id == "b1" and ev.code_kind == "motorcycle"
        assert TS_RE.match(d["ts"]) and d["ts"] == ev.ts      # čas události na jednotce, ne čas odeslání
    assert "odometer_km" not in r.events[-1].detail           # km jen v ACCESS_GRANTED (beze změny významu)
    assert r.events[-4].detail["odometer_km"] == 10450

    # znovuotevření v doběhu = táž relace (druhé DOOR_CLOSED + SESSION_COMPLETED se stejným session_id a fází)
    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN and r.events[-1].detail["session_id"] == sid
    await _close(r)
    assert [e.kind for e in r.events[-2:]] == [EventKind.DOOR_CLOSED, EventKind.SESSION_COMPLETED]
    assert all(e.detail["session_id"] == sid and e.detail["odometer_phase"] == "in" for e in r.events[-2:])

    # nový grant = nová relace; bez fáze (servis / šatna) jen session_id
    r.clock.advance(31)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.session_ctx == {}
    ok, _ = await r.zc.grant_access(booking_id=None, kind="service", source="velin")
    ev = r.events[-1]
    assert ok and ev.kind == EventKind.ACCESS_GRANTED and ev.detail["session_id"] != sid
    assert "odometer_phase" not in ev.detail and "odometer_reading_id" not in ev.detail


async def test_open_timeout_and_late_open_keep_the_grant_session():
    r = await rig_secured()
    await r.zc.grant_access(booking_id="b1", kind="motorcycle", source="ui", detail=dict(RETURN))
    sid = r.events[-1].detail["session_id"]
    r.clock.advance(61)                                       # lock_hold_min_s / door_open_timeout → OPEN_TIMEOUT
    await r.zc.tick()
    to = r.events[-1]
    assert to.kind == EventKind.OPEN_TIMEOUT and to.booking_id == "b1"
    assert (to.detail["session_id"], to.detail["odometer_phase"]) == (sid, "in")
    await r.zc.on_input(False)                                # pozdní otevření = pokračování relace
    late = r.events[-1]
    assert late.kind == EventKind.DOOR_OPENED and late.detail.get("late_open") is True
    assert (late.detail["session_id"], late.detail["odometer_phase"], late.booking_id) == (sid, "in", "b1")
    await _close(r)
    assert all(e.detail["session_id"] == sid and e.detail["odometer_reading_id"] == "r1" for e in r.events[-2:])


async def test_out_of_session_events_have_no_session_and_emergency_grant_is_not_a_session():
    r = await rig_secured()
    await r.zc.grant_access(booking_id="b1", kind="motorcycle", source="ui", detail={"odometer_phase": "in"})
    await r.zc.on_input(False)
    sid = r.zc.session_ctx["session_id"]
    ok, _ = await r.zc.grant_access(booking_id=None, kind="service", source="velin")   # nouzový impulz během relace
    em = r.events[-1]
    assert ok and em.detail.get("emergency") is True
    assert "session_id" not in em.detail and "odometer_phase" not in em.detail
    await _close(r)
    assert r.events[-1].detail["session_id"] == sid           # relace zákazníka pokračuje beze změny
    r.clock.advance(31)
    await r.zc.tick()
    await r.zc.on_input(False)                                # SECURED + otevřeno = FORCED_OPEN mimo relaci
    r.clock.advance(0.6)
    await r.zc.tick()
    fo = r.events[-1]
    assert fo.kind == EventKind.FORCED_OPEN and "session_id" not in fo.detail and fo.booking_id is None


def test_ts_only_on_kiosk_log_open_events():
    ev = Event(kind=EventKind.ACCESS_DENIED, success=False, detail={"source": "ui", "reason": "locked"})
    assert TS_RE.match(ev.ts) and cc.open_detail(ev)["ts"] == ev.ts
    for kind in (EventKind.PIN_INVALID, EventKind.FORCED_OPEN, EventKind.PROTOCOL_SHOWN):
        assert "ts" in cc.open_detail(Event(kind=kind))
    assert "ts" not in cc.open_detail(Event(kind=EventKind.SESSION_OVERTIME))       # kiosk_log_event beze změny
    assert "ts" not in cc.open_detail(Event(kind=EventKind.ODOMETER_RECORDED))
