"""Testy Modbus TCP klienta (kontrakt §21): framing, exception, klient proti simulátoru, offline."""
from __future__ import annotations

import asyncio
import socket

import pytest

from motogo_box.modbus import (ModbusError, ModbusExceptionResponse, ModbusTcpClient,
                               bits_from_bytes, build_mbap, parse_response)
from motogo_box.tools.simulator import SimRelayModule


# ─── čisté funkce ────────────────────────────────────────────────────────────
def test_build_mbap_header():
    pdu = bytes([0x01, 0x00, 0x00, 0x00, 0x10])
    frame = build_mbap(0x1234, 1, pdu)
    assert frame == bytes([0x12, 0x34, 0x00, 0x00, 0x00, 0x06, 0x01]) + pdu
    assert build_mbap(0x1FFFF, 0x1FF, pdu)[:2] == b"\xff\xff"          # tid/unit se ořezávají


def test_parse_response_ok_and_errors():
    pdu = bytes([0x01, 0x02, 0x05, 0x00])
    frame = build_mbap(7, 1, pdu)
    assert parse_response(frame, 7) == pdu
    with pytest.raises(ModbusError):
        parse_response(frame, 8)                                       # tid nesouhlasí
    with pytest.raises(ModbusError):
        parse_response(frame[:-1], 7)                                  # délka nesouhlasí
    with pytest.raises(ModbusError):
        parse_response(b"\x00\x07\x00\x01\x00\x02\x01\x01", 7)         # protocol id != 0
    with pytest.raises(ModbusError):
        parse_response(b"\x00\x07\x00\x00\x00\x01\x01", 7)             # bez PDU


def test_parse_response_exception_frame():
    frame = build_mbap(3, 1, bytes([0x85, 0x02]))
    with pytest.raises(ModbusExceptionResponse) as ei:
        parse_response(frame, 3)
    assert ei.value.function == 0x05 and ei.value.code == 0x02
    assert isinstance(ei.value, ModbusError)


def test_bits_from_bytes():
    assert bits_from_bytes(b"\x05", 3) == [True, False, True]
    assert bits_from_bytes(b"\x01\x01", 9) == [True] + [False] * 7 + [True]
    assert bits_from_bytes(b"", 0) == []
    with pytest.raises(ModbusError):
        bits_from_bytes(b"\x01", 9)


# ─── klient proti simulátoru ─────────────────────────────────────────────────
@pytest.fixture
async def sim645():
    sim = SimRelayModule("wav645", "127.0.0.1", 0)
    await sim.start()
    yield sim
    await sim.stop()


@pytest.fixture
async def sim617():
    sim = SimRelayModule("wav617", "127.0.0.1", 0)
    await sim.start()
    yield sim
    await sim.stop()


def _client(sim: SimRelayModule, **kw) -> ModbusTcpClient:
    kw.setdefault("timeout_ms", 300)
    kw.setdefault("retry_delays_ms", (10, 20))
    return ModbusTcpClient("127.0.0.1", sim.port, 1, name=sim.name, **kw)


async def test_constructor_is_lazy(sim645):
    c = _client(sim645)
    assert not c.connected and c.online and c.failures == 0
    await c.close()                                                    # close bez spojení je no-op


async def test_read_write_coils(sim645):
    c = _client(sim645)
    try:
        assert await c.read_coils(0, 16) == [False] * 16
        await c.write_coil(3, True)
        assert sim645.coils[3] is True
        states = await c.read_coils(0, 16)
        assert states[3] is True and sum(states) == 1
        await c.write_coil(3, False)
        assert await c.read_coils(3, 1) == [False]
        assert c.connected and c.online
    finally:
        await c.close()


async def test_flash_on_and_all_off(sim645):
    c = _client(sim645)
    try:
        await c.write_coil_raw(0x0200 + 5, 2)                          # 2 × 100 ms
        assert (await c.read_coils(5, 1)) == [True]
        await asyncio.sleep(0.35)
        assert (await c.read_coils(5, 1)) == [False]                   # modul vypnul sám
        await c.write_coil(0, True)
        await c.write_coil(15, True)
        await c.write_coil_raw(0x00FF, 0x0000)                         # all off
        assert await c.read_coils(0, 16) == [False] * 16
    finally:
        await c.close()


async def test_exception_response_no_retry_and_stays_online(sim645):
    c = _client(sim645)
    try:
        before = sim645.request_count
        with pytest.raises(ModbusExceptionResponse) as ei:
            await c.read_coils(0x0300, 1)
        assert ei.value.code == 0x02
        assert sim645.request_count == before + 1                      # bez opakování
        assert c.online and c.failures == 0
        with pytest.raises(ModbusError):
            await c.read_discrete_inputs(0, 8)                         # WAV645 nemá vstupy → 0x01
        with pytest.raises(ModbusError):
            await c.write_coil_raw(0x00FF, 0x1234)                     # neplatná hodnota → 0x03
    finally:
        await c.close()


async def test_inputs_and_registers(sim617):
    c = _client(sim617)
    try:
        assert await c.read_discrete_inputs(0, 8) == [True] * 8
        sim617.set_input(2, False)
        vals = await c.read_discrete_inputs(0, 8)
        assert vals[2] is False and vals.count(False) == 1
        sim617.registers[0x1003] = 2
        assert await c.read_holding_registers(0x1000, 8) == [0, 0, 0, 2, 0, 0, 0, 0]
        await c.write_register(0x1003, 0)
        assert sim617.registers[0x1003] == 0
        with pytest.raises(ModbusError):
            await c.write_register(0x2000, 1)
    finally:
        await c.close()


async def test_transaction_ids_and_lock(sim645):
    c = _client(sim645)
    try:
        results = await asyncio.gather(*(c.read_coils(0, 16) for _ in range(20)))
        assert all(r == [False] * 16 for r in results)
        assert c._tid == 20
    finally:
        await c.close()


# ─── offline / recovery ──────────────────────────────────────────────────────
def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def test_offline_after_three_failures_and_recovery():
    port = _free_port()
    changes: list[tuple[str, bool]] = []
    c = ModbusTcpClient("127.0.0.1", port, 1, timeout_ms=50, retry_delays_ms=(5, 5),
                        offline_after=3, name="wav645")
    c.on_online_change = lambda name, online: changes.append((name, online))
    for i in range(1, 4):
        with pytest.raises(ModbusError):
            await c.read_coils(0, 16)
        assert c.failures == i
        assert c.online == (i < 3)
    assert changes == [("wav645", False)]

    sim = SimRelayModule("wav645", "127.0.0.1", port)                  # modul „naběhne“
    await sim.start()
    try:
        assert await c.read_coils(0, 16) == [False] * 16
        assert c.online and c.failures == 0
        assert changes == [("wav645", False), ("wav645", True)]
    finally:
        await c.close()
        await sim.stop()


async def test_reconnect_after_server_restart(sim645):
    c = _client(sim645)
    try:
        await c.write_coil(1, True)
        port = sim645.port
        await sim645.stop()                                            # spojení spadne (EOF)
        sim645.coils[1] = True
        sim645.port = port
        await sim645.start()                                           # stejný port
        assert (await c.read_coils(1, 1)) == [True]                    # reconnect + retry
        assert c.online
    finally:
        await c.close()
