"""Simulátor Waveshare Modbus TCP modulu (WAV645 / WAV617) — kontrakt §20.

Implementuje FC01/02/03/05/06 včetně Waveshare rozšíření: 0x00FF (všechna relé),
0x0200+n flash-on (auto vypnutí po n × 100 ms) a mode registry 0x1000–0x1007.
Neznámá adresa → exception 0x02, neznámá funkce → 0x01, špatná hodnota → 0x03.
Použitelný in-process v testech (`await start()` / `await stop()`, port 0 = dynamický).
"""
from __future__ import annotations

import asyncio
import logging
import struct

log = logging.getLogger("motogo.sim.modbus")

MBAP_LEN = 7
ALL_COILS_ADDR = 0x00FF
FLASH_ON_BASE = 0x0200
FLASH_STEP_S = 0.1
MODE_REG_BASE = 0x1000
COIL_ON = 0xFF00
COIL_OFF = 0x0000
MODULE_COILS = {"wav645": 16, "wav617": 8}
MODULE_INPUTS = {"wav645": 0, "wav617": 8}


class SimException(Exception):
    """Modbus exception odpověď (kód 0x01–0x04)."""

    def __init__(self, code: int) -> None:
        self.code = code
        super().__init__(f"modbus exception 0x{code:02X}")


def _pack_bits(bits: list[bool]) -> bytes:
    out = bytearray((len(bits) + 7) // 8)
    for i, b in enumerate(bits):
        if b:
            out[i >> 3] |= 1 << (i & 7)
    return bytes(out)


class SimRelayModule:
    """Falešný WAV645 (16 relé) nebo WAV617 (8 relé + 8 vstupů) na Modbus TCP.

    Atributy `coils`, `inputs` (seznamy bool) a `registers` (dict adresa → hodnota)
    lze v testech číst i měnit přímo. Vstupy WAV617 startují jako True
    (= zavřené dveře při `contacts.closed_level: 1`).
    """

    def __init__(self, kind: str, host: str = "127.0.0.1", port: int = 0, *,
                 name: str | None = None, default_input: bool = True) -> None:
        kind = kind.lower()
        if kind not in MODULE_COILS:
            raise ValueError(f"neznámý typ modulu '{kind}' (wav645|wav617)")
        self.kind = kind
        self.name = name or kind
        self.host = host
        self.port = int(port)
        self.default_input = default_input
        self.coils: list[bool] = [False] * MODULE_COILS[kind]
        self.inputs: list[bool] = [default_input] * MODULE_INPUTS[kind]
        self.registers: dict[int, int] = {MODE_REG_BASE + i: 0 for i in range(len(self.coils))}
        self.request_count = 0
        self._flash_tasks: dict[int, asyncio.Task] = {}
        self._server: asyncio.AbstractServer | None = None
        self._clients: set[asyncio.StreamWriter] = set()

    # ── životní cyklus ──
    async def start(self) -> None:
        if self._server is not None:
            return
        self._server = await asyncio.start_server(self._handle_client, self.host, self.port)
        self.port = self._server.sockets[0].getsockname()[1]
        log.info("%s (%s) naslouchá na %s:%d", self.name, self.kind, self.host, self.port)

    async def stop(self) -> None:
        for task in list(self._flash_tasks.values()):
            task.cancel()
        self._flash_tasks.clear()
        for writer in list(self._clients):
            writer.close()
        self._clients.clear()
        server, self._server = self._server, None
        if server is not None:
            server.close()
            await server.wait_closed()

    def reset(self) -> None:
        """Všechna relé vypnout, vstupy na výchozí hodnotu, registry na 0."""
        for task in list(self._flash_tasks.values()):
            task.cancel()
        self._flash_tasks.clear()
        self.coils = [False] * len(self.coils)
        self.inputs = [self.default_input] * len(self.inputs)
        for addr in self.registers:
            self.registers[addr] = 0

    def set_input(self, idx: int, value: bool) -> None:
        if not 0 <= idx < len(self.inputs):
            raise IndexError(f"{self.name}: vstup {idx} neexistuje")
        self.inputs[idx] = bool(value)

    def state(self) -> dict:
        return {"kind": self.kind, "host": self.host, "port": self.port,
                "coils": list(self.coils), "inputs": list(self.inputs),
                "registers": {f"0x{a:04X}": v for a, v in sorted(self.registers.items())},
                "requests": self.request_count}

    # ── TCP ──
    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._clients.add(writer)
        try:
            while True:
                header = await reader.readexactly(MBAP_LEN)
                tid, _proto, length, unit = struct.unpack(">HHHB", header)
                if length < 2:
                    break
                pdu = await reader.readexactly(length - 1)
                self.request_count += 1
                resp = self.handle_pdu(pdu)
                writer.write(struct.pack(">HHHB", tid, 0, len(resp) + 1, unit) + resp)
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError, asyncio.CancelledError):
            pass
        finally:
            self._clients.discard(writer)
            writer.close()

    # ── PDU ──
    def handle_pdu(self, pdu: bytes) -> bytes:
        """Zpracuje PDU požadavku a vrátí PDU odpovědi (čistá funkce nad stavem)."""
        if not pdu:
            return bytes([0x80, 0x03])
        fc = pdu[0]
        handlers = {0x01: self._fc_read_coils, 0x02: self._fc_read_inputs, 0x03: self._fc_read_regs,
                    0x05: self._fc_write_coil, 0x06: self._fc_write_reg}
        try:
            handler = handlers.get(fc)
            if handler is None:
                raise SimException(0x01)
            return handler(pdu)
        except SimException as exc:
            return bytes([fc | 0x80, exc.code])
        except struct.error:
            return bytes([fc | 0x80, 0x03])

    def _fc_read_coils(self, pdu: bytes) -> bytes:
        addr, count = struct.unpack(">HH", pdu[1:5])
        if not 1 <= count <= 2000:
            raise SimException(0x03)
        if addr + count > len(self.coils):
            raise SimException(0x02)
        data = _pack_bits(self.coils[addr:addr + count])
        return bytes([0x01, len(data)]) + data

    def _fc_read_inputs(self, pdu: bytes) -> bytes:
        if not self.inputs:
            raise SimException(0x01)
        addr, count = struct.unpack(">HH", pdu[1:5])
        if not 1 <= count <= 2000:
            raise SimException(0x03)
        if addr + count > len(self.inputs):
            raise SimException(0x02)
        data = _pack_bits(self.inputs[addr:addr + count])
        return bytes([0x02, len(data)]) + data

    def _fc_read_regs(self, pdu: bytes) -> bytes:
        addr, count = struct.unpack(">HH", pdu[1:5])
        if not 1 <= count <= 125:
            raise SimException(0x03)
        addrs = range(addr, addr + count)
        if any(a not in self.registers for a in addrs):
            raise SimException(0x02)
        data = b"".join(struct.pack(">H", self.registers[a]) for a in addrs)
        return bytes([0x03, len(data)]) + data

    def _fc_write_coil(self, pdu: bytes) -> bytes:
        addr, value = struct.unpack(">HH", pdu[1:5])
        n = len(self.coils)
        if addr < n:
            if value not in (COIL_ON, COIL_OFF):
                raise SimException(0x03)
            self._set_coil(addr, value == COIL_ON)
        elif addr == ALL_COILS_ADDR:
            if value not in (COIL_ON, COIL_OFF):
                raise SimException(0x03)
            for i in range(n):
                self._set_coil(i, value == COIL_ON)
        elif FLASH_ON_BASE <= addr < FLASH_ON_BASE + n:
            if value == 0:
                raise SimException(0x03)
            self._flash_on(addr - FLASH_ON_BASE, value)
        else:
            raise SimException(0x02)
        return bytes(pdu[:5])

    def _fc_write_reg(self, pdu: bytes) -> bytes:
        addr, value = struct.unpack(">HH", pdu[1:5])
        if addr not in self.registers:
            raise SimException(0x02)
        self.registers[addr] = value
        return bytes(pdu[:5])

    # ── stav relé ──
    def _cancel_flash(self, idx: int) -> None:
        task = self._flash_tasks.pop(idx, None)
        if task is not None and not task.done():
            task.cancel()

    def _set_coil(self, idx: int, on: bool) -> None:
        self._cancel_flash(idx)
        self.coils[idx] = on

    def _flash_on(self, idx: int, steps: int) -> None:
        self._cancel_flash(idx)
        self.coils[idx] = True
        self._flash_tasks[idx] = asyncio.get_running_loop().create_task(self._flash_off(idx, steps * FLASH_STEP_S))

    async def _flash_off(self, idx: int, delay_s: float) -> None:
        try:
            await asyncio.sleep(delay_s)
            self.coils[idx] = False
        except asyncio.CancelledError:
            pass
        finally:
            self._flash_tasks.pop(idx, None)
