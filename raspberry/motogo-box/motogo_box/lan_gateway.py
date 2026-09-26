"""Záložní brána kabelem (2026-09-26): `hardware.network.lan_gateway` z Velína → soubor `<data_dir>/lan_gateway`
→ NM dispečer `50-motogo-lan-addr` (root) drží `default via <gw> dev eth0 metric 50` i bez DHCP serveru na
switchi. Zapisuje controller (uživatel motogo), čte dispečer; health ho při výpadku internetu spouští znovu
(sudoers: dispečer s argumenty `eth0 manual`). Pobočka nesmí zůstat bez internetu jen proto, že modem SIM7600
vypadl z USB a router na kabelu neposkytuje DHCP."""
from __future__ import annotations

import asyncio
import ipaddress
import logging
import os

log = logging.getLogger("motogo.lan_gateway")

FILE_NAME = "lan_gateway"
DISPATCHER = "/etc/NetworkManager/dispatcher.d/50-motogo-lan-addr"
IFACE = "eth0"


def gateway_path(data_dir: str) -> str:
    return os.path.join(data_dir, FILE_NAME)


def write_gateway(data_dir: str, gateway: str | None) -> bool:
    """Zapíše/odstraní soubor s bránou; vrací True při změně obsahu."""
    path = gateway_path(data_dir)
    gw = str(gateway or "").strip()
    if gw:
        try:
            ipaddress.IPv4Address(gw)
        except ValueError:
            log.error("lan_gateway '%s' není IPv4 — ignoruji", gw)
            gw = ""
    try:
        old = open(path, encoding="utf-8").read().strip() if os.path.exists(path) else ""
    except OSError:
        old = ""
    if old == gw:
        return False
    try:
        if gw:
            os.makedirs(data_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(gw + "\n")
        elif os.path.exists(path):
            os.remove(path)
    except OSError as exc:
        log.error("lan_gateway: zápis %s selhal: %s", path, exc)
        return False
    log.warning("Záložní brána kabelem: %s", gw or "žádná")
    return True


async def run_dispatcher() -> bool:
    """Spustí dispečer (sudo, pevné argumenty) — aplikuje adresy I/O sítě i záložní bránu hned."""
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


async def apply(data_dir: str, gateway: str | None) -> None:
    """Zapsat bránu z HW mapy a nechat ji dispečerem aplikovat (jen při změně)."""
    try:
        if write_gateway(data_dir, gateway):
            await run_dispatcher()
    except Exception:  # noqa: BLE001 — síťová brána nesmí shodit sync/start
        log.exception("lan_gateway.apply selhal")
