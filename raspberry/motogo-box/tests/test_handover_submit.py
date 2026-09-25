"""Podpis protokolu z displeje, fronta `protocol_queue` a hradlo v `submit_code` (DESIGN §4)."""
from __future__ import annotations

import asyncio

import pytest

from motogo_box import controller_codes as cc
from motogo_box.handover_submit import SIGNATURE_MAX_BYTES, SIGNATURE_PREFIX, signature_bytes
from motogo_box.models import EventKind

from tests.handover_fakes import SIG, FakeCtrl, protocol, rr_moto

FORM = {"mileage": "1200", "checks": {"clean": True}, "accessories": [{"key": "helmet", "who": "rider", "size": "L"}]}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "123456", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3},
             {"code": "222222", "kind": "motorcycle", "booking_id": "b2", "door_id": "d3", "box_number": 3}],
            [protocol("b1")])
    yield c
    c.close()


async def test_submit_with_then_open_saves_and_opens(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    res = await hm.submit("b1", FORM, SIG, None)
    assert res == {"ok": True, "status": "saved", "error": None,
                   "opened": {"zone": 3, "kind": "motorcycle", "message": "Otevřeno — Kóje 3. Příjemnou cestu! 🏍️"}}
    assert zc.grants == [("b1", "motorcycle", "ui")]
    sent = ctrl.api.submits[0]
    assert sent["booking_id"] == "b1" and sent["form"] == FORM and sent["signature"] == SIG and sent["signed_at"]
    assert ctrl.storage.protocol_queue_status() == {"pending": [], "failed": []}
    assert hm.items == {} and hm.status()["active"] is None and hm.signed_local("b1")
    signed = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_SIGNED]
    assert len(signed) == 1 and signed[0].booking_id == "b1" and signed[0].detail["stored"] is True
    assert await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui") is False   # zastaralé required
    assert (await hm.submit("b1", FORM, SIG, None))["error"] == "not_pending"


async def test_submit_and_protocol_signed_command_open_once(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    ctrl.api.gate = asyncio.Event()
    task = asyncio.create_task(hm.submit("b1", FORM, SIG, None))
    await asyncio.sleep(0)
    assert hm.status()["active"]["saving"] is True and hm.busy() is True
    assert (await hm.submit("b1", FORM, SIG, None))["error"] == "in_progress"
    assert await hm.mark_signed_remote("b1", may_open=True) is None  # trigger po claimu edge — dřív než odpověď
    ctrl.api.gate.set()
    res = await task
    assert res["ok"] and res["opened"]["zone"] == 3 and zc.grants == [("b1", "motorcycle", "ui")]


async def test_submit_needs_motorcycle_code_of_same_booking(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    ctrl.api.resolve = {"123456": None, "222222": None}             # síť dole → offline cache
    assert (await hm.submit("b1", FORM, SIG, None))["error"] == "code_mismatch"
    assert (await hm.submit("b1", FORM, SIG, "000000"))["error"] == "code_mismatch"
    assert (await hm.submit("b1", FORM, SIG, "222222"))["error"] == "code_mismatch"   # cizí rezervace
    assert ctrl.storage.pin_failures_since(0) == 2 and ctrl.kinds().count("PIN_INVALID") == 2
    assert zc.grants == [] and hm.active() is not None
    res = await hm.submit("b1", FORM, SIG, "123 456")
    assert res["ok"] and res["status"] == "saved" and res["opened"]["zone"] == 3
    assert zc.grants == [("b1", "motorcycle", "ui")] and ctrl.storage.pin_failures_since(0) == 2


async def test_submit_signature_validation(ctrl):
    hm = ctrl.handover
    await hm.require_before_open(rr_moto(proto=protocol("b1")), ctrl.zones[3], "ui")
    assert (await hm.submit("b1", FORM, None, None))["error"] == "missing_signature"
    assert (await hm.submit("b1", FORM, "data:image/jpeg;base64,AAAA", None))["error"] == "missing_signature"
    big = SIGNATURE_PREFIX + "A" * (SIGNATURE_MAX_BYTES * 4 // 3 + 400)
    assert signature_bytes(big) > SIGNATURE_MAX_BYTES
    assert (await hm.submit("b1", FORM, big, None))["error"] == "signature_too_large"
    # týž vzorec jako edge util.ts `signatureBytes` a UI signature.js: floor((len − idx(',') − 1) · 3/4), bez paddingu
    assert signature_bytes(SIG) == (len(SIG) - len(SIGNATURE_PREFIX)) * 3 // 4
    assert signature_bytes(SIGNATURE_PREFIX + "A" * (SIGNATURE_MAX_BYTES * 4 // 3)) == SIGNATURE_MAX_BYTES
    for bad in (SIG + "\n", SIG[:-4] + " AAA", SIGNATURE_PREFIX, "data:image/webp;base64,AAAA"):
        assert signature_bytes(bad) is None                          # edge SIG_RE by vrátil 400 = trvalé selhání
        assert (await hm.submit("b1", FORM, bad, None))["error"] == "missing_signature"
    assert (await hm.submit("neznama", FORM, SIG, None))["error"] == "not_pending"
    assert ctrl.api.submits == [] and hm.active() is not None


async def test_submit_lockout_reports_locked_and_own_locker_code_is_not_a_guess(ctrl):
    """Vlastní kód šatny v poli kódu motorky = omyl, ne hádání (bez PIN_INVALID); během lockoutu vrací submit
    `locked` + `locked_until` (jako /api/pin), ne „špatný kód“, a správný kód se ani neověřuje."""
    hm, zc = ctrl.handover, ctrl.zones[3]
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    ctrl.api.resolve = {"123456": None,                              # síť dole → offline cache (kód motorky b1)
                        "888888": {"ok": True, "kind": "accessories", "booking_id": "b1",
                                   "door": {"id": "d8", "door_kind": "accessories"}}}
    res = await hm.submit("b1", FORM, SIG, "888888")
    assert res["error"] == "code_mismatch" and ctrl.storage.pin_failures_since(0) == 0
    assert "PIN_INVALID" not in ctrl.kinds()
    sec = ctrl.hardware.security
    for _ in range(sec.maximum_failed_attempts):
        res = await hm.submit("b1", FORM, SIG, "000000")
    assert res["error"] == "locked" and res["locked_until"] == ctrl.clock() + sec.lockout_minutes * 60
    assert ctrl.kinds().count("PIN_INVALID") == sec.maximum_failed_attempts and "PIN_LOCKOUT" in ctrl.kinds()
    res = await hm.submit("b1", FORM, SIG, "123456")
    assert res["error"] == "locked" and res["locked_until"] and zc.grants == [] and ctrl.api.submits == []
    ctrl.clock.advance(sec.lockout_minutes * 60 + 1)
    res = await hm.submit("b1", FORM, SIG, "123456")
    assert res["ok"] and res["status"] == "saved" and res["opened"]["zone"] == 3


async def test_queue_survives_network_and_4xx(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    ctrl.api.results.append({"ok": False, "permanent": False, "error": "network: ConnectError", "already_filled": False})
    res = await hm.submit("b1", FORM, SIG, None)
    assert res["ok"] and res["status"] == "queued" and res["opened"]["zone"] == 3    # fail-open: kóje se otevře
    assert hm.status()["pending"] == ["b1"] and hm.wake.is_set()
    ctrl.api.results.append({"ok": False, "permanent": True, "error": "forbidden", "already_filled": False})
    assert await hm.flush() == 0
    assert hm.status() == {"active": None, "pending": [], "failed": ["b1"], "waiting": []}
    failed = [e for e in ctrl.events if e.kind == EventKind.PROTOCOL_UPLOAD_FAILED]
    assert len(failed) == 1 and failed[0].level == "error" and failed[0].detail["error"] == "forbidden"
    assert failed[0].detail["signature_bytes"] == signature_bytes(SIG)
    assert await hm.flush() == 0 and len(ctrl.api.submits) == 2      # failed se automaticky neopakuje
    assert hm.retry_failed() == 1 and hm.status()["pending"] == ["b1"]
    ctrl.api.results.append({"ok": True, "permanent": False, "error": None, "already_filled": True})
    assert await hm.flush() == 1
    assert hm.status()["pending"] == [] and ctrl.storage.protocol_queue_pending() == []
    assert len(zc.grants) == 1


async def test_flush_stops_on_network_error_and_keeps_order(ctrl):
    hm = ctrl.handover
    ctrl.storage.protocol_queue_put("b1", {"booking_id": "b1", "signature": SIG})
    ctrl.clock.advance(1)
    ctrl.storage.protocol_queue_put("b2", {"booking_id": "b2", "signature": SIG})
    hm.refresh_queue()
    ctrl.api.results.append({"ok": False, "permanent": False, "error": "http_503", "already_filled": False})
    assert await hm.flush() == 0 and [s["booking_id"] for s in ctrl.api.submits] == ["b1"]
    assert hm.status()["pending"] == ["b1", "b2"]
    assert await hm.flush() == 2 and hm.status()["pending"] == [] and "b2" in hm.signed


async def test_then_open_failure_reports_reason(ctrl):
    hm, zc = ctrl.handover, ctrl.zones[3]
    zc.result = (False, "busy")
    await hm.require_before_open(rr_moto(proto=protocol("b1")), zc, "ui")
    res = await hm.submit("b1", FORM, SIG, None)
    assert res["ok"] and res["status"] == "saved" and res["opened"] is None and res["error"] == "busy"
    assert ctrl.kinds().count("ACCESS_DENIED") == 1 and hm.signed_local("b1")


async def test_submit_code_gate_in_controller_codes(ctrl):
    """Kód motorky bez podpisu → `protocol_required` (bez ACCESS_DENIED, bez lockoutu); kód šatny → grant + remember."""
    ctrl.api.resolve = {"123456": {"ok": True, "kind": "motorcycle", "booking_id": "b1", "box_number": 3,
                                   "door": {"id": "d3", "door_kind": "motorcycle", "box_number": 3},
                                   "protocol": protocol("b1")},
                        "888888": {"ok": True, "kind": "accessories", "booking_id": "b1",
                                   "door": {"id": "d8", "door_kind": "accessories"}, "protocol": protocol("b1")}}
    res = await cc.submit_code(ctrl, "123456", "ui")
    assert res["ok"] is False and res["error"] == "protocol_required" and res["kind"] == "motorcycle"
    assert res["zone"] == 3 and res["booking_id"] == "b1" and "protokol" in res["message"]
    assert ctrl.zones[3].grants == [] and "ACCESS_DENIED" not in ctrl.kinds() and ctrl.storage.pin_failures_since(0) == 0
    assert ctrl.handover.status()["active"]["then_open"] is True
    res = await cc.submit_code(ctrl, "888888", "ui")
    assert res["ok"] and res["kind"] == "accessories" and res["message"] == "Otevřeno — Šatna. Vezměte si výbavu a zavřete dveře šatny."
    assert ctrl.zones[8].grants == [("b1", "accessories", "ui")] and ctrl.handover.protocols["b1"]["required"] is True
    # po podpisu jinde projde kód motorky rovnou
    await ctrl.handover.mark_signed_remote("b1", may_open=True)
    ctrl.api.resolve["123456"]["protocol"] = protocol("b1", required=False)
    assert (await cc.submit_code(ctrl, "123456", "ui"))["ok"] is True
