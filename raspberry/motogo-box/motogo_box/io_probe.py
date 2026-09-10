"""Sondování offline Waveshare modulů mimo poll smyčku (pomocný modul `io_devices`).

Plný retry řetězec `ModbusTcpClient` trvá při nedostupném modulu ~2,9 s. Kdyby
`IoBus.read_all_inputs` četl offline modul inline, momentka kontaktů VŠECH zón
by chodila jen každé ~3 s (SPEC §6 `door_input_poll_ms: 100`). Offline modul
proto sonduje samostatný task každých `PROBE_INTERVAL_S`; po návratu online
provede `RelayModule.reinit()` (WAV617 Normal mode + all_off, §6/§12) a teprve
potom modul uvolní zpět do provozu.
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Callable

from .modbus import ModbusError

if TYPE_CHECKING:  # pragma: no cover
    from .io_devices import RelayModule

log = logging.getLogger("motogo.io")

PROBE_INTERVAL_S = 2.0       # prodleva mezi sondami offline modulu


async def raw_read(module: "RelayModule") -> list[bool]:
    """Vstupy modulu (FC02); modul bez vstupů (WAV645) se sonduje čtením relé → []."""
    if module.inputs:
        return await module.read_inputs()
    await module.read_coils()
    return []


class OfflineProbes:
    """Správce sond offline modulů: jeden task na modul, po obnově task končí."""

    def __init__(self, bus_closed: Callable[[], bool]) -> None:
        self._bus_closed = bus_closed
        self._tasks: dict[str, asyncio.Task] = {}

    def active(self, name: str) -> bool:
        """True = modul je offline nebo právě probíhá jeho obnova (nepoužívat)."""
        return name in self._tasks

    def ensure(self, module: "RelayModule") -> None:
        """Spustí sondu modulu, pokud už neběží (a sběrnice/modul není zastaven)."""
        if self._bus_closed() or module.closed or module.name in self._tasks:
            return
        log.info("%s: offline — sonduji každých %.1f s mimo poll smyčku", module.name, PROBE_INTERVAL_S)
        self._tasks[module.name] = asyncio.create_task(
            self._loop(module), name=f"motogo.io.probe.{module.name}")

    async def cancel_all(self) -> None:
        tasks = list(self._tasks.values())
        for t in tasks:
            t.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._tasks.clear()

    async def _loop(self, module: "RelayModule") -> None:
        """Sonduje offline modul; po návratu online provede `reinit` a skončí."""
        try:
            while not self._bus_closed() and not module.closed:
                if not module.online:
                    try:
                        await raw_read(module)
                    except ModbusError:
                        await asyncio.sleep(PROBE_INTERVAL_S)
                        continue
                    log.warning("%s: modul odpovídá — obnovuji (režim relé + all_off)", module.name)
                if module.needs_reinit and not await module.reinit() and not module.online:
                    await asyncio.sleep(PROBE_INTERVAL_S)   # spojení znovu spadlo → sondovat dál
                    continue
                return
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("%s: sonda offline modulu selhala", module.name)
        finally:
            self._tasks.pop(module.name, None)
