"""Testy stavového automatu zóny (`motogo_box.zone.ZoneController`) s in-memory fakes."""
from __future__ import annotations

import asyncio
import os

import pytest

from motogo_box.config import HardwareConfig, load_hardware_file
from motogo_box.models import Event, EventKind, HwRef, Signal, ZoneHw, ZoneState
from motogo_box.zone import ZoneController

HW_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "brno-9zone.yaml")


# ─── fakes ───────────────────────────────────────────────────────────────────
class Clock:
    def __init__(self, t: float = 1000.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t

    def advance(self, s: float) -> None:
        self.t += s


class FakeIo:
    """In-memory IoBus: coils dict, seznam pulzů, online sada modulů."""

    def __init__(self, online: bool = True, pulse_ok: bool = True, set_ok: bool = True) -> None:
        self.coils: dict[tuple[str, int], bool] = {}
        self.pulses: list[tuple[HwRef, int]] = []
        self.online = online
        self.offline_devs: set[str] = set()      # per-modul výpadek (např. jen wav645)
        self.pulse_ok = pulse_ok
        self.set_ok = set_ok
        self.on_pulse = None                      # volitelný hook: souběh během pulzu

    def is_online(self, name: str) -> bool:
        return self.online and name not in self.offline_devs

    async def set(self, ref: HwRef, on: bool) -> bool:
        if not self.online or not self.set_ok:
            return False
        self.coils[(ref.dev, ref.idx)] = on
        return True

    async def pulse(self, ref: HwRef, ms: int) -> bool:
        self.pulses.append((ref, ms))
        if self.on_pulse is not None:
            await self.on_pulse()
        return self.is_online(ref.dev) and self.pulse_ok


class FakeSignals:
    def __init__(self) -> None:
        self.calls: list[tuple[int, Signal]] = []
        self._cur: dict[int, Signal] = {}

    def current(self, zone: int) -> Signal:
        return self._cur.get(zone, Signal.OFF)

    def online(self, name: str) -> bool:
        return True

    async def set(self, zone_hw: ZoneHw, signal: Signal) -> None:
        self.calls.append((zone_hw.zone, signal))
        self._cur[zone_hw.zone] = signal


class FakeAudio:
    def __init__(self) -> None:
        self.playing_zone: int | None = None
        self.stops = 0

    async def play_zone(self, zone: int) -> bool:
        self.playing_zone = zone
        return True

    async def stop(self, fade: bool = True) -> None:
        self.playing_zone = None
        self.stops += 1

    async def test_tone(self, zone: int, seconds: int = 5) -> bool:
        return True


class Rig:
    """Sestava zóny 1 z brno mapy + fakes + sběr událostí."""

    def __init__(self, **io_kw) -> None:
        self.hw = HardwareConfig.from_dict(load_hardware_file(HW_FILE))
        self.hw.timings.lock_pulse_ms = 10   # ať test nečeká 800 ms reálného času
        self.zone = self.hw.zone_by_number(1)
        self.io = FakeIo(**io_kw)
        self.signals = FakeSignals()
        self.audio = FakeAudio()
        self.clock = Clock()
        self.events: list[Event] = []

        async def emit(ev: Event) -> None:
            self.events.append(ev)

        self.zc = ZoneController(self.zone, self.io, self.signals, self.audio, self.hw, emit, clock=self.clock)

    def kinds(self) -> list[EventKind]:
        return [e.kind for e in self.events]

    def light(self) -> bool | None:
        ref = self.zone.hw.light
        return self.io.coils.get((ref.dev, ref.idx))

    def lock_coil_touched(self) -> bool:
        ref = self.zone.hw.lock
        return (ref.dev, ref.idx) in self.io.coils


async def rig_secured(**io_kw) -> Rig:
    r = Rig(**io_kw)
    await r.zc.startup(True)
    assert r.zc.state == ZoneState.SECURED and r.signals.current(1) == Signal.RED
    return r


async def rig_door_open() -> Rig:
    r = await rig_secured()
    ok, reason = await r.zc.grant_access(booking_id="b-1", kind="motorcycle", source="ui")
    assert (ok, reason) == (True, "ok")
    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN
    return r


# ─── testy ───────────────────────────────────────────────────────────────────
async def test_full_session_pass():
    r = await rig_secured()
    ok, reason = await r.zc.grant_access(booking_id="b-1", kind="motorcycle", source="ui")
    assert (ok, reason) == (True, "ok")
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN and r.zc.booking_id == "b-1"
    assert r.io.pulses == [(r.zone.hw.lock, 10)]          # zámek VÝHRADNĚ pulzem
    assert not r.lock_coil_touched()                       # nikdy io.set na zámek
    assert r.light() is True and r.audio.playing_zone == 1
    assert r.signals.current(1) == Signal.GREEN
    assert r.kinds()[-1] == EventKind.ACCESS_GRANTED
    ev = r.events[-1]
    assert ev.zone == 1 and ev.booking_id == "b-1" and ev.code_kind == "motorcycle" and ev.detail["source"] == "ui"

    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN and r.kinds()[-1] == EventKind.DOOR_OPENED

    await r.zc.on_input(True)                              # zavřeno, ale ještě ne stabilně 1 s
    assert r.zc.state == ZoneState.DOOR_OPEN
    r.clock.advance(1.1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    assert r.signals.current(1) == Signal.RED
    assert r.kinds()[-2:] == [EventKind.DOOR_CLOSED, EventKind.SESSION_COMPLETED]
    assert r.audio.playing_zone == 1 and r.light() is True

    r.clock.advance(10.0)                                  # hudba po 10 s
    await r.zc.tick()
    assert r.audio.playing_zone is None and r.light() is True
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION

    r.clock.advance(20.5)                                  # světlo po 30 s → SECURED
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.light() is False
    assert r.zc.booking_id is None and r.zc.session_started is None
    assert r.zc.status().state == "SECURED" and r.zc.status().music is False


async def test_open_timeout_returns_to_secured():
    r = await rig_secured()
    assert (await r.zc.grant_access(booking_id="b-2", kind="accessories", source="ui"))[0]
    r.clock.advance(29.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN
    r.clock.advance(2.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED
    assert r.light() is False and r.audio.playing_zone is None
    assert r.signals.current(1) == Signal.RED
    assert r.kinds()[-1] == EventKind.OPEN_TIMEOUT and r.events[-1].success is False
    assert r.zc.booking_id is None
    assert len(r.io.pulses) == 1


async def test_forced_open_and_return():
    r = await rig_secured()
    await r.zc.on_input(False)                             # otevřeno bez přístupu, debounce 500 ms
    assert r.zc.state == ZoneState.SECURED
    r.clock.advance(0.6)
    await r.zc.tick()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "forced_open"
    assert r.signals.current(1) == Signal.RED_BLINK
    assert r.kinds()[-1] == EventKind.FORCED_OPEN and r.events[-1].success is False
    assert (await r.zc.grant_access(booking_id=None, kind="service", source="velin")) == (False, "fault")
    await r.zc.on_input(True)
    assert r.zc.state == ZoneState.SECURED and r.zc.fault is None
    assert r.signals.current(1) == Signal.RED and r.kinds()[-1] == EventKind.DOOR_CLOSED


async def test_io_offline_denies_access_and_blinks():
    r = Rig(online=False)
    await r.zc.startup(True)                               # kontakt zavřený, ale moduly offline → porucha
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.signals.current(1) == Signal.BOTH_BLINK and r.kinds() == [EventKind.IO_OFFLINE]
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "io_offline")
    assert r.io.pulses == []
    await r.zc.on_input(None)
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    await r.zc.on_input(None)                              # opakování bez dalších událostí
    assert r.kinds().count(EventKind.IO_OFFLINE) == 1
    r.io.online = True
    await r.zc.on_input(True)                              # návrat hodnoty → startup
    assert r.zc.state == ZoneState.SECURED and r.zc.fault is None
    assert EventKind.IO_ONLINE in r.kinds() and r.signals.current(1) == Signal.RED


async def test_contact_module_only_offline_then_back():
    r = await rig_secured()
    await r.zc.on_input(None)                              # modul kontaktu vypadl (hodnota None)
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.signals.current(1) == Signal.BOTH_BLINK and r.kinds()[-1] == EventKind.IO_OFFLINE
    await r.zc.on_input(True)
    assert r.zc.state == ZoneState.SECURED and r.kinds()[-1] != EventKind.IO_OFFLINE
    assert EventKind.IO_ONLINE in r.kinds()


async def test_startup_variants():
    r = Rig()
    await r.zc.startup(None)
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.signals.current(1) == Signal.BOTH_BLINK
    r2 = Rig()
    await r2.zc.startup(False)
    assert r2.zc.state == ZoneState.FAULT and r2.zc.fault == "open_at_startup"
    assert r2.signals.current(1) == Signal.RED_BLINK and r2.kinds() == [EventKind.CONTACT_FAULT]
    await r2.zc.on_input(True)
    assert r2.zc.state == ZoneState.SECURED


async def test_overtime_after_maximum_session():
    r = await rig_door_open()
    r.clock.advance(599.0)
    await r.zc.tick()
    assert r.zc.overtime is False and r.audio.playing_zone == 1
    r.clock.advance(2.0)
    await r.zc.tick()
    assert r.zc.overtime is True and r.zc.state == ZoneState.DOOR_OPEN
    assert r.signals.current(1) == Signal.GREEN_PULSE
    assert r.audio.playing_zone is None
    assert r.kinds()[-1] == EventKind.SESSION_OVERTIME and r.events[-1].level == "warn"
    assert r.light() is True                               # světlo lze ponechat
    r.clock.advance(599.0)                                 # otevřeno 20 min
    await r.zc.tick()
    await r.zc.tick()
    alerts = [e for e in r.events if e.kind == EventKind.SESSION_OVERTIME_ALERT]
    assert [e.detail["open_min"] for e in alerts] == [20]  # 10 min = samotný SESSION_OVERTIME
    r.clock.advance(600.0)                                 # otevřeno 30 min
    await r.zc.tick()
    alerts = [e for e in r.events if e.kind == EventKind.SESSION_OVERTIME_ALERT]
    assert [e.detail["open_min"] for e in alerts] == [20, 30]
    # zavření po overtime → zelené pulzování končí, červená
    await r.zc.on_input(True)
    r.clock.advance(1.5)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.signals.current(1) == Signal.RED


async def test_closed_confirmation_music_then_light_then_secured():
    r = await rig_door_open()
    await r.zc.on_input(True)
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(9.5)
    await r.zc.tick()
    assert r.audio.playing_zone == 1                       # ještě hraje (< 10 s)
    r.clock.advance(0.6)
    await r.zc.tick()
    assert r.audio.playing_zone is None and r.audio.stops == 1
    r.clock.advance(19.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.light() is True
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.light() is False
    assert r.audio.stops == 1                              # stop se nevolá znovu, když nehraje


async def test_reopen_during_closed_confirmation_keeps_session():
    r = await rig_door_open()
    await r.zc.on_input(True)
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(5.0)
    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b-1"
    assert r.signals.current(1) == Signal.GREEN and r.kinds()[-1] == EventKind.DOOR_OPENED
    r.clock.advance(30.0)                                  # doběh se po znovuotevření neuplatní
    await r.zc.tick()
    assert r.zc.state == ZoneState.DOOR_OPEN and r.light() is True
    assert len(r.io.pulses) == 1


async def test_music_stop_only_when_this_zone_plays():
    r = await rig_door_open()
    r.audio.playing_zone = 2                               # reproduktor převzala jiná zóna
    await r.zc.on_input(True)
    r.clock.advance(1.0)
    await r.zc.tick()
    r.clock.advance(31.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED
    assert r.audio.stops == 0 and r.audio.playing_zone == 2


async def test_grant_refused_when_busy_or_door_open():
    r = await rig_secured()
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui"))[0]
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "busy")
    await r.zc.on_input(False)
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "busy")
    assert len(r.io.pulses) == 1


async def test_lock_pulse_failure_rolls_back():
    r = await rig_secured(pulse_ok=False)
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "lock_failed")
    assert r.zc.state == ZoneState.SECURED and r.light() is False
    assert r.signals.current(1) == Signal.RED and r.audio.playing_zone is None
    assert EventKind.ACCESS_GRANTED not in r.kinds()


async def test_light_failure_is_not_blocking():
    r = await rig_secured(set_ok=False)
    ok, reason = await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")
    assert (ok, reason) == (True, "ok")
    assert r.events[-1].detail.get("light_failed") is True and r.zc.light_on is False


async def test_force_secure_resets_zone():
    r = await rig_door_open()
    await r.zc.force_secure()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "forced_open"   # dveře otevřené bez relace
    assert r.audio.playing_zone is None and r.light() is False and r.zc.booking_id is None
    await r.zc.on_input(True)
    assert r.zc.state == ZoneState.SECURED
    await r.zc.force_secure()
    assert r.zc.state == ZoneState.SECURED and r.signals.current(1) == Signal.RED


async def test_status_payload():
    r = await rig_secured()
    st = r.zc.status().to_dict()
    assert st["zone"] == 1 and st["box_number"] == 1 and st["state"] == "SECURED"
    assert st["signal"] == "red" and st["door_closed"] is True and st["fault"] is None
    assert st["label"] == "Kóje 1" and st["music"] is False


@pytest.mark.parametrize("value", [True, False])
async def test_io_ready_reflects_modules(value):
    r = Rig(online=value)
    assert r.zc.io_ready() is value


# ─── nálezy review: souběh, výpadky modulů, světlo po obnově ─────────────────
async def test_light_physically_off_after_io_recovery_mid_session():
    """Výpadek kontaktu uprostřed relace (světlo svítí) → po obnově světlo skutečně zhasne."""
    r = await rig_door_open()
    assert r.light() is True and r.zc.light_on
    await r.zc.on_input(None)                              # krátký výpadek modulu kontaktu
    assert r.zc.fault == "io_offline" and r.audio.playing_zone is None
    assert r.light() is False and r.zc.light_on is False   # modul světla je online → zhasnuto hned
    r.io.coils[(r.zone.hw.light.dev, r.zone.hw.light.idx)] = True   # simulace: relé zůstalo sepnuté
    r.zc.light_on = True
    await r.zc.on_input(True)                              # návrat → startup(closed)
    assert r.zc.state == ZoneState.SECURED and r.zc.booking_id is None
    assert r.light() is False and r.zc.light_on is False   # SW stav = HW stav


async def test_lock_module_offline_signals_io_offline_per_zone():
    """Výpadek WAV645 (zámky) bez výpadku kontaktu → FAULT io_offline + BOTH_BLINK, po návratu SECURED."""
    r = await rig_secured()
    r.io.offline_devs.add("wav645")
    await r.zc.tick()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.signals.current(1) == Signal.BOTH_BLINK
    ev = r.events[-1]
    assert ev.kind == EventKind.IO_OFFLINE and "wav645" in ev.detail["devices"]
    assert r.zc.status().fault == "io_offline"
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "io_offline")
    await r.zc.tick()
    assert r.kinds().count(EventKind.IO_OFFLINE) == 1     # bez opakování
    r.io.offline_devs.clear()
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.fault is None
    assert r.signals.current(1) == Signal.RED and r.kinds()[-1:] != [EventKind.IO_OFFLINE]
    assert EventKind.IO_ONLINE in r.kinds()


async def test_shelly_offline_signals_io_offline():
    r = await rig_secured()
    r.signals.online = lambda name: name != r.zone.hw.red.dev   # type: ignore[method-assign]
    await r.zc.tick()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.zone.hw.red.dev in r.events[-1].detail["devices"]


async def test_lock_module_offline_mid_session_keeps_session_but_denies_new_access():
    """§12: výpadek WAV645 (pulz už proběhl) s otevřenými dveřmi → relace pokračuje (světlo svítí,
    hudba hraje, kontakt je čitelný), jen nový přístup je zakázán; po zavření a doběhu → io_offline."""
    r = await rig_door_open()
    r.io.offline_devs.add("wav645")
    await r.zc.tick()
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.fault is None and r.zc.degraded
    assert r.audio.playing_zone == 1 and r.light() is True and r.zc.light_on is True
    assert (await r.zc.grant_access(booking_id="b2", kind="motorcycle", source="ui")) == (False, "io_offline")
    await r.zc.on_input(True)
    r.clock.advance(1.5)
    await r.zc.on_input(True)                              # zavření po debounce → CLOSED_CONFIRMATION
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(31.0)
    await r.zc.tick()                                      # doběh světla → SECURED → modul stále offline → io_offline
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline" and r.light() is False


async def test_contact_module_offline_mid_session_aborts():
    """Výpadek modulu KONTAKTU (dveře nelze sledovat) relaci ukončí jako dřív: hudba stop, světlo zhasnout."""
    r = await rig_door_open()
    r.io.offline_devs.add(r.zone.hw.contact.dev)
    await r.zc.on_input(None)
    assert r.zc.fault == "io_offline" and r.audio.playing_zone is None and r.zc.light_on is False


async def test_concurrent_grant_access_only_one_wins():
    """Dva souběžné požadavky (UI PIN + Velín) → jeden 'ok', druhý 'busy'; jediný pulz a jediná událost."""
    r = await rig_secured()
    results = await asyncio.gather(
        r.zc.grant_access(booking_id="b-first", kind="motorcycle", source="ui"),
        r.zc.grant_access(booking_id="b-second", kind="service", source="velin"),
    )
    assert results == [(True, "ok"), (False, "busy")]
    assert len(r.io.pulses) == 1 and r.kinds().count(EventKind.ACCESS_GRANTED) == 1
    assert r.zc.booking_id == "b-first" and r.zc.state == ZoneState.WAITING_FOR_OPEN


async def test_door_opened_during_lock_pulse_is_door_opened_not_forced():
    """Zákazník zatlačí do dveří hned po odjištění (během 800ms pulzu) → DOOR_OPENED, žádný forced_open."""
    r = await rig_secured()

    async def open_during_pulse() -> None:
        # poll_loop během pulzu: kontakt otevřený, sw debounce i forced_open_debounce uplynuly
        await r.zc.on_input(False)
        r.clock.advance(0.8)
        await r.zc.on_input(False)
        await r.zc.tick()

    r.io.on_pulse = open_during_pulse
    ok, reason = await r.zc.grant_access(booking_id="b-1", kind="motorcycle", source="ui")
    assert (ok, reason) == (True, "ok")
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.fault is None and r.zc.booking_id == "b-1"
    assert EventKind.FORCED_OPEN not in r.kinds()
    assert r.kinds()[-2:] == [EventKind.ACCESS_GRANTED, EventKind.DOOR_OPENED]
    assert r.signals.current(1) == Signal.GREEN and r.light() is True
    # relace normálně doběhne a zóna zůstane použitelná
    await r.zc.on_input(True)
    r.clock.advance(1.1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(31.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.fault is None
    assert (await r.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui")) == (True, "ok")


async def test_door_forced_before_pulse_refuses_and_faults():
    """Dveře se otevřou (bez odjištění) během světla/hudby před pulzem → bez pulzu, 'door_open', pak forced_open."""
    r = await rig_secured()
    orig_play = r.audio.play_zone

    async def play_and_force(zone: int) -> bool:
        await r.zc.on_input(False)                         # kontakt otevřený uprostřed sekvence
        r.clock.advance(0.6)
        return await orig_play(zone)

    r.audio.play_zone = play_and_force                     # type: ignore[method-assign]
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui")) == (False, "door_open")
    assert r.io.pulses == [] and r.light() is False and r.audio.playing_zone is None
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "forced_open"
    assert r.signals.current(1) == Signal.RED_BLINK and EventKind.ACCESS_GRANTED not in r.kinds()


class SlowAudio(FakeAudio):
    """Audio, jehož stop/play čekají na uvolnění (simulace fade 0,7 s / 1,5 s)."""

    def __init__(self) -> None:
        super().__init__()
        self.gate = asyncio.Event()

    async def stop(self, fade: bool = True) -> None:
        await self.gate.wait()
        await super().stop(fade)

    async def play_zone(self, zone: int) -> bool:
        await self.gate.wait()
        return await super().play_zone(zone)


async def test_overtime_tick_serialized_with_door_close():
    """Dveře se zavřou během pomalého stopu hudby v overtime → nakonec CLOSED_CONFIRMATION + RED, ne GREEN_PULSE."""
    r = Rig()
    r.audio = SlowAudio()
    r.zc.audio = r.audio
    await r.zc.startup(True)
    r.audio.gate.set()
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui"))[0]
    await r.zc.on_input(False)
    r.clock.advance(601.0)
    r.audio.gate.clear()
    tick_task = asyncio.create_task(r.zc.tick())           # overtime: music_stop visí na fade
    await asyncio.sleep(0)
    assert r.zc.overtime is True
    await r.zc.on_input(True)                              # poll: zavřeno — jen zaznamenáno (zámek držen)
    r.clock.advance(1.5)
    await r.zc.tick()                                      # tick během přechodu se přeskočí
    assert r.zc.state == ZoneState.DOOR_OPEN
    r.audio.gate.set()
    await tick_task
    assert r.signals.current(1) == Signal.GREEN_PULSE and r.kinds()[-1] == EventKind.SESSION_OVERTIME
    await r.zc.tick()                                      # další tick: zavřeno stabilně → RED
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.signals.current(1) == Signal.RED
    assert r.signals.calls[-1] == (1, Signal.RED)


async def test_open_timeout_not_overwritten_by_concurrent_input():
    """Timeout 30 s s pomalým stopem hudby + souběžné otevření dveří → žádný stav navíc, konzistentní výsledek."""
    r = Rig()
    r.audio = SlowAudio()
    r.zc.audio = r.audio
    await r.zc.startup(True)
    r.audio.gate.set()
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui"))[0]
    r.clock.advance(31.0)
    r.audio.gate.clear()
    tick_task = asyncio.create_task(r.zc.tick())
    await asyncio.sleep(0)
    assert r.zc.state == ZoneState.SECURED                 # stav se přepnul atomicky před HW kroky
    await r.zc.on_input(False)                             # otevření během fade → jen zaznamenáno
    r.audio.gate.set()
    await tick_task
    # Zámek IBFM zůstal po pulzu odjištěný (SPEC §2): otevření po timeoutu = pozdní pokračování relace,
    # ne násilné otevření — jednotka rozsvítí, zelená, hudba, původní rezervace.
    assert EventKind.OPEN_TIMEOUT in r.kinds() and r.kinds()[-1] == EventKind.DOOR_OPENED
    assert r.events[-1].detail.get("late_open") is True and r.events[-1].level == "warn"
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b" and r.zc.code_kind == "motorcycle"
    assert r.light() is True and r.signals.current(1) == Signal.GREEN and r.audio.playing_zone == 1
    assert EventKind.FORCED_OPEN not in r.kinds()


async def test_late_open_after_timeout_is_not_forced_open():
    """Zákazník otevře dveře až 45 s po platném kódu (timeout 30 s) → pokračování relace, ne forced_open."""
    r = await rig_secured()
    assert (await r.zc.grant_access(booking_id="b", kind="motorcycle", source="ui"))[0]
    r.clock.advance(31.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.zc.latch_released and r.light() is False
    r.clock.advance(14.0)
    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b" and not r.zc.latch_released
    assert r.kinds()[-1] == EventKind.DOOR_OPENED and r.light() is True
    # zavření → normální dokončení relace; další otevření bez kódu = násilné (zámek už zajištěn)
    await r.zc.on_input(True)
    r.clock.advance(1.5)
    await r.zc.on_input(True)
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(31.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED
    await r.zc.on_input(False)
    r.clock.advance(1.0)
    await r.zc.on_input(False)
    assert r.zc.fault == "forced_open" and r.events[-1].detail.get("source") == "contact"


async def test_closed_confirmation_runoff_does_not_kill_new_access():
    """Opakovaný kód do téže kóje těsně před koncem doběhu: tick nesmí zhasnout/vypnout novou relaci."""
    r = Rig()
    r.audio = SlowAudio()
    r.zc.audio = r.audio
    await r.zc.startup(True)
    r.audio.gate.set()
    assert (await r.zc.grant_access(booking_id="b-1", kind="motorcycle", source="ui"))[0]
    await r.zc.on_input(False)
    await r.zc.on_input(True)
    r.clock.advance(1.1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(29.9)                                  # 0,1 s před koncem doběhu světla
    r.audio.gate.clear()
    grant = asyncio.create_task(r.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui"))
    await asyncio.sleep(0)
    r.clock.advance(1.0)                                   # doběh by teď uplynul
    await r.zc.tick()                                      # přeskočen — přístup drží zámek
    r.audio.gate.set()
    assert await grant == (True, "ok")
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN and r.zc.booking_id == "b-2"
    assert r.light() is True and r.audio.playing_zone == 1 and r.signals.current(1) == Signal.GREEN
    r.clock.advance(1.0)
    await r.zc.tick()
    assert r.zc.state == ZoneState.WAITING_FOR_OPEN        # starý doběh se už neuplatní


async def test_lock_failure_from_closed_confirmation_ends_runoff_cleanly():
    r = await rig_door_open()
    await r.zc.on_input(True)
    r.clock.advance(1.1)
    await r.zc.tick()
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.io.pulse_ok = False
    assert (await r.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui")) == (False, "lock_failed")
    assert r.zc.state == ZoneState.SECURED and r.light() is False and r.audio.playing_zone is None
    assert r.signals.current(1) == Signal.RED and r.zc.booking_id is None
    r.io.pulse_ok = True
    assert (await r.zc.grant_access(booking_id="b-3", kind="motorcycle", source="ui")) == (True, "ok")


async def test_input_during_transition_is_recorded_and_evaluated_later():
    r = await rig_secured()
    async with r.zc._busy:                                 # simulace probíhajícího přechodu
        await r.zc.on_input(False)                         # nesmí blokovat ani vyhodnocovat
        assert r.zc.door_closed is False and r.zc.state == ZoneState.SECURED
    r.clock.advance(0.6)
    await r.zc.tick()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "forced_open"


async def test_force_secure_reports_io_offline_when_module_down():
    r = await rig_secured()
    r.io.offline_devs.add("wav645")
    await r.zc.force_secure()
    assert r.zc.state == ZoneState.FAULT and r.zc.fault == "io_offline"
    assert r.signals.current(1) == Signal.BOTH_BLINK
