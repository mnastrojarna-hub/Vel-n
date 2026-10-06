"""Kód šatny stažený, protože rezervace nemá vybranou výbavu (zadání majitele 2026-10-05: kód šatny jen s vybranou
výbavou; DB `kiosk_resolve_code` → `{error:'invalid_code', reason:'revoked', no_gear:true}`, migrace 20261005j).
Jednotka ≥ 1.2.7: chyba `code_no_gear` — hláška „šatnu nepotřebujete, zadejte kód k motorce“, BEZ PIN lockoutu."""
from __future__ import annotations

import pytest

from motogo_box import controller_codes as cc
from motogo_box.models import CODE_NO_GEAR, EventKind, ResolveResult

from tests.handover_fakes import SIG, FakeCtrl, protocol, rr_moto

FORM = {"mileage": "1200"}
NO_GEAR = {"ok": False, "error": "invalid_code", "reason": "revoked", "no_gear": True}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "123456", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
            [protocol("b1")])
    yield c
    c.close()


@pytest.mark.parametrize("rpc,err", [
    (NO_GEAR, CODE_NO_GEAR),
    ({"ok": False, "error": "invalid_code", "no_gear": True}, CODE_NO_GEAR),           # příznak bez `reason`
    ({"ok": False, "error": "invalid_code", "reason": "revoked", "no_gear": False}, "code_revoked"),
    ({"ok": False, "error": "invalid_code", "reason": "revoked"}, "code_revoked"),     # starší DB bez příznaku
    ({"ok": False, "error": "invalid_code", "reason": "revoked", "no_gear": "true"}, "code_revoked"),   # jen přesně true
    ({"ok": False, "error": "invalid_code", "reason": "expired", "no_gear": True}, "code_expired"),     # jiný důvod vyhrává
    ({"ok": False, "error": "invalid_code", "replaced": True, "no_gear": True}, "code_replaced"),
    ({"ok": False, "error": "invalid_code", "reason": "withheld", "no_gear": True}, "invalid_code"),  # neznámý = počítá se
    ({"ok": False, "error": "unauthorized", "no_gear": True}, "unauthorized"),          # jen u invalid_code
])
def test_from_rpc_maps_no_gear(rpc, err):
    assert ResolveResult.from_rpc(rpc).error == err


def test_no_gear_is_known_error_not_counted():
    assert CODE_NO_GEAR == "code_no_gear"
    assert CODE_NO_GEAR in cc.KNOWN_CODE_ERRORS and CODE_NO_GEAR not in cc.INVALID_CODE_ERRORS
    assert cc.error_text(CODE_NO_GEAR) == ("Rezervace nemá zapůjčenou výbavu — šatnu nepotřebujete. "
                                           "Zadejte kód k motorce.")


async def test_no_gear_code_message_without_lockout(ctrl):
    """Opakované zadání staženého kódu šatny nikdy nezablokuje displej; do Velína ACCESS_DENIED info s důvodem."""
    ctrl.api.resolve = {"888888": dict(NO_GEAR)}
    for _ in range(ctrl.hardware.security.maximum_failed_attempts + 2):
        res = await cc.submit_code(ctrl, "888888", "ui")
        assert res["ok"] is False and res["error"] == CODE_NO_GEAR and "kód k motorce" in res["message"]
    assert ctrl.storage.pin_failures_since(0) == 0 and ctrl.pin_guard.locked_until() is None
    denied = [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]
    assert denied and all(e.level == "info" and e.detail["reason"] == CODE_NO_GEAR for e in denied)
    assert "PIN_INVALID" not in ctrl.kinds() and "PIN_LOCKOUT" not in ctrl.kinds()


async def test_no_gear_code_in_protocol_field_is_not_a_guess(ctrl):
    """Stažený kód šatny v poli „Kód motorky“ protokolu = omyl (code_mismatch), ne hádání — bez PIN_INVALID."""
    hm = ctrl.handover
    hm.remember(rr_moto(proto=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")
    ctrl.api.resolve = {"888888": dict(NO_GEAR)}
    res = await hm.submit("b1", FORM, SIG, "888888")
    assert res["error"] == "code_mismatch" and ctrl.storage.pin_failures_since(0) == 0
    assert "PIN_INVALID" not in ctrl.kinds() and ctrl.api.submits == []
