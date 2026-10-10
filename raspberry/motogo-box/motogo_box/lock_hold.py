"""Držený zámek bez paměti (`timings.lock_hold_until_open`) — minimum držení po kódu `timings.lock_hold_min_s`
(2026-10-06, zadání majitele „kiosek musí držet magnet dveří po zadání kódu alespoň 1 min“) = okno pro OTEVŘENÍ;
jakmile kontakt hlásí otevřeno, zámek se vypne `timings.lock_release_after_open_s` (výchozí 2 s) po otevření
(2026-10-10, zadání majitele: zámek pod napětím nešel zavřít). Pomocný modul
`zone_access` (veřejná jména re-exportuje); vše se volá POD zámkem `ZoneController._busy`.

Okno „dveře jdou legálně otevřít“ (`lock_unlocked`) = zámek drží + krátký dozvuk po jeho vypnutí (`release_grace_s`):
otevření v něm je pokračování relace, NIKDY FORCED_OPEN. Fáze `lock_wait` = po zavření už uplynul doběh
(`light_after_close_s`), relace ale trvá jen kvůli zámku — zóna se pak chová jako dřív po SECURED (hudba stop,
světlo kóje zhasne, venek ji nepočítá), jen znovuotevření zůstává legální.
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .io_devices import FLASH_STEP_MS

if TYPE_CHECKING:  # pragma: no cover
    from .zone import ZoneController

log = logging.getLogger("motogo.zone")

MAX_HOLD_MS = 0xFFFF * FLASH_STEP_MS   # strop HW časovače flash-on (~109 min)
LOCK_HOLD_MIN_MAX_S = 600              # strop timings.lock_hold_min_s (config.LOCK_HOLD_MIN_RANGE_S)
RELEASE_GRACE_MARGIN_S = 0.5           # rezerva dozvuku nad poll + SW debounce kontaktu
RELEASE_AFTER_OPEN_S = 2               # výchozí timings.lock_release_after_open_s (2026-10-10)


def lock_hold_min_s(zc: "ZoneController") -> int:
    """Minimum držení zámku od kódu — JEN zámek bez paměti (`lock_hold_until_open`); impulzní zámek (IBFM) nikdy (0).
    0 = vypnout hned otevřením (chování do 1.2.5)."""
    t = zc.timings
    if not getattr(t, "lock_hold_until_open", False):
        return 0
    try:
        v = int(getattr(t, "lock_hold_min_s", 0) or 0)
    except (TypeError, ValueError):
        return 0
    return max(0, min(LOCK_HOLD_MIN_MAX_S, v))


def open_timeout_s(zc: "ZoneController") -> int:
    """Čekání na otevření dveří = `door_open_timeout_s`, v režimu držení zámku aspoň `lock_hold_min_s`."""
    return max(int(zc.timings.door_open_timeout_s), lock_hold_min_s(zc))


def hold_lock_ms(zc: "ZoneController") -> int:
    """Doba držení zámku = čekání na otevření (+1 s rezerva), v mezích HW časovače modulu (pojistka i při pádu procesu)."""
    return int(min(MAX_HOLD_MS, max(FLASH_STEP_MS, (open_timeout_s(zc) + 1) * 1000)))


def release_after_open_s(zc: "ZoneController") -> float:
    """Doba od skutečného otevření dveří (kontakt), po které se držený zámek vypne — i před `lock_hold_min_s`
    (2026-10-10, zadání majitele: magnet pod napětím nejde zavřít → 2 s po otevření proud vypnout)."""
    try:
        v = float(getattr(zc.timings, "lock_release_after_open_s", RELEASE_AFTER_OPEN_S))
    except (TypeError, ValueError):
        v = RELEASE_AFTER_OPEN_S
    return max(0.0, v)       # rozsah 0–30 hlídá validate_hardware; ≥ lock_hold_min_s = rozhoduje minimum


def lock_min_elapsed(zc: "ZoneController") -> bool:
    """Smí se držený zámek vypnout? Uplynulo minimum `lock_hold_min_s` od sepnutí, NEBO jsou dveře otevřené
    (poprvé od sepnutí) aspoň `release_after_open_s`. (Nedržený zámek = ano.)"""
    since = getattr(zc, "lock_held_since", None)
    if since is None or zc.clock() - since >= lock_hold_min_s(zc):
        return True
    opened = getattr(zc, "lock_opened_at", None)
    return opened is not None and zc.clock() - opened >= release_after_open_s(zc)


def mark_opened(zc: "ZoneController") -> None:
    """Kontakt hlásí otevřeno, zámek drží: od první takové chvíle běží `release_after_open_s` (2026-10-10)."""
    if zc.lock_held and getattr(zc, "lock_opened_at", None) is None:
        zc.lock_opened_at = zc.clock()


def release_grace_s(zc: "ZoneController") -> float:
    """Dozvuk po vypnutí drženého zámku: kontakt dorazí do zóny až po pollu + SW debounce (`polling`), takže dveře
    zatažené v posledních desetinách sekundy držení (magnet ještě pod napětím) zóna uvidí až po vypnutí zámku."""
    p = getattr(zc.hw, "polling", None)
    ms = int(getattr(p, "door_input_poll_ms", 100) or 0) + int(getattr(p, "software_debounce_ms", 300) or 0)
    return max(0, ms) / 1000.0 + RELEASE_GRACE_MARGIN_S


def lock_unlocked(zc: "ZoneController") -> bool:
    """Jdou dveře legálně otevřít? Držený zámek je pod napětím, nebo byl vypnut před méně než `release_grace_s`."""
    if zc.lock_held:
        return True
    at = getattr(zc, "lock_released_at", None)
    return at is not None and zc.clock() - at < release_grace_s(zc)


async def release_lock(zc: "ZoneController", why: str) -> None:
    """Vypne držený zámek (lock_hold_until_open): po minimu od kódu, timeoutu, all-off / poruše / konci relace."""
    if not zc.lock_held:
        return
    zc.lock_held, zc.lock_held_since, zc.lock_released_at = False, None, zc.clock()
    zc.lock_opened_at = None
    lock = zc.zone.hw.lock
    if lock is None:
        return
    if await zc.io.set(lock, False):
        log.info("Zóna %s: držený zámek vypnut (%s)", zc.number, why)
    else:
        log.warning("Zóna %s: vypnutí drženého zámku (%s) nepotvrzeno — vypne HW časovač modulu", zc.number, why)


async def release_lock_if_due(zc: "ZoneController", why: str) -> bool:
    """Otevření dveří / tick: vypne držený zámek, jen když už uplynulo minimum od kódu nebo 2 s od otevření dveří
    (`lock_min_elapsed`) — jinak drží dál a vypne ho `tick_locked` (důvod `min_hold`). Vrací True, když zámek už nedrží."""
    if zc.lock_held and lock_min_elapsed(zc):
        await release_lock(zc, why)
    return not zc.lock_held


async def lock_wait(zc: "ZoneController") -> None:
    """CLOSED_CONFIRMATION po doběhu (`light_after_close_s`), zámek ale ještě drží / dozvuk (`lock_unlocked`) nebo šatna
    čeká na kód motorky (`zone_access.wardrobe_hold`, 2026-10-10 — hudba pak NEzastaví): relace
    trvá (znovuotevření = DOOR_OPEN téže relace), jinak jako dřív po SECURED — hudba jednou stop, světlo kóje zhasne
    (šatna `light_until_moto_code` drží, dokud nepřišel kód motorky), venek zónu nepočítá (`zc.lock_wait`)."""
    if not zc.lock_wait:
        zc.lock_wait = zc.music_done = True
        if not getattr(zc, "hold_until_moto_code", False):   # šatna: hudba hraje do kódu motorky (2026-10-10)
            await zc.music_stop()
    if zc.light_on and (not zc.light_until_moto_code or zc.light_off_on_secure):
        await zc.set_light(False)
