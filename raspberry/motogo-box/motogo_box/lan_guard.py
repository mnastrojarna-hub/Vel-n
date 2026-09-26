"""Strážce I/O sítě (2026-09-26): internet jde VÝHRADNĚ přes LTE, eth0 je jen síť modulů.

Původní „záložní brána kabelem" (`hardware.network.lan_gateway` → `<data_dir>/lan_gateway` → default route eth0
metrika 50 `onlink`) vznikla z chybné diagnózy a na pobočce bez routeru poslala internet do prázdna (trasa 50 < LTE 100).
Tenhle modul dělá opak: při startu controlleru soubor smaže a spustí NM dispečer `50-motogo-lan-addr`, který odstraní
každou výchozí trasu přes eth0 a zajistí adresy modulů. Hodnota z Velína se IGNORUJE (validate_hardware → CONFIG_PROBLEM).
"""
from __future__ import annotations

import asyncio
import logging
import os

log = logging.getLogger("motogo.lan_guard")

FILE_NAME = "lan_gateway"
DISPATCHER = "/etc/NetworkManager/dispatcher.d/50-motogo-lan-addr"
IFACE = "eth0"


def remove_gateway_file(data_dir: str) -> bool:
    """Smaže pozůstatek zrušené brány; vrací True, když soubor existoval."""
    path = os.path.join(data_dir, FILE_NAME)
    if not os.path.exists(path):
        return False
    try:
        os.remove(path)
        log.warning("Odstraněn soubor zrušené brány kabelem %s — internet jde jen přes LTE", path)
        return True
    except OSError as exc:
        log.error("lan_guard: smazání %s selhalo: %s", path, exc)
        return False


async def run_dispatcher() -> bool:
    """Spustí dispečer (sudo, pevné argumenty `eth0 manual`) — adresy I/O sítě + smazání tras přes eth0."""
    if not os.path.exists(DISPATCHER):
        return False
    try:
        proc = await asyncio.create_subprocess_exec("sudo", "-n", DISPATCHER, IFACE, "manual",
                                                    stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        _, err = await asyncio.wait_for(proc.communicate(), 20)
        if proc.returncode != 0:
            log.warning("dispečer %s rc=%s: %s", DISPATCHER, proc.returncode, (err or b"").decode(errors="replace")[:200])
        return proc.returncode == 0
    except (OSError, asyncio.TimeoutError) as exc:
        log.warning("dispečer %s se nespustil: %s", DISPATCHER, exc)
        return False


async def apply(data_dir: str) -> None:
    """Při startu: smazat soubor brány (když je) a nechat dispečer uklidit trasy; chyba nesmí shodit start."""
    try:
        remove_gateway_file(data_dir)
        await run_dispatcher()
    except Exception:  # noqa: BLE001
        log.exception("lan_guard.apply selhal")
