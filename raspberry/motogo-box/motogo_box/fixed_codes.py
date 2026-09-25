"""Pevné servisní kódy na otevření jednotlivých dveří (zadání 2026-09-25).

`39301A` → kóje 1 … `39301G` → kóje 7, `39301H` → šatna. Fungují kdykoli — bez Velína,
bez internetu i bez rezervace (servis na místě); velikost písmen nerozhoduje. Otevření jde
plnou přístupovou sekvencí zóny (světlo, signalizace, hudba, impulz zámku, audit) stejně
jako „Otevřít" v servisním panelu (`kind='service'`). Lockout po neplatných pokusech platí
i pro ně (`submit_code` ho kontroluje dřív).
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from .models import Event, EventKind

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController
    from .zone import ZoneController

PREFIX = "39301"
# písmeno → číslo zóny (kóje 1–7); "H" = šatna (zóna s kind=accessories, jinak zóna 8)
LETTER_ZONES: dict[str, int] = {ch: i + 1 for i, ch in enumerate("ABCDEFG")}
WARDROBE_LETTER, WARDROBE_ZONE = "H", 8
SOURCE = "fixed_service_code"


def target(code: str) -> str | None:
    """Písmeno pevného kódu (`A`–`H`), nebo None, pokud kód není pevný servisní."""
    code = (code or "").strip().upper()
    if len(code) != len(PREFIX) + 1 or not code.startswith(PREFIX):
        return None
    letter = code[-1]
    return letter if letter in LETTER_ZONES or letter == WARDROBE_LETTER else None


def zone_for(ctrl: "BoxController", letter: str) -> "ZoneController | None":
    if letter == WARDROBE_LETTER:
        wardrobe = next((zc for zc in ctrl.zones.values() if zc.zone.kind == "accessories"), None)
        return wardrobe or ctrl.find_zone(zone=WARDROBE_ZONE)
    return ctrl.find_zone(zone=LETTER_ZONES[letter])


async def open_fixed(ctrl: "BoxController", letter: str, base: dict, source: str) -> dict:
    """Otevře dveře pevného kódu; výsledek ve tvaru `submit_code` (`kind='service_door'`)."""
    from .controller_codes import open_result_text   # cyklický import (controller_codes → fixed_codes)

    zc = zone_for(ctrl, letter)
    label = "Šatna" if letter == WARDROBE_LETTER else f"Kóje {LETTER_ZONES[letter]}"
    res = {**base, "kind": "service_door"}
    if zc is None:
        await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="warn", code_kind="service",
                              message=f"Pevný servisní kód: {label} není nastavena",
                              detail={"source": source, "via": SOURCE, "reason": "zone_not_configured"}))
        return {**res, "error": "zone_not_configured", "message": f"{label} není v této pobočce nastavena."}
    name = zc.zone.display_name
    ok, reason = await zc.grant_access(booking_id=None, kind="service", source=SOURCE)
    if not ok:
        await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="warn", code_kind="service",
                              zone=zc.number, door_id=zc.zone.door_id, box_number=zc.zone.box_number,
                              message=f"{name}: otevření pevným servisním kódem selhalo ({reason})",
                              detail={"source": source, "via": SOURCE, "reason": reason}))
    return {**res, "ok": ok, "error": None if ok else reason, "zone": zc.number,
            "message": open_result_text(ok, reason, "service", name)}
