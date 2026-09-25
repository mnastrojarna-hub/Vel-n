"""Modbus RTU přes TCP (transparentní režim Waveshare) — čisté funkce framování.

Waveshare Modbus POE ETH Relay z výroby běží jako TCP server s „Transfer Protocol: None“:
síťový port jen transparentně přeposílá bajty na interní sériovou linku (Modbus RTU,
typicky port 4196). Rámec = unit id + PDU + CRC16 (little-endian), bez MBAP hlavičky.
Klient (`modbus.ModbusTcpClient`, framing `rtu`/`auto`) tak ovládá modul hned po vybalení,
bez ručního přepínání na Modbus TCP ve VirComu.
"""
from __future__ import annotations

import asyncio

RTU_DEFAULT_PORT = 4196
_FIXED_REPLY = {0x05: 4, 0x06: 4}             # FC05/FC06 echo: adresa + hodnota
_COUNTED_REPLY = (0x01, 0x02, 0x03, 0x04)     # FC01–04: byte count + data


def crc16(data: bytes) -> int:
    """Modbus CRC16 (polynom 0xA001, počáteční 0xFFFF)."""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build_rtu(unit: int, pdu: bytes) -> bytes:
    body = bytes((unit & 0xFF,)) + bytes(pdu)
    return body + crc16(body).to_bytes(2, "little")


def check_rtu(frame: bytes, unit: int) -> bytes:
    """Ověří CRC a unit id RTU odpovědi, vrátí PDU. Chyba → ValueError."""
    if len(frame) < 4:
        raise ValueError(f"příliš krátký RTU rámec ({len(frame)} B)")
    if crc16(frame[:-2]) != int.from_bytes(frame[-2:], "little"):
        raise ValueError("RTU CRC nesouhlasí")
    if frame[0] != (unit & 0xFF):
        raise ValueError(f"RTU odpověď od unit {frame[0]}, očekáván {unit}")
    return bytes(frame[1:-2])


async def read_rtu_reply(reader: asyncio.StreamReader, unit: int) -> bytes:
    """Přečte jednu RTU odpověď (délka dle funkčního kódu) a vrátí její PDU."""
    head = await reader.readexactly(2)                    # unit + FC
    fc = head[1]
    if fc & 0x80:
        rest = await reader.readexactly(3)                # exception kód + CRC
    elif fc in _COUNTED_REPLY:
        count = await reader.readexactly(1)
        rest = count + await reader.readexactly(count[0] + 2)
    elif fc in _FIXED_REPLY:
        rest = await reader.readexactly(_FIXED_REPLY[fc] + 2)
    else:
        raise ValueError(f"nepodporovaný funkční kód v RTU odpovědi: 0x{fc:02X}")
    return check_rtu(head + rest, unit)
