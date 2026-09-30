"""Pravidla stavu tachometru při vrácení (CONTRACT §30) — čisté funkce a datové typy pro `odometer.py`.

Hranice MUSÍ počítat stejně jako SQL `_kiosk_odometer` (jinak by server čtení označil jako sporné):
  * nápověda = min = `odo.hint` (motorcycles.mileage) zvednutý o vlastní NEodeslaná čtení téže motorky (fronta);
  * max = start_km + per_day × dny, dny = kalendářní dny v Praze včetně od `odo.start_at`; max ≤ min → min + per_day
    (zastaralý start_km nesmí dát prázdný rozsah); `hint` neznámý (motorka bez km) → bez horní meze;
  * per_day VÝHRADNĚ ze serveru (`odo.per_day`: 1000 km / 24 mth); bez bloku `odo` (stará DB) 1000/24 a stav
    z protokolu převzetí na této jednotce (lokální `start_km` / `start_at`).
Fáze bez lokálního stavu = důkazy serveru: poslední otevření kóje (`last_open_at` + `last_open_phase`; události před
aktualizací = `out`), jinak přistavení / SOS (`delivered` + `delivered_at`), jinak nic (fail-open = bez výzvy).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone, tzinfo
from typing import Any

from .pins import parse_iso

PER_DAY_FALLBACK = {"km": 1000, "mh": 24}
DIGITS_RE = re.compile(r"[0-9]{1,7}")     # celá čísla, max 9 999 999 (= CHECK v DB); jen ASCII (\d bere i „١٢٣“)
try:
    from zoneinfo import ZoneInfo
    PRAGUE: tzinfo = ZoneInfo("Europe/Prague")
except Exception:  # noqa: BLE001  # pragma: no cover — bez tzdata: UTC (hranice dne o 1–2 h jinde, jen velkorysejší)
    PRAGUE = timezone.utc


def ts(value: Any) -> float | None:
    """Unix čas z čísla / ISO textu; jinak None."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    dt = parse_iso(value)
    return dt.timestamp() if dt is not None else None


def pos_int(value: Any) -> int | None:
    """Kladné celé číslo, jinak None (0 = neznámý stav, jako NULLIF v SQL)."""
    if isinstance(value, bool):
        return None
    try:
        n = int(value)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


def rental_days(start_ts: float | None, now_ts: float) -> int:
    """Kalendářní dny v Praze včetně (shodně s SQL `_kiosk_odometer`): týž den = 1, přes půlnoc = 2."""
    if start_ts is None:
        return 1
    d0 = datetime.fromtimestamp(start_ts, PRAGUE).date()
    return max(1, (datetime.fromtimestamp(now_ts, PRAGUE).date() - d0).days + 1)


def unit_label(unit: str) -> str:
    """Jednotka pro zákazníka (displej, hláška): km | mth."""
    return "mth" if unit == "mh" else "km"


@dataclass
class OdoPrompt:
    """Výzva k zadání stavu (vrácení) — `public()` jde do odpovědi `/api/pin` (overlay #odometer)."""

    booking_id: str
    unit: str
    hint: int | None
    min: int | None
    max: int | None
    days: int
    zone: int | None = None

    def public(self) -> dict:
        return {"unit": self.unit, "hint": self.hint, "min": self.min, "max": self.max, "days": self.days,
                "zone": self.zone}


@dataclass
class OdoPlan:
    """Rozhodnutí pro jeden kód motorky: aktuální fáze (+ čas), fáze po otevření, případná výzva / čtení."""

    booking_id: str
    phase: str | None            # None = bez důkazu o převzetí
    at: float | None
    phase_after: str = "out"
    moto_id: str | None = None
    unit: str = "km"
    prompt: OdoPrompt | None = None
    reading: dict | None = None  # {reading_id, km, unit} — uložené čtení (nové nebo neotevřené k opakování)

    @property
    def returning(self) -> bool:
        """Vrácení / kód po vrácení: hradla převzetí (šatna, protokol) se neuplatní."""
        return self.phase_after == "in"


def evidence(odo: dict | None) -> tuple[str | None, float | None]:
    """Fáze a její čas ze serveru, když jednotka nemá lokální stav (převzetí před aktualizací, reinstalace, přistavení)."""
    if not isinstance(odo, dict):
        return None, None
    last = ts(odo.get("last_open_at"))
    if last is not None:
        return ("in" if odo.get("last_open_phase") == "in" else "out"), last
    delivered = ts(odo.get("delivered_at")) if odo.get("delivered") else None
    return ("out", delivered) if delivered is not None else (None, None)


def bounds(odo: dict | None, local: dict, unit: str, unacked: int | None, now: float
           ) -> tuple[int | None, int | None, int | None, int]:
    """(nápověda, min, max, dny) — shodně se serverem; bez známého stavu jen spodní mez z neodeslaných čtení."""
    if odo is not None:
        per_day = pos_int(odo.get("per_day")) or PER_DAY_FALLBACK[unit]
        hint, start_ts = pos_int(odo.get("hint")), ts(odo.get("start_at"))
        start_km = pos_int(odo.get("start_km")) or hint
    else:                                     # stará DB bez bloku odo: stav z protokolu při převzetí na jednotce
        per_day = PER_DAY_FALLBACK[unit]
        hint = start_km = pos_int(local.get("start_km"))
        start_ts = ts(local.get("start_at"))
    days = rental_days(start_ts, now)
    if hint is None:
        return unacked, unacked, None, days
    lo = max(hint, unacked or 0)
    hi = (start_km or lo) + per_day * days
    return lo, lo, (hi if hi > lo else lo + per_day), days


def validate(prompt: OdoPrompt, raw: Any) -> tuple[int | None, str | None]:
    """(km, None) nebo (None, důvod not_number | too_low | too_high); mezery uvnitř se ignorují („10 450“)."""
    text = "".join(str(raw if raw is not None else "").split())
    if not DIGITS_RE.fullmatch(text):
        return None, "not_number"
    km = int(text)
    if prompt.min is not None and km < prompt.min:
        return None, "too_low"
    if prompt.max is not None and km > prompt.max:
        return None, "too_high"
    return km, None
