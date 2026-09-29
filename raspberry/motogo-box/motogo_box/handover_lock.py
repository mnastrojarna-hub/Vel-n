"""Zámek přejímky (rozhodnutí majitele 2026-09-28) — pomocná třída `handover.py` (CONTRACT §28).

Po zavření šatny zákazníkem přijímá kiosk JEN kódy téže rezervace (kód motorky, případně znovu kód šatny), dokud se
neotevře kóje motorky té rezervace: zákazník, který právě zavřel šatnu, podepíše protokol a zadá kód motorky; ostatní
čekají („Nejprve musí být dokončena předchozí přejímka“ — `controller_codes.submit_code`, chyba `handover_in_progress`).
Nikdo se tak nehromadí v šatně a přejímky jdou jedna po druhé. Zámek NIKDY nezablokuje kiosk natrvalo: bez aktivity
(zavření šatny, dotyk/podpis protokolu, přijatý kód téže rezervace) vyprší po `TimingsCfg.handover_lock_s` (300 s) —
zákazník, který odešel, nesmí kiosk „zaseknout“. Servisní hesla, pevné servisní kódy 39301A–H ani diagnostické kódy
zámek nezastaví; servisní „Vše vypnout“ ho uvolní. Stav `{booking_id, zone, since, last_activity, customer_name}` se
persistuje v kv `handover` (klíč `lock`) — přežije restart procesu (a vyprší stejně).
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Callable

log = logging.getLogger("motogo.handover")

DEFAULT_LOCK_S = 600             # 2026-09-29: 10 min (= handover_idle_s, protokol nesmí přežít zámek)


def iso_ts(ts: float | None) -> str | None:
    return None if ts is None else datetime.fromtimestamp(float(ts), timezone.utc).isoformat(timespec="seconds")


class HandoverLock:
    """Jediný zámek na jednotku; `on_change` = persist (HandoverManager._save)."""

    def __init__(self, clock: Callable[[], float], lock_s: Callable[[], int], on_change: Callable[[], None]) -> None:
        self.clock, self._lock_s, self._on_change = clock, lock_s, on_change
        self.state: dict | None = None

    @property
    def lock_s(self) -> int:
        return int(self._lock_s() or DEFAULT_LOCK_S)

    @property
    def booking_id(self) -> str | None:
        return self.state["booking_id"] if self.state else None

    # ─── persist ─────────────────────────────────────────────────────────────
    def load(self, raw: Any) -> None:
        if not isinstance(raw, dict) or not raw.get("booking_id"):
            return
        try:
            self.state = {"booking_id": str(raw["booking_id"]), "zone": raw.get("zone"),
                          "since": float(raw.get("since") or 0.0), "last_activity": float(raw.get("last_activity") or 0.0),
                          "customer_name": raw.get("customer_name")}
        except (TypeError, ValueError):
            self.state = None

    def to_dict(self) -> dict | None:
        return dict(self.state) if self.state else None

    # ─── stav ────────────────────────────────────────────────────────────────
    def active(self, now: float | None = None) -> bool:
        if not self.state:
            return False
        now = self.clock() if now is None else now
        return now - self.state["last_activity"] < self.lock_s

    def blocks(self, booking_id: str | None, now: float | None = None) -> bool:
        """Zákaznický kód JINÉ rezervace se odmítá, dokud je zámek aktivní."""
        return self.active(now) and str(booking_id or "") != self.state["booking_id"]

    def set(self, booking_id: str, zone: int | None, customer_name: str | None = None) -> None:
        """Zavření šatny zákazníkem: zámek pro tuto rezervaci (táž rezervace = jen obnovit aktivitu, `since` zůstává)."""
        now, bid = self.clock(), str(booking_id)
        if self.state and self.state["booking_id"] == bid:
            self.state["zone"], self.state["last_activity"] = zone, now
            if customer_name:
                self.state["customer_name"] = customer_name
        else:
            if self.state and self.active(now):
                log.info("handover: zámek přejímky %s přebírá rezervace %s (další zavření šatny)", self.state["booking_id"], bid)
            self.state = {"booking_id": bid, "zone": zone, "since": now, "last_activity": now, "customer_name": customer_name}
            log.info("handover: zámek přejímky pro rezervaci %s (šatna zóna %s) — ostatní kódy čekají, max %d s bez aktivity",
                     bid, zone, self.lock_s)
        self._on_change()

    def touch(self, booking_id: str | None) -> bool:
        """Aktivita zamčené rezervace (přijatý kód, dotyk/podpis protokolu) → odklad vypršení."""
        if not self.state or str(booking_id or "") != self.state["booking_id"]:
            return False
        self.state["last_activity"] = self.clock()
        self._on_change()
        return True

    def release(self, booking_id: str | None = None, reason: str = "") -> bool:
        """Uvolnit: kóje motorky rezervace otevřena; `booking_id=None` = bez ohledu na rezervaci (servisní all_off)."""
        if not self.state or (booking_id is not None and str(booking_id) != self.state["booking_id"]):
            return False
        log.info("handover: zámek přejímky %s uvolněn (%s)", self.state["booking_id"], reason or "-")
        self.state = None
        self._on_change()
        return True

    def expire(self, now: float | None = None) -> bool:
        """tick_loop: bez aktivity déle než lock_s zámek zaniká (zákazník odešel — kiosk se nesmí zaseknout)."""
        if not self.state or self.active(now):
            return False
        log.warning("handover: zámek přejímky %s vypršel bez otevření kóje motorky (%d s bez aktivity)",
                    self.state["booking_id"], self.lock_s)
        self.state = None
        self._on_change()
        return True

    def status(self, now: float | None = None) -> dict | None:
        """Snapshot `handover.lock` (§14): null, nebo {booking_id, zone, until, customer_name} — bez osobních údajů navíc."""
        if not self.active(now):
            return None
        s = self.state
        return {"booking_id": s["booking_id"], "zone": s["zone"], "until": iso_ts(s["last_activity"] + self.lock_s),
                "customer_name": s.get("customer_name")}
