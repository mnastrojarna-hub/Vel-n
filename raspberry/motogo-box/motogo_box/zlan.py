"""Správa síťového čipu modulů Waveshare Modbus POE ETH Relay přes protokol ZLAN (UDP 1092).

Waveshare v těchto modulech používá sériový server ZLAN — stejný protokol mluví jejich
nástroj VirCom. Paket = `b"ZL"` + příkaz (1 B) + blok parametrů (167 B):
- `0x00` hledání (broadcast), `0x04` čtení (unicast) → zařízení odpoví `0x01` + svůj blok,
- `0x02` zápis celého bloku → zařízení ho uloží a samo se restartuje (~3 s).

Zapisuje se VŽDY blok právě přečtený ze zařízení, změní se jen IP / maska / brána / statický
režim — ostatní bajty (heslo webu, port, režim, protokol) zůstávají beze změny. Offsety dle
veřejně popsaného protokolu (pywaveshare, MIT). Modul nemusí být ve stejné podsíti jako
Raspberry: hledá se broadcastem a LAN profil má pomocnou adresu v tovární síti 192.168.1.0/24.
"""
from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
from dataclasses import dataclass

log = logging.getLogger("motogo.zlan")

PORT = 1092
MAGIC = b"ZL"
CMD_DISCOVER, CMD_RESPONSE, CMD_WRITE, CMD_READ = 0x00, 0x01, 0x02, 0x04
PARAM_LEN = 167
PACKET_LEN = 3 + PARAM_LEN
FACTORY_IP = "192.168.1.254"            # tovární IP modulů Waveshare Modbus POE ETH Relay

_IP, _MASK, _GW = slice(0, 4), slice(4, 8), slice(8, 12)
_LOCAL_PORT = slice(16, 18)
_DEVICE_ID = slice(31, 37)
_IP_MODE = 56                           # 0 = statická, 1 = DHCP
_APP_PROTOCOL = 60                      # 0 = žádný (transparentní = Modbus RTU přes TCP)


@dataclass(frozen=True)
class ZlanDevice:
    raw: bytes          # celý blok parametrů přečtený ze zařízení (167 B)
    source: str         # IP, ze které přišla odpověď

    @property
    def mac(self) -> str:
        return self.raw[_DEVICE_ID].hex(":").upper()

    @property
    def ip(self) -> str:
        return str(ipaddress.IPv4Address(self.raw[_IP]))

    @property
    def netmask(self) -> str:
        return str(ipaddress.IPv4Address(self.raw[_MASK]))

    @property
    def local_port(self) -> int:
        return int.from_bytes(self.raw[_LOCAL_PORT], "big")

    @property
    def dhcp(self) -> bool:
        return self.raw[_IP_MODE] == 1

    @property
    def transparent(self) -> bool:
        """True = transparentní režim (Modbus RTU přes TCP na `local_port`), jinak Modbus TCP."""
        return self.raw[_APP_PROTOCOL] == 0

    def as_dict(self) -> dict:
        return {"mac": self.mac, "ip": self.ip, "netmask": self.netmask, "port": self.local_port,
                "dhcp": self.dhcp, "protocol": "rtu" if self.transparent else "tcp"}


def query_packet(cmd: int = CMD_DISCOVER) -> bytes:
    return MAGIC + bytes((cmd,)) + bytes(PARAM_LEN)


def parse_packet(packet: bytes, source: str) -> ZlanDevice | None:
    """Odpověď zařízení → `ZlanDevice`; cokoli jiného (vlastní dotaz, cizí paket) → None."""
    if len(packet) != PACKET_LEN or packet[:2] != MAGIC or packet[2] != CMD_RESPONSE:
        return None
    dev = ZlanDevice(bytes(packet[3:]), source)
    return dev if dev.raw[_DEVICE_ID] != bytes(6) else None


def write_packet(dev: ZlanDevice, ip: str, netmask: str, gateway: str) -> bytes:
    """Zápis: přečtený blok se změněnou IP/maskou/bránou a statickým režimem."""
    raw = bytearray(dev.raw)
    raw[_IP] = ipaddress.IPv4Address(ip).packed
    raw[_MASK] = ipaddress.IPv4Address(netmask).packed
    raw[_GW] = ipaddress.IPv4Address(gateway).packed
    raw[_IP_MODE] = 0
    return MAGIC + bytes((CMD_WRITE,)) + bytes(raw)


class _Collector(asyncio.DatagramProtocol):
    def __init__(self) -> None:
        self.found: dict[str, ZlanDevice] = {}

    def datagram_received(self, data: bytes, addr) -> None:
        dev = parse_packet(data, addr[0])
        if dev is not None:
            self.found[dev.mac] = dev


async def discover(broadcasts: list[str], timeout_s: float = 1.5, port: int = PORT) -> list[ZlanDevice]:
    """Rozešle dotaz na zadané broadcast adresy a vrátí odpovídající moduly (dle MAC)."""
    loop = asyncio.get_running_loop()
    transport, proto = await loop.create_datagram_endpoint(
        _Collector, local_addr=("0.0.0.0", 0), family=socket.AF_INET, allow_broadcast=True)
    try:
        for target in broadcasts:
            try:
                transport.sendto(query_packet(), (target, port))
            except OSError as exc:
                log.debug("ZLAN dotaz na %s selhal: %s", target, exc)
        await asyncio.sleep(timeout_s)
    finally:
        transport.close()
    return [proto.found[k] for k in sorted(proto.found)]


async def write(dev: ZlanDevice, ip: str, netmask: str, gateway: str, port: int = PORT) -> None:
    """Jediný zápis (bez opakování — zařízení se po přijetí hned restartuje) na jeho současnou IP."""
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        asyncio.DatagramProtocol, remote_addr=(dev.source, port), family=socket.AF_INET)
    try:
        transport.sendto(write_packet(dev, ip, netmask, gateway))
        await asyncio.sleep(0.05)
    finally:
        transport.close()
