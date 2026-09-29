"""Trvalá fronta stavů tachometru (storage_odometer.py, odometer_queue.py) a mapování RPC `kiosk_submit_odometer`
(supabase_api.submit_odometer) — CONTRACT §30: nikdy nezahodit, opakovat dočasné chyby, trvalé = failed + událost,
disputed = hotovo + varování, idempotence dle reading_id."""
from __future__ import annotations

import pytest

from tests.handover_fakes import DEVICE_ID, TOKEN, FakeClock, FakeCtrl
from motogo_box.odometer import OdometerManager
from motogo_box.storage import Storage
from motogo_box.supabase_api import ApiError, SupabaseApi
from tests.test_odometer import CODE, OUT_3H, T0, code, events, moto_rpc, odo


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path, FakeClock(T0))
    c.odometer = OdometerManager(c, clock=c.clock)
    c.api.resolve[CODE] = moto_rpc(odo(**OUT_3H))
    yield c
    c.close()


async def test_upload_transient_permanent_retry(ctrl):
    assert (await code(ctrl, "10500"))["ok"]
    ctrl.api.odo_results.append({"ok": False, "permanent": False, "error": "network"})
    assert await ctrl.odometer.flush() == 0
    assert ctrl.storage.odometer_queue_pending()[0]["attempts"] == 1
    assert ctrl.odometer.status() == {"pending": ["b1"], "failed": []}
    ctrl.api.odo_results.append({"ok": False, "permanent": True, "error": "forbidden"})
    assert await ctrl.odometer.flush() == 0
    assert ctrl.odometer.status() == {"pending": [], "failed": ["b1"]}
    ev = events(ctrl, "ODOMETER_UPLOAD_FAILED")
    assert len(ev) == 1 and ev[0].level == "error" and ev[0].detail["error"] == "forbidden"
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10000      # failed = server odmítl → meze neovlivní
    assert ctrl.odometer.retry_failed() == 1 and ctrl.odometer.status()["pending"] == ["b1"]
    assert await ctrl.odometer.flush() == 1 and ctrl.odometer.status() == {"pending": [], "failed": []}
    p = ctrl.api.odo_submits[-1]
    assert set(p) == {"p_reading_id", "p_booking_id", "p_km", "p_recorded_at", "p_detail"}
    assert p["p_km"] == 10500 and p["p_booking_id"] == "b1" and len({s["p_reading_id"] for s in ctrl.api.odo_submits}) == 1
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10500      # přijato: drží do dalšího syncu
    ctrl.clock.advance(301)
    assert ctrl.odometer.pickup_mileage({"mileage": 10000}, "m1") == 10000


async def test_disputed_is_done_with_warning(ctrl):
    assert (await code(ctrl, "10500"))["ok"]
    ctrl.api.odo_results.append({"ok": True, "status": "disputed", "reason": "too_high", "duplicate": False})
    assert await ctrl.odometer.flush() == 1 and ctrl.storage.odometer_queue_pending() == []
    ev = events(ctrl, "ODOMETER_DISPUTED")
    assert len(ev) == 1 and ev[0].level == "warn" and ev[0].detail["reason"] == "too_high"


async def test_submit_wakes_upload_loop(ctrl):
    ctrl.odometer.wake.clear()
    assert (await code(ctrl, "10500"))["ok"] and ctrl.odometer.wake.is_set()


def test_queue_durable_and_idempotent(tmp_path):
    path = str(tmp_path / "q.db")
    st = Storage(path)
    st.odometer_queue_put("r1", "b1", "m1", 100, {"p_km": 100}, kv=("odometer", {"b": {"b1": {"phase": "out", "at": 1.0}}}))
    st.odometer_queue_put("r1", "b1", "m1", 999, {"p_km": 999})           # stejné reading_id = nic
    st.close()
    st = Storage(path)                                                     # restart jednotky
    rows = st.odometer_queue_pending()
    assert len(rows) == 1 and rows[0]["km"] == 100 and rows[0]["payload"] == {"p_km": 100}
    assert st.kv_get("odometer")["b"]["b1"]["phase"] == "out"
    assert st.odometer_queue_max_km("m1") == 100 and st.odometer_queue_max_km("m2") is None
    for _ in range(80):                                                    # žádný limit pokusů (na rozdíl od outboxu)
        st.odometer_queue_fail("r1", "network", False)
    assert st.odometer_queue_pending()[0]["attempts"] == 80
    st.odometer_queue_fail("r1", "forbidden", True)
    assert st.odometer_queue_pending() == [] and st.odometer_queue_max_km("m1") is None   # failed meze neovlivní
    assert st.odometer_queue_status() == {"pending": [], "failed": ["b1"]}
    st.close()


def test_queue_put_atomic_with_kv(tmp_path):
    st = Storage(str(tmp_path / "a.db"))
    cyclic: dict = {}
    cyclic["self"] = cyclic
    with pytest.raises(ValueError):
        st.odometer_queue_put("r1", "b1", "m1", 5, {}, kv=("odometer", cyclic))
    assert st.odometer_queue_pending() == [] and st.kv_get("odometer") is None
    st.odometer_queue_put("r2", "b1", "m1", 6, {}, kv=("odometer", {"b": {}}))   # spojení bez visícího BEGIN
    assert len(st.odometer_queue_pending()) == 1 and st.kv_get("odometer") == {"b": {}}
    st.close()


async def test_api_submit_odometer_mapping(tmp_path):
    st = Storage(str(tmp_path / "api.db"))
    api = SupabaseApi("http://127.0.0.1:1", "anon", DEVICE_ID, TOKEN, st, "1.1.0+test")
    outcomes: list = [
        ({"ok": True, "id": "r1", "status": "accepted", "duplicate": False}, (True, False)),
        ({"ok": True, "status": "disputed", "reason": "too_high", "duplicate": True}, (True, False)),
        ({"ok": False, "error": "forbidden"}, (False, True)),
        ({"ok": False, "error": "conflict"}, (False, True)),
        ({"ok": False, "error": "unauthorized"}, (False, False)),                 # přepárování to spraví
        (ApiError(404, '{"code":"PGRST202","message":"Could not find the function '
                       'public.kiosk_submit_odometer"}'), (False, False)),        # SQL ještě nenasazené
        (ApiError(0, "ConnectError"), (False, False)),
        (ApiError(503, "x"), (False, False)),
        (ApiError(401, "jwt"), (False, False)),
        (ApiError(400, '{"code":"22P02"}'), (False, True)),
    ]
    calls: list = []

    async def fake_rpc(name, params, timeout_s=10):
        calls.append((name, params))
        r = outcomes[len(calls) - 1][0]
        if isinstance(r, Exception):
            raise r
        return r
    api.rpc = fake_rpc
    for i, (_, (ok, permanent)) in enumerate(outcomes):
        res = await api.submit_odometer({"p_reading_id": "r1", "p_booking_id": "b1", "p_km": 5})
        assert (res["ok"], res["permanent"]) == (ok, permanent), i
    assert calls[1][0] == "kiosk_submit_odometer" and calls[0][1]["p_device_id"] == DEVICE_ID
    assert calls[0][1]["p_device_token"] == TOKEN and calls[0][1]["p_km"] == 5
    await api.close()
    st.close()
