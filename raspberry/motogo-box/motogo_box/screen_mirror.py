"""Zrcadlení obrazovky kiosku do Velína (+ vzdálený tap) přes Chrome DevTools Protocol — CONTRACT §29.

Chromium na displeji běží s `--remote-debugging-port` (JEN 127.0.0.1, `scripts/kiosk-ui.sh`). Relaci zakládá admin
ve Velíně (`kiosk_screen_sessions`) a pošle `screen_mirror {session_id, on: true, control}`; tady se připojíme na
WebSocket stránky, spustíme `Page.startScreencast` (JPEG, max_width × 9/16, quality) a každý ZMĚNĚNÝ snímek
(Chromium posílá jen při překreslení; navíc SHA-1 dedup + limit fps) pošleme RPC `kiosk_push_screen_frame`. Odpověď
RPC říká, zda relace trvá (`active`) a zda smí admin klepat (`control`). Relace končí: Velín ji ukončil (active false),
TTL, 60 s bez úspěšného odeslání, Chromium nedostupné. Nic z toho neběží, dokud Velín nepožádá — bez relace je
datový provoz nulový. Data: ~50 kB/snímek, typická relace 5–8 MB / 10 min (jen při změnách obrazu).

Vzdálený vstup (`screen_input`): `tap {x, y}` v 0..1 → `Page.getLayoutMetrics` → `Input.dispatchMouseEvent`
(moved/pressed/released = klik, stejná cesta jako dotyk); `dialog {text|null}` → `Page.handleJavaScriptDialog`
(terminál na displeji používá nativní `window.prompt`, který screencast nevidí — jednotka ho ohlásí v `meta.dialog`).
Pojistky: jen s `control`, jen v aktivní relaci, tap starší 5 s se zahodí, max 5 vstupů/s, souřadnice oříznuté.
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
import time
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

import aiohttp

if TYPE_CHECKING:
    from .config import ScreenCfg

log = logging.getLogger("motogo.screen")

RECONNECT_TRIES = 3          # UI se po změně verze samo znovu načte → WS spadne → zkusit znovu
RECONNECT_DELAY_S = 2.0
STALE_INPUT_S = 5.0          # tap starší než 5 s (fronta příkazů) se neprovede
MAX_INPUTS_PER_S = 5
CDP_TIMEOUT_S = 8.0


class ScreenMirror:
    def __init__(self, api: Any, cfg: "ScreenCfg", *, clock=time.monotonic) -> None:
        self.api, self.cfg, self.clock = api, cfg, clock
        self.session_id: str | None = None
        self.control = False
        self.since: float | None = None
        self.since_iso: str | None = None
        self.ttl_s = float(cfg.max_session_s)
        self.max_fps = float(cfg.max_fps)
        self.quality = int(cfg.quality)
        self.max_width = int(cfg.max_width)
        self.frames = 0
        self.bytes = 0
        self.last_error: str | None = None
        self.stop_reason: str | None = None
        self._task: asyncio.Task | None = None
        self._ws: aiohttp.ClientWebSocketResponse | None = None
        self._http: aiohttp.ClientSession | None = None
        self._pending: dict[int, asyncio.Future] = {}
        self._msg_id = 0
        self._latest: dict | None = None        # poslední snímek čekající na odeslání (fps limit)
        self._latest_event = asyncio.Event()
        self._last_hash: str | None = None
        self._last_push = 0.0
        self._last_ok_push = 0.0
        self._seq = 0
        self._meta: dict = {}
        self._input_times: list[float] = []
        self._stopping = False

    # ─── stav ────────────────────────────────────────────────────────────────
    @property
    def active(self) -> bool:
        return self._task is not None and not self._task.done()

    def status(self) -> dict:
        return {"active": self.active, "control": bool(self.control and self.active), "since": self.since_iso,
                "session_id": self.session_id if self.active else None, "frames": self.frames, "bytes": self.bytes,
                "last_error": self.last_error, "stop_reason": self.stop_reason}

    # ─── relace ──────────────────────────────────────────────────────────────
    async def start(self, session_id: str, *, control: bool = False, max_fps: float | None = None,
                    quality: int | None = None, max_width: int | None = None, ttl_s: float | None = None) -> dict:
        """Spustí (nebo jen přenastaví běžící) relaci. Vrací `status()` nebo `{error}`."""
        if self.active and self.session_id == session_id:
            self.control = bool(control)
            return self.status()
        if self.active:
            await self.stop("replaced")
        self.session_id, self.control = str(session_id), bool(control)
        self.max_fps = max(0.2, min(4.0, float(max_fps or self.cfg.max_fps)))
        self.quality = max(20, min(80, int(quality or self.cfg.quality)))
        self.max_width = max(320, min(1920, int(max_width or self.cfg.max_width)))
        self.ttl_s = max(30.0, min(3600.0, float(ttl_s or self.cfg.max_session_s)))
        self.frames = self.bytes = 0
        self._seq, self._last_hash, self._latest, self._meta = 0, None, None, {}
        self._last_push = self._last_ok_push = self.clock()
        self.last_error = self.stop_reason = None
        self._stopping = False
        self.since = self.clock()
        self.since_iso = datetime.now(timezone.utc).isoformat()
        try:
            await self._page_ws_url()                # Chromium bez CDP → Velín dostane důvod hned, nic se nespouští
        except Exception as exc:  # noqa: BLE001
            self.last_error = self.stop_reason = "cdp_unavailable"
            await self._close_ws()
            return {"error": "cdp_unavailable", "detail": f"{type(exc).__name__}: {exc}"[:200], **self.status()}
        self._task = asyncio.create_task(self._run(), name="motogo.screen")
        return self.status()

    async def stop(self, reason: str = "stopped") -> None:
        self._stopping = True
        self.stop_reason = reason
        task, self._task = self._task, None
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        await self._close_ws()
        self.control = False
        if reason != "replaced":
            log.info("Zrcadlení obrazovky ukončeno (%s): %d snímků, %d B", reason, self.frames, self.bytes)

    # ─── CDP ─────────────────────────────────────────────────────────────────
    def _base(self) -> str:
        return f"http://127.0.0.1:{int(self.cfg.cdp_port)}"

    async def _http_session(self) -> aiohttp.ClientSession:
        if self._http is None or self._http.closed:
            self._http = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=CDP_TIMEOUT_S))
        return self._http

    async def _page_ws_url(self) -> str:
        http = await self._http_session()
        async with http.get(self._base() + "/json/list") as resp:
            targets = await resp.json(content_type=None)
        for t in targets or []:
            if isinstance(t, dict) and t.get("type") == "page" and t.get("webSocketDebuggerUrl"):
                return str(t["webSocketDebuggerUrl"])
        raise RuntimeError("cdp_no_page")

    async def _connect(self) -> None:
        url = await self._page_ws_url()
        http = await self._http_session()
        self._ws = await http.ws_connect(url, max_msg_size=8 * 1024 * 1024, heartbeat=20)

    async def _close_ws(self) -> None:
        ws, self._ws = self._ws, None
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel()
        self._pending.clear()
        if ws is not None and not ws.closed:
            try:
                await ws.close()
            except Exception:  # noqa: BLE001
                pass
        http, self._http = self._http, None
        if http is not None and not http.closed:
            await http.close()

    async def send(self, method: str, params: dict | None = None) -> None:
        """Příkaz bez čekání na odpověď — pro volání ZE smyčky příjmu (ack snímku, stopScreencast při konci): čekat
        na výsledek tam nejde, odpovědi rozděluje právě ta smyčka."""
        ws = self._ws
        if ws is None or ws.closed:
            return
        self._msg_id += 1
        await ws.send_json({"id": self._msg_id, "method": method, "params": params or {}})

    async def call(self, method: str, params: dict | None = None, timeout: float = CDP_TIMEOUT_S) -> dict:
        ws = self._ws
        if ws is None or ws.closed:
            raise RuntimeError("cdp_disconnected")
        self._msg_id += 1
        mid = self._msg_id
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[mid] = fut
        await ws.send_json({"id": mid, "method": method, "params": params or {}})
        try:
            return await asyncio.wait_for(fut, timeout)
        finally:
            self._pending.pop(mid, None)

    async def _run(self) -> None:
        tries = 0
        try:
            while not self._stopping:
                try:
                    await self._connect()
                except Exception as exc:  # noqa: BLE001
                    self.last_error = f"cdp_unavailable: {type(exc).__name__}: {exc}"[:200]
                    tries += 1
                    if tries > RECONNECT_TRIES:
                        self.stop_reason = "cdp_unavailable"
                        return
                    await asyncio.sleep(RECONNECT_DELAY_S)
                    continue
                tries = 0
                recv = asyncio.create_task(self._receive(), name="motogo.screen.recv")
                pusher = asyncio.create_task(self._pusher(), name="motogo.screen.push")
                try:
                    await self.call("Page.enable")
                    await self.call("Page.startScreencast", {
                        "format": "jpeg", "quality": self.quality, "maxWidth": self.max_width,
                        "maxHeight": max(180, round(self.max_width * 9 / 16)), "everyNthFrame": 1})
                    await asyncio.wait({recv, pusher}, return_when=asyncio.FIRST_COMPLETED)
                finally:
                    for t in (recv, pusher):
                        t.cancel()
                        try:
                            await t
                        except (asyncio.CancelledError, Exception):  # noqa: BLE001
                            pass
                if self._stopping or self.stop_reason:
                    return
                self.last_error = "cdp_disconnected"          # UI reload / pád Chromia → zkusit znovu
                await self._close_ws()
                await asyncio.sleep(RECONNECT_DELAY_S)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            self.last_error = f"{type(exc).__name__}: {exc}"[:200]
            self.stop_reason = self.stop_reason or "error"
            log.warning("Zrcadlení obrazovky selhalo: %s", self.last_error)
        finally:
            self._task = None
            try:
                await asyncio.wait_for(self.send("Page.stopScreencast"), 2.0)
            except Exception:  # noqa: BLE001
                pass
            await self._close_ws()
            self.control = False

    async def _receive(self) -> None:
        ws = self._ws
        assert ws is not None
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = msg.json()
                except ValueError:
                    continue
                await self._on_message(data)
            elif msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                break

    async def _on_message(self, data: dict) -> None:
        mid = data.get("id")
        if mid is not None:
            fut = self._pending.get(int(mid))
            if fut is not None and not fut.done():
                if "error" in data:
                    fut.set_exception(RuntimeError(str(data["error"])[:200]))
                else:
                    fut.set_result(data.get("result") or {})
            return
        method, params = data.get("method"), data.get("params") or {}
        if method == "Page.screencastFrame":
            sid = params.get("sessionId")
            self._offer_frame(params)
            if sid is not None:
                try:
                    await self.send("Page.screencastFrameAck", {"sessionId": sid})
                except Exception:  # noqa: BLE001
                    pass
        elif method == "Page.javascriptDialogOpening":
            self._meta["dialog"] = {"type": params.get("type"), "message": str(params.get("message") or "")[:300],
                                    "default": str(params.get("defaultPrompt") or "")[:100]}
            self._latest_event.set()
        elif method == "Page.javascriptDialogClosed":
            self._meta.pop("dialog", None)
            self._meta["dialog_closed"] = True
            self._latest_event.set()

    def _offer_frame(self, params: dict) -> None:
        data = params.get("data")
        if not isinstance(data, str) or not data:
            return
        digest = hashlib.sha1(data.encode("ascii", "ignore")).hexdigest()
        if digest == self._last_hash:
            return                                 # stejný obraz — neposílat
        meta = params.get("metadata") or {}
        self._latest = {"data": data, "hash": digest, "width": meta.get("deviceWidth"), "height": meta.get("deviceHeight")}
        self._latest_event.set()

    # ─── odesílání do Supabase ──────────────────────────────────────────────
    async def _pusher(self) -> None:
        ping_s = float(self.cfg.ping_s)
        while True:
            wait = max(0.05, min(ping_s, 1.0 / self.max_fps - (self.clock() - self._last_push)))
            try:
                await asyncio.wait_for(self._latest_event.wait(), timeout=wait)
            except asyncio.TimeoutError:
                pass
            self._latest_event.clear()
            now = self.clock()
            if self.since is not None and now - self.since >= self.ttl_s:
                self.stop_reason, self._stopping = "ttl", True
                return
            if now - self._last_ok_push > float(self.cfg.stall_s):
                self.stop_reason, self._stopping = "stalled", True
                return
            due = now - self._last_push >= 1.0 / self.max_fps
            frame = self._latest if due else None
            meta_dirty = bool(self._meta)
            if frame is None and not meta_dirty and now - self._last_push < ping_s:
                continue
            if frame is not None:
                self._latest = None
            await self._push(frame, dict(self._meta) if meta_dirty else {})
            if meta_dirty:
                self._meta.pop("dialog_closed", None)
            if self._stopping:
                return

    async def _push(self, frame: dict | None, meta: dict) -> None:
        self._last_push = self.clock()
        seq = self._seq + 1 if frame is not None else self._seq
        try:
            res = await self.api.push_screen_frame(self.session_id, seq, frame["data"] if frame else None,
                                                   frame.get("width") if frame else None,
                                                   frame.get("height") if frame else None, meta)
        except Exception as exc:  # noqa: BLE001
            self.last_error = f"push: {type(exc).__name__}: {exc}"[:200]
            if frame is not None:
                self._latest = self._latest or frame          # neposlaný snímek zkusit znovu
            return
        if not isinstance(res, dict):
            return
        self._last_ok_push = self.clock()
        if res.get("active") is False:
            self.stop_reason, self._stopping = "ended_by_velin", True
            return
        if res.get("ok"):
            if frame is not None:
                self._seq, self._last_hash = seq, frame["hash"]
                self.frames += 1
                self.bytes += len(frame["data"])
            self.control = bool(res.get("control"))
            self.last_error = None
        elif res.get("error") == "rate_limited" and frame is not None:
            self._latest = self._latest or frame
        else:
            self.last_error = str(res.get("error") or "push_rejected")[:100]

    # ─── vzdálený vstup ───────────────────────────────────────────────────
    def _input_allowed(self, session_id: str | None, sent_at: str | None) -> str | None:
        if not self.active or self._ws is None or self._ws.closed:
            return "not_active"
        if session_id and session_id != self.session_id:
            return "session_mismatch"
        if not self.control:
            return "control_disabled"
        if sent_at:
            try:
                age = time.time() - datetime.fromisoformat(str(sent_at).replace("Z", "+00:00")).timestamp()
                if age > STALE_INPUT_S:
                    return "stale_input"
            except ValueError:
                pass
        now = self.clock()
        self._input_times = [t for t in self._input_times if now - t < 1.0]
        if len(self._input_times) >= MAX_INPUTS_PER_S:
            return "rate_limited"
        self._input_times.append(now)
        return None

    async def tap(self, x: float, y: float, *, session_id: str | None = None, sent_at: str | None = None) -> tuple[bool, dict]:
        why = self._input_allowed(session_id, sent_at)
        if why:
            return False, {"error": why}
        fx, fy = max(0.0, min(1.0, float(x))), max(0.0, min(1.0, float(y)))
        metrics = await self.call("Page.getLayoutMetrics")
        vp = metrics.get("cssVisualViewport") or metrics.get("visualViewport") or {}
        w, h = float(vp.get("clientWidth") or 1920), float(vp.get("clientHeight") or 1080)
        px, py = round(fx * w), round(fy * h)
        for kind in ("mouseMoved", "mousePressed", "mouseReleased"):
            p = {"type": kind, "x": px, "y": py, "button": "left" if kind != "mouseMoved" else "none",
                 "clickCount": 1 if kind != "mouseMoved" else 0}
            if kind != "mouseMoved":
                p["buttons"] = 1 if kind == "mousePressed" else 0
            await self.call("Input.dispatchMouseEvent", p)
        self._latest_event.set()
        return True, {"x": px, "y": py, "viewport": [w, h]}

    async def dialog(self, text: str | None, *, session_id: str | None = None, sent_at: str | None = None) -> tuple[bool, dict]:
        why = self._input_allowed(session_id, sent_at)
        if why:
            return False, {"error": why}
        params: dict = {"accept": text is not None}
        if text is not None:
            params["promptText"] = str(text)[:500]
        await self.call("Page.handleJavaScriptDialog", params)
        self._meta.pop("dialog", None)
        return True, {"accepted": text is not None}
