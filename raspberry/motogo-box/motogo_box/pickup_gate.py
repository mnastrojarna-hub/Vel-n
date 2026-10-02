"""Výdej až od 12:00 (rozhodnutí majitele 2026-10-01, CONTRACT §31) — pomocný modul `controller_codes.submit_code`.

Samoobslužná pobočka, převzetí NA POBOČCE, rezervace se slevou za pozdní vyzvednutí (`late_pickup_discount_amount > 0`
= 50 % 1. dne za vyzvednutí od 12:00), ještě nevyzvednutá: šatnu i kóji motorky kiosk vydá až od `release_at` = 12:00
Europe/Prague dne začátku (server `_kiosk_release_at`). Kód zadaný dřív = hláška `pickup_too_early` s výzvou upravit
rezervaci (dřívější čas vyzvednutí → sleva zanikne, rozdíl doplatí, kód platí hned). Kód je PLATNÝ → do lockoutu se
NEpočítá (žádné `register_failure`), jen ACCESS_DENIED (info, reason `pickup_too_early`) do Velína.

Online rozhoduje `kiosk_resolve_code` (hodiny serveru → `ok:false, error:'pickup_too_early'`), offline `LocalResolver`
z `codes[].release_at` (hodiny jednotky). `blocks(rr)` = pojistka pro OFFLINE odpověď `ok` s budoucím `release_at`
(online `ok` = server už rozhodl svými hodinami; hodiny jednotky po restartu bez RTC mohou jít pozadu a zákazníka by
po 12:00 zbytečně odmítly). `release_at` chybí (stará DB / cache) = bez hradla.
"""
from __future__ import annotations

import math
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

from .models import Event, EventKind
from .odometer_rules import PRAGUE
from .pins import parse_iso

if TYPE_CHECKING:  # pragma: no cover
    from .models import ResolveResult

ERROR = "pickup_too_early"
TITLE = "Vyzvednutí až od 12:00"
_WHY = "Vaše rezervace má slevu 50 % na 1. den za vyzvednutí od 12:00, proto vám motorku i šatnu vydáme {w}."
_EDIT = ("Potřebujete ji dřív? V aplikaci MotoGo24 nebo na motogo24.cz/upravit-rezervaci změňte čas vyzvednutí "
         "na dřívější — sleva zanikne, rozdíl doplatíte a kód bude platit hned.")


def _now(now: datetime | None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    return now if now.tzinfo is not None else now.replace(tzinfo=timezone.utc)


def too_early(release_at: Any, now: datetime | None = None, slack_s: float = 0.0) -> bool:
    """True = `release_at` (ISO / datetime) je ještě v budoucnu (o víc než `slack_s`); chybí / nevalidní → False."""
    rel = parse_iso(release_at)
    return rel is not None and _now(now).timestamp() + max(0.0, slack_s) < rel.timestamp()


def blocks(rr: "ResolveResult", now: datetime | None = None) -> bool:
    """Pojistka pro OFFLINE výsledek `ok` s budoucím `release_at`. Online rozhodl
    server svými hodinami (ok = už po release_at) — hodiny jednotky (po restartu
    bez RTC mohou jít pozadu) by zákazníka po 12:00 zbytečně odmítly."""
    if not rr.ok or rr.is_service or not rr.release_at or not rr.offline:
        return False
    return too_early(rr.release_at, now, 0.0)


def minutes_left(release_at: Any, now: datetime | None = None) -> int | None:
    """Celé minuty do výdeje (nahoru, min. 1); `release_at` chybí → None."""
    rel = parse_iso(release_at)
    if rel is None:
        return None
    return max(1, math.ceil((rel - _now(now)).total_seconds() / 60))


def message(release_at: Any, now: datetime | None = None) -> str:
    """Česká hláška pro displej (UI ji v cizím jazyce skládá samo z `release_at`, ui/i18n-pickup.js)."""
    rel, cur = parse_iso(release_at), _now(now)
    if rel is None:
        when = "až od 12:00 v den začátku pronájmu"
    else:
        local = rel.astimezone(PRAGUE)
        t = local.strftime("%H:%M")
        if local.date() == cur.astimezone(PRAGUE).date():
            when = f"dnes od {t} (za {minutes_left(rel, cur)} min)"
        else:
            when = f"{local.day}. {local.month}. {local.year} od {t}"
    return _WHY.format(w=when) + " " + _EDIT


async def refuse(ctrl: Any, rr: "ResolveResult", base: dict, source: str) -> dict:
    """Odmítnutí platného kódu před výdejem: ACCESS_DENIED (info) do Velína + odpověď pro UI. Bez lockoutu."""
    rel = parse_iso(rr.release_at)
    at = rel.astimezone(PRAGUE).strftime("%d. %m. %H:%M") if rel is not None else "12:00"
    await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="info", code_kind=rr.kind or None,
                          door_id=rr.door_id, booking_id=rr.booking_id, box_number=rr.box_number,
                          message=f"Kód odmítnut — výdej až od {at} (sleva za vyzvednutí od 12:00)",
                          detail={"source": source, "reason": ERROR, "release_at": rr.release_at,
                                  "booking_id": rr.booking_id, "kind": rr.kind, "offline": rr.offline}))
    return {**base, "kind": rr.kind or base.get("kind"), "booking_id": rr.booking_id, "error": ERROR,
            "release_at": rr.release_at, "message": message(rr.release_at)}


__all__ = ["ERROR", "TITLE", "too_early", "blocks", "minutes_left", "message", "refuse"]
