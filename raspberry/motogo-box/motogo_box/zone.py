"""Stavový automat jedné zóny (kóje) — kontrakt §11, specifikace §9 a §12.

Zóna nikdy nesepne zámek jinak než HW pulzem uvnitř `grant_access`, hudbu
ovládá výhradně přes `AudioController` a všechny časy měří injektovanými
hodinami `clock()` (výchozí `time.monotonic`), takže je plně testovatelná.

Souběh: VŠECHNY přechody stavu (vyhodnocení kontaktu, časové přechody v `tick`,
`grant_access`, `startup`, `force_secure`) běží pod zámkem `_busy`, takže se
žádný přechod nemůže prolnout s jiným ani přepsat jeho výsledek po pomalé
HW operaci (fade hudby, Modbus, Shelly). `on_input` a `tick` zámek NEČEKAJÍ:
pokud právě probíhá přechod, jen si zaznamenají hodnotu kontaktu a skončí —
držitel zámku kontakt vyhodnotí sám po dokončení a další poll/tick (≤ 250 ms)
to zopakuje. Poll/tick smyčky ostatních zón tak nikdy nestojí.

Debounce: poller předává už softwarově odfiltrovanou hodnotu kontaktu
(`on_input`), zóna si navíc sama hlídá `forced_open_debounce_ms` a
`door_close_debounce_ms` — pamatuje si čas první změny a přechod provede až
po uplynutí příslušné doby (vyhodnocuje se v `on_input` i v `tick`).

Dostupnost I/O (§7, §12): zóna je v poruše `io_offline` nejen při výpadku
modulu kontaktu (hodnota None), ale i modulu zámku, světla nebo Shelly
signalizace (`io_ready()` — kontroluje se při každém vyhodnocení).
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import TYPE_CHECKING, Awaitable, Callable

from . import zone_access
from .models import Event, EventKind, Signal, Zone, ZoneState, ZoneStatus, now_iso

if TYPE_CHECKING:  # pragma: no cover — jen typy, moduly píší jiné části programu
    from .audio import AudioController
    from .config import HardwareConfig
    from .io_devices import IoBus
    from .shelly import SignalController

log = logging.getLogger("motogo.zone")

EventSink = Callable[[Event], Awaitable[None]]

FAULT_IO_OFFLINE = "io_offline"
FAULT_FORCED_OPEN = "forced_open"
FAULT_OPEN_AT_STARTUP = "open_at_startup"
ACTIVE_STATES = (ZoneState.WAITING_FOR_OPEN, ZoneState.DOOR_OPEN, ZoneState.CLOSED_CONFIRMATION)


class ZoneController:
    """Řídí jednu zónu: kontakt, zámek (HW pulz), bílé světlo, signalizaci a hudbu."""

    def __init__(self, zone: Zone, io: "IoBus", signals: "SignalController", audio: "AudioController",
                 hw: "HardwareConfig", emit: EventSink,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.zone = zone
        self.io = io
        self.signals = signals
        self.audio = audio
        self.hw = hw
        self.emit = emit
        self.clock = clock
        self.lock_gate: asyncio.Lock = asyncio.Lock()   # controller nahradí sdíleným zámkem pulzů
        self.state: ZoneState = ZoneState.SECURED
        self.fault: str | None = None
        self.door_closed: bool | None = None
        self.booking_id: str | None = None
        self.light_on: bool = False
        self.session_started: float | None = None
        self.session_started_at: str | None = None
        self.overtime: bool = False
        self.last_event: str | None = None
        self.code_kind: str | None = None
        self.source: str | None = None
        self._input_changed_at: float | None = None   # čas první změny hodnoty kontaktu
        self.waiting_since: float | None = None
        self.opened_at: float | None = None
        self.closed_at: float | None = None
        self.music_done: bool = False
        self.alerts_sent: set[int] = set()
        # IBFM 9500 zůstává po pulzu mechanicky odjištěný až do prvního otevření (SPEC §2):
        # po OPEN_TIMEOUT je otevření dveří opožděné pokračování relace, ne násilné otevření.
        self.latch_released: bool = False
        self._late_booking: tuple | None = None       # (booking_id, code_kind, source) relace po timeoutu
        self.degraded: bool = False                    # relace běží, ale část I/O je offline (§12: jen zákaz nového přístupu)
        self._busy = asyncio.Lock()                    # serializuje všechny přechody stavu

    # ─── pomocné ─────────────────────────────────────────────────────────────
    @property
    def number(self) -> int:
        return self.zone.number

    @property
    def timings(self):
        return self.hw.timings

    def status(self) -> ZoneStatus:
        return ZoneStatus(
            zone=self.number, door_id=self.zone.door_id, box_number=self.zone.box_number,
            kind=self.zone.kind, label=self.zone.display_name, state=self.state.value,
            door_closed=self.door_closed, fault=self.fault, light=self.light_on,
            signal=self.signals.current(self.number).value,
            music=self._music_playing(),
            session_started_at=self.session_started_at, booking_id=self.booking_id,
            last_event=self.last_event, latch_released=self.latch_released, degraded=self.degraded,
        )

    def _music_playing(self) -> bool:
        """Hraje hudba v této zóně (`audio.is_playing`; starší engine/fake jen `playing_zone`)."""
        is_playing = getattr(self.audio, "is_playing", None)
        return bool(is_playing(self.number)) if is_playing is not None else self.audio.playing_zone == self.number

    def io_problems(self) -> list[str]:
        """Nedostupné/chybějící I/O zóny (prázdný seznam = vše online): zámek, kontakt, světlo, Shelly."""
        z = self.zone.hw
        out: list[str] = []
        for role, ref in (("lock", z.lock), ("contact", z.contact), ("light", z.light)):
            if ref is None:
                out.append(f"{role} nenastaven")
            elif not self.io.is_online(ref.dev) and ref.dev not in out:
                out.append(ref.dev)
        for ref in (z.red, z.green):
            if ref is not None and not self.signals.online(ref.dev) and ref.dev not in out:
                out.append(ref.dev)
        return out

    def io_ready(self) -> bool:
        """Online zámkový modul, modul kontaktu, modul světla a Shelly signalizace (pokud jsou definované)."""
        return not self.io_problems()

    async def emit_event(self, kind: EventKind, *, success: bool = True, level: str = "info",
                         message: str = "", **detail) -> None:
        self.last_event = kind.value
        ev = Event(kind=kind, zone=self.number, door_id=self.zone.door_id, booking_id=self.booking_id,
                   success=success, level=level, message=message or f"{kind.value} {self.zone.display_name}",
                   detail={"source": self.source, **detail}, box_number=self.zone.box_number,
                   code_kind=self.code_kind)
        try:
            await self.emit(ev)
        except Exception:  # noqa: BLE001 — logování nesmí shodit automat
            log.exception("Zóna %s: emit %s selhal", self.number, kind.value)

    async def signal(self, signal: Signal) -> None:
        try:
            await self.signals.set(self.zone.hw, signal)
        except Exception:  # noqa: BLE001
            log.exception("Zóna %s: signalizace %s selhala", self.number, signal.value)

    async def music_stop(self) -> None:
        """Zastaví hudbu jen pokud právě hraje v této zóně (exkluzivita reproduktoru).

        Kontrola „hraje tady?“ běží POD zámkem audia (`stop_zone`), aby čekající stop
        nevypnul hudbu zóně, která reproduktor mezitím převzala (§13.7).
        """
        try:
            stop_zone = getattr(self.audio, "stop_zone", None)
            if stop_zone is not None:
                await stop_zone(self.number)
            elif self.audio.playing_zone == self.number:
                await self.audio.stop()
        except Exception:  # noqa: BLE001
            log.exception("Zóna %s: zastavení hudby selhalo", self.number)

    async def _light_off_if_on(self) -> None:
        """Fyzicky zhasne světlo, pokud si o něm zóna myslí, že svítí (stav SW = stav HW)."""
        if self.light_on:
            await self.set_light(False)

    def reset_session(self) -> None:
        self.booking_id = None
        self.code_kind = None            # audit mimo relaci (forced_open, kontakt) nesmí nést druh kódu minulé relace
        self.source = None
        self.session_started = None
        self.session_started_at = None
        self.overtime = False
        self.waiting_since = None
        self.opened_at = None
        self.closed_at = None
        self.music_done = False
        self.alerts_sent = set()

    # ─── start a vstup kontaktu ─────────────────────────────────────────────
    async def startup(self, door_closed: bool | None) -> None:
        """§12 kroky 6–7: zavřené+funkční → SECURED + RED; None / I/O offline → FAULT io_offline;
        otevřené → FAULT open_at_startup."""
        async with self._busy:
            await self._startup_locked(door_closed)

    async def _startup_locked(self, door_closed: bool | None) -> None:
        self.door_closed = door_closed
        self._input_changed_at = self.clock()
        self.reset_session()
        self.latch_released, self._late_booking, self.degraded = False, None, False
        await self._light_off_if_on()          # obnova uprostřed relace: světlo skutečně zhasnout
        self.light_on = False
        problems = self.io_problems()
        if door_closed is None or problems:
            await self._enter_io_offline(problems)
        elif door_closed:
            self.state, self.fault = ZoneState.SECURED, None
            await self.signal(Signal.RED)
            log.info("Zóna %s: start — zavřeno, SECURED", self.number)
        else:
            self.state, self.fault = ZoneState.FAULT, FAULT_OPEN_AT_STARTUP
            await self.signal(Signal.RED_BLINK)
            await self.emit_event(EventKind.CONTACT_FAULT, success=False, level="error",
                             message=f"{self.zone.display_name}: dveře otevřené při startu", reason=self.fault)

    async def _enter_io_offline(self, problems: list[str]) -> None:
        """FAULT io_offline: hudba stop, světlo zhasnout (je-li jeho modul online), BOTH_BLINK, událost."""
        self.state, self.fault = ZoneState.FAULT, FAULT_IO_OFFLINE
        await self.music_stop()
        await self._light_off_if_on()
        await self.signal(Signal.BOTH_BLINK)
        what = ", ".join(problems) if problems else "modul kontaktu"
        await self.emit_event(EventKind.IO_OFFLINE, success=False, level="warn",
                         message=f"{self.zone.display_name}: I/O nedostupné ({what})",
                         reason=self.fault, devices=problems)

    async def on_input(self, door_closed: bool | None) -> None:
        """Přijme sw-debounced hodnotu kontaktu (True zavřeno / False otevřeno / None offline).

        Probíhá-li právě přechod (zámek držen), hodnota se jen zaznamená — držitel ji
        vyhodnotí po dokončení (a další poll ji zopakuje); poll smyčka tak neblokuje.
        """
        if door_closed != self.door_closed:
            self.door_closed = door_closed
            self._input_changed_at = self.clock()
        if self._busy.locked():
            return
        async with self._busy:
            await self.evaluate_locked()

    async def evaluate_locked(self) -> None:
        """Vyhodnotí přechody závislé na kontaktu a dostupnosti I/O (volat POD `_busy`)."""
        closed = self.door_closed
        problems = self.io_problems()
        # §12: výpadek Modbus/Shelly = zákaz NOVÉHO přístupu. Běžící relaci (kontakt čitelný) nerušit —
        # zhasnout světlo zákazníkovi v kóji by bylo horší než chybějící signalizace/zámek (pulz už byl).
        if closed is None or (problems and self.state not in ACTIVE_STATES):
            if self.fault != FAULT_IO_OFFLINE:
                await self._enter_io_offline(problems)
            return
        if problems and not self.degraded:
            self.degraded = True
            log.warning("Zóna %s: I/O částečně offline během relace (%s) — relace pokračuje, nový přístup zakázán",
                        self.number, ", ".join(problems))
        elif not problems:
            self.degraded = False
        if self.fault == FAULT_IO_OFFLINE:
            await self.emit_event(EventKind.IO_ONLINE, message=f"{self.zone.display_name}: I/O opět online")
            await self._startup_locked(closed)
            return
        stable_ms = (self.clock() - (self._input_changed_at or 0.0)) * 1000.0
        if self.state == ZoneState.SECURED and not closed:
            if self.latch_released:
                await self._late_open_locked()
            elif stable_ms >= self.timings.forced_open_debounce_ms:
                self.state, self.fault = ZoneState.FAULT, FAULT_FORCED_OPEN
                await self.signal(Signal.RED_BLINK)
                await self.emit_event(EventKind.FORCED_OPEN, success=False, level="error", source="contact",
                                 message=f"{self.zone.display_name}: dveře otevřeny bez přístupu", reason=self.fault)
        elif self.state == ZoneState.FAULT and closed and self.fault in (FAULT_FORCED_OPEN, FAULT_OPEN_AT_STARTUP):
            self.state, self.fault = ZoneState.SECURED, None
            await self.signal(Signal.RED)
            await self.emit_event(EventKind.DOOR_CLOSED, message=f"{self.zone.display_name}: dveře zavřeny (porucha odezněla)")
        elif self.state == ZoneState.WAITING_FOR_OPEN and not closed:
            self.state = ZoneState.DOOR_OPEN
            self.latch_released = False          # otevřením se zámek mechanicky vrátil do zajištěného stavu
            self.opened_at = self.clock()
            await self.emit_event(EventKind.DOOR_OPENED, message=f"{self.zone.display_name}: dveře otevřeny")
        elif self.state == ZoneState.DOOR_OPEN and closed:
            if stable_ms >= self.timings.door_close_debounce_ms:
                self.state = ZoneState.CLOSED_CONFIRMATION
                self.closed_at = self.clock()
                self.music_done = False
                await self.signal(Signal.RED)
                await self.emit_event(EventKind.DOOR_CLOSED, message=f"{self.zone.display_name}: dveře zavřeny")
                await self.emit_event(EventKind.SESSION_COMPLETED, overtime=self.overtime,
                                      message=f"{self.zone.display_name}: relace dokončena")
        elif self.state == ZoneState.CLOSED_CONFIRMATION and not closed:
            self.state = ZoneState.DOOR_OPEN     # stejná relace pokračuje
            self.closed_at = None
            await self.signal(Signal.GREEN_PULSE if self.overtime else Signal.GREEN)
            await self.emit_event(EventKind.DOOR_OPENED, message=f"{self.zone.display_name}: dveře znovu otevřeny")

    async def _late_open_locked(self) -> None:
        """Otevření po OPEN_TIMEOUT (zámek zůstal odjištěný, SPEC §2): pokračování povolené relace."""
        booking, kind, source = self._late_booking or (None, None, None)
        self.latch_released, self._late_booking = False, None
        self.booking_id, self.code_kind, self.source = booking, kind, source or "contact"
        self.state = ZoneState.DOOR_OPEN
        self.session_started = self.opened_at = self.clock()
        self.session_started_at = now_iso()
        await self.set_light(True)
        await self.signal(Signal.GREEN)
        await self.emit_event(EventKind.DOOR_OPENED, level="warn", late_open=True,
                              message=f"{self.zone.display_name}: dveře otevřeny po vypršení čekání (zámek byl odjištěný)")
        try:
            await self.audio.play_zone(self.number)
        except Exception:  # noqa: BLE001
            log.exception("Zóna %s: spuštění hudby selhalo", self.number)

    # ─── přístup ────────────────────────────────────────────────────────────
    async def grant_access(self, *, booking_id: str | None, kind: str, source: str) -> tuple[bool, str]:
        """§9 „Platný PIN" kroky 4–12. Vrací (True,'ok') nebo (False, důvod).

        Celý průběh drží `_busy`: souběžný druhý požadavek na tutéž zónu počká a dostane
        'busy'; tick ani vyhodnocení kontaktu nemohou relaci během pomalých kroků přepsat.
        """
        async with self._busy:
            await self.evaluate_locked()       # čerstvý stav kontaktu / I/O před rozhodnutím
            if not self.io_ready():
                return False, "io_offline"
            if self.fault:
                return False, "fault"
            if self.state in (ZoneState.WAITING_FOR_OPEN, ZoneState.DOOR_OPEN):
                return False, "busy"
            if self.door_closed is not True:
                return False, "door_open"
            return await zone_access.grant_locked(self, booking_id, kind, source)

    # ─── časové přechody ────────────────────────────────────────────────────
    async def tick(self) -> None:
        """Periodické vyhodnocení timeoutů (volá controller každých 250 ms).

        Probíhá-li právě jiný přechod, tick se přeskočí (další za 250 ms) — nikdy
        nesmí přepsat stav rozpracovaného přechodu ani blokovat tick ostatních zón.
        """
        if self._busy.locked():
            return
        async with self._busy:
            await self.evaluate_locked()
            await zone_access.tick_locked(self)

    # ─── servisní ovládání ──────────────────────────────────────────────────
    async def force_secure(self) -> None:
        """All-off zóny: hudba (jen když hraje tady), světlo, signalizace a stav dle kontaktu/I/O."""
        async with self._busy:
            await self.music_stop()
            await self.set_light(False)
            self.reset_session()
            self.latch_released, self._late_booking, self.degraded = False, None, False
            if self.door_closed is None or not self.io_ready():
                self.state, self.fault = ZoneState.FAULT, FAULT_IO_OFFLINE
                await self.signal(Signal.BOTH_BLINK)
            elif self.door_closed:
                self.state, self.fault = ZoneState.SECURED, None
                await self.signal(Signal.RED)
            else:
                self.state, self.fault = ZoneState.FAULT, FAULT_FORCED_OPEN
                await self.signal(Signal.RED_BLINK)

    async def set_light(self, on: bool) -> bool:
        ref = self.zone.hw.light
        if ref is None:
            return False
        try:
            ok = bool(await self.io.set(ref, on))
        except Exception:  # noqa: BLE001
            log.exception("Zóna %s: světlo %s selhalo", self.number, on)
            ok = False
        if ok:
            self.light_on = on
        return ok

    async def set_signal(self, signal: Signal) -> None:
        """Ruční override signalizace (Velín) — platí do další změny stavu zóny."""
        await self.signal(signal)

    def expected_signal(self) -> Signal:
        """Vzor signalizace odpovídající aktuálnímu stavu zóny (SPEC §7)."""
        if self.state == ZoneState.FAULT:
            return Signal.BOTH_BLINK if self.fault == FAULT_IO_OFFLINE else Signal.RED_BLINK
        if self.state == ZoneState.DOOR_OPEN:
            return Signal.GREEN_PULSE if self.overtime else Signal.GREEN
        if self.state == ZoneState.WAITING_FOR_OPEN:
            return Signal.GREEN
        return Signal.RED          # SECURED i CLOSED_CONFIRMATION (červená hned po zavření)

    async def refresh_signal(self) -> None:
        """Obnoví signalizaci podle skutečného stavu (po identify / dočasném overridu)."""
        await self.signal(self.expected_signal())

    async def test_sequence(self) -> dict:
        """Servisní test BEZ zámku: světlo → GREEN 1 s → obnovit signál i světlo; audio 3 s.

        Odmítne se, když v zóně běží relace (zákazníkovi nesmí zhasnout světlo ani zmizet hudba);
        audio se testuje jen pokud reproduktor nikdo nepoužívá.
        """
        async with self._busy:                    # nesmí se prolnout s tickem/relací
            if self.state in ACTIVE_STATES:
                return {"error": "busy", "light": False, "signal": False, "audio": False}
            prev_light = self.light_on
            light = False
            try:
                light = await self.set_light(True)
                await self.signal(Signal.GREEN)
                await asyncio.sleep(1.0)
            finally:
                # i při zrušení (timeout diagnostiky) se signál i světlo vždy vrátí do původního stavu
                await self.refresh_signal()
                light = await self.set_light(prev_light) and light
            z = self.zone.hw
            signal_ok = all(self.signals.online(r.dev) for r in (z.red, z.green) if r is not None)
            audio_ok = False
            if self.audio.playing_zone is None:
                try:
                    audio_ok = bool(await self.audio.test_tone(self.number, 3))
                except Exception:  # noqa: BLE001
                    log.exception("Zóna %s: audio test selhal", self.number)
            else:
                log.info("Zóna %s: audio test přeskočen — reproduktor používá zóna %s", self.number, self.audio.playing_zone)
        return {"light": light, "signal": signal_ok, "audio": audio_ok}
