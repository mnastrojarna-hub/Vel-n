"""Výzva „nejdřív kód šatny“ (zadání majitele 2026-09-29) — pomocný modul `controller_codes.submit_code`.

„Pokud mám rezervovanou motorku i příslušenství, mělo by mě to na kiosku vyzvat: zadejte prvně kód příslušenství.“
Kód motorky rezervace s nárokem na šatnu (`protocol.needs_locker`), která výbavu ještě nevyzvedla (DB
`gear_collected_at`) a na této jednotce zatím neotevřela žádné dveře, kóji NEotevře ani neukáže protokol — displej
řekne „Nejdřív zadejte kód šatny“ (chyba `locker_first`, bez lockoutu).

MĚKKÉ hradlo (nikdy nezablokuje výdej motorky):
  * druhé zadání kódu motorky do `REPEAT_S` po výzvě = „výbavu nechci“ → pustí dál (protokol → kóje);
  * šatna se počítá za navštívenou už ÚSPĚŠNÝM otevřením zámku (grant), ne až dveřním kontaktem (vadný kontakt
    by jinak zákazníka zablokoval), a také když šatna otevřít nešla (porucha → výbava stejně nejde vydat);
  * rezervace, která už na jednotce otevřela jakékoli dveře (šatna, nebo kóje = vracení), výzvu nedostane;
  * fail-open: stav protokolu neznámý / `absent` (offline po podpisu), šatna téže rezervace nenalezena v HW mapě,
    porucha / modul offline, kód šatny rezervace v cache kódů není (zákazník ho nemá).
Záznamy v SQLite kv `handover_locker` = {"opened": {bid: ts}, "prompted": {bid: ts}}; přežijí restart.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from .pins import parse_iso

KV = "handover_locker"
KEEP_S = 60 * 86400          # otevření rezervace si jednotka pamatuje po dobu nejdelšího pronájmu (jako music_phase)
REPEAT_S = 10 * 60           # opakovaný kód motorky do 10 min po výzvě = zákazník výbavu nechce → pustit dál
UNAVAILABLE = frozenset({"lock_failed", "io_offline", "fault"})    # šatna nejde otevřít → motorku nezdržovat


def _load(storage: Any, now: float) -> dict[str, dict[str, float]]:
    raw = storage.kv_get(KV)
    out: dict[str, dict[str, float]] = {"opened": {}, "prompted": {}}
    if isinstance(raw, dict):
        for key, keep in (("opened", KEEP_S), ("prompted", REPEAT_S)):
            d = raw.get(key)
            if isinstance(d, dict):
                out[key] = {str(k): float(v) for k, v in d.items()
                            if isinstance(v, (int, float)) and 0 <= now - float(v) <= keep}
    return out


def _save(storage: Any, data: dict) -> None:
    try:
        storage.kv_set(KV, data)
    except Exception:  # noqa: BLE001 — záznam je jen pomůcka výzvy, otevření dveří nesmí shodit
        pass


def mark_opened(storage: Any, booking_id: str | None, now: float) -> None:
    """Rezervace otevřela dveře (šatna / kóje), nebo šatna otevřít nešla → výzva se jí už neukáže."""
    bid = str(booking_id or "")
    if storage is None or not bid:
        return
    data = _load(storage, now)
    data["opened"][bid] = now
    data["prompted"].pop(bid, None)
    _save(storage, data)


def _locker_row(ctrl: Any, bid: str, now: datetime) -> dict | None:
    cache = ctrl.storage.load_code_cache() or {}
    for row in cache.get("codes") or []:
        if not isinstance(row, dict) or row.get("kind") != "accessories" or str(row.get("booking_id") or "") != bid:
            continue
        vf, vu = parse_iso(row.get("valid_from")), parse_iso(row.get("valid_until"))
        if (vf is None or vf <= now) and (vu is None or vu >= now):
            return row
    return None


def _usable(zc: Any) -> bool:
    ready = getattr(zc, "io_ready", None)
    return not getattr(zc, "fault", None) and (ready() if callable(ready) else True)


def check(ctrl: Any, rr: Any, now: float, zone_for_code: Any) -> int | None:
    """Kód motorky: None = pustit dál, číslo zóny šatny = vyzvat `locker_first` (a zapamatovat výzvu)."""
    bid, p = str(rr.booking_id or ""), rr.protocol
    if rr.kind != "motorcycle" or not bid or not isinstance(p, dict) or p.get("absent"):
        return None
    if p.get("needs_locker") is not True or p.get("gear_collected_at"):
        return None
    data = _load(ctrl.storage, now)
    if bid in data["opened"]:
        return None
    if bid in data["prompted"]:                       # druhé zadání = výbavu nechce → dál, výzvu už neopakovat
        data["prompted"].pop(bid, None)
        data["opened"][bid] = now
        _save(ctrl.storage, data)
        return None
    row = _locker_row(ctrl, bid, datetime.fromtimestamp(now, timezone.utc))
    if row is None:
        return None
    wz = zone_for_code(ctrl, row.get("door_id"), row.get("box_number"), "accessories")
    if wz is None or not _usable(wz):
        return None
    data["prompted"][bid] = now
    _save(ctrl.storage, data)
    return int(wz.number)


__all__ = ["check", "mark_opened", "UNAVAILABLE", "KV", "REPEAT_S"]
