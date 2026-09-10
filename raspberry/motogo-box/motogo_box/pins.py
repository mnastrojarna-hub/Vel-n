"""Práce s přístupovými kódy (kontrakt §8): normalizace, maskování, HMAC,
ochrana proti hrubé síle (PinGuard) a offline ověření proti lokální cache
(LocalResolver).

HMAC musí být bit po bitu shodný s SQL v RPC ``kiosk_sync_config``::

    encode(hmac(convert_to(p_device_id::text||':'||code,'UTF8'),
                convert_to(p_device_token::text,'UTF8'), 'sha256'), 'hex')

Postgres vypisuje UUID malými písmeny, proto se obě UUID před výpočtem převedou
na lowercase; samotný kód se nemění (číslice / servisní heslo).
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import re
import time
from datetime import datetime, timezone
from typing import Callable

from .config import SecurityCfg
from .models import ResolveResult, ServiceDoor
from .storage import Storage

log = logging.getLogger("motogo.pins")

PIN_RE = re.compile(r"^\d{6}$")
KV_LOCKOUT_STARTED = "pin_lockout_started"


def normalize_code(text: str) -> str:
    """Ořízne okraje a odstraní všechny mezery uvnitř (zákazník často píše ``123 456``)."""
    return "".join(str(text or "").split())


def is_pin(code: str) -> bool:
    """True = přesně 6 číslic (zákaznický kód); jinak jde o servisní heslo / nesmysl."""
    return bool(PIN_RE.match(code or ""))


def mask(code: str) -> str:
    """Maskování pro logy a UI: ``12••••`` (první dva znaky viditelné)."""
    code = code or ""
    if len(code) <= 2:
        return "•" * len(code)
    return code[:2] + "•" * (len(code) - 2)


def hmac_code(device_id: str, device_token: str, code: str) -> str:
    """HMAC-SHA256(key=device_token, msg=device_id:code) v hex — shodné s SQL (viz hlavička)."""
    key = str(device_token or "").strip().lower().encode("utf-8")
    msg = f"{str(device_id or '').strip().lower()}:{code}".encode("utf-8")
    return hmac.new(key, msg, hashlib.sha256).hexdigest()


def parse_iso(value: object) -> datetime | None:
    """ISO 8601 → aware datetime (naivní hodnoty bere jako UTC); nevalidní → None."""
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        text = str(value).strip()
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            log.warning("Nevalidní datum v cache kódů: %r", value)
            return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


class PinGuard:
    """Lockout dle §10: ``maximum_failed_attempts`` selhání v okně
    ``attempt_window_minutes`` → zákaz zadávání na ``lockout_minutes``.

    Stav je v ``Storage`` (přežije restart); ``clock`` lze v testech podstrčit.
    """

    def __init__(self, storage: Storage, sec: SecurityCfg, clock: Callable[[], float] = time.time) -> None:
        self.storage = storage
        self.sec = sec
        self.clock = clock

    def locked_until(self) -> float | None:
        """Unix čas konce lockoutu; None = zadávání povoleno (prošlý lockout se smaže)."""
        until = self.storage.lockout_until()
        if until is None:
            return None
        if until > self.clock():
            return until
        self.storage.set_lockout_until(None)
        return None

    def failures_in_window(self) -> int:
        """Počet selhání v aktuálním okně (selhání před posledním lockoutem se nepočítají)."""
        since = self.clock() - self.sec.attempt_window_minutes * 60
        started = self.storage.kv_get(KV_LOCKOUT_STARTED)
        if isinstance(started, (int, float)):
            since = max(since, float(started))
        return self.storage.pin_failures_since(since)

    def register_failure(self, masked: str) -> float | None:
        """Zaznamená neúspěch; pokud právě spustil lockout, vrátí jeho konec, jinak None."""
        now = self.clock()
        self.storage.pin_attempt(False, masked, ts=now)
        failures = self.failures_in_window()
        if failures < max(1, self.sec.maximum_failed_attempts):
            return None
        until = now + self.sec.lockout_minutes * 60
        self.storage.set_lockout_until(until)
        self.storage.kv_set(KV_LOCKOUT_STARTED, now)
        log.warning("PIN lockout: %d selhání (%s) → zamčeno na %d min",
                    failures, masked, self.sec.lockout_minutes)
        return until

    def register_success(self, masked: str) -> None:
        """Úspěšný kód se jen zaznamená — okno selhání NEresetuje (jinak by držitel jednoho platného
        kódu mohl hádat cizí PINy bez lockoutu, §10); lockout během platného lockoutu nikdy nenastane
        (submit_code ho kontroluje dřív)."""
        self.storage.pin_attempt(True, masked, ts=self.clock())


class LocalResolver:
    """Offline ověření proti cache z ``kiosk_sync_config`` (hashe, položky ``{"h": …}``)
    nebo ``kiosk_sync_codes`` (plaintext, legacy — položky ``{"code": …}`` / řetězce).

    Tvar se pozná po položkách, takže lze zpracovat i smíšený payload.
    """

    def __init__(self, device_id: str, device_token: str) -> None:
        self.device_id = device_id or ""
        self.device_token = device_token or ""

    def _matches(self, item: object, code: str, digest: str) -> bool:
        """Porovná položku cache (dict s ``h``/``code`` nebo plain řetězec) s kódem."""
        if isinstance(item, dict):
            if item.get("h") is not None:
                return hmac.compare_digest(str(item["h"]).lower(), digest)
            if item.get("code") is not None:
                return str(item["code"]).strip() == code
            return False
        return str(item).strip() == code

    @staticmethod
    def _service_doors(cache: dict) -> list[ServiceDoor]:
        doors: list[ServiceDoor] = []
        for d in cache.get("doors") or []:
            if not isinstance(d, dict):
                continue
            hw = d.get("hw") if isinstance(d.get("hw"), dict) else None
            zone = None
            if hw and hw.get("zone") is not None:
                try:
                    zone = int(hw["zone"])
                except (TypeError, ValueError):
                    zone = None
            doors.append(ServiceDoor(
                id=d.get("id"), kind=str(d.get("door_kind") or ""), box_number=d.get("box_number"),
                label=str(d.get("label") or ""), zone=zone,
                configured=bool(hw) or bool(d.get("relay_url")),
            ))
        return doors

    def resolve(self, code: str, cache: dict | None, now: datetime) -> ResolveResult | None:
        """Vrátí výsledek ověření z cache; None = kód v cache není (neznámý)."""
        if not isinstance(cache, dict):
            return None
        code = normalize_code(code)
        if not code:
            return None
        if now.tzinfo is None:
            now = now.replace(tzinfo=timezone.utc)
        digest = hmac_code(self.device_id, self.device_token, code)

        for item in cache.get("service_codes") or []:
            if self._matches(item, code, digest):
                action = str(item.get("action") or "service") if isinstance(item, dict) else "service"
                return ResolveResult(ok=True, kind="service", doors=self._service_doors(cache), offline=True,
                                     action=action)

        matched_expired: str | None = None
        for row in cache.get("codes") or []:
            if not isinstance(row, dict) or not self._matches(row, code, digest):
                continue
            valid_from, valid_until = parse_iso(row.get("valid_from")), parse_iso(row.get("valid_until"))
            if valid_from is not None and now < valid_from:
                matched_expired = "code_not_yet_valid"
                continue
            if valid_until is not None and now > valid_until:
                matched_expired = "code_expired"
                continue
            kind = str(row.get("kind") or "motorcycle")
            door_id, box = row.get("door_id"), row.get("box_number")
            if kind == "accessories":
                # Kód k oblečení otevírá VÝHRADNĚ dveře oblečení (door_id) — box_number motorky
                # z rezervace nesmí offline vést na kóji motorky (shodné s online kiosk_resolve_code).
                box = None
            return ResolveResult(
                ok=True, kind=kind, booking_id=row.get("booking_id"),
                door_id=door_id, box_number=box, door_configured=bool(door_id or box is not None),
                offline=True,
            )
        if matched_expired:
            return ResolveResult(ok=False, error=matched_expired, offline=True)
        return None
