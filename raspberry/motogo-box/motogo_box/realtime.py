"""Supabase Realtime (Phoenix protokol) — probuzení při vzdáleném příkazu (kontrakt §10).

Box běží pod anon klíčem, takže nemůže číst ``kiosk_commands`` přes postgres_changes.
Velín po vložení příkazu pošle DB broadcast na neuhodnutelný topic ``kiosk:<device_id>``
(trigger ``kiosk_command_broadcast``); listener při zprávě ``event=="cmd"`` jen zavolá
``on_wake`` a controller si příkazy bezpečně stáhne token-ověřenou RPC.

Protokol (vsn=1.0.0): JSON zprávy ``{"topic","event","payload","ref"}``:
``phx_join`` → ``phx_reply`` (status ok) → připojeno; heartbeat na topic ``phoenix`` každých
25 s; broadcast: ``{"event":"broadcast","payload":{"type":"broadcast","event":"cmd","payload":{…}}}``.
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Awaitable, Callable
from urllib.parse import quote

from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

log = logging.getLogger("motogo.realtime")

HEARTBEAT_S = 25.0
BACKOFF_MIN_S = 5.0
BACKOFF_MAX_S = 60.0
JOIN_TIMEOUT_S = 15.0
STABLE_SESSION_S = 60.0     # spojení delší než toto resetuje backoff


def ws_url(url: str, anon_key: str) -> str:
    """``https://host`` → ``wss://host/realtime/v1/websocket?apikey=<anon>&vsn=1.0.0``."""
    base = (url or "").strip().rstrip("/")
    if base.startswith("https://"):
        base = "wss://" + base[len("https://"):]
    elif base.startswith("http://"):
        base = "ws://" + base[len("http://"):]
    elif not base.startswith(("ws://", "wss://")):
        base = "wss://" + base
    return f"{base}/realtime/v1/websocket?apikey={quote(anon_key or '', safe='')}&vsn=1.0.0"


def is_wake_message(msg: dict) -> bool:
    """True = broadcast s ``payload.event == "cmd"`` (Velín vložil příkaz)."""
    if not isinstance(msg, dict) or msg.get("event") != "broadcast":
        return False
    payload = msg.get("payload")
    if not isinstance(payload, dict):
        return False
    if payload.get("event") == "cmd":
        return True
    inner = payload.get("payload")
    return payload.get("type") == "broadcast" and isinstance(inner, dict) and inner.get("event") == "cmd"


def parse_message(raw: str | bytes) -> dict | None:
    """Text rámce → dict; nevalidní JSON / ne-objekt → None."""
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return None
    return data if isinstance(data, dict) else None


class RealtimeListener:
    """Udržuje WebSocket na Realtime a při broadcastu ``cmd`` volá ``on_wake``."""

    def __init__(self, url: str, anon_key: str, topic: str,
                 on_wake: Callable[[], Awaitable[None]]) -> None:
        self.url = ws_url(url, anon_key)
        self.topic = topic if topic.startswith("realtime:") else f"realtime:{topic}"
        self.on_wake = on_wake
        self.connected = False
        self.wakes = 0
        self._stop = asyncio.Event()
        self._ref = 0
        self._ws: Any = None
        self._close_task: asyncio.Task | None = None

    def _next_ref(self) -> str:
        self._ref += 1
        return str(self._ref)

    def stop(self) -> None:
        """Ukončí smyčku `run` (spojení se zavře při nejbližší příležitosti)."""
        self._stop.set()
        ws = self._ws
        if ws is not None:
            try:
                self._close_task = asyncio.get_running_loop().create_task(ws.close())
            except RuntimeError:
                pass

    async def run(self) -> None:
        """Nekonečná smyčka s reconnectem (backoff 5 → 60 s) až do `stop()`."""
        backoff = BACKOFF_MIN_S
        loop = asyncio.get_running_loop()
        while not self._stop.is_set():
            started = loop.time()
            try:
                await self._session()
            except (OSError, asyncio.TimeoutError, WebSocketException, ValueError) as exc:
                log.warning("Realtime spojení selhalo: %s", exc)
            except Exception:  # noqa: BLE001 — smyčka nesmí zemřít kvůli chybě knihovny
                log.exception("Realtime: neočekávaná chyba")
            finally:
                self.connected = False
                self._ws = None
            if self._stop.is_set():
                break
            if loop.time() - started > STABLE_SESSION_S:
                backoff = BACKOFF_MIN_S
            log.info("Realtime reconnect za %.0f s", backoff)
            try:
                await asyncio.wait_for(self._stop.wait(), timeout=backoff)
            except asyncio.TimeoutError:
                pass
            backoff = min(BACKOFF_MAX_S, backoff * 2)
        log.info("Realtime listener ukončen")

    async def _send(self, ws: Any, topic: str, event: str, payload: dict, ref: str | None) -> None:
        await ws.send(json.dumps({"topic": topic, "event": event, "payload": payload, "ref": ref}))

    async def _session(self) -> None:
        """Jedno spojení: join → čtení zpráv + heartbeat; končí výjimkou nebo `stop()`."""
        async with connect(self.url, open_timeout=JOIN_TIMEOUT_S, ping_interval=None,
                           max_size=1 << 20) as ws:
            self._ws = ws
            join_ref = self._next_ref()
            await self._send(ws, self.topic, "phx_join", {
                "config": {"broadcast": {"self": False}, "presence": {"key": ""}, "postgres_changes": []},
            }, join_ref)
            loop = asyncio.get_running_loop()
            next_hb = loop.time() + HEARTBEAT_S
            join_deadline = loop.time() + JOIN_TIMEOUT_S
            stop_task = asyncio.ensure_future(self._stop.wait())
            try:
                while not self._stop.is_set():
                    now = loop.time()
                    if now >= next_hb:
                        await self._send(ws, "phoenix", "heartbeat", {}, self._next_ref())
                        next_hb = now + HEARTBEAT_S
                    if not self.connected and now >= join_deadline:
                        raise asyncio.TimeoutError("join bez odpovědi")
                    recv_task = asyncio.ensure_future(ws.recv())
                    done, _ = await asyncio.wait({recv_task, stop_task}, timeout=max(0.05, next_hb - now),
                                                 return_when=asyncio.FIRST_COMPLETED)
                    if recv_task not in done:
                        recv_task.cancel()
                        continue
                    await self._handle(parse_message(recv_task.result()), join_ref)
            finally:
                stop_task.cancel()

    async def _handle(self, msg: dict | None, join_ref: str) -> None:
        """Zpracuje jednu zprávu: potvrzení joinu, chyby kanálu, broadcast ``cmd``."""
        if msg is None:
            return
        event = msg.get("event")
        if event == "phx_reply" and msg.get("ref") == join_ref:
            payload = msg.get("payload") or {}
            if payload.get("status") == "ok":
                self.connected = True
                log.info("Realtime připojeno (%s)", self.topic)
            else:
                raise ValueError(f"join odmítnut: {payload.get('response')}")
            return
        if event in ("phx_error", "phx_close") and msg.get("topic") == self.topic:
            raise ConnectionError(f"kanál {self.topic} uzavřen ({event})")
        if is_wake_message(msg):
            self.wakes += 1
            log.info("Realtime: příkaz z Velína → probouzím controller")
            try:
                await self.on_wake()
            except Exception:  # noqa: BLE001 — chyba controlleru nesmí shodit spojení
                log.exception("on_wake selhal")


__all__ = ["RealtimeListener", "is_wake_message", "parse_message", "ws_url"]
