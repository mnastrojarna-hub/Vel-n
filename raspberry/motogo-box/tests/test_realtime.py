"""Testy realtime.py: parsování zpráv, URL a průchod join → broadcast → on_wake proti
in-process websockets serveru (fake Supabase Realtime)."""
from __future__ import annotations

import asyncio
import json

from websockets.asyncio.server import serve

from motogo_box import realtime
from motogo_box.realtime import RealtimeListener, is_wake_message, parse_message, ws_url


def test_ws_url():
    assert ws_url("https://abc.supabase.co", "k+y") == \
        "wss://abc.supabase.co/realtime/v1/websocket?apikey=k%2By&vsn=1.0.0"
    assert ws_url("http://127.0.0.1:4000/", "k").startswith("ws://127.0.0.1:4000/realtime/v1/websocket?apikey=k")
    assert ws_url("abc.supabase.co", "k").startswith("wss://abc.supabase.co/")


def test_is_wake_message():
    assert is_wake_message({"topic": "realtime:kiosk:x", "event": "broadcast",
                            "payload": {"type": "broadcast", "event": "cmd", "payload": {"id": "c1"}}, "ref": None})
    assert is_wake_message({"event": "broadcast", "payload": {"event": "cmd"}})
    assert is_wake_message({"event": "broadcast", "payload": {"type": "broadcast", "payload": {"event": "cmd"}}})
    assert not is_wake_message({"event": "broadcast", "payload": {"type": "broadcast", "event": "other"}})
    assert not is_wake_message({"event": "phx_reply", "payload": {"status": "ok", "event": "cmd"}})
    assert not is_wake_message({"event": "broadcast", "payload": "cmd"})
    assert not is_wake_message({"event": "broadcast"})
    assert not is_wake_message({})
    assert not is_wake_message(None)  # type: ignore[arg-type]


def test_parse_message():
    assert parse_message('{"event":"heartbeat"}') == {"event": "heartbeat"}
    assert parse_message(b'{"a":1}') == {"a": 1}
    assert parse_message("[1,2]") is None
    assert parse_message("not json") is None


class FakeRealtime:
    """Fake Phoenix server: potvrdí join, odpoví na heartbeat, umí poslat broadcast."""

    def __init__(self) -> None:
        self.received: list[dict] = []
        self.clients: list = []
        self.joined = asyncio.Event()
        self._server = None
        self.port = 0

    async def _handler(self, ws) -> None:
        self.clients.append(ws)
        try:
            async for raw in ws:
                msg = json.loads(raw)
                self.received.append(msg)
                if msg["event"] == "phx_join":
                    await ws.send(json.dumps({"topic": msg["topic"], "event": "phx_reply",
                                              "payload": {"status": "ok", "response": {}}, "ref": msg["ref"]}))
                    self.joined.set()
                elif msg["event"] == "heartbeat":
                    await ws.send(json.dumps({"topic": "phoenix", "event": "phx_reply",
                                              "payload": {"status": "ok", "response": {}}, "ref": msg["ref"]}))
        finally:
            self.clients.remove(ws)

    async def start(self) -> None:
        self._server = await serve(self._handler, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def broadcast(self, topic: str, event: str) -> None:
        for ws in list(self.clients):
            await ws.send(json.dumps({"topic": topic, "event": "broadcast",
                                      "payload": {"type": "broadcast", "event": event, "payload": {}}, "ref": None}))


async def test_listener_join_wake_and_stop(monkeypatch):
    monkeypatch.setattr(realtime, "HEARTBEAT_S", 0.2)
    srv = FakeRealtime()
    await srv.start()
    wakes = 0

    async def on_wake() -> None:
        nonlocal wakes
        wakes += 1

    listener = RealtimeListener(f"http://127.0.0.1:{srv.port}", "anon", "kiosk:dev-1", on_wake)
    task = asyncio.create_task(listener.run())
    try:
        await asyncio.wait_for(srv.joined.wait(), 5)
        join = srv.received[0]
        assert join["topic"] == "realtime:kiosk:dev-1" and join["event"] == "phx_join"
        assert join["payload"]["config"]["broadcast"] == {"self": False}
        assert join["payload"]["config"]["postgres_changes"] == []
        for _ in range(50):
            if listener.connected:
                break
            await asyncio.sleep(0.02)
        assert listener.connected

        await srv.broadcast("realtime:kiosk:dev-1", "other")
        await srv.broadcast("realtime:kiosk:dev-1", "cmd")
        for _ in range(50):
            if wakes:
                break
            await asyncio.sleep(0.02)
        assert wakes == 1 and listener.wakes == 1

        await asyncio.sleep(0.5)          # heartbeat (zkrácený na 0.2 s)
        assert any(m["event"] == "heartbeat" and m["topic"] == "phoenix" for m in srv.received)

        listener.stop()
        await asyncio.wait_for(task, 5)
        assert listener.connected is False
    finally:
        if not task.done():
            task.cancel()
        await srv.stop()


async def test_listener_reconnects_after_server_drop(monkeypatch):
    monkeypatch.setattr(realtime, "BACKOFF_MIN_S", 0.1)
    monkeypatch.setattr(realtime, "BACKOFF_MAX_S", 0.2)
    srv = FakeRealtime()
    await srv.start()

    async def on_wake() -> None:
        return None

    listener = RealtimeListener(f"http://127.0.0.1:{srv.port}", "anon", "kiosk:dev-2", on_wake)
    task = asyncio.create_task(listener.run())
    try:
        await asyncio.wait_for(srv.joined.wait(), 5)
        srv.joined.clear()
        for ws in list(srv.clients):      # server shodí spojení
            await ws.close()
        await asyncio.wait_for(srv.joined.wait(), 5)    # listener se znovu připojil a joinul
        joins = [m for m in srv.received if m["event"] == "phx_join"]
        assert len(joins) == 2
    finally:
        listener.stop()
        try:
            await asyncio.wait_for(task, 5)
        except asyncio.TimeoutError:
            task.cancel()
        await srv.stop()
