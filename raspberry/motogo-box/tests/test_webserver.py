"""Testy webserver.py — aiohttp test client s falešným controllerem (bez sítě, bez Supabase)."""
from __future__ import annotations

import asyncio
import json

import pytest
from aiohttp.test_utils import TestClient, TestServer

from motogo_box import shell, webserver, webserver_service
from motogo_box.config import LocalConfig
from motogo_box.config_outdoor import OutdoorCfg
from motogo_box.models import EventKind, HwRef
from motogo_box.webserver import WebServer

SERVICE_TOKEN = "svc-token-ok"


class FakeAudio:
    mode = "selector"

    def __init__(self) -> None:
        self.playing_zone: int | None = None
        self.channels: list[str] = []

    async def play_zone(self, zone: int) -> bool:
        self.playing_zone = zone
        return True

    async def stop(self, fade: bool = True) -> None:
        self.playing_zone = None


class FakeAudioMulti(FakeAudio):
    mode = "multi"

    async def play_channel(self, name: str) -> bool:
        self.channels.append(name)
        return True

    async def stop_channel(self, name: str, fade: bool = True) -> bool:
        self.channels = [c for c in self.channels if c != name]
        return True


class FakeOutdoor:
    def __init__(self) -> None:
        self.cfg = OutdoorCfg(zone=9, light=HwRef("wav617b", 0), present=True)
        self.light_on = False

    async def set_light(self, on: bool) -> bool:
        self.light_on = on
        return True


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
        self.outdoor = FakeOutdoor()
        self.zones = {1: FakeZone(1), 2: FakeZone(2)}
        self.calls: list[tuple] = []
        self.tick = 0
        self.all_off_called = False
        self.events: list = []

    async def emit(self, event) -> None:
        self.events.append(event)

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

    def kv_delete(self, key: str) -> None:
        self.kv.pop(key, None)

    def events_recent(self, limit: int = 100) -> list[dict]:
        return [{"kind": "STARTUP", "limit": limit}]

    def outbox_count(self) -> int:
        return 3

    def load_code_cache(self) -> dict:
        return {"codes": [{"h": "x"}, {"h": "y"}], "service_codes": [{"h": "s"}]}

    def code_cache_saved_at(self) -> float:
        return 1_000_000.0


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
    # offline cache a outbox musí být vidět zdálky (audit 2026-09-20 je ve /api/state hledal marně)
    assert st["outbox_pending"] == 3
    assert st["code_cache"]["codes"] == 2 and st["code_cache"]["service_codes"] == 1
    assert st["code_cache"]["age_s"] is not None
    r = await client.get("/")
    assert r.status == 200 and "Zadejte přístupový kód" in await r.text()
    # všechny soubory, na které se odkazuje index.html (redesign 2026-09-10: diag/i18n/overlays/logo-light/logo-icon;
    # 2026-09-25 předávací protokol: i18n-handover/signature/handover/style-handover)
    for f in ("app.js", "diag.js", "i18n.js", "keyboard.js", "panel.js", "shell.js", "style.css", "style-overlays.css",
              "logo.svg", "logo-light.svg", "logo-icon.svg",
              "i18n-handover.js", "signature.js", "handover.js", "style-handover.css"):
        assert (await client.get(f"/static/{f}")).status == 200, f
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
    for path in ("open", "music", "light", "all_off", "restart", "shell"):
        r = await client.post(f"/api/service/{path}", json={"service_token": "spatny", "zone": 1})
        assert r.status == 403, path
        assert (await r.json()) == {"ok": False, "error": "forbidden"}
    r = await client.post("/api/service/open", json={"service_token": SERVICE_TOKEN, "zone": 2})
    assert (await r.json())["ok"] is True and ctrl.calls[-1] == ("service_open", None, 2)
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 1, "on": True})
    assert (await r.json())["ok"] is True and ctrl.zones[1].light is True
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 5, "on": True})
    assert r.status == 404
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "zone": 2, "on": True})
    assert (await r.json())["ok"] is True and ctrl.audio.playing_zone == 2
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "on": False})
    assert (await r.json())["ok"] is True and ctrl.audio.playing_zone is None
    r = await client.post("/api/service/all_off", json={"service_token": SERVICE_TOKEN})
    assert (await r.json())["ok"] is True and ctrl.all_off_called


async def test_service_outdoor_light_and_music(env):
    """Zóna venku (9 = hw.outdoor.zone): světlo přes ctrl.outdoor, hudba jen v multi (kanál outdoor)."""
    client, ctrl, *_ = env
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": True})
    assert (await r.json()) == {"ok": True, "zone": 9, "on": True, "error": None} and ctrl.outdoor.light_on is True
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": False})
    assert (await r.json())["ok"] is True and ctrl.outdoor.light_on is False and ctrl.zones[1].light is False
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": True})
    assert (await r.json()) == {"ok": False, "on": False, "zone": 9, "error": "outdoor_requires_multi"}
    assert ctrl.audio.playing_zone is None
    ctrl.audio = FakeAudioMulti()
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": True})
    assert (await r.json())["ok"] is True and ctrl.audio.channels == ["outdoor"] and ctrl.audio.playing_zone is None
    r = await client.post("/api/service/music", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": False})
    assert (await r.json()) == {"ok": True, "on": False, "zone": 9} and ctrl.audio.channels == []
    ctrl.outdoor.cfg = OutdoorCfg(zone=9, present=True)              # venek bez světla/audia = nenastaven
    r = await client.post("/api/service/light", json={"service_token": SERVICE_TOKEN, "zone": 9, "on": True})
    assert r.status == 404
    r = await client.get("/api/state")
    assert "security" not in await r.json()                            # kód je viditelný — UI blok security nečte


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


async def test_pair_clears_cached_branch_name():
    """Přepárování na jinou pobočku musí zahodit název z předchozího párování — jinak by displej
    do prvního úspěšného heartbeatu ukazoval název STARÉ pobočky (musí být 1:1 s Velínem)."""
    ctrl, api, storage = FakeController(), FakeApi(device_id=""), FakeStorage()
    storage.kv["branch_name"] = "Brno"
    ctrl.branch_name = "Brno"
    server = WebServer(ctrl, api, storage, LocalConfig())
    async with TestClient(TestServer(server.app)) as client:
        r = await client.post("/api/service/pair", json={"device_id": "d2", "device_token": "t2"})
        assert (await r.json())["ok"] is True
    assert "branch_name" not in storage.kv and ctrl.branch_name is None


async def test_health_and_events_localhost_only(env, monkeypatch):
    client, ctrl, *_ = env
    r = await client.post("/api/health", json={"internet": True, "lte": {"rssi": -70}})
    assert (await r.json())["ok"] is True and ctrl.health["lte"]["rssi"] == -70
    r = await client.get("/api/events?limit=5")
    assert (await r.json())["events"] == [{"kind": "STARTUP", "limit": 5}]
    monkeypatch.setattr(webserver, "is_local_request", lambda request: False)
    assert (await client.post("/api/health", json={"internet": True})).status == 403
    assert (await client.get("/api/events")).status == 403


async def test_health_actions_emit_lte_reset_and_reboot_events(env):
    """CONTRACT §15: reconnect/usb_reset → LTE_RESET, reboot → REBOOT (warn), neznámé akce ignorovat."""
    client, ctrl, *_ = env
    r = await client.post("/api/health", json={"internet": False, "lte": {"rssi": -90},
                                               "actions": ["reconnect", "usb_reset", "reboot", "x"]})
    assert (await r.json())["ok"] is True
    # první hlášení „internet False“ = navíc INTERNET_DOWN (2026-09-26), akce obnovy za ním
    assert [e.kind for e in ctrl.events] == [EventKind.INTERNET_DOWN, EventKind.LTE_RESET, EventKind.LTE_RESET, EventKind.REBOOT]
    assert all(e.level == "warn" for e in ctrl.events[1:])
    assert ctrl.events[1].detail == {"source": "health", "action": "reconnect", "lte": {"rssi": -90}, "last_link_uptime_s": None}
    assert ctrl.events[3].message == "LTE obnova: reboot"
    ctrl.events.clear()
    for body in ({"internet": True}, {"internet": True, "actions": []}, {"internet": True, "actions": "x"}):
        assert (await client.post("/api/health", json=body)).status == 200
    assert [e.kind for e in ctrl.events] == [EventKind.INTERNET_UP]     # obnova po výpadku výše, pak beze změny nic


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


async def test_service_shell(env):
    """Servisní terminál (§27): nabídka, připravený příkaz, volné psaní jen po odemčení z Velína."""
    client, ctrl, *_ = env
    ctrl.shell_until, ctrl.shell_tokens = 0.0, {}

    r = await client.post("/api/service/shell", json={"service_token": SERVICE_TOKEN})
    body = await r.json()
    assert body["ok"] is True and body["free"] is False
    assert any(p["id"] == "net.addr" for p in body["menu"])
    assert all("argv" not in p for p in body["menu"])

    # servisní heslo smí volné psaní i bez odemčení z Velína (offline pobočka)
    r = await client.post("/api/service/shell", json={"service_token": SERVICE_TOKEN, "command": "echo ahoj"})
    body = await r.json()
    assert body["ok"] is True and body["service"] is True and body["output"].strip() == "ahoj"

    # token terminálu z diagnostického kódu volné psaní NEMÁ, dokud ho nepovolí Velín
    token = shell.issue_token(ctrl)
    r = await client.post("/api/service/shell", json={"shell_token": token, "command": "echo ne"})
    body = await r.json()
    assert body["error"] == "locked" and body["service"] is False
    r = await client.post("/api/service/shell", json={"shell_token": token, "preset": "sys.disk"})
    body = await r.json()
    assert body["ok"] is True and body["rc"] == 0

    shell.unlock(ctrl, 30)
    r = await client.post("/api/service/shell", json={"shell_token": token, "command": "echo ahoj"})
    body = await r.json()
    assert body["ok"] is True and body["output"].strip() == "ahoj" and body["free_s"] > 0

    # prošlý / cizí token → 403 jako u ostatních servisních endpointů
    ctrl.shell_tokens.clear()
    r = await client.post("/api/service/shell", json={"shell_token": token, "preset": "sys.disk"})
    assert r.status == 403


class FakeHandover:
    def __init__(self) -> None:
        self.calls: list[tuple] = []

    async def submit(self, booking_id, form, signature, code, source="ui"):
        self.calls.append(("submit", booking_id, form, signature, code, source))
        return {"ok": True, "status": "saved", "opened": {"zone": 3, "kind": "motorcycle", "message": "Otevřeno"},
                "error": None}

    def dismiss(self, booking_id):
        self.calls.append(("dismiss", booking_id))
        return booking_id == "b1"

    def touch(self, booking_id):
        self.calls.append(("touch", booking_id))
        return booking_id == "b1"


async def test_protocol_endpoints(env):
    client, ctrl, *_ = env
    r = await client.post("/api/protocol/submit", json={"booking_id": "b1", "signature": "x"})
    body = await r.json()
    assert body["ok"] is False and body["error"] == "not_pending"      # controller bez HandoverManageru
    ctrl.handover = FakeHandover()
    sig = "data:image/png;base64," + "A" * 200_000                        # ~150 kB PNG projde limitem těla (1 MiB)
    r = await client.post("/api/protocol/submit", json={"booking_id": " b1 ", "code": "123456",
                                                        "form": {"mileage": "12"}, "signature": sig})
    assert r.status == 200 and (await r.json())["opened"]["zone"] == 3
    assert ctrl.handover.calls[-1] == ("submit", "b1", {"mileage": "12"}, sig, "123456", "ui")
    r = await client.post("/api/protocol/submit", json={"form": {}})
    assert r.status == 400 and (await r.json())["error"] == "missing_booking_id"
    r = await client.post("/api/protocol/dismiss", json={"booking_id": "b1"})
    assert (await r.json()) == {"ok": True, "dismissed": True}
    r = await client.post("/api/protocol/dismiss", json={"booking_id": "b2"})
    assert (await r.json()) == {"ok": True, "dismissed": False}
    r = await client.post("/api/protocol/touch", json={"booking_id": "b1"})
    assert (await r.json()) == {"ok": True, "active": True}
    r = await client.post("/api/protocol/touch", json={})
    assert r.status == 400
    r = await client.post("/api/protocol/submit", data=b"x" * (webserver.BODY_MAX_BYTES + 1),
                          headers={"Content-Type": "application/json"})
    assert r.status == 413 and (await r.json()) == {"ok": False, "error": "body_too_large"}


async def test_state_timings_include_handover_idle(env):
    client, ctrl, *_ = env
    from types import SimpleNamespace
    ctrl.hardware = SimpleNamespace(timings=SimpleNamespace(pin_entry_timeout_s=20, door_open_timeout_s=30,
                                                            maximum_session_s=600, handover_idle_s=120))
    st = await (await client.get("/api/state")).json()
    assert st["timings"] == {"pin_entry_timeout_s": 20, "door_open_timeout_s": 30, "maximum_session_s": 600,
                             "handover_idle_s": 120}


async def test_health_internet_transitions_emit_events(env):
    """Výpadek/obnova internetu = INTERNET_DOWN (error) / INTERNET_UP (warn, duration_s); beze změny nic."""
    client, ctrl, *_ = env
    await client.post("/api/health", json={"internet": True, "lte": {"state": "connected"}})
    assert ctrl.events == []
    await client.post("/api/health", json={"internet": False, "lte": {"state": "unavailable", "modem_gone": True}, "lan": {"problem": None}})
    await client.post("/api/health", json={"internet": False})
    assert [e.kind for e in ctrl.events] == [EventKind.INTERNET_DOWN]
    assert ctrl.events[0].level == "error" and ctrl.events[0].detail["modem_gone"] is True
    await client.post("/api/health", json={"internet": True, "lte": {"state": "connected"}})
    assert [e.kind for e in ctrl.events][-1] == EventKind.INTERNET_UP
    assert ctrl.events[-1].level == "warn" and isinstance(ctrl.events[-1].detail["duration_s"], int)
    ctrl.events.clear()
    ctrl.health = {}
    await client.post("/api/health", json={"internet": False})      # první hlášení po startu bez internetu = výpadek
    assert [e.kind for e in ctrl.events] == [EventKind.INTERNET_DOWN]


async def test_health_samples_go_to_net_history(env, tmp_path):
    from motogo_box.storage import Storage
    client, ctrl, api, storage, *_ = env
    real = Storage(str(tmp_path / "h.db"))
    storage.net_sample_add = real.net_sample_add          # FakeStorage nemá historii — přidat skutečnou
    await client.post("/api/health", json={"internet": False, "lte": {"state": "unavailable", "modem_gone": True, "rssi": -80},
                                           "lan": {"problem": None}, "net": {"default_dev": "eth0", "dns": ["1.1.1.1"]}, "actions": ["usb_reset"]})
    rows = real.net_history(60)
    assert len(rows) == 1 and rows[0]["internet"] is False and rows[0]["modem_gone"] is True and rows[0]["gw_dev"] == "eth0"
    assert rows[0]["dns"] == "1.1.1.1" and rows[0]["action"] == "usb_reset" and rows[0]["rssi"] == -80
    real.close()
