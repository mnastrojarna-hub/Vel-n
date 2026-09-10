"""Raw Modbus TCP klient bez pymodbus (kontrakt §3, SPEC §6).

Waveshare moduly používají nestandardní FC05 (flash-on s časovou hodnotou,
0x00FF pro všechna relé), proto je klient napsaný přímo nad PDU. Framování
(`build_mbap`, `parse_response`, `bits_from_bytes`) jsou čisté funkce
testovatelné bez sítě.
"""
from __future__ import annotations

import asyncio
import logging
import struct
from typing import Callable, Sequence

log = logging.getLogger("motogo.modbus")

MBAP_LEN = 7
PROTOCOL_ID = 0
MAX_PDU_LEN = 253

FC_READ_COILS = 0x01
FC_READ_DISCRETE_INPUTS = 0x02
FC_READ_HOLDING_REGISTERS = 0x03
FC_WRITE_SINGLE_COIL = 0x05
FC_WRITE_SINGLE_REGISTER = 0x06

COIL_ON = 0xFF00
COIL_OFF = 0x0000

EXCEPTION_NAMES = {
    0x01: "ILLEGAL_FUNCTION",
    0x02: "ILLEGAL_DATA_ADDRESS",
    0x03: "ILLEGAL_DATA_VALUE",
    0x04: "SLAVE_DEVICE_FAILURE",
    0x05: "ACKNOWLEDGE",
    0x06: "SLAVE_DEVICE_BUSY",
    0x08: "MEMORY_PARITY_ERROR",
    0x0A: "GATEWAY_PATH_UNAVAILABLE",
    0x0B: "GATEWAY_TARGET_FAILED",
}


class ModbusError(Exception):
    """Chyba Modbus komunikace (timeout, ztráta spojení, vadný rámec, exception response)."""


class ModbusExceptionResponse(ModbusError):
    """Zařízení odpovědělo exception rámcem (fc | 0x80 + kód). Neopakuje se."""

    def __init__(self, function: int, code: int) -> None:
        self.function = function
        self.code = code
        name = EXCEPTION_NAMES.get(code, "UNKNOWN")
        super().__init__(f"Modbus exception FC{function:02X}: kód 0x{code:02X} ({name})")


# ─── Čisté funkce (framing) ──────────────────────────────────────────────────
def build_mbap(tid: int, unit: int, pdu: bytes) -> bytes:
    """Sestaví ADU: MBAP (transaction id, protocol 0, length = 1 + len(pdu), unit id) + PDU."""
    if not pdu or len(pdu) > MAX_PDU_LEN:
        raise ValueError(f"neplatná délka PDU: {len(pdu)}")
    return struct.pack(">HHHB", tid & 0xFFFF, PROTOCOL_ID, len(pdu) + 1, unit & 0xFF) + bytes(pdu)


def parse_response(frame: bytes, expect_tid: int) -> bytes:
    """Ověří MBAP odpovědi a vrátí PDU (bez hlavičky).

    Vyhazuje `ModbusError` při vadném rámci (délka, protokol, transaction id)
    a `ModbusExceptionResponse` (podtřída), pokud je odpověď exception (fc | 0x80).
    """
    if len(frame) < MBAP_LEN + 1:
        raise ModbusError(f"příliš krátký rámec ({len(frame)} B)")
    tid, proto, length, _unit = struct.unpack(">HHHB", frame[:MBAP_LEN])
    pdu = bytes(frame[MBAP_LEN:])
    if proto != PROTOCOL_ID:
        raise ModbusError(f"neznámý protocol id {proto}")
    if tid != (expect_tid & 0xFFFF):
        raise ModbusError(f"transaction id nesouhlasí (očekáváno {expect_tid}, přišlo {tid})")
    if length != len(pdu) + 1:
        raise ModbusError(f"délka v MBAP ({length}) neodpovídá PDU ({len(pdu) + 1})")
    fc = pdu[0]
    if fc & 0x80:
        code = pdu[1] if len(pdu) > 1 else 0
        raise ModbusExceptionResponse(fc & 0x7F, code)
    return pdu


def bits_from_bytes(data: bytes, count: int) -> list[bool]:
    """Rozbalí `count` bitů z bajtů odpovědi FC01/FC02 (LSB-first v každém bajtu)."""
    if count < 0:
        raise ValueError("count musí být >= 0")
    if len(data) * 8 < count:
        raise ModbusError(f"nedostatek dat: {len(data)} B pro {count} bitů")
    return [bool((data[i >> 3] >> (i & 7)) & 1) for i in range(count)]


def _check_u16(value: int, what: str) -> int:
    if not 0 <= int(value) <= 0xFFFF:
        raise ValueError(f"{what} mimo rozsah 0..65535: {value}")
    return int(value)


# ─── Klient ──────────────────────────────────────────────────────────────────
class ModbusTcpClient:
    """Modbus TCP klient pro jeden modul: jedno TCP spojení, jeden request v letu.

    Spojení se navazuje LÍNĚ při prvním requestu (konstruktor nic neotvírá).
    Timeout / ztráta spojení → zavřít, znovu připojit a opakovat dle
    `retry_delays_ms`. Po `offline_after` po sobě jdoucích neúspěšných
    requestech se `online` přepne na False (callback `on_online_change`);
    první úspěch vrátí `online=True` a vynuluje `failures`.
    """

    def __init__(self, host: str, port: int = 502, unit_id: int = 1, *,
                 timeout_ms: int = 500, retry_delays_ms: Sequence[int] = (100, 250, 500),
                 offline_after: int = 3, name: str = "") -> None:
        self.host = host
        self.port = int(port)
        self.unit_id = int(unit_id)
        self.timeout_s = max(1, int(timeout_ms)) / 1000.0
        self.retry_delays_s = [max(0, int(d)) / 1000.0 for d in retry_delays_ms]
        self.offline_after = max(1, int(offline_after))
        self.name = name or f"{host}:{port}"
        self.online = True
        self.failures = 0
        self.on_online_change: Callable[[str, bool], None] | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._tid = 0
        self._lock = asyncio.Lock()

    # ── spojení ──
    @property
    def connected(self) -> bool:
        return self._writer is not None and not self._writer.is_closing()

    async def connect(self) -> None:
        """Idempotentní pokus o připojení; chybu jen zaloguje (řeší se při requestu)."""
        if self.connected:
            return
        try:
            await self._open()
        except (OSError, asyncio.TimeoutError) as exc:
            log.debug("%s: připojení k %s:%s selhalo: %s", self.name, self.host, self.port, exc)

    async def _open(self) -> None:
        await self.close()
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(self.host, self.port), self.timeout_s)
        self._reader, self._writer = reader, writer
        log.debug("%s: připojeno k %s:%s", self.name, self.host, self.port)

    async def close(self) -> None:
        writer, self._reader, self._writer = self._writer, None, None
        if writer is None:
            return
        try:
            writer.close()
            await asyncio.wait_for(writer.wait_closed(), 1.0)
        except (OSError, asyncio.TimeoutError):
            pass

    # ── stav online ──
    def _set_online(self, online: bool) -> None:
        if self.online == online:
            return
        self.online = online
        (log.info if online else log.warning)(
            "%s: modul %s", self.name, "ONLINE" if online else f"OFFLINE ({self.failures} selhání)")
        cb = self.on_online_change
        if cb is not None:
            try:
                cb(self.name, online)
            except Exception:  # noqa: BLE001 — callback nesmí shodit I/O
                log.exception("%s: on_online_change selhal", self.name)

    def _mark_success(self) -> None:
        self.failures = 0
        self._set_online(True)

    def _mark_failure(self) -> None:
        self.failures += 1
        if self.failures >= self.offline_after:
            self._set_online(False)

    # ── request ──
    async def request(self, pdu: bytes, *, retry: bool = True) -> bytes:
        """Odešle PDU a vrátí PDU odpovědi (bez MBAP). Viz docstring třídy.

        `retry=False` = jediný pokus (neidempotentní zápisy, např. flash-on WAV645).
        """
        if not pdu or len(pdu) > MAX_PDU_LEN:
            raise ValueError("neplatná délka PDU")
        async with self._lock:
            return await self._request_locked(bytes(pdu), retry)

    async def _request_locked(self, pdu: bytes, retry: bool = True) -> bytes:
        attempts = len(self.retry_delays_s) + 1 if retry else 1
        last_err: Exception | None = None
        for attempt in range(attempts):
            if attempt:
                await asyncio.sleep(self.retry_delays_s[attempt - 1])
            try:
                resp = await self._exchange(pdu)
            except ModbusExceptionResponse:
                self._mark_success()          # zařízení odpovědělo → komunikace je v pořádku
                raise
            except (OSError, EOFError, asyncio.TimeoutError, ModbusError) as exc:
                last_err = exc
                log.debug("%s: FC%02X pokus %d/%d selhal: %r", self.name, pdu[0], attempt + 1, attempts, exc)
                await self.close()
                continue
            self._mark_success()
            return resp
        self._mark_failure()
        raise ModbusError(f"{self.name}: FC{pdu[0]:02X} selhal po {attempts} pokusech: {last_err!r}")

    async def _exchange(self, pdu: bytes) -> bytes:
        if not self.connected:
            await self._open()
        assert self._reader is not None and self._writer is not None
        self._tid = (self._tid + 1) & 0xFFFF
        tid = self._tid
        async with asyncio.timeout(self.timeout_s):
            self._writer.write(build_mbap(tid, self.unit_id, pdu))
            await self._writer.drain()
            header = await self._reader.readexactly(MBAP_LEN)
            length = struct.unpack(">H", header[4:6])[0]
            if length < 2 or length > MAX_PDU_LEN + 1:
                raise ModbusError(f"nesmyslná délka v MBAP: {length}")
            body = await self._reader.readexactly(length - 1)
        return parse_response(header + body, tid)

    # ── vysokoúrovňové operace ──
    async def read_coils(self, addr: int, count: int) -> list[bool]:
        """FC01 — čtení stavu relé."""
        pdu = await self.request(struct.pack(">BHH", FC_READ_COILS, _check_u16(addr, "addr"), _check_u16(count, "count")))
        return self._parse_bits(pdu, FC_READ_COILS, count)

    async def read_discrete_inputs(self, addr: int, count: int) -> list[bool]:
        """FC02 — čtení digitálních vstupů."""
        pdu = await self.request(struct.pack(">BHH", FC_READ_DISCRETE_INPUTS, _check_u16(addr, "addr"), _check_u16(count, "count")))
        return self._parse_bits(pdu, FC_READ_DISCRETE_INPUTS, count)

    async def read_holding_registers(self, addr: int, count: int) -> list[int]:
        """FC03 — čtení 16bit registrů (big-endian)."""
        pdu = await self.request(struct.pack(">BHH", FC_READ_HOLDING_REGISTERS, _check_u16(addr, "addr"), _check_u16(count, "count")))
        if len(pdu) < 2 or pdu[0] != FC_READ_HOLDING_REGISTERS:
            raise ModbusError(f"{self.name}: neočekávaná odpověď FC03: {pdu.hex()}")
        n = pdu[1]
        data = pdu[2:2 + n]
        if n != 2 * count or len(data) < n:
            raise ModbusError(f"{self.name}: FC03 byte count {n} neodpovídá {count} registrům")
        return list(struct.unpack(f">{count}H", data))

    async def write_coil(self, addr: int, on: bool) -> None:
        """FC05 — zapnutí/vypnutí jednoho relé (0xFF00 / 0x0000)."""
        await self.write_coil_raw(addr, COIL_ON if on else COIL_OFF)

    async def write_coil_raw(self, addr: int, value: int, *, retry: bool = True) -> None:
        """FC05 s libovolnou 16bit hodnotou (Waveshare flash-on, all-off 0x00FF). Ověřuje echo."""
        req = struct.pack(">BHH", FC_WRITE_SINGLE_COIL, _check_u16(addr, "addr"), _check_u16(value, "value"))
        resp = await self.request(req, retry=retry)
        if resp != req:
            raise ModbusError(f"{self.name}: FC05 echo nesouhlasí: {resp.hex()} != {req.hex()}")

    async def write_register(self, addr: int, value: int) -> None:
        """FC06 — zápis jednoho registru. Ověřuje echo."""
        req = struct.pack(">BHH", FC_WRITE_SINGLE_REGISTER, _check_u16(addr, "addr"), _check_u16(value, "value"))
        resp = await self.request(req)
        if resp != req:
            raise ModbusError(f"{self.name}: FC06 echo nesouhlasí: {resp.hex()} != {req.hex()}")

    def _parse_bits(self, pdu: bytes, fc: int, count: int) -> list[bool]:
        if len(pdu) < 2 or pdu[0] != fc:
            raise ModbusError(f"{self.name}: neočekávaná odpověď FC{fc:02X}: {pdu.hex()}")
        n = pdu[1]
        data = pdu[2:2 + n]
        if len(data) < n or n < (count + 7) // 8:
            raise ModbusError(f"{self.name}: FC{fc:02X} byte count {n} nestačí pro {count} bitů")
        return bits_from_bytes(data, count)
