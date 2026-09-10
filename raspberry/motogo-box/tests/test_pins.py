"""Testy pins.py: HMAC shoda s referencí, lockout, LocalResolver (hashed + legacy)."""
from __future__ import annotations

import hashlib
import hmac
from datetime import datetime, timedelta, timezone

import pytest

from motogo_box.config import SecurityCfg
from motogo_box.pins import (
    LocalResolver, PinGuard, hmac_code, is_pin, mask, normalize_code, parse_iso,
)
from motogo_box.storage import Storage

DEVICE_ID = "6F1C2B8E-3A4D-4E5F-9A0B-1C2D3E4F5A6B"
TOKEN = "0A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D"


@pytest.fixture
def storage(tmp_path):
    st = Storage(str(tmp_path / "t.db"))
    yield st
    st.close()


class FakeClock:
    def __init__(self, t: float = 1_000_000.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t

    def advance(self, seconds: float) -> None:
        self.t += seconds


# ─── základní funkce ────────────────────────────────────────────────────────
def test_normalize_and_is_pin():
    assert normalize_code("  123 456 ") == "123456"
    assert is_pin("123456")
    assert not is_pin("12345")
    assert not is_pin("12345a")
    assert not is_pin("")


def test_mask():
    assert mask("123456") == "12••••"
    assert mask("ab") == "••"
    assert mask("") == ""


def test_hmac_matches_sql_reference():
    """Reference = HMAC-SHA256(key=token, msg=device_id:code), UUID malými písmeny (Postgres)."""
    code = "123456"
    ref = hmac.new(TOKEN.lower().encode("utf-8"), f"{DEVICE_ID.lower()}:{code}".encode("utf-8"),
                   hashlib.sha256).hexdigest()
    assert hmac_code(DEVICE_ID, TOKEN, code) == ref
    assert hmac_code(DEVICE_ID.lower(), TOKEN.lower(), code) == ref
    # jiný kód / token → jiný hash
    assert hmac_code(DEVICE_ID, TOKEN, "123457") != ref
    assert hmac_code(DEVICE_ID, TOKEN.replace("0", "1"), code) != ref


def test_hmac_known_vector():
    """Pevná hodnota spočítaná nezávisle (stdlib) pro regresní kontrolu."""
    dev = "11111111-1111-1111-1111-111111111111"
    tok = "22222222-2222-2222-2222-222222222222"
    expected = hmac.new(tok.encode(), f"{dev}:000000".encode(), hashlib.sha256).hexdigest()
    assert hmac_code(dev, tok, "000000") == expected
    assert len(expected) == 64


def test_parse_iso():
    assert parse_iso(None) is None
    assert parse_iso("nesmysl") is None
    z = parse_iso("2026-09-09T08:00:00Z")
    assert z is not None and z.tzinfo is not None
    naive = parse_iso("2026-09-09T08:00:00")
    assert naive is not None and naive.tzinfo == timezone.utc


# ─── PinGuard ───────────────────────────────────────────────────────────────
def test_lockout_after_max_failures(storage):
    clock = FakeClock()
    sec = SecurityCfg(maximum_failed_attempts=5, attempt_window_minutes=5, lockout_minutes=15)
    guard = PinGuard(storage, sec, clock)
    assert guard.locked_until() is None
    for i in range(4):
        assert guard.register_failure("12••••") is None
        clock.advance(10)
    until = guard.register_failure("12••••")
    assert until == pytest.approx(clock.t + 15 * 60)
    assert guard.locked_until() == pytest.approx(until)
    # lockout přežije nový PinGuard (persistováno)
    assert PinGuard(storage, sec, clock).locked_until() == pytest.approx(until)
    # po vypršení odemčeno
    clock.advance(15 * 60 + 1)
    assert guard.locked_until() is None
    # selhání před lockoutem se už nepočítají → jedno další selhání nezamkne
    assert guard.register_failure("12••••") is None


def test_failures_outside_window_do_not_count(storage):
    clock = FakeClock()
    sec = SecurityCfg(maximum_failed_attempts=3, attempt_window_minutes=5, lockout_minutes=15)
    guard = PinGuard(storage, sec, clock)
    guard.register_failure("a")
    guard.register_failure("b")
    clock.advance(6 * 60)          # okno 5 min uplynulo
    assert guard.register_failure("c") is None
    assert guard.register_failure("d") is None
    assert guard.register_failure("e") is not None


def test_success_clears_lockout(storage):
    clock = FakeClock()
    sec = SecurityCfg(maximum_failed_attempts=2, attempt_window_minutes=5, lockout_minutes=15)
    guard = PinGuard(storage, sec, clock)
    guard.register_failure("x")
    assert guard.register_failure("x") is not None
    assert guard.locked_until() is not None
    guard.register_success("12••••")
    assert guard.locked_until() is None


# ─── LocalResolver ──────────────────────────────────────────────────────────
NOW = datetime(2026, 9, 9, 10, 0, tzinfo=timezone.utc)


def _hashed_cache() -> dict:
    h = lambda c: hmac_code(DEVICE_ID, TOKEN, c)  # noqa: E731
    return {
        "ok": True,
        "doors": [
            {"id": "door-1", "door_kind": "motorcycle", "box_number": 1, "label": "Kóje 1",
             "hw": {"zone": 1, "lock": {"dev": "wav645", "coil": 0}}},
            {"id": "door-acc", "door_kind": "accessories", "box_number": None, "label": "Oblečení", "hw": {}},
        ],
        "service_codes": [{"h": h("servis-heslo")}],
        "codes": [
            {"h": h("111111"), "kind": "motorcycle", "booking_id": "b-1",
             "valid_from": (NOW - timedelta(hours=1)).isoformat(),
             "valid_until": (NOW + timedelta(hours=8)).isoformat(),
             "door_id": "door-1", "box_number": 1},
            {"h": h("222222"), "kind": "accessories", "booking_id": "b-2",
             "valid_from": None, "valid_until": (NOW - timedelta(minutes=1)).isoformat(),
             "door_id": "door-acc", "box_number": None},
            {"h": h("333333"), "kind": "motorcycle", "booking_id": "b-3",
             "valid_from": (NOW + timedelta(hours=1)).isoformat(), "valid_until": None,
             "door_id": None, "box_number": None},
        ],
    }


def _legacy_cache() -> dict:
    return {
        "ok": True, "legacy": True,
        "doors": [{"id": "door-1", "door_kind": "motorcycle", "box_number": 1, "label": "Kóje 1",
                   "relay_url": "http://relay/1", "light_url": None}],
        "service_codes": ["servis-heslo"],
        "codes": [{"code": "444444", "kind": "motorcycle", "booking_id": "b-4",
                   "valid_from": None, "valid_until": "2026-09-09T20:00:00+02:00",
                   "door_id": "door-1", "box_number": 1, "label": "Kóje 1",
                   "relay_url": "http://relay/1", "light_url": None}],
    }


def test_resolver_hashed_service_and_customer():
    r = LocalResolver(DEVICE_ID, TOKEN)
    cache = _hashed_cache()
    svc = r.resolve("servis-heslo", cache, NOW)
    assert svc is not None and svc.ok and svc.is_service and svc.offline
    assert [d.id for d in svc.doors] == ["door-1", "door-acc"]
    assert svc.doors[0].zone == 1 and svc.doors[0].configured
    assert not svc.doors[1].configured

    cust = r.resolve("111 111", cache, NOW)
    assert cust is not None and cust.ok and cust.kind == "motorcycle" and cust.offline
    assert cust.booking_id == "b-1" and cust.door_id == "door-1" and cust.box_number == 1
    assert cust.door_configured

    assert r.resolve("999999", cache, NOW) is None
    assert r.resolve("", cache, NOW) is None
    assert r.resolve("111111", None, NOW) is None


def test_resolver_expiry_and_not_yet_valid():
    r = LocalResolver(DEVICE_ID, TOKEN)
    cache = _hashed_cache()
    expired = r.resolve("222222", cache, NOW)
    assert expired is not None and not expired.ok and expired.error == "code_expired"
    # o dvě minuty dříve byl ještě platný
    ok = r.resolve("222222", cache, NOW - timedelta(minutes=2))
    assert ok is not None and ok.ok and ok.kind == "accessories" and ok.door_configured
    assert ok.door_id == "door-acc" and ok.box_number is None
    future = r.resolve("333333", cache, NOW)
    assert future is not None and not future.ok and future.error == "code_not_yet_valid"
    later = r.resolve("333333", cache, NOW + timedelta(hours=2))
    assert later is not None and later.ok and not later.door_configured


def test_resolver_wrong_device_token_does_not_match():
    cache = _hashed_cache()
    assert LocalResolver(DEVICE_ID, "ffffffff-0000-0000-0000-000000000000").resolve("111111", cache, NOW) is None


def test_resolver_legacy_plaintext():
    r = LocalResolver(DEVICE_ID, TOKEN)
    cache = _legacy_cache()
    svc = r.resolve("servis-heslo", cache, NOW)
    assert svc is not None and svc.ok and svc.is_service
    assert svc.doors[0].configured and svc.doors[0].zone is None
    cust = r.resolve("444444", cache, NOW)
    assert cust is not None and cust.ok and cust.booking_id == "b-4" and cust.door_id == "door-1"
    # po valid_until (20:00 +02:00 = 18:00 UTC) už neplatí
    late = r.resolve("444444", cache, datetime(2026, 9, 9, 18, 30, tzinfo=timezone.utc))
    assert late is not None and not late.ok
    assert r.resolve("555555", cache, NOW) is None
