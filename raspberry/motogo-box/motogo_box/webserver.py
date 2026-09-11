"""Lokální HTTP/WebSocket server pro dotykové UI (kontrakt §16).

Servíruje statické UI (``ui/``), JSON API nad ``BoxController`` a WebSocket
``/ws``, po kterém UI dostává snapshot stavu: hned po připojení, dále každou
sekundu a navíc okamžitě, jakmile se snapshot změní (porovnání hashe bez
proměnlivých klíčů ``ts``/``uptime_s``). Servisní endpointy vyžadují platný
``service_token`` (vydává ``BoxController.submit_code`` po servisním hesle);
``/api/health``, ``/api/events`` a ``/api/diagnostics`` (report) jsou jen pro localhost.
Chyby se vrací jako ``{"ok": false, "error": "…"}`` — nikdy traceback.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import time
from typing import Any, Awaitable, Callable

from aiohttp import WSMsgType, web

from . import webserver_service as svc
from .models import Event, EventKind

log = logging.getLogger("motogo.web")

UI_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui")
LOCAL_HOSTS = frozenset({"127.0.0.1", "::1", "localhost", "::ffff:127.0.0.1"})
WS_PUSH_INTERVAL_S = 1.0       # pravidelný push i beze změny
WS_CHECK_INTERVAL_S = 0.2      # jak často se kontroluje změna snapshotu
WS_HEARTBEAT_S = 15.0          # aiohttp ping/pong
EVENTS_LIMIT_DEFAULT = 100
EVENTS_LIMIT_MAX = 1000
BODY_MAX_BYTES = 256 * 1024
HASH_IGNORED_KEYS = ("ts", "uptime_s")


# ─── pomocné funkce ──────────────────────────────────────────────────────────
def _dumps(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, default=str)


def _json(data: Any, status: int = 200) -> web.Response:
    return web.json_response(data, status=status, dumps=_dumps)


def _err(error: str, status: int = 400) -> web.Response:
    return _json({"ok": False, "error": error}, status)


def is_local_request(request: web.Request) -> bool:
    """True pro požadavek z localhostu (health monitor, ladění)."""
    return (request.remote or "") in LOCAL_HOSTS


def _to_int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


async def _read_body(request: web.Request) -> dict:
    """JSON tělo jako dict; neplatný/prázdný JSON → {} (chyby řeší handler)."""
    try:
        raw = await request.read()
        if not raw:
            return {}
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


@web.middleware
async def _api_middleware(request: web.Request, handler: Callable) -> web.StreamResponse:
    """Cache-Control: no-store pro API, chyby vždy jako JSON bez tracebacku."""
    is_api = request.path.startswith("/api/") or request.path == "/ws"
    try:
        resp = await handler(request)
    except web.HTTPException as exc:
        if not is_api:
            raise
        error = "not_found" if exc.status == 404 else ("method_not_allowed" if exc.status == 405 else "http_error")
        resp = _err(error, exc.status)
    except asyncio.CancelledError:
        raise
    except Exception:  # noqa: BLE001 — server nesmí nikdy vrátit traceback
        log.exception("Neošetřená chyba v %s %s", request.method, request.path)
        resp = _err("internal", 500)
    if is_api:
        resp.headers["Cache-Control"] = "no-store"
    elif request.path == "/" or request.path.startswith("/static/"):
        resp.headers["Cache-Control"] = "no-cache"      # po update_software musí Chromium načíst nové JS/CSS
    return resp


_HEALTH_ACTION_KINDS = {"reconnect": EventKind.LTE_RESET, "usb_reset": EventKind.LTE_RESET,
                        "reboot": EventKind.REBOOT}

# ─── server ──────────────────────────────────────────────────────────────────
class WebServer:
    """aiohttp server pro UI na ``local.web.host:port`` (výchozí 127.0.0.1:8080)."""

    def __init__(self, ctrl: Any, api: Any, storage: Any, local: Any) -> None:
        self.ctrl = ctrl
        self.api = api
        self.storage = storage
        self.local = local
        self.host: str = str(getattr(getattr(local, "web", None), "host", "127.0.0.1"))
        self.port: int = int(getattr(getattr(local, "web", None), "port", 8080))
        self._clients: set[web.WebSocketResponse] = set()
        self._runner: web.AppRunner | None = None
        self._push_task: asyncio.Task | None = None
        self._last_hash: str | None = None
        self._last_push: float = 0.0
        self._exit: Callable[[int], Any] = os._exit   # v testech nahraditelné
        self.app = self._build_app()

    # ── životní cyklus ────────────────────────────────────────────────────
    def _build_app(self) -> web.Application:
        app = web.Application(middlewares=[_api_middleware], client_max_size=BODY_MAX_BYTES)
        r = app.router
        r.add_get("/", self._index)
        r.add_get("/ws", self._ws)
        r.add_get("/api/state", self._state)
        r.add_get("/api/events", self._events)
        r.add_post("/api/pin", self._pin)
        r.add_post("/api/health", self._health)
        r.add_get("/api/diagnostics", self._delegate(svc.diagnostics_get))
        r.add_post("/api/diagnostics/run", self._delegate(svc.diagnostics_run))
        for name, handler in (("open", svc.service_open), ("music", svc.service_music),
                              ("light", svc.service_light), ("all_off", svc.service_all_off),
                              ("pair", svc.service_pair), ("restart", svc.service_restart)):
            r.add_post(f"/api/service/{name}", self._delegate(handler))
        if os.path.isdir(UI_DIR):
            r.add_static("/static/", UI_DIR, show_index=False, follow_symlinks=False)
        else:
            log.error("Adresář UI %s neexistuje — statika nebude servírována", UI_DIR)
        app.on_startup.append(self._on_startup)
        app.on_cleanup.append(self._on_cleanup)
        return app

    def _delegate(self, handler: Callable[[Any, web.Request], Awaitable[web.Response]]) -> Callable:
        async def wrapped(request: web.Request) -> web.Response:
            return await handler(self, request)
        return wrapped

    # Pomocné funkce sdílené se ``webserver_service`` (JSON odpovědi, čtení těla).
    json = staticmethod(_json)
    error = staticmethod(_err)
    read_body = staticmethod(_read_body)

    async def _on_startup(self, _app: web.Application) -> None:
        if self._push_task is None or self._push_task.done():
            self._push_task = asyncio.create_task(self._push_loop(), name="web-push")

    async def _on_cleanup(self, _app: web.Application) -> None:
        if self._push_task is not None:
            self._push_task.cancel()
            try:
                await self._push_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
            self._push_task = None
        for ws in list(self._clients):
            try:
                await ws.close(code=1001, message=b"shutdown")
            except Exception:  # noqa: BLE001
                pass
        self._clients.clear()

    async def start(self) -> None:
        """Spustí HTTP server (idempotentní)."""
        if self._runner is not None:
            return
        self._runner = web.AppRunner(self.app, access_log=None)
        await self._runner.setup()
        site = web.TCPSite(self._runner, self.host, self.port, reuse_address=True)
        await site.start()
        log.info("Web UI naslouchá na http://%s:%s", self.host, self.port)

    async def stop(self) -> None:
        """Zavře klienty a ukončí server."""
        if self._runner is None:
            return
        try:
            await self._runner.cleanup()
        except Exception:  # noqa: BLE001
            log.exception("Ukončení web serveru selhalo")
        self._runner = None

    # ── snapshot stavu ────────────────────────────────────────────────────
    def state(self) -> dict:
        """Snapshot controlleru doplněný o údaje, které UI potřebuje (párování, timings, security)."""
        try:
            snap = dict(self.ctrl.snapshot() or {})
        except Exception:  # noqa: BLE001
            log.exception("ctrl.snapshot() selhal")
            snap = {"ready": False, "last_error": "snapshot_failed", "zones": []}
        device_id = str(getattr(self.api, "device_id", "") or "")
        paired = getattr(self.api, "paired", None)
        if paired is None:
            paired = bool(device_id and getattr(self.api, "device_token", ""))
        snap.setdefault("paired", bool(paired))
        snap.setdefault("device_id", device_id)
        hw = getattr(self.ctrl, "hardware", None)
        timings = getattr(hw, "timings", None)
        if "timings" not in snap and timings is not None:
            snap["timings"] = {k: getattr(timings, k) for k in ("pin_entry_timeout_s", "door_open_timeout_s",
                                                                 "maximum_session_s") if hasattr(timings, k)}
        security = getattr(hw, "security", None)
        if "security" not in snap and security is not None:
            snap["security"] = {k: getattr(security, k) for k in ("mask_pin_on_screen", "pin_length")
                                if hasattr(security, k)}
        snap.setdefault("last_error", getattr(self.ctrl, "last_error", None))
        return snap

    def _state_message(self) -> tuple[str, str]:
        """(JSON zpráva pro WS, hash bez proměnlivých klíčů)."""
        snap = self.state()
        stable = {k: v for k, v in snap.items() if k not in HASH_IGNORED_KEYS}
        digest = hashlib.sha1(_dumps(stable).encode("utf-8")).hexdigest()
        return _dumps({"type": "state", "state": snap}), digest

    # ── WebSocket ─────────────────────────────────────────────────────────
    async def _ws(self, request: web.Request) -> web.StreamResponse:
        ws = web.WebSocketResponse(heartbeat=WS_HEARTBEAT_S, autoping=True)
        await ws.prepare(request)
        self._clients.add(ws)
        log.debug("WS klient připojen (%s), celkem %d", request.remote, len(self._clients))
        try:
            payload, _ = self._state_message()
            await ws.send_str(payload)
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    await self._ws_message(ws, msg.data)
                elif msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE, WSMsgType.CLOSING):
                    break
        except (ConnectionResetError, asyncio.CancelledError):
            pass
        except Exception:  # noqa: BLE001
            log.exception("WS spojení skončilo chybou")
        finally:
            self._clients.discard(ws)
        return ws

    async def _ws_message(self, ws: web.WebSocketResponse, data: str) -> None:
        try:
            msg = json.loads(data)
        except ValueError:
            return
        kind = msg.get("type") if isinstance(msg, dict) else None
        if kind == "ping":
            await ws.send_str(_dumps({"type": "pong", "ts": time.time()}))
        elif kind == "get_state":
            payload, _ = self._state_message()
            await ws.send_str(payload)

    async def _push_loop(self) -> None:
        """Rozesílá stav: při změně okamžitě, jinak každou sekundu."""
        while True:
            await asyncio.sleep(WS_CHECK_INTERVAL_S)
            if not self._clients:
                continue
            try:
                payload, digest = self._state_message()
                now = time.monotonic()
                if digest != self._last_hash or now - self._last_push >= WS_PUSH_INTERVAL_S:
                    self._last_hash, self._last_push = digest, now
                    await self._broadcast(payload)
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001
                log.exception("Push stavu selhal")

    async def _broadcast(self, payload: str) -> None:
        for ws in list(self._clients):
            if ws.closed:
                self._clients.discard(ws)
                continue
            try:
                await ws.send_str(payload)
            except Exception:  # noqa: BLE001
                self._clients.discard(ws)

    # ── statika ───────────────────────────────────────────────────────────
    async def _index(self, request: web.Request) -> web.StreamResponse:
        path = os.path.join(UI_DIR, "index.html")
        if not os.path.isfile(path):
            return web.Response(status=503, text="UI není nainstalované (chybí ui/index.html)")
        return web.FileResponse(path)

    # ── API ───────────────────────────────────────────────────────────────
    async def _state(self, request: web.Request) -> web.Response:
        return _json(self.state())

    async def _events(self, request: web.Request) -> web.Response:
        if not is_local_request(request):
            return _err("forbidden", 403)
        limit = _to_int(request.query.get("limit")) or EVENTS_LIMIT_DEFAULT
        limit = max(1, min(EVENTS_LIMIT_MAX, limit))
        return _json({"ok": True, "events": self.storage.events_recent(limit)})

    async def _health(self, request: web.Request) -> web.Response:
        if not is_local_request(request):
            return _err("forbidden", 403)
        body = await _read_body(request)
        if not body:
            return _err("bad_request")
        self.ctrl.health = body
        # CONTRACT §15: obnova LTE (reconnect/usb_reset → LTE_RESET, reboot → REBOOT) musí zůstat
        # v kiosk_logs, ne jen ve 30s snapshotu health.actions (reboot health posílá PŘED restartem).
        actions = body.get("actions")
        for action in actions if isinstance(actions, list) else []:
            kind = _HEALTH_ACTION_KINDS.get(action)
            if kind is not None:
                await self.ctrl.emit(Event(kind=kind, level="warn", message=f"LTE obnova: {action}",
                                           detail={"source": "health", "action": action,
                                                   "lte": body.get("lte")}))
        return _json({"ok": True})

    async def _pin(self, request: web.Request) -> web.Response:
        body = await _read_body(request)
        code = body.get("code")
        if not isinstance(code, str) or not code.strip():
            return _err("empty_code")
        result = await self.ctrl.submit_code(code, "ui")
        if not isinstance(result, dict):
            return _err("bad_result", 500)
        return _json(result)
