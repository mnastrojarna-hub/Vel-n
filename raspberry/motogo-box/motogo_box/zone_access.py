"""Pomalé sekvence stavového automatu zóny — přístupová sekvence (§9 „Platný PIN")
a časové přechody (`tick`). Pomocný modul `zone.py`; veřejné API zůstává tam.

VŠECHNY funkce tohoto modulu se volají výhradně POD zámkem `ZoneController._busy`
(držitel: `grant_access` / `tick`), takže se s vyhodnocením kontaktu ani jiným
přechodem nikdy neprolnou.
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING

from .models import EventKind, Signal, ZoneState, now_iso

if TYPE_CHECKING:  # pragma: no cover
    from .zone import ZoneController

log = logging.getLogger("motogo.zone")


async def grant_locked(zc: "ZoneController", booking_id: str | None, kind: str, source: str) -> tuple[bool, str]:
    """Kroky 6–12 §9 po ověřených podmínkách: světlo, zelená, hudba, HW pulz zámku, událost, WAITING_FOR_OPEN."""
    zc.code_kind, zc.source = kind, source
    zc.reset_session()                      # ukončí doběh předchozí relace (CLOSED_CONFIRMATION)
    detail: dict = {}
    if not await zc.set_light(True):
        detail["light_failed"] = True        # světlo není bezpečnostní prvek — pokračujeme
        log.warning("Zóna %s: bílé světlo nepotvrzeno", zc.number)
    await zc.signal(Signal.GREEN)
    try:
        detail["music"] = bool(await zc.audio.play_zone(zc.number))
    except Exception:  # noqa: BLE001
        log.exception("Zóna %s: spuštění hudby selhalo", zc.number)
        detail["music"] = False
    # Znovu po pomalých krocích: dveře mezitím otevřené (bez odjištění) nebo modul offline → bez pulzu.
    reason = "door_open" if zc.door_closed is not True else ("io_offline" if not zc.io_ready() else "")
    ok = False
    if not reason:
        lock = zc.zone.hw.lock
        pulse_ms = int(zc.timings.lock_pulse_ms)
        async with zc.lock_gate:                  # dva zámky nikdy nemají impulz zároveň
            ok = lock is not None and await zc.io.pulse(lock, pulse_ms)
            if ok:
                await asyncio.sleep(pulse_ms / 1000.0)
        reason = "" if ok else "lock_failed"
    if not ok:
        log.error("Zóna %s: přístup neproveden (%s)", zc.number, reason)
        await zc.set_light(False)
        await zc.signal(Signal.RED)
        await zc.music_stop()
        zc.state = ZoneState.SECURED             # doběh předchozí relace byl právě ukončen
        zc.reset_session()
        await zc.evaluate_locked()               # otevřené dveře / offline modul → příslušná porucha
        return False, reason
    zc.booking_id = booking_id
    zc.state = ZoneState.WAITING_FOR_OPEN
    zc.session_started = zc.waiting_since = zc.clock()
    zc.session_started_at = now_iso()
    await zc.emit_event(EventKind.ACCESS_GRANTED, message=f"{zc.zone.display_name}: přístup povolen ({kind})",
                        code_kind=kind, **detail)
    await zc.evaluate_locked()                   # dveře otevřené už během pulzu → DOOR_OPEN (ne forced_open)
    return True, "ok"


async def tick_locked(zc: "ZoneController") -> None:
    """Časové přechody: timeout otevření, overtime, doběh hudby/světla po zavření."""
    now = zc.clock()
    t = zc.timings
    if zc.state == ZoneState.WAITING_FOR_OPEN and zc.waiting_since is not None:
        if now - zc.waiting_since > t.door_open_timeout_s:
            zc.state = ZoneState.SECURED         # nejdřív stav, teprve pak pomalé HW kroky
            await zc.music_stop()
            await zc.set_light(False)
            await zc.signal(Signal.RED)
            await zc.emit_event(EventKind.OPEN_TIMEOUT, success=False, level="warn",
                                message=f"{zc.zone.display_name}: dveře nebyly otevřeny do {t.door_open_timeout_s} s")
            zc.reset_session()
    elif zc.state == ZoneState.DOOR_OPEN and zc.opened_at is not None:
        await _tick_door_open(zc, now - zc.opened_at)
    elif zc.state == ZoneState.CLOSED_CONFIRMATION and zc.closed_at is not None:
        elapsed = now - zc.closed_at
        if not zc.music_done and elapsed >= t.music_after_close_s:
            zc.music_done = True
            await zc.music_stop()
        if elapsed >= t.light_after_close_s:
            zc.state = ZoneState.SECURED
            zc.reset_session()
            await zc.music_stop()
            await zc.set_light(False)
            await zc.signal(Signal.RED)          # idempotentní — jistota, že SECURED = červená
            log.info("Zóna %s: relace uzavřena, SECURED", zc.number)


async def _tick_door_open(zc: "ZoneController", elapsed: float) -> None:
    """Překročení maximální doby otevření (§9): overtime + opakovaná upozornění."""
    t = zc.timings
    if elapsed > t.maximum_session_s and not zc.overtime:
        zc.overtime = True
        await zc.music_stop()
        await zc.signal(Signal.GREEN_PULSE)
        await zc.emit_event(EventKind.SESSION_OVERTIME, success=False, level="warn",
                            message=f"{zc.zone.display_name}: dveře otevřené déle než {t.maximum_session_s} s",
                            open_s=int(elapsed))
    if not zc.overtime:
        return
    for minutes in t.overtime_alert_minutes or []:
        m = int(minutes)
        if m * 60 <= t.maximum_session_s or m in zc.alerts_sent or elapsed < m * 60:
            continue
        zc.alerts_sent.add(m)
        await zc.emit_event(EventKind.SESSION_OVERTIME_ALERT, success=False, level="warn",
                            message=f"{zc.zone.display_name}: dveře otevřené už {m} min", open_min=m)
