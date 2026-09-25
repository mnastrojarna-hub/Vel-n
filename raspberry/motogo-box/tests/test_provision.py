"""Tovární moduly Waveshare bez ručního nastavení: Modbus RTU přes TCP (`framing auto`),
protokol ZLAN (`zlan.py`) a automatické přeadresování dle HW mapy (`io_provision.py`)."""
from __future__ import annotations

import asyncio
import ipaddress
import socket

from motogo_box import zlan
from motogo_box.config import HardwareConfig
from motogo_box.io_provision import IoProvisioner
from motogo_box.modbus import ModbusTcpClient
from motogo_box.modbus_rtu import build_rtu, check_rtu, crc16


# ─── RTU framing ─────────────────────────────────────────────────────────────
def test_crc_matches_waveshare_wiki_vector():
    assert build_rtu(1, bytes.fromhex("050000FF00")) == bytes.fromhex("01050000FF008C3A")   # „relé 0 zap“ z wiki
    assert build_rtu(1, bytes.fromhex("0200000008")) == bytes.fromhex("01020000000879CC")   # čtení 8 vstupů
    assert check_rtu(bytes.fromhex("01050000FF008C3A"), 1) == bytes.fromhex("050000FF00")
    assert crc16(b"") == 0xFFFF


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def _rtu_server(coils: list[bool]):
    """Minimální transparentní Waveshare: RTU rámce FC01/FC05 nad TCP."""
    async def handle(reader, writer):
        try:
            while True:
                req = await reader.readexactly(8)
                pdu = check_rtu(req, 1)
                fc, addr, val = pdu[0], int.from_bytes(pdu[1:3], "big"), int.from_bytes(pdu[3:5], "big")
                if fc == 0x05:
                    coils[addr] = val == 0xFF00
                    writer.write(req)
                elif fc == 0x01:
                    bits = sum(1 << i for i in range(val) if coils[addr + i])
                    writer.write(build_rtu(1, bytes((1, 1, bits))))
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError):
            writer.close()
    return await asyncio.start_server(handle, "127.0.0.1", 0)


async def test_auto_framing_falls_back_to_rtu_when_modbus_tcp_port_refused():
    coils = [False] * 8
    server = await _rtu_server(coils)
    rtu_port = server.sockets[0].getsockname()[1]
    client = ModbusTcpClient("127.0.0.1", _free_port(), timeout_ms=500, retry_delays_ms=(), rtu_port=rtu_port)
    try:
        await client.write_coil(7, True)                       # CH8 (šatna)
        assert coils[7] and client.rtu and client.active_port == rtu_port
        assert (await client.read_coils(7, 1)) == [True]
    finally:
        await client.close()
        server.close()


# ─── ZLAN ────────────────────────────────────────────────────────────────────
def _block(ip="192.168.1.254", mac="AABBCCDDEEFF", port=4196, proto=0) -> bytes:
    raw = bytearray(zlan.PARAM_LEN)
    raw[0:4] = ipaddress.IPv4Address(ip).packed
    raw[4:8] = ipaddress.IPv4Address("255.255.255.0").packed
    raw[16:18] = port.to_bytes(2, "big")
    raw[31:37] = bytes.fromhex(mac)
    raw[60] = proto
    raw[100] = 0x5A                       # „cizí“ bajt (heslo apod.) musí zápis zachovat
    return bytes(raw)


def _device(**kw) -> zlan.ZlanDevice:
    ip = kw.get("ip", "192.168.1.254")
    return zlan.parse_packet(zlan.MAGIC + bytes((zlan.CMD_RESPONSE,)) + _block(**kw), ip)


def test_zlan_parse_and_write_changes_only_network():
    dev = _device()
    assert dev.as_dict() == {"mac": "AA:BB:CC:DD:EE:FF", "ip": "192.168.1.254", "netmask": "255.255.255.0",
                             "port": 4196, "dhcp": False, "protocol": "rtu"}
    assert zlan.parse_packet(zlan.query_packet(), "x") is None             # vlastní dotaz (broadcast echo)
    pkt = zlan.write_packet(dev, "192.168.50.21", "255.255.255.0", "192.168.50.10")
    assert pkt[:3] == b"ZL\x02" and len(pkt) == zlan.PACKET_LEN
    body = pkt[3:]
    assert body[0:4] == ipaddress.IPv4Address("192.168.50.21").packed
    assert body[8:12] == ipaddress.IPv4Address("192.168.50.10").packed
    assert body[12:] == dev.raw[12:]                                       # zbytek bloku beze změny


# ─── automatické zřízení ─────────────────────────────────────────────────────
HW = HardwareConfig.from_dict({"devices": {
    "wav645": {"type": "wav645", "host": "192.168.50.20"},
    "wav617a": {"type": "wav617", "host": "192.168.50.21"},
    "wav617b": {"type": "wav617", "host": "192.168.50.22"},
    "shelly1": {"type": "shelly_rgbww", "host": "192.168.50.31"}}})
NETS = [ipaddress.IPv4Interface("192.168.50.10/24"), ipaddress.IPv4Interface("192.168.1.253/24")]


class Kv:
    def __init__(self):
        self.d = {}

    def kv_get(self, k, default=None):
        return self.d.get(k, default)

    def kv_set(self, k, v):
        self.d[k] = v


def _prov(found, identify_result, storage=None):
    writes = []

    async def discover(broadcasts, timeout_s=1.5):
        assert "192.168.1.255" in broadcasts and "192.168.50.255" in broadcasts
        return found

    async def write(dev, ip, mask, gw):
        writes.append((dev.mac, ip, mask, gw))

    async def identify(host, port, framing="auto"):
        return identify_result

    async def networks():
        return NETS

    return IoProvisioner(storage, discover=discover, write=write, identify=identify, networks=networks), writes


async def test_factory_relay_b_gets_address_of_missing_wav617():
    prov, writes = _prov([_device()], {"coils": 8, "inputs": 8})
    kv = Kv()
    prov.storage = kv
    actions = await prov.run(HW, lambda n: False)
    assert writes == [("AA:BB:CC:DD:EE:FF", "192.168.50.21", "255.255.255.0", "192.168.50.10")]
    assert actions[0]["device"] == "wav617a" and kv.d["io_provision"] == {"AA:BB:CC:DD:EE:FF": "wav617a"}
    assert await prov.run(HW, lambda n: False) == []                       # stejný modul ne dřív než za 5 min


async def test_provision_never_touches_configured_or_online_modules():
    prov, writes = _prov([_device(ip="192.168.50.21")], {"coils": 8, "inputs": 8})
    assert await prov.run(HW, lambda n: n != "wav645") == []               # wav645 chybí, ale kandidát má IP z mapy
    prov, writes = _prov([_device()], {"coils": 8, "inputs": 8})
    assert await prov.run(HW, lambda n: True) == [] and writes == []       # vše online → ani se nehledá


async def test_type_mismatch_is_not_assigned():
    prov, writes = _prov([_device()], {"coils": 16, "inputs": 0})          # 16CH modul, chybí jen WAV617
    assert await prov.run(HW, lambda n: n not in ("wav617a",)) == [] and writes == []


async def test_zlan_discover_over_udp_loopback():
    class FakeModule(asyncio.DatagramProtocol):
        def connection_made(self, transport):
            self.t = transport

        def datagram_received(self, data, addr):
            if data == zlan.query_packet():
                self.t.sendto(zlan.MAGIC + bytes((zlan.CMD_RESPONSE,)) + _block(), addr)

    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(FakeModule, local_addr=("127.0.0.1", 0))
    port = transport.get_extra_info("sockname")[1]
    try:
        found = await zlan.discover(["127.0.0.1"], timeout_s=0.3, port=port)
    finally:
        transport.close()
    assert [f.mac for f in found] == ["AA:BB:CC:DD:EE:FF"] and found[0].source == "127.0.0.1"
