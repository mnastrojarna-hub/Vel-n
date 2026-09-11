"""Waveshare reléové moduly nad Modbus TCP (kontrakt §4, SPEC §5, §6, §12).

- `Wav645` — 16 relé (zámky + audio selektory), HW flash-on pro pulz zámku.
- `Wav617` — 8 relé + 8 vstupů (dveřní kontakty, bílé světlo), relé v Normal mode.
- `IoBus` — sdružuje moduly z `HardwareConfig`, adresuje kanály přes `HwRef`.

Bezpečnostní pravidla (§12): každý příkaz na relé se ověřuje čtením, all-off
se NIKDY neplete s all-on (0xFF00), offline modul → operace vrací False.

Offline modul se v `read_all_inputs` nečte inline (retry ~2,9 s by zdržel všechny
zóny) — sonduje ho `io_probe.OfflineProbes` a po návratu ho obnoví `reinit()`.
Zastavený modul (`stop()`) je uzavřený natrvalo — žádná operace už neotevře
spojení (ochrana před „zombie" sběrnicí po přestavbě konfigurace).
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Awaitable, Callable

from .config import DeviceCfg, HardwareConfig, PollingCfg
from .io_probe import OfflineProbes, raw_read
from .modbus import ModbusError, ModbusExceptionResponse, ModbusTcpClient
from .models import HwRef

log = logging.getLogger("motogo.io")

ALL_COILS_ADDR = 0x00FF      # FC05: všechna relé najednou
ALL_OFF_VALUE = 0x0000       # 0xFF00 by všechna relé ZAPNULO — nikdy nepoužívat
FLASH_ON_BASE = 0x0200       # FC05: časované sepnutí, hodnota = počet 100ms kroků
FLASH_STEP_MS = 100
MODE_REG_BASE = 0x1000       # FC03/FC06: režim relé (0 = Normal)
MODE_NORMAL = 0


class RelayModule:
    """Obecný reléový modul; konkrétní parametry určují podtřídy."""

    COILS = 0
    INPUTS = 0
    HW_FLASH = False

    def __init__(self, name: str, client: ModbusTcpClient) -> None:
        self.name = name
        self.client = client
        self.coils = self.COILS
        self.inputs = self.INPUTS
        self.closed = False          # po stop(): trvale mimo provoz, spojení se už neotevře
        self.needs_reinit = False    # po návratu online (nebo neúspěšném startu) znovu obnovit

    @property
    def online(self) -> bool:
        return not self.closed and self.client.online

    async def start(self) -> None:
        """Naváže spojení (chybu spolkne — online se řeší při requestu)."""
        self.closed = False
        await self.client.connect()

    async def stop(self) -> None:
        """Uzavře modul natrvalo: další operace vrací False / ModbusError bez reconnectu."""
        self.closed = True
        await self.client.close()

    def _check_idx(self, idx: int) -> int:
        if not 0 <= int(idx) < self.coils:
            raise ValueError(f"{self.name}: index relé {idx} mimo rozsah 0..{self.coils - 1}")
        return int(idx)

    def _check_open(self) -> None:
        if self.closed:
            raise ModbusError(f"{self.name}: modul je zastaven (stop) — komunikace odmítnuta")

    async def read_coils(self) -> list[bool]:
        """FC01 — stav všech relé (vyhazuje ModbusError)."""
        self._check_open()
        return await self.client.read_coils(0, self.coils)

    async def read_inputs(self) -> list[bool]:
        """FC02 — všechny vstupy; modul bez vstupů vrací [] bez komunikace."""
        if not self.inputs:
            return []
        self._check_open()
        return await self.client.read_discrete_inputs(0, self.inputs)

    async def set_coil(self, idx: int, on: bool) -> bool:
        """Zapíše relé a OVĚŘÍ čtením; vrací True, když skutečný stav == `on`."""
        idx = self._check_idx(idx)
        try:
            self._check_open()
            await self.client.write_coil(idx, bool(on))
            state = await self.client.read_coils(idx, 1)
        except ModbusError as exc:
            log.warning("%s: set_coil(%d, %s) selhal: %s", self.name, idx, on, exc)
            return False
        ok = bool(state) and state[0] == bool(on)
        if not ok:
            log.error("%s: relé %d po zápisu %s hlásí %s", self.name, idx, on, state)
        return ok

    async def all_off(self) -> bool:
        """Vypne všechna relé (FC05 0x00FF = 0x0000) a ověří; při neúspěchu coil po coilu.

        Coil po coilu má smysl jen když modul odpověděl (hromadný příkaz odmítl nebo
        relé zůstala sepnutá). Při selhání komunikace by opakoval totéž mrtvé
        spojení 8–16× (každé s plným retry) a zdržel start/stop o desítky sekund.
        """
        try:
            self._check_open()
            await self.client.write_coil_raw(ALL_COILS_ADDR, ALL_OFF_VALUE)
            states = await self.read_coils()
            if not any(states):
                return True
            log.warning("%s: po all_off zůstala sepnutá relé %s — vypínám jednotlivě",
                        self.name, [i for i, s in enumerate(states) if s])
        except ModbusExceptionResponse as exc:
            log.warning("%s: hromadné vypnutí odmítnuto (%s) — vypínám jednotlivě", self.name, exc)
        except ModbusError as exc:
            log.warning("%s: all_off selhal: %s", self.name, exc)
            return False
        if not self.online:
            return False
        return await self._off_one_by_one()

    async def _off_one_by_one(self) -> bool:
        ok = True
        for i in range(self.coils):
            if not await self.set_coil(i, False):
                ok = False
                if not self.online:
                    break
        return ok

    async def pulse(self, idx: int, ms: int) -> bool:
        """Časované sepnutí relé: HW flash-on (WAV645) nebo softwarově (WAV617)."""
        idx = self._check_idx(idx)
        if int(ms) <= 0:
            raise ValueError("ms musí být > 0")
        if self.HW_FLASH:
            return await self._pulse_hw(idx, int(ms))
        return await self._pulse_sw(idx, int(ms))

    async def _pulse_hw(self, idx: int, ms: int) -> bool:
        steps = min(max(1, round(ms / FLASH_STEP_MS)), 0xFFFF)
        try:
            self._check_open()
            # Flash-on není idempotentní: opakovaný zápis by restartoval časovač pulzu (zámek pod
            # napětím déle) — bez retry; potvrzené echo = modul příkaz přijal.
            await self.client.write_coil_raw(FLASH_ON_BASE + idx, steps, retry=False)
        except ModbusError as exc:
            log.warning("%s: flash-on relé %d selhal: %s", self.name, idx, exc)
            return False
        t0 = time.monotonic()
        try:
            state = await self.client.read_coils(idx, 1)
        except ModbusError as exc:
            state = None
            log.warning("%s: ověření relé %d po flash-on selhalo: %s", self.name, idx, exc)
        ok = bool(state) and state[0]
        if not ok and (time.monotonic() - t0) * 1000.0 >= steps * FLASH_STEP_MS:
            # Ověření (retry řetězec) doběhlo až po skončení pulzu — relé už legitimně odpadlo;
            # echo FC05 přišlo, zámek byl sepnutý. Nehlásit lock_failed (dveře jsou odjištěné).
            log.warning("%s: ověření relé %d doběhlo až po pulzu (%d×100 ms) — pulz považován za doručený",
                        self.name, idx, steps)
            ok = True
        if not ok:
            log.error("%s: relé %d po flash-on (%d×100 ms) není sepnuté", self.name, idx, steps)
        return ok

    async def _pulse_sw(self, idx: int, ms: int) -> bool:
        on_ok = await self.set_coil(idx, True)
        off_ok = False
        try:
            if on_ok:
                await asyncio.sleep(ms / 1000.0)
        finally:
            off_ok = await self.set_coil(idx, False)
            if not off_ok and on_ok:
                log.critical("%s: relé %d se po pulzu NEPODAŘILO vypnout!", self.name, idx)
        return on_ok and off_ok

    async def _reinit_mode(self) -> bool:
        """Obnova režimu relé po výpadku (podtřída WAV617 = Normal mode)."""
        return True

    async def reinit(self) -> bool:
        """Obnova po návratu online (§6, §12 kroky 1–2): režim relé + ověřený all_off.

        `needs_reinit` zůstává jen při selhání KOMUNIKACE; když modul odpověděl
        a přesto odmítl, opakování každých 100 ms nemá smysl (chyba je v logu).
        """
        if self.closed:
            return False
        mode_ok = await self._reinit_mode()
        off_ok = self.online and await self.all_off()
        ok = mode_ok and off_ok
        comm_failed = not ok and self.client.failures > 0
        # Dokud obnova neproběhla (komunikace NEBO relé odmítlo vypnout = zaseklé/svařené), zůstává
        # modul „v obnově“: IoBus.is_online → False → zóny na něm jsou FAULT io_offline (§12 krok 1–2).
        self.needs_reinit = not ok
        level = log.info if ok else (log.warning if comm_failed else log.error)
        level("%s: obnova po výpadku %s (režim=%s, all_off=%s)", self.name, "OK" if ok else "SELHALA", mode_ok, off_ok)
        return ok


class Wav645(RelayModule):
    """Waveshare Modbus POE ETH Relay 16CH — v šabloně Brno zámky R1–R8, audio R10, R9/R11–R16 rezerva (mapu určuje HW mapa)."""

    COILS = 16
    INPUTS = 0
    HW_FLASH = True


class Wav617(RelayModule):
    """Waveshare Modbus POE ETH Relay (B) — 8 relé + 8 opticky oddělených vstupů."""

    COILS = 8
    INPUTS = 8
    HW_FLASH = False

    async def start(self) -> None:
        await super().start()
        if not await self.set_normal_mode():
            self.needs_reinit = True     # zopakuje IoBus, jakmile modul odpovídá
            log.warning("%s: relé se nepodařilo přepnout do Normal mode", self.name)

    async def _reinit_mode(self) -> bool:
        return await self.set_normal_mode()

    async def set_normal_mode(self) -> bool:
        """FC06 0x1000+r = 0 pro každé relé, ověří FC03 0x1000 × 8 == [0]*8."""
        try:
            self._check_open()
            for r in range(self.coils):
                await self.client.write_register(MODE_REG_BASE + r, MODE_NORMAL)
            regs = await self.client.read_holding_registers(MODE_REG_BASE, self.coils)
        except ModbusError as exc:
            log.warning("%s: set_normal_mode selhal: %s", self.name, exc)
            return False
        ok = regs == [MODE_NORMAL] * self.coils
        if not ok:
            log.error("%s: režimy relé po zápisu: %s (očekáváno samé 0)", self.name, regs)
        return ok


MODULE_TYPES: dict[str, type[RelayModule]] = {"wav645": Wav645, "wav617": Wav617}


def make_module(name: str, dev: DeviceCfg, polling: PollingCfg) -> RelayModule:
    """Vytvoří modul dle `dev.type`; spojení se navazuje až v `start()`/prvním requestu."""
    cls = MODULE_TYPES.get(str(dev.type).lower())
    if cls is None:
        raise ValueError(f"{name}: neznámý typ Modbus modulu '{dev.type}'")
    client = ModbusTcpClient(
        dev.host, dev.port, dev.unit_id,
        timeout_ms=polling.modbus_timeout_ms,
        retry_delays_ms=tuple(polling.retry_delays_ms or ()),
        offline_after=polling.device_offline_after_failures,
        name=name,
    )
    return cls(name, client)


class IoBus:
    """Sběrnice všech Waveshare modulů; adresuje kanály přes `HwRef(dev, idx)`."""

    def __init__(self, hw: HardwareConfig) -> None:
        self.modules: dict[str, RelayModule] = {}
        self.on_online_change: Callable[[str, bool], None] | None = None
        self.on_reinit: Callable[[str], Awaitable[None]] | None = None   # po úspěšné obnově modulu (all_off)
        self.closed = False
        self._probes = OfflineProbes(lambda: self.closed)   # offline moduly / probíhající obnova
        for name, dev in hw.modbus_devices().items():
            try:
                module = make_module(name, dev, hw.polling)
            except ValueError as exc:
                log.error("Modul %s přeskočen: %s", name, exc)
                continue
            module.client.on_online_change = self._online_changed
            self.modules[name] = module

    def _online_changed(self, name: str, online: bool) -> None:
        module = self.modules.get(name)
        if online and module is not None:
            module.needs_reinit = True       # návrat online → Normal mode + all_off (reinit)
        cb = self.on_online_change
        if cb is not None:
            try:
                cb(name, online)
            except Exception:  # noqa: BLE001
                log.exception("on_online_change(%s) selhal", name)

    async def start(self) -> None:
        """Spustí všechny moduly paralelně; chyby loguje, nepadá."""
        self.closed = False
        await asyncio.gather(*(self._start_one(m) for m in self.modules.values()))

    async def _start_one(self, module: RelayModule) -> None:
        try:
            await module.start()
        except Exception:  # noqa: BLE001
            log.exception("%s: start selhal", module.name)

    async def stop(self) -> None:
        """Zruší sondy a uzavře všechny moduly natrvalo (žádný pozdější reconnect)."""
        self.closed = True
        await self._probes.cancel_all()
        await asyncio.gather(*(m.stop() for m in self.modules.values()), return_exceptions=True)

    def is_online(self, name: str) -> bool:
        """Online = modul odpovídá A má dokončenou obnovu (Normal mode + ověřené all_off)."""
        m = self.modules.get(name)
        return bool(m and m.online and not m.needs_reinit and not self._probes.active(name))

    def mark_reinit(self, name: str) -> None:
        """Vynutí obnovu modulu (např. all_off při startu selhalo) — zóny na něm jsou zatím io_offline."""
        m = self.modules.get(name)
        if m is not None:
            m.needs_reinit = True

    def get(self, name: str) -> RelayModule:
        return self.modules[name]

    async def all_off(self) -> dict[str, bool]:
        """all_off na všech modulech paralelně; výsledek per modul."""
        names = list(self.modules)
        results = await asyncio.gather(*(self.modules[n].all_off() for n in names), return_exceptions=True)
        out: dict[str, bool] = {}
        for name, res in zip(names, results):
            if isinstance(res, BaseException):
                log.error("%s: all_off vyhodil %r", name, res)
                out[name] = False
            else:
                out[name] = bool(res)
        return out

    def _module_for(self, ref: HwRef, action: str) -> RelayModule | None:
        m = self.modules.get(ref.dev)
        if m is None:
            log.error("%s: neznámý modul '%s'", action, ref.dev)
            return None
        if self.closed or m.closed:
            log.error("%s: sběrnice/modul %s je zastaven — %s[%d] odmítnuto", action, ref.dev, ref.dev, ref.idx)
            return None
        if not m.online or self._probes.active(ref.dev):
            log.warning("%s: modul %s je offline/v obnově — %s[%d] odmítnuto", action, ref.dev, ref.dev, ref.idx)
            return None
        return m

    async def set(self, ref: HwRef, on: bool) -> bool:
        m = self._module_for(ref, "set")
        if m is None:
            return False
        try:
            return await m.set_coil(ref.idx, on)
        except (ValueError, ModbusError) as exc:
            log.error("set %s[%d]=%s selhal: %s", ref.dev, ref.idx, on, exc)
            return False

    async def pulse(self, ref: HwRef, ms: int) -> bool:
        m = self._module_for(ref, "pulse")
        if m is None:
            return False
        try:
            return await m.pulse(ref.idx, ms)
        except (ValueError, ModbusError) as exc:
            log.error("pulse %s[%d] %d ms selhal: %s", ref.dev, ref.idx, ms, exc)
            return False

    async def read_all_inputs(self) -> dict[str, list[bool] | None]:
        """Přečte vstupy všech ONLINE modulů paralelně. None = modul offline / chyba / v obnově.

        Modul bez vstupů (WAV645) se sonduje čtením relé (stav online zámků).
        Offline modul se nečte inline — sondu a obnovu řeší `OfflineProbes`.
        """
        names = list(self.modules)
        results = await asyncio.gather(*(self._read_one(self.modules[n]) for n in names))
        return dict(zip(names, results))

    async def _read_one(self, module: RelayModule) -> list[bool] | None:
        if self.closed or module.closed or self._probes.active(module.name):
            return None
        if not module.online:
            self._probes.ensure(module)
            return None
        try:
            if module.needs_reinit:
                if not await module.reinit():
                    if not module.online:
                        self._probes.ensure(module)
                    return None
                if self.on_reinit is not None:
                    asyncio.create_task(self.on_reinit(module.name), name=f"motogo.reinit.{module.name}")
            return await raw_read(module)
        except ModbusError as exc:
            log.debug("%s: čtení vstupů selhalo: %s", module.name, exc)
            if not module.online:
                self._probes.ensure(module)
            return None

    def input_value(self, snapshot: dict[str, list[bool] | None], ref: HwRef) -> bool | None:
        """Hodnota vstupu z momentky; None = modul offline nebo index mimo rozsah."""
        values = snapshot.get(ref.dev)
        if values is None or not 0 <= ref.idx < len(values):
            return None
        return bool(values[ref.idx])
