"""Testy webserver.py — aiohttp test client s falešným controllerem (bez sítě, bez Supabase)."""
from __future__ import annotations

import asyncio
import json

import pytest
from aiohttp.test_utils import TestClient, TestServer

from motogo_box import webserver, webserver_service
from motogo_box.config import LocalConfig
from motogo_box.webserver import WebServer

SERVICE_TOKEN = "svc-token-ok"


class FakeAudio:
    def __init__(self) -> None:
        self.playing_zone: int | None = None

    async def play_zone(self, zone: int) -> bool:
        self.playing_zone = zone
        return True

    async def stop(self, fade: bool = True) -> None:
        self.playing_zone = None


class FakeZone:
    def __init__(self, number: int) -> None:
        self.number = number
        self.light = False

    async def set_light(self, on: bool) -> bool:
        self.light = on
        return True


class FakeController:
    """Minimální náhrada BoxController pro webserver (kontrakt §12 — jen použité metody)."""

    def __init__(self) -> None:
        self.health: dict = {}
        self.hardware = None
        self.last_error = None
        self.audio = FakeAudio()
        self.zones = {1: FakeZone(1), 2: FakeZone(2)}
        self.calls: list[tuple] = []
        self.tick = 0
        self.all_off_called = False

    def snapshot(self) -> dict:
        return {
            "ts": "2026-09-09T10:00:00+02:00", "version": "1.0.0+test", "uptime_s": 5, "ready": True,
            "branch_name": "Brno", "internet": True, "modules": {"wav645": True},
            "zones": [{"zone": 1, "state": "SECURED", "signal": "red", "tick": self.tick}],
            "notice": None,
        }

    async def submit_code(self, code: str, source: str = "ui") -> dict:
        self.calls.append(("submit_code", code, source))
        if code == "123456":
            return {"ok": True, "kind": "motorcycle", "error": None, "message": "Otevřeno", "zone": 1}
        if code == "servis":
            return {"ok": True, "kind": "service", "service_token": SERVICE_TOKEN, "doors": []}
        return {"ok": False, "kind": "invalid", "error": "invalid_code", "message": "Neplatný kód"}

    def check_service_token(self, token: str | None) -> bool:
        return token == SERVICE_TOKEN

    async def service_open(self, door_id: str | None, zone: int | None) -> dict:
        self.calls.append(("service_open", door_id, zone))
        return {"ok": True, "zone": zone}

    def find_zone(self, *, door_id=None, zone=None, box_number=None):
        return self.zones.get(zone) if zone is not None else None

    async def all_off(self) -> None:
        self.all_off_called = True

    async def resync(self) -> dict:
        return {"changed": True, "problems": []}


class FakeApi:
    def __init__(self, device_id: str = "") -> None:
        self.device_id = device_id
        self.device_token = "tok-" + device_id if device_id else ""
        self.pair_error: str | None = None

    @property
    def paired(self) -> bool:
        return bool(self.device_id and self.device_token)

    async def validate_pairing(self, device_id: str, token: str) -> str | None:
        return self.pair_error

    def set_device(self, device_id: str, device_token: str) -> None:
        self.device_id, self.device_token = device_id, device_token


class FakeStorage:
    def __init__(self) -> None:
        self.kv: dict = {}

    def kv_set(self, key: str, value) -> None:
        self.kv[key] = value

    def events_recent(self, limit: int = 100) -> list[dict]:
        return [{"kind": "STARTUP", "limit": limit}]


@pytest.fixture
async def env():
    ctrl, api, storage = FakeController(), FakeApi(device_id="dev-1"), FakeStorage()
    server = WebServer(ctrl, api, storage, LocalConfig())
    exits: list[int] = []
    server._exit = exits.append
    client = TestClient(TestServer(server.app))
    await client.start_server()
    try:
        yield client, ctrl, api, storage, exits
    finally:
        await client.close()


async def test_state_and_static(env):
    client, ctrl, *_ = env
    r = await client.get("/api/state")
    assert r.status == 200 and r.headers["Cache-Control"] == "no-store"
    st = await r.json()
    assert st["branch_name"] == "Brno" and st["paired"] is True and st["device_id"] == "dev-1"
    assert st["zones"][0]["zone"] == 1
    r = await client.get("/")
    assert r.status == 200 and "Zadejte přístupový kód" in await r.text()
    for f in ("app.js", "keyboard.js", "panel.js", "style.css", "logo.svg"):
        assert (await client.get(f"/static/{f}")).status == 200
    assert (await client.get("/static/../config.py")).status in (403, 404)
    r = await client.get("/api/neexistuje")
    assert r.status == 404 and (await r.json()) == {"ok": False, "error": "not_found"}


async def test_pin(env):
    client, ctrl, *_ = env
    r = await client.post("/api/pin", json={"code": "123456"})
    assert (await r.json())["ok"] is True and ctrl.calls[-1] == ("submit_code", "123456", "ui")
    r = await client.post("/api/pin", json={"code": "000000"})
    body = await r.json()
    assert body["ok"] is False and body["error"] == "invalid_code"
    r = await client.post("/api/pin", json={})
    assert r.status == 400 and (await r.json())["error"] == "empty_code"
    r = await client.post("/api/pin", data=b"not json")
    assert r.status == 400


async def test_service_token_required(env):
    client, ctrl, *_ = env
    for path in ("open", "music", "light", "all_off", "restart"):
        r = await client.post(f"/api/service/{path}", json={"service_token": "spatny", "zone": 1})
        assert r.status == 403, path
        assert (await r.json()) == {"ok": False, "error": "forbidden"}
    r = await client.post("/api/service/open", json={"service_token": SERVICE_TOKEN, "zone": 2})
    assert (await r.json())["ok"] is True and ctrl.calls[-1] == ("service_open", None, 2)
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 1, "on": True})
    assert (await r.json())["ok"] is True and ctrl.zones[1].light is True
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": True})
    assert r.status == 404
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "zone": 2, "on": True})
    assert (await r.json())["ok"] is True and ctrl.audio.playing_zone == 2
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "on": False})
    assert (await r.json())["ok"] is True and ctrl.audio.playing_zone is None
    r = await client.post("/api/service/all_off", json={"service_token": SERVICE_TOKEN})
    assert (await r.json())["ok"] is True and ctrl.all_off_called


async def test_restart_calls_exit(env):
    client, ctrl, api, storage, exits = env
    r = await client.post("/api/service/restart", json={"service_token": SERVICE_TOKEN})
    assert (await r.json())["ok"] is True
    await asyncio.sleep(webserver_service.RESTART_DELAY_S + 0.2)
    assert exits == [0]


async def test_pair_requires_token_when_paired(env):
    client, ctrl, api, storage, _ = env
    r = await client.post("/api/service/pair", json={"device_id": "new", "device_token": "tok"})
    assert r.status == 403
    r = await client.post("/api/service/pair", json={"device_id": "new", "device_token": "tok",
                                                    "service_token": SERVICE_TOKEN})
    body = await r.json()
    assert body["ok"] is True and api.device_id == "new" and storage.kv["device_token"] == "tok"
    assert body["resync"] == {"changed": True, "problems": []}


async def test_pair_without_token_when_unpaired():
    ctrl, api, storage = FakeController(), FakeApi(device_id=""), FakeStorage()
    server = WebServer(ctrl, api, storage, LocalConfig())
    async with TestClient(TestServer(server.app)) as client:
        st = await (await client.get("/api/state")).json()
        assert st["paired"] is False
        api.pair_error = "Neplatný token"
        r = await client.post("/api/service/pair", json={"device_id": "d", "device_token": "t"})
        assert (await r.json()) == {"ok": False, "error": "Neplatný token"}
        api.pair_error = None
        r = await client.post("/api/service/pair", json={"device_id": "d", "device_token": "t"})
        assert (await r.json())["ok"] is True and storage.kv["device_id"] == "d"
        r = await client.post("/api/service/pair", json={"device_id": "", "device_token": "t",
                                                        "service_token": SERVICE_TOKEN})
        assert r.status == 400 and (await r.json())["error"] == "missing_inputs"


async def test_health_and_events_localhost_only(env, monkeypatch):
    client, ctrl, *_ = env
    r = await client.post("/api/health", json={"internet": True, "lte": {"rssi": -70}})
    assert (await r.json())["ok"] is True and ctrl.health["lte"]["rssi"] == -70
    r = await client.get("/api/events?limit=5")
    assert (await r.json())["events"] == [{"kind": "STARTUP", "limit": 5}]
    monkeypatch.setattr(webserver, "is_local_request", lambda request: False)
    assert (await client.post("/api/health", json={"internet": True})).status == 403
    assert (await client.get("/api/events")).status == 403


async def test_websocket_state_and_push_on_change(env):
    client, ctrl, *_ = env
    async with client.ws_connect("/ws") as ws:
        first = json.loads(await ws.receive_str())
        assert first["type"] == "state" and first["state"]["zones"][0]["tick"] == 0
        await ws.send_str(json.dumps({"type": "ping"}))
        msgs = []
        for _ in range(3):
            msgs.append(json.loads(await asyncio.wait_for(ws.receive_str(), 2)))
        assert any(m["type"] == "pong" for m in msgs)
        ctrl.tick = 7
        deadline = asyncio.get_running_loop().time() + 1.5
        seen = False
        while asyncio.get_running_loop().time() < deadline and not seen:
            m = json.loads(await asyncio.wait_for(ws.receive_str(), 2))
            seen = m["type"] == "state" and m["state"]["zones"][0]["tick"] == 7
        assert seen, "změna snapshotu se nepropsala do WS"


async def test_handler_exception_is_json(env):
    client, ctrl, *_ = env

    async def boom(code: str, source: str = "ui") -> dict:
        raise RuntimeError("kaboom")

    ctrl.submit_code = boom
    r = await client.post("/api/pin", json={"code": "123456"})
    assert r.status == 500
    assert (await r.json()) == {"ok": False, "error": "internal"}
