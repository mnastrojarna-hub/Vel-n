"""Automatické zřízení modulů Waveshare: IP adresa podle HW mapy z Velína bez VirComu.

Když některý Modbus modul z HW mapy (`devices`) neodpovídá, jednotka broadcastem ZLAN
(`zlan.py`) najde Waveshare moduly na LAN (i v tovární síti 192.168.1.254 — LAN profil má
pomocnou adresu 192.168.1.253/24) a modulu, který nemá žádnou adresu z mapy, nastaví IP,
kterou mapa pro chybějící zařízení čeká. Protokol se nemění: tovární transparentní režim
(Modbus RTU přes TCP, port 4196) umí klient sám (`framing: auto`).

Párování chybějící zařízení ↔ nalezený modul: 1) MAC dřív přiřazená témuž jménu, 2) shodný
typ podle sondy (8 vstupů = WAV617 / Relay (B), 16 relé bez vstupů = WAV645), 3) jediný
kandidát pro jediné chybějící zařízení. Stejný modul se přepisuje nejvýš jednou za 5 minut
(ochrana proti smyčce). Moduly s adresou z mapy se NIKDY nemění.
"""
from __future__ import annotations

import ipaddress
import logging
import time
from typing import Awaitable, Callable

from . import net_scan, zlan
from .config import HardwareConfig

log = logging.getLogger("motogo.provision")

LAN_IFACE = "eth0"
KV_KEY = "io_provision"                 # {mac: jméno zařízení} — poslední přiřazení
REWRITE_GUARD_S = 300.0


async def lan_networks(iface: str = LAN_IFACE) -> list[ipaddress.IPv4Interface]:
    """IPv4 adresy rozhraní I/O sítě (vč. pomocné tovární)."""
    data = await net_scan._ip_json("-4", "addr", "show", "dev", iface) or []
    out: list[ipaddress.IPv4Interface] = []
    for link in data:
        for a in link.get("addr_info") or []:
            try:
                out.append(ipaddress.IPv4Interface(f"{a['local']}/{a['prefixlen']}"))
            except (KeyError, ValueError):
                continue
    return out


def _guess(info: dict | None) -> str | None:
    if not info:
        return None
    if info.get("inputs") == 8:
        return "wav617"
    return "wav645" if (info.get("coils") or 0) >= 16 else None


class IoProvisioner:
    def __init__(self, storage=None, *, discover=zlan.discover, write=zlan.write,
                 identify=net_scan.modbus_identify, networks: Callable[[], Awaitable[list]] = lan_networks,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.storage = storage
        self._discover, self._write, self._identify, self._networks = discover, write, identify, networks
        self.clock = clock
        self._written: dict[str, float] = {}
        self.last_found: list[dict] = []      # poslední nalezené moduly (diagnostika / log)

    def _remembered(self) -> dict:
        try:
            data = self.storage.kv_get(KV_KEY) if self.storage is not None else None
        except Exception:  # noqa: BLE001
            data = None
        return dict(data) if isinstance(data, dict) else {}

    def _remember(self, mac: str, name: str) -> None:
        if self.storage is None:
            return
        data = {k: v for k, v in self._remembered().items() if v != name}
        data[mac] = name
        try:
            self.storage.kv_set(KV_KEY, data)
        except Exception:  # noqa: BLE001
            log.warning("Přiřazení modulu %s → %s se nepodařilo uložit", mac, name)

    async def _type_of(self, dev: zlan.ZlanDevice) -> str | None:
        first = "rtu" if dev.transparent else "tcp"
        for framing in (first, "tcp" if first == "rtu" else "rtu"):
            port = dev.local_port if framing == first and dev.local_port else (502 if framing == "tcp" else 4196)
            guess = _guess(await self._identify(dev.source, port, framing=framing))
            if guess:
                return guess
        return None

    async def run(self, hw: HardwareConfig, is_online: Callable[[str], bool]) -> list[dict]:
        """Jedno kolo: najde a přeadresuje moduly pro nedostupná zařízení. Vrací provedené změny."""
        devices = hw.modbus_devices()
        missing = [(n, d) for n, d in sorted(devices.items()) if not is_online(n)]
        if not missing:
            return []
        nets = await self._networks()
        if not nets:
            return []
        found = await self._discover(sorted({str(n.network.broadcast_address) for n in nets} | {"255.255.255.255"}))
        self.last_found = [f.as_dict() for f in found]
        hosts = {d.host for d in devices.values()}
        present = {f.ip for f in found}
        now = self.clock()
        free = [f for f in found if f.ip not in hosts and now - self._written.get(f.mac, -1e9) >= REWRITE_GUARD_S
                and any(ipaddress.ip_address(f.source) in n.network for n in nets)]
        remembered = self._remembered()
        types: dict[str, str | None] = {}
        actions: list[dict] = []
        for name, dev in missing:
            try:
                target = ipaddress.ip_address(dev.host)
            except ValueError:
                continue
            net = next((n for n in nets if target in n.network), None)
            if dev.host in present or net is None or not free:
                continue            # modul na své adrese je (problém jinde) / adresa mimo I/O síť / není co přiřadit
            ordered = sorted(free, key=lambda f: remembered.get(f.mac) != name)
            pick = None
            for f in ordered:
                if f.mac not in types:
                    types[f.mac] = await self._type_of(f)
                if remembered.get(f.mac) == name or types[f.mac] == dev.type:
                    pick = f
                    break
            if pick is None and len(missing) == 1 and len(free) == 1 and types.get(free[0].mac) is None:
                pick = free[0]      # jediný neznámý modul pro jediné chybějící zařízení
            if pick is None:
                continue
            log.warning("Modul Waveshare %s (%s) → %s = %s (automatické zřízení)", pick.mac, pick.ip, name, dev.host)
            await self._write(pick, dev.host, str(net.netmask), str(net.ip))
            self._written[pick.mac] = now
            free.remove(pick)
            self._remember(pick.mac, name)
            actions.append({"device": name, "mac": pick.mac, "from_ip": pick.ip, "to_ip": dev.host,
                            "type": types.get(pick.mac), "protocol": "rtu" if pick.transparent else "tcp"})
        return actions
