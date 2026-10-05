"""Výdej až od 12:00 (`pickup_gate.py`, rozhodnutí majitele 2026-10-01, CONTRACT §31): rezervace se slevou za pozdní
vyzvednutí — šatna i motorka až od `release_at`; hláška bez lockoutu, hradlo PŘED zámkem přejímky / šatnou / protokolem."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from motogo_box import controller_codes as cc
from motogo_box import handover_locker as hl
from motogo_box import pickup_gate as pg
from motogo_box.models import EventKind, ResolveResult

from tests.handover_fakes import SIG, FakeCtrl, protocol

FORM = {"mileage": "1200"}


def _iso(delta: timedelta) -> str:
    return (datetime.now(timezone.utc) + delta).isoformat()


def _door(kind: str, zone: int, box: int | None = None) -> dict:
    return {"id": f"d{zone}", "door_kind": kind, "box_number": box}


def _online(ctrl, *, moto: dict | None = None, acc: dict | None = None) -> None:
    p = protocol("b1")
    ctrl.api.resolve = {
        "111111": {"booking_id": "b1", "kind": "motorcycle", "box_number": 3, "door": _door("motorcycle", 3, 3),
                   "protocol": p, **(moto or {"ok": True})},
        "888888": {"booking_id": "b1", "kind": "accessories", "door": _door("accessories", 8), "protocol": p,
                   **(acc or {"ok": True})},
    }


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "888888", "kind": "accessories", "booking_id": "b1", "door_id": "d8"},
             {"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3},
             {"code": "222222", "kind": "motorcycle", "booking_id": "b2", "door_id": "d3", "box_number": 3}],
            [protocol("b1"), protocol("b2", needs_locker=False)])
    yield c
    c.close()


def _denied(ctrl) -> list:
    return [e for e in ctrl.events if e.kind == EventKind.ACCESS_DENIED]


# ─── čisté funkce ───────────────────────────────────────────────────────────
def test_helpers_and_czech_message_in_prague_time():
    now = datetime(2026, 10, 1, 8, 25, tzinfo=timezone.utc)           # 10:25 v Praze (CEST)
    rel = "2026-10-01T10:00:00+00:00"                                    # 12:00 v Praze
    assert pg.too_early(rel, now) and not pg.too_early(rel, now + timedelta(hours=2))
    assert not pg.too_early(rel, datetime(2026, 10, 1, 10, 0, tzinfo=timezone.utc))   # přesně v release_at = vydat
    assert pg.too_early(rel, now, slack_s=60) and not pg.too_early(rel, now, slack_s=96 * 60)
    assert not pg.too_early(None, now) and not pg.too_early("nesmysl", now)
    assert pg.minutes_left(rel, now) == 95 and pg.minutes_left(rel, now + timedelta(hours=3)) == 1
    msg = pg.message(rel, now)
    assert "slevu 50 % na 1. den za vyzvednutí od 12:00" in msg and "vydáme dnes od 12:00 (za 95 min)." in msg
    assert "motogo24.cz/upravit-rezervaci" in msg and "sleva zanikne, rozdíl doplatíte a kód bude platit hned." in msg
    assert cc.error_text("pickup_too_early", rel) == pg.message(rel)
    # jiný den: „{datum} od 12:00“ bez minut; zimní čas (12:00 Prahy = 11:00 UTC)
    other = pg.message("2026-12-05T11:00:00Z", now)
    assert "vydáme 5. 12. 2026 od 12:00. Potřebujete" in other and "min)" not in other
    # těsně po půlnoci Prahy (předchozí den UTC) je to pořád „dnes“
    late = pg.message(rel, datetime(2026, 9, 30, 22, 30, tzinfo=timezone.utc))
    assert "dnes od 12:00 (za 690 min)" in late
    assert "až od 12:00 v den začátku pronájmu" in pg.message(None, now)


def test_blocks_only_customer_ok_with_future_release():
    soon, later = _iso(timedelta(seconds=30)), _iso(timedelta(hours=1))
    assert not pg.blocks(ResolveResult(ok=True, kind="motorcycle", release_at=later))    # online rozhodl server
    assert pg.blocks(ResolveResult(ok=True, kind="motorcycle", release_at=later, offline=True))
    assert pg.blocks(ResolveResult(ok=True, kind="motorcycle", release_at=soon, offline=True))
    assert not pg.blocks(ResolveResult(ok=True, kind="motorcycle", release_at=soon))     # online: hodiny jednotky se neřeší
    assert not pg.blocks(ResolveResult(ok=True, kind="service", release_at=later))
    assert not pg.blocks(ResolveResult(ok=False, error="pickup_too_early", release_at=later))
    assert not pg.blocks(ResolveResult(ok=True, kind="motorcycle", release_at=_iso(timedelta(hours=-1))))
    assert not pg.blocks(ResolveResult(ok=True, kind="motorcycle"))


# ─── submit_code ────────────────────────────────────────────────────────────
@pytest.mark.parametrize("code,kind,zone", [("111111", "motorcycle", 3), ("888888", "accessories", 8)])
async def test_online_refusal_without_lockout(ctrl, code, kind, zone):
    rel = _iso(timedelta(hours=2))
    _online(ctrl, **{("moto" if kind == "motorcycle" else "acc"): {
        "ok": False, "error": "pickup_too_early", "release_at": rel}})
    sec = ctrl.hardware.security
    for _ in range(sec.maximum_failed_attempts + 2):                   # opakované zadání NIKDY nezamkne klávesnici
        res = await cc.submit_code(ctrl, code, "ui")
        assert res["ok"] is False and res["error"] == "pickup_too_early" and res["locked_until"] is None
    assert res["kind"] == kind and res["booking_id"] == "b1" and res["release_at"] == rel
    assert "upravit-rezervaci" in res["message"] and "sleva zanikne" in res["message"]
    assert ctrl.zones[zone].grants == [] and ctrl.storage.pin_failures_since(0) == 0
    assert ctrl.pin_guard.locked_until() is None and "PIN_INVALID" not in ctrl.kinds() and "PIN_LOCKOUT" not in ctrl.kinds()
    denied = _denied(ctrl)
    assert len(denied) == sec.maximum_failed_attempts + 2 and denied[0].level == "info" and denied[0].code_kind == kind
    assert denied[0].booking_id == "b1" and denied[0].detail == {
        "source": "ui", "reason": "pickup_too_early", "release_at": rel, "booking_id": "b1", "kind": kind,
        "offline": False}
    assert ctrl.handover.status()["active"] is None and "PROTOCOL_SHOWN" not in ctrl.kinds()


async def test_offline_cache_gate_then_release(ctrl):
    rel = _iso(timedelta(hours=1))
    ctrl.cache([{"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3,
                 "release_at": rel}], [protocol("b1", needs_locker=False)])
    ctrl.api.resolve = {"111111": None}                                # síť dole → offline cache
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "pickup_too_early" and res["kind"] == "motorcycle" and res["booking_id"] == "b1"
    assert pg.parse_iso(res["release_at"]) == pg.parse_iso(rel) and _denied(ctrl)[0].detail["offline"] is True
    assert ctrl.storage.pin_failures_since(0) == 0 and ctrl.zones[3].grants == []
    ctrl.cache([{"code": "111111", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3,
                 "release_at": _iso(timedelta(minutes=-1))}], [protocol("b1", needs_locker=False)])
    res = await cc.submit_code(ctrl, "111111", "ui")                   # po 12:00 → běžný tok (protokol)
    assert res["error"] == "protocol_required" and ctrl.handover.status()["active"]["then_open"] is True


async def test_gate_precedes_locker_protocol_and_handover_lock(ctrl):
    """Odmítnutí serverem: PŘED výzvou šatny, protokolem i zámkem přejímky jiné rezervace."""
    _online(ctrl, moto={"ok": False, "error": "pickup_too_early", "kind": "motorcycle", "booking_id": "b1",
                        "release_at": _iso(timedelta(hours=1))})
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "pickup_too_early" and "b1" not in hl._load(ctrl.storage, ctrl.clock())["prompted"]
    assert ctrl.handover.status()["active"] is None and "PROTOCOL_SHOWN" not in ctrl.kinds()
    ctrl.handover.lock.set("b2", 8, "Jan N.")                          # jiná rezervace právě zavřela šatnu
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "pickup_too_early"
    assert [e.detail["reason"] for e in _denied(ctrl)] == ["pickup_too_early", "pickup_too_early"]
    _online(ctrl, moto={"ok": True, "release_at": _iso(timedelta(hours=1))})   # online ok = rozhodl server → dál
    assert (await cc.submit_code(ctrl, "111111", "ui"))["error"] == "handover_in_progress"


async def test_diagnostics_window_treats_gated_code_as_invalid(ctrl):
    _online(ctrl, moto={"ok": False, "error": "pickup_too_early", "release_at": _iso(timedelta(hours=1))})
    res = await cc.submit_code(ctrl, "111111", "diag_ui", diagnostics_only=True)
    assert res["error"] == "invalid_code" and "release_at" not in res and "12:00" not in res["message"]
    assert ctrl.storage.pin_failures_since(0) == 1 and "PIN_INVALID" in ctrl.kinds() and not _denied(ctrl)


async def test_locker_row_ignores_future_release(ctrl):
    ctrl.cache([{"code": "888888", "kind": "accessories", "booking_id": "b1", "door_id": "d8",
                 "release_at": _iso(timedelta(hours=1))}], [protocol("b1")])
    now = datetime.now(timezone.utc)
    assert hl._locker_row(ctrl, "b1", now) is None
    assert hl._locker_row(ctrl, "b1", now + timedelta(hours=2))["door_id"] == "d8"


# ─── podpis protokolu z displeje (handover_submit._verify_code) ──────────────
async def test_protocol_submit_with_gated_code(ctrl):
    hm = ctrl.handover
    hm.remember(ResolveResult(ok=True, kind="accessories", booking_id="b1", door_id="d8", protocol=protocol("b1")))
    await hm.on_wardrobe_closed(8, "b1")                               # overlay s needs_code (bez then_open)
    rel = _iso(timedelta(hours=1))
    _online(ctrl, moto={"ok": False, "error": "pickup_too_early", "release_at": rel})
    ctrl.api.resolve["222222"] = {"ok": False, "error": "pickup_too_early", "kind": "motorcycle", "booking_id": "b2",
                                  "release_at": rel}
    res = await hm.submit("b1", FORM, SIG, "111111")
    assert res == {"ok": False, "status": None, "opened": None, "error": "pickup_too_early", "release_at": rel}
    assert ctrl.storage.pin_failures_since(0) == 0 and ctrl.api.submits == [] and ctrl.zones[3].grants == []
    assert hm.active() is not None                                     # položka zůstává, podpis se neuložil
    res = await hm.submit("b1", FORM, SIG, "222222")                   # platný kód JINÉ rezervace = hádání
    assert res["error"] == "code_mismatch" and ctrl.storage.pin_failures_since(0) == 1
    _online(ctrl, moto={"ok": True, "release_at": _iso(timedelta(minutes=-5))})
    res = await hm.submit("b1", FORM, SIG, "111111")
    assert res["ok"] and res["opened"]["zone"] == 3 and ctrl.zones[3].grants == [("b1", "motorcycle", "ui")]


async def test_replaced_code_message_without_lockout(ctrl):
    """2026-10-05: starý kód ze SMS po regeneraci (přesun kóje) — DB `invalid_code` + `replaced` → vlastní hláška, bez lockoutu."""
    ctrl.api.resolve = {"444444": {"ok": False, "error": "invalid_code", "replaced": True}}
    for _ in range(ctrl.hardware.security.maximum_failed_attempts + 2):
        res = await cc.submit_code(ctrl, "444444", "ui")
        assert res["ok"] is False and res["error"] == "code_replaced" and "nový" in res["message"]
    assert ctrl.storage.pin_failures_since(0) == 0 and ctrl.pin_guard.locked_until() is None
    assert [e.detail["reason"] for e in _denied(ctrl)][-1] == "code_replaced"
    assert ResolveResult.from_rpc({"ok": False, "error": "invalid_code"}).error == "invalid_code"


@pytest.mark.parametrize("rpc,err,word", [
    ({"reason": "revoked"}, "code_revoked", "zrušena"),
    ({"reason": "withheld"}, "code_withheld", "doklady"),
    ({"reason": "not_yet_valid", "valid_from": "2026-10-06T07:00:00+00:00"}, "code_not_yet_valid", "6. 10. 2026 9:00"),
    ({"reason": "expired"}, "code_expired", "skončila"),
    ({"reason": "wrong_branch", "branch_name": "MotoGo24 Mezná"}, "code_wrong_branch", "Mezná"),
])
async def test_known_code_reasons_without_lockout(ctrl, rpc, err, word):
    """2026-10-05: kód existuje, ale teď neplatí (`reason` z RPC) — hláška, ACCESS_DENIED info, NIKDY lockout."""
    ctrl.api.resolve = {"454545": {"ok": False, "error": "invalid_code", **rpc}}
    for _ in range(ctrl.hardware.security.maximum_failed_attempts + 2):
        res = await cc.submit_code(ctrl, "454545", "ui")
        assert res["ok"] is False and res["error"] == err and word in res["message"]
    assert ctrl.storage.pin_failures_since(0) == 0 and ctrl.pin_guard.locked_until() is None
    d = _denied(ctrl)[-1]
    assert d.level == "info" and d.detail["reason"] == err and "PIN_INVALID" not in ctrl.kinds()


async def test_unknown_code_still_locks_and_attempts_logged(ctrl):
    """Neznámý kód se počítá dál (ochrana proti hádání); pokus během blokace jde do Velína (ACCESS_DENIED reason locked)."""
    ctrl.api.resolve = {}
    for i in range(ctrl.hardware.security.maximum_failed_attempts):
        res = await cc.submit_code(ctrl, f"90000{i}", "ui")
    assert res["error"] == "locked" and ctrl.pin_guard.locked_until() is not None
    res = await cc.submit_code(ctrl, "111111", "ui")
    assert res["error"] == "locked" and _denied(ctrl)[-1].detail["reason"] == "locked"
