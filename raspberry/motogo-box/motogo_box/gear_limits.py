"""Velikosti půjčené výbavy na samoobslužné pobočce (zadání majitele 2026-10-10, CONTRACT §28 `sizes`).

Jednotka stojí VŽDY na samoobslužné pobočce, proto pravidlo platí bez dalšího rozlišení:
- helma nejmenší S a největší 3XL; bunda, kalhoty a rukavice největší 4XL (spodní mez beze změny);
- boty (čísla), kukla a dětská motorka (`is_child`) beze změny.
Filtruje se podle POŘADÍ písmenných velikostí (XXS < XS < S < … < 2XL = XXL < 3XL = XXXL < 4XL = XXXXL < 5XL < 6XL;
porovnává se po trim + upper). Hodnoty, které pořadí nezná (čísla bot, dětské texty „4–7 let“), projdou beze změny.
Klíč, který `gear_sizes` ze syncu nemá (živá DB nemá řádek `jacket`), dostane u dospělé výbavy záložní řadu.
Totéž pravidlo vynucuje edge `submit-handover-protocol` (gear.ts) — do rezervace se mimo rozsah nic nezapíše.
"""
from __future__ import annotations

from typing import Any

ORDER = ("XXS", "XS", "S", "M", "L", "XL", "2XL", "3XL", "4XL", "5XL", "6XL")
ALIASES = {"XXL": "2XL", "XXXL": "3XL", "XXXXL": "4XL", "XXXXXL": "5XL", "XXXXXXL": "6XL"}
RANK = {s: i for i, s in enumerate(ORDER)}
LIMITS: dict[str, tuple[str | None, str | None]] = {
    "helmet": ("S", "3XL"), "jacket": (None, "4XL"), "pants": (None, "4XL"), "gloves": (None, "4XL")}
_ADULT = ("S", "M", "L", "XL", "2XL", "3XL", "4XL")
FALLBACK: dict[str, tuple[str, ...]] = {"helmet": _ADULT[:-1], "jacket": _ADULT, "pants": _ADULT, "gloves": _ADULT}


def rank(size: Any) -> int | None:
    """Pořadí písmenné velikosti; None = pořadí ji nezná (čísla, dětské texty, prázdno)."""
    s = str(size if size is not None else "").strip().upper()
    return RANK.get(ALIASES.get(s, s))


def size_ok(key: Any, size: Any, is_child: bool = False) -> bool:
    """Smí se velikost na samoobsluze nabídnout / zapsat? Dětská motorka, typ bez meze a neznámé hodnoty vždy ano."""
    if is_child or key not in LIMITS:
        return True
    r = rank(size)
    if r is None:
        return True
    lo, hi = LIMITS[key]
    return (lo is None or r >= RANK[lo]) and (hi is None or r <= RANK[hi])


def allowed_sizes(key: Any, sizes: Any, is_child: bool = False) -> list:
    """Nabídka velikostí pro displej: řada ze syncu (u dospělé výbavy záloha pro chybějící / prázdný klíč) bez
    velikostí mimo rozsah samoobsluhy; pořadí i zápis hodnot zůstávají jako v číselníku."""
    src = list(sizes) if isinstance(sizes, (list, tuple)) else []
    if not src and not is_child:
        src = list(FALLBACK.get(key, ()))
    return [s for s in src if size_ok(key, s, is_child)]


def clamp(key: Any, size: Any, offered: Any, is_child: bool = False) -> Any:
    """Rezervovaná velikost mimo rozsah → NEJBLIŽŠÍ povolená z nabídky (5XL/6XL → 4XL, helma XS → S); nikdy prázdno.
    Velikost v rozsahu (i mimo nabídku) a neznámé hodnoty vrací beze změny. Deterministické (UI `gearSig`)."""
    if size_ok(key, size, is_child):
        return size
    r = rank(size)
    cands = [(abs(rank(o) - r), i, o) for i, o in enumerate(offered if isinstance(offered, (list, tuple)) else [])
             if rank(o) is not None and size_ok(key, o)]
    if cands:
        return min(cands)[2]
    lo, hi = LIMITS[key]
    return hi if hi is not None and r > RANK[hi] else lo


def clamp_gear(gear: Any, sizes: dict, is_child: bool = False) -> Any:
    """Kopie `data.gear` pro snapshot s velikostmi posunutými `clamp` (vstupní seznam ani položky nemění)."""
    if not isinstance(gear, list):
        return gear
    out = []
    for g in gear:
        if isinstance(g, dict):
            new = clamp(g.get("key"), g.get("size"), sizes.get(g.get("key")), is_child)
            if new != g.get("size"):
                g = {**g, "size": new}
        out.append(g)
    return out
