"""Držený zámek bez paměti (`timings.lock_hold_until_open`) — minimum držení po kódu `timings.lock_hold_min_s`
(2026-10-06, zadání majitele „kiosek musí držet magnet dveří po zadání kódu alespoň 1 min“). Pomocný modul
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


def lock_min_elapsed(zc: "ZoneController") -> bool:
    """Uplynulo od sepnutí drženého zámku minimum `lock_hold_min_s`? (Nedržený zámek = ano.)"""
    since = getattr(zc, "lock_held_since", None)
    return since is None or zc.clock() - since >= lock_hold_min_s(zc)


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
    lock = zc.zone.hw.lock
    if lock is None:
        return
    if await zc.io.set(lock, False):
        log.info("Zóna %s: držený zámek vypnut (%s)", zc.number, why)
    else:
        log.warning("Zóna %s: vypnutí drženého zámku (%s) nepotvrzeno — vypne HW časovač modulu", zc.number, why)


async def release_lock_if_due(zc: "ZoneController", why: str) -> bool:
    """Otevření dveří / tick: vypne držený zámek, jen když už uplynulo minimum od kódu — jinak drží dál a vypne ho
    `tick_locked` (důvod `min_hold`). Vrací True, když zámek už nedrží."""
    if zc.lock_held and lock_min_elapsed(zc):
        await release_lock(zc, why)
    return not zc.lock_held


async def lock_wait(zc: "ZoneController") -> None:
    """CLOSED_CONFIRMATION po doběhu (`light_after_close_s`), zámek ale ještě drží / dozvuk (`lock_unlocked`): relace
    trvá (znovuotevření = DOOR_OPEN téže relace), jinak jako dřív po SECURED — hudba jednou stop, světlo kóje zhasne
    (šatna `light_until_moto_code` drží, dokud nepřišel kód motorky), venek zónu nepočítá (`zc.lock_wait`)."""
    if not zc.lock_wait:
        zc.lock_wait = zc.music_done = True
        await zc.music_stop()
    if zc.light_on and (not zc.light_until_moto_code or zc.light_off_on_secure):
        await zc.set_light(False)
