"""Uvítací skladba (č. 1) vs. skladba návratu (č. 2) po zákaznickém kódu (zadání majitele 2026-09-28).

Hodiny běží od PRVNÍHO otevření rezervace na této jednotce (šatna i kóje jedné rezervace sdílí čas): opakované
otevření během vyzvedávání (2×, 3×, za hodinu pro zapomenutou věc) = skladba 1; od `timings.music_return_after_min`
(výchozí 180 min) = návrat = skladba 2. Servisní otevření / kód bez rezervace → None (celý playlist cíle jako dřív).
Časy v SQLite kv `booking_first_open` {booking_id: epoch}; záznamy starší než 60 dní se průběžně mažou.
"""
from __future__ import annotations

import logging
import time
from typing import Any

log = logging.getLogger("motogo.audio")

KV_KEY = "booking_first_open"
KEEP_S = 60 * 86400
CUSTOMER_KINDS = ("motorcycle", "accessories")


def track_for_grant(storage: Any, booking_id: str | None, kind: str | None, return_after_s: float,
                    now: float | None = None) -> int | None:
    """1 = uvítací, 2 = návrat, None = celý playlist (servis / bez rezervace / bez úložiště)."""
    if storage is None or not booking_id or kind not in CUSTOMER_KINDS:
        return None
    now = time.time() if now is None else now
    try:
        seen = storage.kv_get(KV_KEY, {}) or {}
        if not isinstance(seen, dict):
            seen = {}
        first = seen.get(str(booking_id))
        if not isinstance(first, (int, float)):
            seen = {k: v for k, v in seen.items() if isinstance(v, (int, float)) and now - v < KEEP_S}
            seen[str(booking_id)] = now
            storage.kv_set(KV_KEY, seen)
            return 1
        return 2 if now - first >= max(0.0, float(return_after_s)) else 1
    except Exception as exc:  # noqa: BLE001 — hudba nesmí zastavit otevření dveří
        log.warning("Fáze hudby rezervace %s nelze určit: %s", booking_id, exc)
        return 1


__all__ = ["track_for_grant", "KV_KEY"]
