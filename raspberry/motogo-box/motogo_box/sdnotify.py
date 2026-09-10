"""Minimální sd_notify klient (systemd) — kontrakt §18.

`notify()` pošle datagram na unixový socket z env `NOTIFY_SOCKET` (abstraktní
socket začíná `@` → nulový byte). Bez proměnné je vše no-op, takže program
běží stejně i mimo systemd (vývoj, testy).
"""
from __future__ import annotations

import asyncio
import logging
import os
import socket
from typing import Callable

log = logging.getLogger("motogo.sdnotify")


def notify(state: str) -> None:
    """Pošle stav systemd (např. `READY=1`, `WATCHDOG=1`, `STATUS=…`); bez socketu nic nedělá."""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    if addr.startswith("@"):
        addr = "\0" + addr[1:]
    sock: socket.socket | None = None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.setblocking(False)
        sock.sendto(state.encode("utf-8"), addr)
    except OSError as exc:
        log.debug("sd_notify(%r) selhal: %s", state, exc)
    finally:
        if sock is not None:
            sock.close()


def watchdog_interval_s(default: float | None = None) -> float | None:
    """Interval pro `WATCHDOG=1` odvozený z env `WATCHDOG_USEC` (třetina — jeden vynechaný ping
    kvůli přechodnému stavu modulů ještě nesmí znamenat restart), jinak `default`."""
    raw = os.environ.get("WATCHDOG_USEC")
    if not raw:
        return default
    try:
        usec = int(raw)
    except ValueError:
        return default
    if usec <= 0:
        return default
    return max(0.5, usec / 3_000_000.0)


async def watchdog_loop(interval_s: float, healthy: Callable[[], bool]) -> None:
    """Každých `interval_s` pošle `WATCHDOG=1`, ale JEN když `healthy()` — jinak systemd proces restartuje."""
    interval = max(0.5, float(interval_s))
    while True:
        try:
            if healthy():
                notify("WATCHDOG=1")
            else:
                log.warning("Watchdog: proces není zdravý — WATCHDOG=1 neodesláno")
        except Exception:  # noqa: BLE001 — smyčka nesmí spadnout
            log.exception("Watchdog: kontrola zdraví selhala")
        await asyncio.sleep(interval)
