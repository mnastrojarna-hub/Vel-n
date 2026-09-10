"""Testy supabase_api.py proti in-test fake PostgREST serveru (aiohttp)."""
from __future__ import annotations

import asyncio

import pytest
from aiohttp import web

from motogo_box.storage import Storage
from motogo_box.supabase_api import ApiError, SupabaseApi

DEVICE_ID = "6f1c2b8e-3a4d-4e5f-9a0b-1c2d3e4f5a6b"
TOKEN = "0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d"
ANON = "anon-key-xyz"


class FakePostgrest:
    """Minimální PostgREST: ``POST /rest/v1/rpc/<name>``; zaznamenává volání."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict, dict]] = []   # (name, params, headers)
        self.sync_config_missing = True
        self.status_missing = False
        self.fail_all = False
        self._runner: web.AppRunner | None = None
        self.port = 0

    def _authorized(self, p: dict) -> bool:
        return p.get("p_device_id") == DEVICE_ID and p.get("p_device_token") == TOKEN

    async def _rpc(self, request: web.Request) -> web.Response:
        name = request.match_info["name"]
        params = await request.json()
        self.calls.append((name, params, dict(request.headers)))
        if self.fail_all:
            return web.Response(status=503, text="service unavailable")
        if request.headers.get("apikey") != ANON:
            return web.json_response({"message": "No API key found in request"}, status=401)
        if name == "kiosk_heartbeat":
            if not self._authorized(params):
                return web.json_response({"ok": False, "error": "unauthorized"})
            return web.json_response({"ok": True, "branch_name": "Test", "branch_id": "b-1"})
        if name == "kiosk_resolve_code":
            if params.get("p_code") == "123456":
                return web.json_response({"ok": True, "kind": "motorcycle", "booking_id": "bk", "box_number": 3,
                                          "door": {"id": "d3", "door_kind": "motorcycle", "box_number": 3}})
            return web.json_response({"ok": False, "error": "invalid_code"})
        if name == "kiosk_sync_config":
            if self.sync_config_missing:
                return web.json_response(
                    {"code": "PGRST202", "hint": None, "details": None,
                     "message": "Could not find the function public.kiosk_sync_config(p_device_id, p_device_token) in the schema cache"},
                    status=404)
            return web.json_response({"ok": True, "doors": [], "service_codes": [{"h": "x"}], "codes": [],
                                      "hardware": {"timings": {"lock_pulse_ms": 700}}})
        if name == "kiosk_sync_codes":
            return web.json_response({"ok": True, "doors": [], "service_codes": ["svc"], "codes": []})
        if name == "kiosk_fetch_commands":
            if not self._authorized(params):
                return web.json_response({"ok": False, "error": "unauthorized"})
            return web.json_response({"ok": True, "commands": [{"id": "c1", "command": "identify", "params": {}}]})
        if name == "kiosk_report_status":
            if self.status_missing:
                return web.json_response({"code": "PGRST202", "message": "Could not find the function public.kiosk_report_status"}, status=404)
            return web.Response(status=204)
        if name == "kiosk_report_diagnostics":
            n = sum(1 for c in self.calls if c[0] == name)
            if n > 1:
                return web.json_response({"ok": False, "error": "rate_limited"})
            return web.json_response({"ok": True, "id": "diag-1"})
        if name in ("kiosk_log_open", "kiosk_log_event", "kiosk_complete_command", "kiosk_report_power"):
            if name == "kiosk_log_open" and params.get("p_door_id") == "not-a-uuid":
                return web.json_response({"code": "22P02", "message": "invalid input syntax for type uuid"}, status=400)
            return web.Response(status=204)
        return web.json_response({"code": "PGRST202", "message": f"Could not find the function public.{name}"}, status=404)

    async def start(self, port: int = 0) -> None:
        app = web.Application()
        app.router.add_post("/rest/v1/rpc/{name}", self._rpc)
        self._runner = web.AppRunner(app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, "127.0.0.1", port)
        await site.start()
        self.port = site._server.sockets[0].getsockname()[1]  # noqa: SLF001

    async def stop(self) -> None:
        if self._runner is not None:
            await self._runner.cleanup()
            self._runner = None

    def names(self) -> list[str]:
        return [c[0] for c in self.calls]


@pytest.fixture
async def server():
    srv = FakePostgrest()
    await srv.start()
    try:
        yield srv
    finally:
        await srv.stop()


@pytest.fixture
def storage(tmp_path):
    st = Storage(str(tmp_path / "api.db"))
    yield st
    st.close()


def make_api(server: FakePostgrest, storage: Storage, token: str = TOKEN) -> SupabaseApi:
    return SupabaseApi(f"http://127.0.0.1:{server.port}", ANON, DEVICE_ID, token, storage, "1.0.0+test")


async def test_heartbeat_headers_and_result(server, storage):
    api = make_api(server, storage)
    try:
        assert api.online is False
        res = await api.heartbeat()
        assert res == {"ok": True, "branch_name": "Test", "branch_id": "b-1"}
        assert api.online is True
        name, params, headers = server.calls[-1]
        assert name == "kiosk_heartbeat"
        assert params["p_platform"] == "rpi" and params["p_app_version"] == "1.0.0+test"
        assert headers["apikey"] == ANON and headers["Authorization"] == f"Bearer {ANON}"
        assert headers["Content-Type"].startswith("application/json")
    finally:
        await api.close()


async def test_heartbeat_unauthorized_returns_none(server, storage):
    api = make_api(server, storage, token="wrong")
    try:
        assert await api.heartbeat() is None
        assert api.online is True         # server odpověděl, jen odmítl
    finally:
        await api.close()


async def test_resolve_code(server, storage):
    api = make_api(server, storage)
    try:
        ok = await api.resolve_code("123456")
        assert ok and ok["ok"] and ok["box_number"] == 3
        bad = await api.resolve_code("000000")
        assert bad == {"ok": False, "error": "invalid_code"}
        server.fail_all = True
        assert await api.resolve_code("123456") is None       # 5xx → None (offline cache)
    finally:
        await api.close()


async def test_sync_config_falls_back_to_legacy(server, storage):
    api = make_api(server, storage)
    try:
        payload = await api.sync_config()
        assert payload is not None and payload["legacy"] is True
        assert payload["service_codes"] == ["svc"]
        assert server.names() == ["kiosk_sync_config", "kiosk_sync_codes"]
        server.calls.clear()
        server.sync_config_missing = False
        payload = await api.sync_config()
        assert payload is not None and "legacy" not in payload
        assert payload["hardware"]["timings"]["lock_pulse_ms"] == 700
        assert server.names() == ["kiosk_sync_config"]
        server.fail_all = True
        assert await api.sync_config() is None
        assert api.online is True
    finally:
        await api.close()


async def test_rpc_errors(server, storage):
    api = make_api(server, storage)
    try:
        with pytest.raises(ApiError) as ei:
            await api.rpc("kiosk_unknown_rpc", {})
        assert ei.value.status == 404 and ei.value.is_missing_function("kiosk_unknown_rpc")
        assert not ei.value.is_transient
        assert await api.rpc("kiosk_log_event", {"p_level": "info"}) is None    # 204 bez těla
    finally:
        await api.close()


async def test_log_open_offline_goes_to_outbox_and_flushes(storage):
    srv = FakePostgrest()
    await srv.start()
    port = srv.port
    await srv.stop()                       # server "vypnutý" → connection refused
    api = SupabaseApi(f"http://127.0.0.1:{port}", ANON, DEVICE_ID, TOKEN, storage, "1.0.0")
    try:
        await api.log_open("d3", "motorcycle", "bk", True, {"event": "ACCESS_GRANTED", "zone": 3})
        await api.log_event("warn", "zone", "test message", {"x": 1})
        await api.complete_command("c1", True, {"done": True})
        assert api.online is False
        pending = storage.outbox_pending()
        assert [k for _, k, _ in pending] == ["log_open", "log_event", "complete_command"]
        assert "p_device_token" not in pending[0][2]           # auth se do outboxu neukládá
        assert pending[0][2]["p_detail"]["zone"] == 3
        # flush při vypnutém serveru: nic, položky zůstávají, attempts+1
        assert await api.flush_outbox() == 0
        assert storage.outbox_count() == 3

        await srv.start(port)              # server zapnut na stejném portu
        try:
            sent = await api.flush_outbox()
            assert sent == 3 and storage.outbox_count() == 0 and api.online is True
            names = srv.names()
            assert names == ["kiosk_log_open", "kiosk_log_event", "kiosk_complete_command"]
            p = srv.calls[0][1]
            assert p["p_device_id"] == DEVICE_ID and p["p_device_token"] == TOKEN
            assert p["p_door_id"] == "d3" and p["p_booking_id"] == "bk" and p["p_success"] is True
            assert srv.calls[1][1]["p_app_version"] == "1.0.0"
            assert srv.calls[2][1]["p_command_id"] == "c1"
        finally:
            await srv.stop()
    finally:
        await api.close()


async def test_flush_skips_permanently_rejected_item(server, storage):
    api = make_api(server, storage)
    try:
        storage.outbox_add("log_open", {"p_door_id": "not-a-uuid", "p_kind": "x", "p_success": True})
        storage.outbox_add("log_event", {"p_level": "info", "p_source": "t", "p_message": "m"})
        storage.outbox_add("nonsense", {})
        assert await api.flush_outbox() == 1
        pending = storage.outbox_pending()
        assert len(pending) == 1 and pending[0][1] == "log_open"    # 4xx → attempts+1, zůstává
    finally:
        await api.close()


async def test_report_status_missing_rpc_is_silent(server, storage):
    api = make_api(server, storage)
    try:
        await api.report_status({"ready": True})
        assert api.status_rpc_missing is False
        server.status_missing = True
        await api.report_status({"ready": True})
        assert api.status_rpc_missing is True
        server.fail_all = True
        await api.report_power({"soc": 55})
        assert storage.outbox_count() == 0     # stavové reporty se nefrontují
    finally:
        await api.close()


async def test_fetch_commands_and_validate_pairing(server, storage):
    api = make_api(server, storage, token="wrong")
    try:
        assert await api.fetch_commands() == []            # unauthorized → []
        api.set_device(DEVICE_ID, TOKEN)
        cmds = await api.fetch_commands()
        assert cmds == [{"id": "c1", "command": "identify", "params": {}}]
        assert await api.validate_pairing(DEVICE_ID, TOKEN) is None
        assert await api.validate_pairing(DEVICE_ID, "bad") == "unauthorized"
        assert await api.validate_pairing("", "") == "missing_inputs"
        assert api.device_token == TOKEN                    # validate_pairing nemění identitu
    finally:
        await api.close()


async def test_validate_pairing_network_error(storage):
    srv = FakePostgrest()
    await srv.start()
    port = srv.port
    await srv.stop()
    api = SupabaseApi(f"http://127.0.0.1:{port}", ANON, "", "", storage, "1.0.0")
    try:
        assert await api.validate_pairing(DEVICE_ID, TOKEN) == "network"
        assert await api.flush_outbox() == 0               # nespárováno → nic
        await asyncio.sleep(0)
    finally:
        await api.close()


async def test_flush_retries_rate_limited_report_later(server, storage):
    """Dva reporty diagnostiky ve frontě (např. po spárování): druhý dostane rate_limited → zůstává na příště."""
    api = make_api(server, storage)
    try:
        storage.outbox_add("report_diagnostics", {"p_report": {"id": "a"}})
        storage.outbox_add("report_diagnostics", {"p_report": {"id": "b"}})
        storage.outbox_add("log_event", {"p_level": "info", "p_source": "t", "p_message": "m"})
        assert await api.flush_outbox() == 1
        pending = storage.outbox_pending()
        assert [k for _, k, _ in pending] == ["report_diagnostics", "log_event"]
        assert pending[0][2]["p_report"]["id"] == "b"
    finally:
        await api.close()
