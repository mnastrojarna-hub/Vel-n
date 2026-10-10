"""Pomalé sekvence stavového automatu zóny — přístupová sekvence (§9 „Platný PIN")
a časové přechody (`tick`). Pomocný modul `zone.py`; veřejné API zůstává tam.

VŠECHNY funkce tohoto modulu se volají výhradně POD zámkem `ZoneController._busy`
(držitel: `grant_access` / `tick`), takže se s vyhodnocením kontaktu ani jiným
přechodem nikdy neprolnou.
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from typing import TYPE_CHECKING

from . import music_phase
from .io_devices import FLASH_STEP_MS
# Držený zámek bez paměti (minimum lock_hold_min_s, 2026-10-06) — re-export pro zone.py a testy.
from .lock_hold import (MAX_HOLD_MS, hold_lock_ms, lock_hold_min_s, lock_unlocked, lock_wait,  # noqa: F401
                        mark_opened, open_timeout_s, release_lock, release_lock_if_due)
from .models import EventKind, Signal, ZoneState, now_iso

if TYPE_CHECKING:  # pragma: no cover
    from .zone import ZoneController

log = logging.getLogger("motogo.zone")

# Relace zóny v událostech (1.2.8, 2026-10-06, CONTRACT §15/§32): všechny události jedné relace nesou `session_id`
# (32 hex, nové při každém grantu) a relace s fází tachometru i `odometer_phase` / `odometer_reading_id` svého
# ACCESS_GRANTED — server (`booking_kiosk_returns`) z nich pozná zavření kóje po VRÁCENÍ i při přeházeném pořadí doručení.
SESSION_EVENTS = frozenset({EventKind.ACCESS_GRANTED, EventKind.DOOR_OPENED, EventKind.DOOR_CLOSED,
                            EventKind.SESSION_COMPLETED, EventKind.OPEN_TIMEOUT})
SESSION_KEYS = ("odometer_phase", "odometer_reading_id")


def new_session(detail: dict | None = None) -> dict:
    """Kontext nové relace: `session_id` + fáze/čtení tachometru z detailu grantu (jen přítomné klíče)."""
    ctx = {"session_id": uuid.uuid4().hex}
    ctx.update({k: (detail or {})[k] for k in SESSION_KEYS if (detail or {}).get(k) is not None})
    return ctx


async def service_unlock_locked(zc: "ZoneController", source: str) -> tuple[bool, str]:
    """Nouzové servisní otevření (2026-09-26): impulz zámku BEZ OHLEDU na stav zóny (porucha, otevřené dveře,
    běžící relace, offline kontakt/světlo). Jediná podmínka: nastavený a online modul zámku. Stav ani relace
    zóny se nemění (porucha zůstane, dokud kontakt neřekne jinak) — jen bílé světlo (best effort) a událost
    ACCESS_GRANTED s `emergency`. Zákaznické kódy tudy NIKDY nejdou (zachovávají všechny pojistky §9)."""
    lock = zc.zone.hw.lock
    if lock is None:
        return False, "not_configured"
    if not zc.io.is_online(lock.dev):
        return False, "lock_offline"
    detail: dict = {"emergency": True, "state": zc.state.name, "fault": zc.fault, "door_closed": zc.door_closed}
    if not await zc.set_light(True):
        detail["light_failed"] = True
    pulse_ms = int(zc.timings.lock_pulse_ms)
    hold_ms = max(pulse_ms, max(1, round(pulse_ms / FLASH_STEP_MS)) * FLASH_STEP_MS)
    async with zc.lock_gate:
        ok = await zc.io.pulse(lock, pulse_ms)
        if ok:
            await asyncio.sleep(hold_ms / 1000.0)
    if not ok:
        log.error("Zóna %s: nouzové servisní otevření selhalo (pulz zámku %s)", zc.number, lock.dev)
        return False, "lock_failed"
    zc.unlocks_since_start = getattr(zc, "unlocks_since_start", 0) + 1
    log.warning("Zóna %s: NOUZOVÉ servisní otevření (%s) ve stavu %s/%s", zc.number, source, zc.state.name, zc.fault)
    zc.source = source
    await zc.emit_event(EventKind.ACCESS_GRANTED, level="warn",
                        message=f"{zc.zone.display_name}: nouzové servisní otevření (stav {zc.state.name}"
                                f"{', porucha ' + zc.fault if zc.fault else ''})", code_kind="service", **detail)
    return True, "ok"


MUSIC_WAIT_S = 1.5     # na start hudby se před pulzem zámku čeká nejdéle takto dlouho (zbytek doběhne na pozadí)


def has_speaker(zc: "ZoneController") -> bool:
    """Má zóna reproduktor (multi: výstup `hw.audio.out`, selector: audio relé)? Starší engine/fake = ano."""
    fn = getattr(zc.audio, "has_output", None)
    return bool(fn(zc.number)) if fn is not None else True


async def start_music(zc: "ZoneController", detail: dict) -> None:
    """Hudba po otevření: jen zapnutá (`music_enabled`) a jen zóna s reproduktorem — zóna bez výstupu
    nehraje nikde jinde a není to chyba (`no_speaker`). Pulz zámku na hudbu nečeká déle než MUSIC_WAIT_S
    (restart mpv / pomalá USB karta nesmí zdržet otevření); hudba pak doběhne na pozadí."""
    detail["music"] = False
    if not zc.music_enabled:
        detail["music_disabled"] = True
        return
    if not has_speaker(zc):
        detail["no_speaker"] = True
        return
    track = getattr(zc, "music_track", None)
    if track:
        detail["music_track"] = track          # Hlášení a chyby: která skladba hrála (1 uvítací / 2 návrat)
    # restart (2026-10-06, zadání majitele): po kódu hraje hudba VŽDY od začátku — i když už hraje (2. kód v doběhu)
    # nebo zůstala pozastavená uprostřed skladby. Ruční „Hudba ▶“ z Velína a kanál venku hrají dál bez přetáčení.
    task = asyncio.ensure_future(zc.audio.play_zone(zc.number, track, restart=True))
    try:
        detail["music"] = bool(await asyncio.wait_for(asyncio.shield(task), MUSIC_WAIT_S))
    except asyncio.TimeoutError:
        detail["music"], detail["music_pending"] = True, True
        task.add_done_callback(lambda t: t.cancelled() or t.exception())   # výjimku nenechat „neodebranou“
        log.warning("Zóna %s: hudba startuje pomalu — otevírám bez čekání", zc.number)
    except Exception:  # noqa: BLE001
        log.exception("Zóna %s: spuštění hudby selhalo", zc.number)


async def grant_locked(zc: "ZoneController", booking_id: str | None, kind: str, source: str,
                       extra: dict | None = None) -> tuple[bool, str]:
    """Kroky 6–12 §9 po ověřených podmínkách: světlo, zelená, hudba, HW pulz zámku, událost, WAITING_FOR_OPEN.
    `extra` = klíče navíc do detailu ACCESS_GRANTED (fáze / stav tachometru, odometer.py)."""
    # 2. kód v doběhu, kdy zámek předchozí relace ještě drží (lock_hold_min_s): dveře jdou legálně otevřít i během
    # pomalých kroků níže — takové otevření NENÍ door_open ani FORCED_OPEN, přístup pokračuje (→ DOOR_OPEN).
    was_unlocked = zc.state == ZoneState.CLOSED_CONFIRMATION and lock_unlocked(zc)
    zc.reset_session()                      # ukončí doběh předchozí relace (CLOSED_CONFIRMATION)
    zc.code_kind, zc.source = kind, source
    zc.latch_released, zc._late_booking = False, None
    detail: dict = dict(extra or {})
    # Uvítací (1) / návrat (2) dle času od 1. otevření rezervace (music_phase, 2026-09-28); pozdní otevření ho převezme.
    zc.music_track = music_phase.track_for_grant(getattr(zc, "music_store", None), booking_id, kind,
                                                 60 * float(getattr(zc.hw.timings, "music_return_after_min", 180) or 0))
    if not await zc.set_light(True):
        detail["light_failed"] = True        # světlo není bezpečnostní prvek — pokračujeme
        log.warning("Zóna %s: bílé světlo nepotvrzeno", zc.number)
    await zc.signal(Signal.GREEN)
    # Hudba se po zadání kódu spustí, JEN pokud je zapnutá (hlavní vypínač pobočky `audio.music_enabled`
    # nebo přepis této zóny `hw.music_enabled` — zadání uživatele 2026-09-14). Vypnutá hudba nijak
    # neovlivňuje otevření dveří; ruční „Hudba ▶“ z Velína funguje dál (servisní zkouška).
    await start_music(zc, detail)
    # Znovu po pomalých krocích: dveře mezitím otevřené (bez odjištění) nebo modul offline → bez pulzu.
    held_open = was_unlocked and zc.door_closed is False
    reason = "door_open" if zc.door_closed is not True and not held_open else ("io_offline" if not zc.io_ready() else "")
    ok = False
    if not reason:
        lock = zc.zone.hw.lock
        if zc.timings.lock_hold_until_open:
            # Zámek bez paměti (2026-09-26): pod napětím od kódu, dokud kontakt nehlásí otevřeno (zone.evaluate_locked
            # → io.set off), nejdéle door_open_timeout_s (HW časovač modulu = pojistka i při pádu procesu).
            # 2026-10-06: na otevření čeká aspoň lock_hold_min_s od kódu; 2026-10-10: po otevření dveří (kontakt) se
            # vypne lock_release_after_open_s (2 s) — magnet pod napětím nejde zavřít (release_lock_if_due / tick_locked).
            # Čas PŘED zápisem: HW časovač běží od zápisu cívky, ověření (read_coils + retry) trvá až ~3 s.
            t0 = zc.clock()
            ok = lock is not None and await zc.io.hold(lock, hold_lock_ms(zc))
            if ok:
                zc.lock_held, zc.lock_held_since, zc.lock_opened_at = True, t0, None
        else:
            pulse_ms = int(zc.timings.lock_pulse_ms)
            # WAV645 flash-on běží v krocích po 100 ms (zaokrouhleno) — brána musí držet i tuto dobu.
            hold_ms = max(pulse_ms, max(1, round(pulse_ms / FLASH_STEP_MS)) * FLASH_STEP_MS)
            async with zc.lock_gate:                  # dva zámky nikdy nemají impulz zároveň
                ok = lock is not None and await zc.io.pulse(lock, pulse_ms)
                if ok:
                    await asyncio.sleep(hold_ms / 1000.0)
        reason = "" if ok else "lock_failed"
        if ok:
            zc.unlocks_since_start = getattr(zc, "unlocks_since_start", 0) + 1   # diagnostika: kontakt se po otevření musí změnit
    if not ok:
        log.error("Zóna %s: přístup neproveden (%s)", zc.number, reason)
        await release_lock(zc, "přístup neproveden")   # zámek držený z předchozí relace (nový kód v doběhu)
        await zc.set_light(False)
        await zc.signal(Signal.RED)
        await zc.music_stop()
        zc.state = ZoneState.SECURED             # doběh předchozí relace byl právě ukončen
        zc.reset_session()
        if held_open:   # dveře otevřené, dokud zámek předchozí relace držel → pokračování (pozdní otevření), ne poplach
            # nová relace bez ACCESS_GRANTED → bez fáze tachometru (server ji spáruje s posledním grantem rezervace)
            zc.latch_released, zc._late_booking = True, (booking_id, kind, source, new_session())
        await zc.evaluate_locked()               # otevřené dveře / offline modul → příslušná porucha
        return False, reason
    zc.booking_id = booking_id
    zc.session_ctx = new_session(detail)          # session_id + fáze grantu → i DOOR_* / SESSION_COMPLETED / OPEN_TIMEOUT
    zc.state = ZoneState.WAITING_FOR_OPEN
    zc.session_started = zc.waiting_since = zc.clock()
    zc.session_started_at = now_iso()
    await zc.emit_event(EventKind.ACCESS_GRANTED, message=f"{zc.zone.display_name}: přístup povolen ({kind})",
                        code_kind=kind, **detail)
    await zc.evaluate_locked()                   # dveře otevřené už během pulzu → DOOR_OPEN (ne forced_open)
    return True, "ok"


async def tick_locked(zc: "ZoneController") -> None:
    """Časové přechody: držený zámek, timeout otevření, overtime, doběh hudby/světla po zavření."""
    now = zc.clock()
    t = zc.timings
    if zc.lock_held and zc.state != ZoneState.WAITING_FOR_OPEN:
        if zc.state in (ZoneState.DOOR_OPEN, ZoneState.CLOSED_CONFIRMATION):
            await release_lock_if_due(zc, "min_hold")     # minimum od kódu uplynulo (dveře už otevřené)
        else:
            await release_lock(zc, "konec relace")        # pojistka: mimo relaci zámek nikdy nedrží
    if zc.state == ZoneState.WAITING_FOR_OPEN and zc.waiting_since is not None:
        limit = open_timeout_s(zc)
        if now - zc.waiting_since > limit:
            zc.state = ZoneState.SECURED         # nejdřív stav, teprve pak pomalé HW kroky
            await release_lock(zc, "timeout")
            # Zámek IBFM zůstává mechanicky odjištěný do prvního otevření (SPEC §2) → pozdní otevření
            # dveří je pokračování této relace (zone._late_open_locked), ne násilné otevření.
            zc._late_booking = (zc.booking_id, zc.code_kind, zc.source, dict(zc.session_ctx))
            zc.latch_released = True
            await zc.music_stop()
            await zc.set_light(False)
            await zc.signal(Signal.RED)
            await zc.emit_event(EventKind.OPEN_TIMEOUT, success=False, level="warn",
                                message=f"{zc.zone.display_name}: dveře nebyly otevřeny do {limit} s")
            zc.reset_session()
            await zc.evaluate_locked()           # dveře otevřené během pomalých kroků → pozdní otevření hned
    elif zc.state == ZoneState.DOOR_OPEN and zc.opened_at is not None:
        await _tick_door_open(zc, now - zc.opened_at)
    elif zc.state == ZoneState.CLOSED_CONFIRMATION and zc.closed_at is not None:
        elapsed = now - zc.closed_at
        if not zc.music_done and elapsed >= t.music_after_close_s:
            zc.music_done = True
            await zc.music_stop()
        if elapsed >= t.light_after_close_s:
            if lock_unlocked(zc):
                # Zámek ještě drží minimum od kódu (+ dozvuk po vypnutí) → dveře jdou legálně znovu otevřít: relace trvá
                # (znovuotevření = DOOR_OPEN téže relace, nikdy FORCED_OPEN), SECURED až potom; jinak jako po SECURED.
                await lock_wait(zc)
                return
            off_now = zc.light_off_on_secure     # kód motorky přišel v doběhu → světlo šatny po SECURED nedržet
            zc.state = ZoneState.SECURED
            zc.reset_session()
            await zc.music_stop()
            if zc.light_until_moto_code and zc.light_on and not off_now:
                zc.light_hold_since = now        # šatna: světlo drží, zhasne ho kód motorky (nebo pojistka níže)
            else:
                await zc.set_light(False)
            await zc.signal(Signal.RED)          # idempotentní — jistota, že SECURED = červená
            log.info("Zóna %s: relace uzavřena, SECURED", zc.number)
            await zc.evaluate_locked()           # modul offline během relace (degraded) → teď už porucha
    elif zc.state == ZoneState.SECURED and zc.light_hold_since is not None:
        # Pojistka drženého světla šatny: zákazník kód motorky nezadal (odešel) → po maximum_session_s zhasnout.
        if not zc.light_on:
            zc.light_hold_since = None
        elif now - zc.light_hold_since >= t.maximum_session_s:
            zc.light_hold_since = None
            await zc.set_light(False)
            log.info("Zóna %s: držené světlo zhaslo po %d s bez kódu motorky", zc.number, t.maximum_session_s)


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
