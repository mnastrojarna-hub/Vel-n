"""Supabase PostgREST RPC klient MotoGo Boxu (kontrakt §9).

Zařízení se neautentizuje JWT, ale dvojicí ``device_id`` + ``device_token``
(parametry ``p_device_id``/``p_device_token`` každé RPC ``kiosk_*``); HTTP volání
jde pod anon klíčem. Zápisové RPC (audit otevření, logy, výsledky příkazů) se
při výpadku sítě ukládají do outboxu ve ``Storage`` a odesílají později
(`flush_outbox`). Stavové reporty (status/power) se nefrontují — zajímá jen
poslední stav.
"""
from __future__ import annotations

import logging
from typing import Any

import httpx

from .storage import Storage

log = logging.getLogger("motogo.api")

# kind v outboxu → název RPC
OUTBOX_RPC: dict[str, str] = {
    "log_open": "kiosk_log_open",
    "log_event": "kiosk_log_event",
    "complete_command": "kiosk_complete_command",
}
_MISSING_HINTS = ("not find", "does not exist", "pgrst202")


class ApiError(Exception):
    """Chyba RPC volání. ``status`` 0 = síťová chyba (timeout, DNS, odmítnuté spojení)."""

    def __init__(self, status: int, text: str) -> None:
        super().__init__(f"HTTP {status}: {text[:200]}" if status else f"network: {text[:200]}")
        self.status = int(status)
        self.text = text or ""

    @property
    def is_network(self) -> bool:
        return self.status == 0

    @property
    def is_transient(self) -> bool:
        """Síť nebo 5xx — má smysl to zkusit později (outbox)."""
        return self.status == 0 or self.status >= 500

    def is_missing_function(self, name: str) -> bool:
        """PostgREST nezná RPC (migrace ještě není nasazená): 404 nebo PGRST202."""
        low = self.text.lower()
        return (self.status == 404 and (not low or name in low or "pgrst202" in low)) or (
            name in low and any(h in low for h in _MISSING_HINTS)
        )


class SupabaseApi:
    """Asynchronní klient RPC ``kiosk_*``; ``online`` = výsledek posledního volání."""

    def __init__(self, url: str, anon_key: str, device_id: str, device_token: str,
                 storage: Storage, version: str) -> None:
        self.url = (url or "").rstrip("/")
        self.anon_key = anon_key or ""
        self.device_id = device_id or ""
        self.device_token = device_token or ""
        self.storage = storage
        self.version = version
        self.online = False
        self.status_rpc_missing = False
        self.platform = "rpi"
        self._client = httpx.AsyncClient(
            base_url=self.url, timeout=httpx.Timeout(10.0, connect=5.0),
            headers={
                "apikey": self.anon_key,
                "Authorization": f"Bearer {self.anon_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": f"motogo-box/{version}",
            },
        )

    # ─── základ ─────────────────────────────────────────────────────────────
    @property
    def paired(self) -> bool:
        return bool(self.device_id and self.device_token)

    def set_device(self, device_id: str, device_token: str) -> None:
        self.device_id = (device_id or "").strip()
        self.device_token = (device_token or "").strip()

    def _auth(self, device_id: str | None = None, token: str | None = None) -> dict:
        return {"p_device_id": device_id if device_id is not None else self.device_id,
                "p_device_token": token if token is not None else self.device_token}

    async def rpc(self, name: str, params: dict, timeout_s: float = 10) -> Any:
        """POST ``/rest/v1/rpc/<name>``; vrací rozparsovaný JSON (dict/list/None).

        HTTP mimo 2xx → ``ApiError(status, text)``; síťová chyba → ``ApiError(0, …)``.
        """
        try:
            resp = await self._client.post(f"/rest/v1/rpc/{name}", json=params, timeout=timeout_s)
        except httpx.HTTPError as exc:
            self.online = False
            raise ApiError(0, f"{type(exc).__name__}: {exc}") from exc
        self.online = True
        if not 200 <= resp.status_code < 300:
            raise ApiError(resp.status_code, resp.text)
        if not resp.content or not resp.content.strip():
            return None
        try:
            return resp.json()
        except ValueError:
            log.warning("RPC %s: neplatný JSON v odpovědi (%d B)", name, len(resp.content))
            return None

    async def _rpc_ok(self, name: str, params: dict, timeout_s: float = 10) -> dict | None:
        """RPC, které vrací ``{ok: bool, …}`` — dict jen při ``ok: true``."""
        res = await self.rpc(name, params, timeout_s)
        if isinstance(res, dict) and res.get("ok") is True:
            return res
        err = res.get("error") if isinstance(res, dict) else "bad_response"
        log.warning("RPC %s odmítnuto: %s", name, err)
        return None

    # ─── čtení ──────────────────────────────────────────────────────────────
    async def heartbeat(self) -> dict | None:
        """``kiosk_heartbeat`` → konfigurace pobočky; None při chybě / unauthorized."""
        try:
            return await self._rpc_ok("kiosk_heartbeat", {
                **self._auth(), "p_app_version": self.version, "p_platform": self.platform,
            })
        except ApiError as exc:
            log.warning("Heartbeat selhal: %s", exc)
            return None

    async def resolve_code(self, code: str) -> dict | None:
        """``kiosk_resolve_code`` → dict i při ``ok:false``; None JEN při síti/5xx."""
        try:
            res = await self.rpc("kiosk_resolve_code", {**self._auth(), "p_code": code})
        except ApiError as exc:
            if exc.is_transient:
                log.warning("resolve_code: server nedostupný (%s) → offline cache", exc)
                return None
            log.error("resolve_code: HTTP %d %s", exc.status, exc.text[:200])
            return {"ok": False, "error": f"api_{exc.status}", "detail": exc.text[:200]}
        if isinstance(res, dict):
            return res
        log.error("resolve_code: neočekávaná odpověď %r", res)
        return {"ok": False, "error": "bad_response"}

    async def sync_config(self) -> dict | None:
        """``kiosk_sync_config``; pokud RPC ještě neexistuje → ``kiosk_sync_codes`` + ``legacy=True``."""
        try:
            return await self._rpc_ok("kiosk_sync_config", self._auth(), timeout_s=20)
        except ApiError as exc:
            if not exc.is_missing_function("kiosk_sync_config"):
                log.warning("sync_config selhal: %s", exc)
                return None
            log.info("kiosk_sync_config není nasazená → fallback kiosk_sync_codes")
        try:
            payload = await self._rpc_ok("kiosk_sync_codes", self._auth(), timeout_s=20)
        except ApiError as exc:
            log.warning("sync_codes selhal: %s", exc)
            return None
        if payload is not None:
            payload["legacy"] = True
        return payload

    async def fetch_commands(self) -> list[dict]:
        """``kiosk_fetch_commands`` → seznam ``{id, command, params}``; chyba → []."""
        try:
            res = await self._rpc_ok("kiosk_fetch_commands", self._auth())
        except ApiError as exc:
            log.warning("fetch_commands selhal: %s", exc)
            return []
        rows = res.get("commands") if res else None
        return [r for r in rows if isinstance(r, dict)] if isinstance(rows, list) else []

    # ─── zápisy s outboxem ──────────────────────────────────────────────────
    async def _send_or_queue(self, kind: str, params: dict) -> None:
        """Pošle RPC ``OUTBOX_RPC[kind]``; při chybě uloží do outboxu (bez auth údajů)."""
        try:
            await self.rpc(OUTBOX_RPC[kind], {**self._auth(), **params})
        except ApiError as exc:
            oid = self.storage.outbox_add(kind, params)
            log.warning("%s se nepodařilo odeslat (%s) → outbox #%d", kind, exc, oid)

    async def log_open(self, door_id: str | None, kind: str, booking_id: str | None,
                       success: bool, detail: dict | None) -> None:
        await self._send_or_queue("log_open", {
            "p_door_id": door_id, "p_kind": kind, "p_booking_id": booking_id,
            "p_success": bool(success), "p_detail": detail or {},
        })

    async def log_event(self, level: str, source: str, message: str, detail: dict | None = None) -> None:
        await self._send_or_queue("log_event", {
            "p_level": level or "info", "p_source": source, "p_message": str(message)[:4000],
            "p_detail": detail or {}, "p_app_version": self.version,
        })

    async def complete_command(self, command_id: str, success: bool, result: dict) -> None:
        await self._send_or_queue("complete_command", {
            "p_command_id": command_id, "p_success": bool(success), "p_result": result or {},
        })

    async def flush_outbox(self) -> int:
        """Odešle čekající položky; vrací počet odeslaných. Při výpadku sítě končí hned."""
        if not self.paired:
            return 0
        sent = 0
        for oid, kind, payload in self.storage.outbox_pending():
            name = OUTBOX_RPC.get(kind)
            if name is None:
                log.warning("Outbox #%d: neznámý druh %r → zahazuji", oid, kind)
                self.storage.outbox_done(oid)
                continue
            try:
                await self.rpc(name, {**self._auth(), **payload})
            except ApiError as exc:
                if exc.is_transient:
                    # Výpadek sítě/serveru se do limitu pokusů NEpočítá — auditní události
                    # (ACCESS_GRANTED, DOOR_OPENED…) musí přežít i dlouhý výpadek LTE.
                    log.info("flush_outbox: server nedostupný (%s), zbytek později", exc)
                    break
                self.storage.outbox_fail(oid)     # trvalé odmítnutí (4xx) → po limitu zahodit
                log.warning("Outbox #%d (%s) odmítnut: %s", oid, kind, exc)
                continue
            self.storage.outbox_done(oid)
            sent += 1
        if sent:
            log.info("flush_outbox: odesláno %d položek", sent)
        return sent

    # ─── stavové reporty (bez fronty) ───────────────────────────────────────
    async def report_status(self, status: dict) -> None:
        """``kiosk_report_status`` (nová RPC); chybějící RPC tiše ignoruje."""
        try:
            await self.rpc("kiosk_report_status", {**self._auth(), "p_status": status})
            self.status_rpc_missing = False
        except ApiError as exc:
            if exc.is_missing_function("kiosk_report_status"):
                if not self.status_rpc_missing:
                    log.info("kiosk_report_status není nasazená — status se nehlásí")
                self.status_rpc_missing = True
            else:
                log.debug("report_status selhal: %s", exc)

    async def report_power(self, payload: dict) -> None:
        try:
            await self.rpc("kiosk_report_power", {**self._auth(), "p_payload": payload})
        except ApiError as exc:
            log.debug("report_power selhal: %s", exc)

    # ─── párování ───────────────────────────────────────────────────────────
    async def validate_pairing(self, device_id: str, token: str) -> str | None:
        """Ověří dvojici ID+token přes ``kiosk_heartbeat``; None = OK, jinak text chyby."""
        device_id, token = (device_id or "").strip(), (token or "").strip()
        if not device_id or not token:
            return "missing_inputs"
        try:
            res = await self.rpc("kiosk_heartbeat", {
                **self._auth(device_id, token), "p_app_version": self.version, "p_platform": self.platform,
            })
        except ApiError as exc:
            return "network" if exc.is_network else f"http_{exc.status}"
        if isinstance(res, dict) and res.get("ok") is True:
            return None
        return str(res.get("error") or "unauthorized") if isinstance(res, dict) else "bad_response"

    async def close(self) -> None:
        await self._client.aclose()
