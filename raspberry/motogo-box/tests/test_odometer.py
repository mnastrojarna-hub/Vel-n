"""Stav tachometru při vrácení (odometer.py, rozhodnutí majitele 2026-09-29, CONTRACT §30) — tok kódu motorky:
převzetí bez výzvy, vrácení s výzvou, grace, parkování přes noc, hranice (km / mth), důkazy serveru, offline cache,
fail-open, přeskočení hradel převzetí, km do protokolu převzetí a šatna po vrácení."""
from __future__ import annotations

from datetime import datetime, timezone

import pytest

from tests.handover_fakes import SIG, FakeClock, FakeCtrl, protocol
from motogo_box import controller_codes as cc
from motogo_box.config import HardwareConfig
from motogo_box.models import ResolveResult
from motogo_box.odometer import OdometerManager, rental_days

T0 = datetime(2026, 9, 29, 8, 0, tzinfo=timezone.utc).timestamp()      # 10:00 Praha (SELČ)
CODE = "111111"
H = 3600


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).isoformat()


def odo(**kw) -> dict:
    """Blok `odo` jako z `_kiosk_odometer` (resolve / codes[].odo)."""
    d = {"booking_id": "b1", "moto_id": "m1", "unit": "km", "per_day": 1000, "hint": 10000, "min": 10000,
         "max": 11000, "start_km": 10000, "start_at": iso(T0 - 3 * H), "days": 1, "last_open_at": None,
         "last_open_phase": None, "delivered": False, "delivered_at": None}
    d.update(kw)
    return d


OUT_3H = {"last_open_at": iso(T0 - 3 * H), "last_open_phase": "out"}       # převzato před 3 h (důkaz serveru)


def moto_rpc(block: dict | None = None, proto: dict | None = None, booking: str = "b1") -> dict:
    return {"ok": True, "kind": "motorcycle", "booking_id": booking, "box_number": 3,
            "door": {"id": "d3", "door_kind": "motorcycle", "box_number": 3}, "door_configured": True,
            "protocol": proto if proto is not None else protocol(booking, required=False, moto_id="m1"), "odo": block}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path, FakeClock(T0))
    c.odometer = OdometerManager(c, clock=c.clock)
    yield c
    c.close()


async def code(ctrl, odometer=None, c: str = CODE) -> dict:
    return await cc.submit_code(ctrl, c, "ui", odometer=odometer)


def events(ctrl, kind: str) -> list:
    return [e for e in ctrl.events if e.kind.value == kind]


async def test_pickup_no_prompt_reentry_in_grace_then_return(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo())
    zc = ctrl.zones[3]
    res = await code(ctrl)                                   # převzetí: km se nikdy nechtějí
    assert res["ok"] and zc.details[-1] == {"odometer_phase": "out"} and "odometer" not in res
    ctrl.clock.advance(30 * 60)                              # zapomenutá věc do 60 min → bez výzvy
    assert (await code(ctrl))["ok"] and zc.details[-1] == {"odometer_phase": "out"}
    ctrl.clock.advance(31 * 60)                              # 61 min od převzetí = vrácení
    res = await code(ctrl)
    assert res["ok"] is False and res["error"] == "odometer_required" and res["booking_id"] == "b1"
    assert res["odometer"] == {"unit": "km", "hint": 10000, "min": 10000, "max": 11000, "days": 1, "zone": 3}
    assert len(zc.grants) == 2 and not events(ctrl, "ACCESS_DENIED") and not events(ctrl, "PIN_INVALID")
    assert ctrl.pin_guard.failures_in_window() == 0

    queued: list = []
    orig = zc.grant_access

    async def spy(**kw):
        queued.append(ctrl.storage.odometer_queue_pending())
        return await orig(**kw)
    zc.grant_access = spy
    res = await code(ctrl, "10 450")
    assert res["ok"] and res["odometer"] == {"km": 10450, "unit": "km"}
    assert res["message"].endswith("Stav tachometru 10450 km uložen.")
    row = queued[0][0]                                       # čtení je ve frontě PŘED otevřením kóje
    assert row["km"] == 10450 and row["moto_id"] == "m1" and row["payload"]["p_booking_id"] == "b1"
    assert row["payload"]["p_detail"] == {"source": "ui", "offline": False, "zone": 3, "min": 10000, "max": 11000,
                                          "days": 1, "unit": "km"}
    assert zc.details[-1] == {"odometer_phase": "in", "odometer_km": 10450, "odometer_reading_id": row["reading_id"]}
    assert ctrl.odometer.returned("b1") and events(ctrl, "ODOMETER_RECORDED")[0].detail["km"] == 10450


@pytest.mark.parametrize("value,reason", [("9999", "too_low"), ("11001", "too_high"), ("12a", "not_number"),
                                          ("12345678", "not_number"), ("-5", "not_number")])
async def test_invalid_value_keeps_bay_closed(ctrl, value, reason):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    res = await code(ctrl, value)
    assert res["error"] == "odometer_invalid" and res["reason"] == reason
    assert res["odometer"]["min"] == 10000 and res["odometer"]["max"] == 11000
    assert ctrl.zones[3].grants == [] and ctrl.storage.odometer_queue_pending() == []
    ev = events(ctrl, "ODOMETER_REJECTED")
    assert len(ev) == 1 and ev[0].level == "warn" and ev[0].detail["reason"] == reason
    assert ctrl.pin_guard.failures_in_window() == 0 and ctrl.pin_guard.locked_until() is None


@pytest.mark.parametrize("value", ["10000", "11000"])
async def test_bounds_inclusive(ctrl, value):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    assert (await code(ctrl, value))["ok"]


def test_rental_days_prague_calendar():
    late = datetime(2026, 9, 28, 21, 30, tzinfo=timezone.utc).timestamp()     # 23:30 Praha
    assert rental_days(late, late + 20 * 60) == 1                                 # 23:50 týž den
    assert rental_days(late, late + H) == 2                                       # 00:30 další den
    assert rental_days(late, late + 2 * 86400) == 3 and rental_days(None, late) == 1


async def test_days_and_mh_unit(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(start_at=iso(T0 - 2 * 86400), **OUT_3H))
    assert (await code(ctrl))["odometer"]["max"] == 13000                         # 3 kalendářní dny × 1000 km
    ctrl.api.resolve[CODE] = moto_rpc(odo(unit="mh", per_day=24, hint=500, min=500, start_km=500,
                                          start_at=iso(T0 - 2 * 86400), **OUT_3H))
    res = await code(ctrl)
    assert res["odometer"] == {"unit": "mh", "hint": 500, "min": 500, "max": 572, "days": 3, "zone": 3}
    assert (await code(ctrl, "573"))["reason"] == "too_high"
    res = await code(ctrl, "560")
    assert res["ok"] and res["odometer"] == {"km": 560, "unit": "mh"} and res["message"].endswith("560 mth uložen.")


async def test_stale_start_km_never_empty_range(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(hint=20000, min=20000, start_km=10000, **OUT_3H))
    assert (await code(ctrl))["odometer"]["max"] == 21000                         # ≤ min → min + per_day


async def test_multi_day_overnight_parking(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(start_at=iso(T0)))
    assert (await code(ctrl))["ok"]                                              # převzetí
    ctrl.clock.advance(8 * H)                                                    # večer do kóje
    assert (await code(ctrl))["error"] == "odometer_required"
    assert (await code(ctrl, "10300"))["ok"]
    ctrl.clock.advance(12 * H)                                                   # ráno znovu vyjíždí — km ne
    assert (await code(ctrl))["ok"] and ctrl.zones[3].details[-1] == {"odometer_phase": "out"}
    ctrl.clock.advance(10 * H)                                                   # večer znovu do kóje
    res = await code(ctrl)
    assert res["error"] == "odometer_required" and res["odometer"]["hint"] == res["odometer"]["min"] == 10300
    assert res["odometer"]["days"] == 2 and res["odometer"]["max"] == 12000
    assert (await code(ctrl, "10200"))["reason"] == "too_low"                   # neodeslané čtení zvedá spodní mez
    assert await ctrl.odometer.flush() == 1                                      # potvrzeno → platí jen server
    assert (await code(ctrl, "10200"))["ok"]


async def test_reentry_after_return_within_grace(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    assert (await code(ctrl, "10100"))["ok"]
    at = ctrl.storage.kv_get("odometer")["b"]["b1"]["at"]
    ctrl.clock.advance(15 * 60)
    res = await code(ctrl)
    assert res["ok"] and "odometer" not in res and ctrl.zones[3].details[-1] == {"odometer_phase": "in"}
    assert ctrl.storage.kv_get("odometer")["b"]["b1"]["at"] == at and ctrl.odometer.returned("b1")


async def test_grace_from_velin_timings(ctrl):
    ctrl.hardware.timings.odometer_grace_min = 10
    ctrl.api.resolve[CODE] = moto_rpc(odo())
    assert (await code(ctrl))["ok"]
    ctrl.clock.advance(15 * 60)
    assert (await code(ctrl))["error"] == "odometer_required"


@pytest.mark.parametrize("block,prompt", [
    (odo(**OUT_3H), True),                                                        # převzato dřív (i starý firmware)
    (odo(last_open_at=iso(T0 - 3 * H), last_open_phase="in"), False),             # zaparkováno → znovu vyjíždí
    (odo(last_open_at=iso(T0 - 20 * 60), last_open_phase="out"), False),          # v grace
    (odo(delivered=True, delivered_at=iso(T0 - 86400)), True),                    # přistavení / SOS → vrací do kóje
    (odo(), False),                                                               # bez důkazu (jen cron picked_up_at)
    (None, False),                                                                # stará DB bez bloku odo
])
async def test_server_evidence_without_local_state(ctrl, block, prompt):
    ctrl.api.resolve[CODE] = moto_rpc(block)
    res = await code(ctrl)
    if prompt:
        assert res["error"] == "odometer_required" and ctrl.zones[3].grants == []
    else:
        assert res["ok"] and ctrl.zones[3].details[-1] == {"odometer_phase": "out"}


async def test_offline_cache_odo_and_fail_open_without_it(ctrl):
    row = {"kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}
    ctrl.api.resolve[CODE] = None                                                 # síť dole → offline cache
    ctrl.cache([{**row, "code": CODE, "odo": odo(**OUT_3H)}], None)
    res = await code(ctrl)
    assert res["error"] == "odometer_required" and res["odometer"]["max"] == 11000
    res = await code(ctrl, "10500")
    assert res["ok"] and ctrl.storage.odometer_queue_pending()[0]["payload"]["p_detail"]["offline"] is True
    ctrl.storage.kv_delete("odometer")
    ctrl.cache([{**row, "code": CODE}], None)                                     # stará cache bez odo
    assert (await code(ctrl))["ok"]


def test_resolve_result_odo_parsing():
    assert ResolveResult.from_rpc({"ok": True, "kind": "motorcycle", "odo": {"hint": 5}}).odo == {"hint": 5}
    assert ResolveResult.from_rpc({"ok": True, "kind": "motorcycle", "odo": "x"}).odo is None
    t = HardwareConfig.from_dict({"timings": {"odometer_grace_min": "30"}}).timings
    assert t.odometer_grace_min == 30 and t.odometer_idle_s == 120


async def test_grant_failure_keeps_reading_for_retry(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    zc = ctrl.zones[3]
    zc.result = (False, "lock_failed")
    res = await code(ctrl, "10500")
    rows = ctrl.storage.odometer_queue_pending()
    assert res["error"] == "lock_failed" and len(rows) == 1 and not ctrl.odometer.returned("b1")
    zc.result = (True, "ok")
    ctrl.clock.advance(120)
    res = await code(ctrl)                                                        # bez nové výzvy, totéž čtení
    assert res["ok"] and zc.details[-1]["odometer_reading_id"] == rows[0]["reading_id"]
    assert len(ctrl.storage.odometer_queue_pending()) == 1 and ctrl.odometer.returned("b1")
    assert "unopened" not in ctrl.storage.kv_get("odometer")["b"]["b1"]


async def test_no_known_km_no_bounds(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(hint=None, min=None, max=None, start_km=None, **OUT_3H))
    res = await code(ctrl)
    assert (res["odometer"]["hint"], res["odometer"]["min"], res["odometer"]["max"]) == (None, None, None)
    assert (await code(ctrl, "7"))["ok"]


async def test_old_db_bounds_from_local_pickup(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(None)                   # bez `odo`; km převzetí z protokolu (data.mileage 1200)
    assert (await code(ctrl))["ok"]
    ctrl.clock.advance(3 * H)
    assert (await code(ctrl))["odometer"] == {"unit": "km", "hint": 1200, "min": 1200, "max": 2200, "days": 1, "zone": 3}


async def test_return_skips_protocol_and_locker_gates(ctrl):
    # nepodepsaný protokol převzetí (SOS výměna) + výbava v šatně: při vrácení ani protokol, ani „nejdřív šatna“
    ctrl.cache([{"code": "333333", "kind": "accessories", "booking_id": "b1", "door_id": "d8", "box_number": None}], None)
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H), proto=protocol("b1", required=True, moto_id="m1"))
    assert (await code(ctrl))["error"] == "odometer_required"
    res = await code(ctrl, "10500")
    assert res["ok"] and ctrl.handover.status()["active"] is None
    ctrl.api.resolve["222222"] = moto_rpc(odo(booking_id="b2"), proto=protocol("b2", required=True), booking="b2")
    ctrl.cache([{"code": "444444", "kind": "accessories", "booking_id": "b2", "door_id": "d8", "box_number": None}], None)
    assert (await code(ctrl, c="222222"))["error"] == "locker_first"                # převzetí: hradla platí dál


async def test_pickup_protocol_uses_unacked_return_km(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    assert (await code(ctrl, "10450"))["ok"]                  # b1 vrátil motorku m1, čtení čeká ve frontě
    p2 = protocol("b2", required=True, moto_id="m1", needs_locker=False)
    p2["data"]["mileage"] = 10000
    ctrl.api.resolve["222222"] = moto_rpc(odo(booking_id="b2"), proto=p2, booking="b2")
    assert (await code(ctrl, c="222222"))["error"] == "protocol_required"
    res = await ctrl.handover.submit("b2", {"mileage": "10000", "accessories": []}, SIG, None)
    assert res["ok"] and ctrl.api.submits[-1]["form"]["mileage"] == "10450"
    assert ctrl.zones[3].details[-1] == {"odometer_phase": "out"}
    st = ctrl.storage.kv_get("odometer")["b"]["b2"]
    assert st["phase"] == "out" and st["start_km"] == 10450 and st["moto_id"] == "m1"
    await ctrl.odometer.flush()                               # přijato serverem → řádek fronty pryč, ale do dalšího
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10450      # syncu drží km převzetí (zastaralé data)
    ctrl.clock.advance(301)                                   # po RECENT_ACK_S → km převzetí jen ze serveru
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10000


async def test_pickup_km_after_upload_before_sync(ctrl):
    """Čtení předchozího zákazníka odešlo, až když byl protokol převzetí na displeji (data.mileage z doby před zápisem):
    km převzetí = přijaté čtení; sporné (disputed) čtení km převzetí nedrží."""
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    assert (await code(ctrl, "10450"))["ok"]
    p2 = protocol("b2", required=True, moto_id="m1", needs_locker=False)
    p2["data"]["mileage"] = 10000                             # zastaralé: resolve kódu b2 proběhl před odesláním čtení
    ctrl.api.resolve["222222"] = moto_rpc(odo(booking_id="b2"), proto=p2, booking="b2")
    assert (await code(ctrl, c="222222"))["error"] == "protocol_required"
    assert await ctrl.odometer.flush() == 1 and ctrl.storage.odometer_queue_pending() == []
    res = await ctrl.handover.submit("b2", {"mileage": "10000", "accessories": []}, SIG, None)
    assert res["ok"] and ctrl.api.submits[-1]["form"]["mileage"] == "10450"
    ctrl.odometer.recent.clear()
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H), booking="b3")
    ctrl.api.odo_results.append({"ok": True, "permanent": False, "error": None, "status": "disputed",
                                 "reason": "too_high", "duplicate": False})
    assert (await code(ctrl, "10900"))["ok"] and await ctrl.odometer.flush() == 1
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10000


async def test_wardrobe_close_after_return_no_lock(ctrl):
    ctrl.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    assert await ctrl.handover.on_wardrobe_closed(8, "b1", protocol("b1", required=False)) == "done"
    assert ctrl.handover.lock.state is not None                                  # převzetí: zámek přejímky jako dřív
    assert (await code(ctrl, "10500"))["ok"] and ctrl.handover.lock.state is None
    ctrl.clock.advance(10)
    ctrl.handover.tick()                                                          # toast DONE z převzetí zmizí
    assert await ctrl.handover.on_wardrobe_closed(8, "b1", protocol("b1", required=False)) is None
    assert ctrl.handover.lock.state is None and ctrl.handover.status()["active"] is None


async def test_real_zone_access_granted_detail():
    """ZoneController.grant_access(detail=…) → ACCESS_GRANTED → detail pro kiosk_log_open (server z něj bere fázi)."""
    from tests.test_zone import rig_secured
    r = await rig_secured()
    ok, _ = await r.zc.grant_access(booking_id="b1", kind="motorcycle", source="ui",
                                    detail={"odometer_phase": "in", "odometer_km": 10450, "odometer_reading_id": "r1"})
    d = cc.open_detail(r.events[-1])
    assert ok and d["event"] == "ACCESS_GRANTED" and d["source"] == "ui"
    assert (d["odometer_phase"], d["odometer_km"], d["odometer_reading_id"]) == ("in", 10450, "r1")
