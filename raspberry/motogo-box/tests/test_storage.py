"""Testy storage.py: kv, cache kódů, outbox, PIN pokusy, ring buffer událostí."""
from __future__ import annotations

import time

import pytest

from motogo_box.models import Event, EventKind
from motogo_box.storage import EVENTS_MAX, OUTBOX_MAX_ATTEMPTS, Storage


@pytest.fixture
def storage(tmp_path):
    st = Storage(str(tmp_path / "motogo.db"))
    yield st
    st.close()


def test_kv_roundtrip_and_persistence(tmp_path):
    path = str(tmp_path / "kv.db")
    st = Storage(path)
    assert st.kv_get("missing") is None
    assert st.kv_get("missing", "dflt") == "dflt"
    st.kv_set("device_id", "abc")
    st.kv_set("cfg", {"a": [1, 2, {"b": None}], "č": "ř"})
    st.kv_set("cfg", {"a": 1})          # přepis
    st.close()
    st2 = Storage(path)
    assert st2.kv_get("device_id") == "abc"
    assert st2.kv_get("cfg") == {"a": 1}
    st2.kv_delete("device_id")
    assert st2.kv_get("device_id") is None
    st2.close()


def test_code_cache(storage):
    assert storage.load_code_cache() is None
    assert storage.code_cache_saved_at() is None
    payload = {"ok": True, "codes": [{"h": "x"}], "doors": []}
    storage.save_code_cache(payload)
    assert storage.load_code_cache() == payload
    assert storage.code_cache_saved_at() == pytest.approx(time.time(), abs=5)
    storage.save_code_cache({"ok": True, "legacy": True})
    assert storage.load_code_cache() == {"ok": True, "legacy": True}


def test_outbox_lifecycle(storage):
    a = storage.outbox_add("log_open", {"p_kind": "motorcycle", "p_success": True})
    b = storage.outbox_add("log_event", {"p_level": "warn"})
    assert a < b
    pending = storage.outbox_pending()
    assert [(o, k) for o, k, _ in pending] == [(a, "log_open"), (b, "log_event")]
    assert pending[0][2] == {"p_kind": "motorcycle", "p_success": True}
    assert storage.outbox_pending(limit=1) == [pending[0]]
    storage.outbox_done(a)
    assert [o for o, _, _ in storage.outbox_pending()] == [b]
    storage.outbox_fail(b)
    assert storage.outbox_count() == 1
    for _ in range(OUTBOX_MAX_ATTEMPTS):
        storage.outbox_fail(b)
    assert storage.outbox_pending() == []      # > 50 pokusů → zahozeno
    assert storage.outbox_count() == 0
    storage.outbox_done(9999)                   # neexistující id nevadí


def test_pin_attempts_and_failures_since(storage):
    t0 = 1_000_000.0
    storage.pin_attempt(False, "11••••", ts=t0)
    storage.pin_attempt(False, "22••••", ts=t0 + 10)
    storage.pin_attempt(True, "33••••", ts=t0 + 20)
    storage.pin_attempt(False, "44••••", ts=t0 + 30)
    assert storage.pin_failures_since(t0) == 3
    assert storage.pin_failures_since(t0 + 10) == 2     # ts >= since_ts (včetně)
    assert storage.pin_failures_since(t0 + 11) == 1
    assert storage.pin_failures_since(t0 + 31) == 0


def test_lockout_until_via_kv(storage):
    assert storage.lockout_until() is None
    storage.set_lockout_until(123.5)
    assert storage.lockout_until() == 123.5
    assert storage.kv_get("pin_lockout_until") == 123.5
    storage.set_lockout_until(None)
    assert storage.lockout_until() is None


def _event(i: int) -> Event:
    return Event(kind=EventKind.DOOR_OPENED, zone=i % 9 + 1, door_id=f"d{i}", booking_id=None,
                 success=True, level="info", message=f"msg {i}", detail={"i": i})


def test_events_ring_buffer(storage):
    n = EVENTS_MAX + 120
    for i in range(n):
        storage.event_add(_event(i))
    assert storage.events_count() == EVENTS_MAX
    recent = storage.events_recent(limit=3)
    assert [e["message"] for e in recent] == [f"msg {n-1}", f"msg {n-2}", f"msg {n-3}"]
    assert recent[0]["detail"] == {"i": n - 1}
    assert recent[0]["kind"] == "DOOR_OPENED" and recent[0]["success"] is True
    oldest = storage.events_recent(limit=EVENTS_MAX)[-1]
    assert oldest["message"] == f"msg {n - EVENTS_MAX}"


def test_event_add_serializes_detail(storage):
    ev = Event(kind=EventKind.FORCED_OPEN, zone=2, success=False, level="error",
               message="násilné otevření", detail={"event": "FORCED_OPEN", "zone": 2})
    storage.event_add(ev)
    row = storage.events_recent(1)[0]
    assert row["success"] is False and row["level"] == "error" and row["zone"] == 2
    assert row["detail"]["event"] == "FORCED_OPEN" and row["ts"] == ev.ts
