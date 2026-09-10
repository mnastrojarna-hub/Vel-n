"""Testy Waveshare modulů a IoBus (kontrakt §21): all_off ověřený, HW flash, Normal mode, offline."""
from __future__ import annotations

import asyncio
import socket

import pytest

from motogo_box.config import HardwareConfig
from motogo_box.io_devices import IoBus, Wav617, Wav645, make_module
from motogo_box.modbus import ModbusError, ModbusTcpClient
from motogo_box.models import HwRef
from motogo_box.tools.simulator import SimRelayModule


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
async def sims():
    """wav645 + wav617a běží; wav617b má zavřený port (offline modul)."""
    a = SimRelayModule("wav645", "127.0.0.1", 0, name="wav645")
    b = SimRelayModule("wav617", "127.0.0.1", 0, name="wav617a")
    await a.start()
    await b.start()
    yield {"wav645": a, "wav617a": b, "dead_port": _free_port()}
    await a.stop()
    await b.stop()


def _hw(sims: dict) -> HardwareConfig:
    d = {
        "devices": {
            "wav645": {"type": "wav645", "host": "127.0.0.1", "port": sims["wav645"].port},
            "wav617a": {"type": "wav617", "host": "127.0.0.1", "port": sims["wav617a"].port},
            "wav617b": {"type": "wav617", "host": "127.0.0.1", "port": sims["dead_port"]},
            "shelly1": {"type": "shelly_rgbww", "host": "127.0.0.1", "port": 18031},
        },
        "polling": {"modbus_timeout_ms": 100, "retry_delays_ms": [5, 5], "device_offline_after_failures": 3},
        "zones": [{"zone": 1, "lock": {"dev": "wav645", "coil": 0}, "contact": {"dev": "wav617a", "input": 0},
                   "light": {"dev": "wav617a", "coil": 0}, "audio": {"dev": "wav645", "coil": 9}}],
    }
    return HardwareConfig.from_dict(d)


# ─── moduly ──────────────────────────────────────────────────────────────────
async def test_make_module_types(sims):
    hw = _hw(sims)
    m645 = make_module("wav645", hw.devices["wav645"], hw.polling)
    m617 = make_module("wav617a", hw.devices["wav617a"], hw.polling)
    assert isinstance(m645, Wav645) and m645.coils == 16 and m645.inputs == 0 and m645.HW_FLASH
    assert isinstance(m617, Wav617) and m617.coils == 8 and m617.inputs == 8 and not m617.HW_FLASH
    assert m645.client.timeout_s == 0.1 and m645.client.offline_after == 3
    assert not m645.client.connected                                    # líné připojení
    with pytest.raises(ValueError):
        make_module("shelly1", hw.devices["shelly1"], hw.polling)


async def test_wav645_all_off_verified(sims):
    sim = sims["wav645"]
    m = Wav645("wav645", ModbusTcpClient("127.0.0.1", sim.port, timeout_ms=200, retry_delays_ms=(5,)))
    try:
        sim.coils[2] = True
        sim.coils[10] = True
        assert await m.all_off() is True
        assert sim.coils == [False] * 16
        assert await m.read_coils() == [False] * 16
    finally:
        await m.stop()


async def test_wav645_set_coil_verifies(sims):
    sim = sims["wav645"]
    m = Wav645("wav645", ModbusTcpClient("127.0.0.1", sim.port, timeout_ms=200, retry_delays_ms=(5,)))
    try:
        assert await m.set_coil(9, True) is True and sim.coils[9] is True
        assert await m.set_coil(9, False) is True and sim.coils[9] is False
        with pytest.raises(ValueError):
            await m.set_coil(16, True)
        assert await m.read_inputs() == []                              # bez vstupů, bez komunikace
    finally:
        await m.stop()


async def test_wav645_pulse_is_hw_flash(sims):
    sim = sims["wav645"]
    m = Wav645("wav645", ModbusTcpClient("127.0.0.1", sim.port, timeout_ms=200, retry_delays_ms=(5,)))
    try:
        t0 = asyncio.get_running_loop().time()
        assert await m.pulse(0, 200) is True                            # 2 × 100 ms
        assert asyncio.get_running_loop().time() - t0 < 0.15            # nečeká na vypnutí
        assert sim.coils[0] is True
        await asyncio.sleep(0.3)
        assert sim.coils[0] is False                                    # vypnul modul sám
        assert await m.pulse(1, 40) is True                             # min 1 krok
        assert sim.coils[1] is True
    finally:
        await m.stop()


async def test_wav617_pulse_is_software(sims):
    sim = sims["wav617a"]
    m = Wav617("wav617a", ModbusTcpClient("127.0.0.1", sim.port, timeout_ms=200, retry_delays_ms=(5,)))
    try:
        seen: list[bool] = []

        async def watch():
            for _ in range(20):
                seen.append(sim.coils[2])
                await asyncio.sleep(0.01)

        ok, _ = await asyncio.gather(m.pulse(2, 100), watch())
        assert ok is True
        assert True in seen and sim.coils[2] is False
    finally:
        await m.stop()


async def test_wav617_set_normal_mode(sims):
    sim = sims["wav617a"]
    m = Wav617("wav617a", ModbusTcpClient("127.0.0.1", sim.port, timeout_ms=200, retry_delays_ms=(5,)))
    try:
        for r in range(8):
            sim.registers[0x1000 + r] = 1                               # linkage/toggle režim
        assert await m.set_normal_mode() is True
        assert [sim.registers[0x1000 + r] for r in range(8)] == [0] * 8
        sim.registers[0x1005] = 3
        await m.start()                                                 # start = connect + normal mode
        assert sim.registers[0x1005] == 0 and m.client.connected
        sim.set_input(4, False)
        assert (await m.read_inputs())[4] is False
    finally:
        await m.stop()


async def test_offline_module_operations_return_false(sims):
    m = Wav617("wav617b", ModbusTcpClient("127.0.0.1", sims["dead_port"], timeout_ms=50,
                                          retry_delays_ms=(5,), offline_after=1))
    assert await m.set_normal_mode() is False
    assert not m.online
    assert await m.set_coil(0, True) is False
    assert await m.all_off() is False
    assert await m.pulse(0, 50) is False


# ─── IoBus ───────────────────────────────────────────────────────────────────
async def test_iobus_read_all_inputs_and_offline(sims):
    bus = IoBus(_hw(sims))
    assert set(bus.modules) == {"wav645", "wav617a", "wav617b"}
    changes: list[tuple[str, bool]] = []
    bus.on_online_change = lambda n, o: changes.append((n, o))
    try:
        await bus.start()
        sims["wav617a"].set_input(3, False)
        snap = await bus.read_all_inputs()
        assert snap["wav645"] == []                                     # sonda relé, bez vstupů
        assert snap["wav617a"] == [True, True, True, False, True, True, True, True]
        assert snap["wav617b"] is None                                  # offline modul
        assert bus.input_value(snap, HwRef("wav617a", 3)) is False
        assert bus.input_value(snap, HwRef("wav617a", 0)) is True
        assert bus.input_value(snap, HwRef("wav617b", 0)) is None
        assert bus.input_value(snap, HwRef("wav617a", 8)) is None
        assert bus.input_value(snap, HwRef("nope", 0)) is None
        for _ in range(3):
            await bus.read_all_inputs()
        assert bus.is_online("wav617a") and bus.is_online("wav645")
        assert not bus.is_online("wav617b") and not bus.is_online("unknown")
        assert ("wav617b", False) in changes
        with pytest.raises(KeyError):
            bus.get("unknown")
        assert bus.get("wav645").coils == 16
    finally:
        await bus.stop()


async def test_iobus_set_pulse_all_off(sims):
    bus = IoBus(_hw(sims))
    try:
        await bus.start()
        await bus.read_all_inputs()
        assert await bus.set(HwRef("wav617a", 0), True) is True
        assert sims["wav617a"].coils[0] is True
        assert await bus.pulse(HwRef("wav645", 0), 800) is True
        assert sims["wav645"].coils[0] is True
        assert await bus.set(HwRef("unknown", 0), True) is False
        assert await bus.set(HwRef("wav617a", 99), True) is False
        for _ in range(3):
            await bus.read_all_inputs()                                 # wav617b → offline
        assert await bus.set(HwRef("wav617b", 0), True) is False
        assert await bus.pulse(HwRef("wav617b", 0), 100) is False
        result = await bus.all_off()
        assert result == {"wav645": True, "wav617a": True, "wav617b": False}
        assert sims["wav645"].coils == [False] * 16
        assert sims["wav617a"].coils == [False] * 8
    finally:
        await bus.stop()


# ─── review: pomalý poll při offline modulu, obnova po návratu, zombie po stop ──
@pytest.fixture
async def silent_server():
    """TCP server, který spojení přijme, ale nikdy neodpoví (modul „visí" → timeouty)."""
    holders: list[asyncio.StreamWriter] = []

    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        holders.append(writer)
        try:
            await reader.read()
        finally:
            writer.close()

    srv = await asyncio.start_server(handle, "127.0.0.1", 0)
    yield srv.sockets[0].getsockname()[1]
    for w in holders:
        w.close()
    srv.close()
    await srv.wait_closed()


async def test_offline_module_does_not_slow_polling(sims, silent_server, monkeypatch):
    """Nález 1: nedostupný modul (timeout) nesmí zdržet momentku ostatních zón (poll 100 ms)."""
    from motogo_box import io_probe
    monkeypatch.setattr(io_probe, "PROBE_INTERVAL_S", 0.05)
    hw = _hw({**sims, "dead_port": silent_server})
    bus = IoBus(hw)
    try:
        await bus.start()                                               # wav617b: Normal mode timeoutuje
        snap = await bus.read_all_inputs()                              # zbytek selhání → offline
        assert snap["wav617b"] is None and not bus.is_online("wav617b")
        assert bus._probes.active("wav617b")                            # sonda běží mimo poll
        loop = asyncio.get_running_loop()
        for _ in range(5):
            t0 = loop.time()
            snap = await bus.read_all_inputs()
            assert loop.time() - t0 < 0.1, "offline modul zdržel poll"
            assert snap["wav617b"] is None
            assert snap["wav617a"] == [True] * 8 and snap["wav645"] == []
            await asyncio.sleep(0.02)
        assert await bus.set(HwRef("wav617b", 0), True) is False        # offline → odmítnuto
        assert bus.is_online("wav617a") and bus.is_online("wav645")
    finally:
        await bus.stop()
    assert not bus._probes.active("wav617b")                            # sonda zrušena při stop


async def test_module_recovers_with_normal_mode_and_all_off(sims, monkeypatch):
    """Nález 2: modul nedostupný při startu → po naběhnutí Normal mode + all_off, pak k dispozici."""
    from motogo_box import io_probe
    monkeypatch.setattr(io_probe, "PROBE_INTERVAL_S", 0.05)
    port = _free_port()
    late = SimRelayModule("wav617", "127.0.0.1", port, name="wav617b")
    for r in range(8):
        late.registers[0x1000 + r] = 2                                  # modul „zapomněl" Normal mode
    late.coils[3] = True                                                # a má sepnuté relé
    hw = _hw({**sims, "dead_port": port})
    bus = IoBus(hw)
    changes: list[tuple[str, bool]] = []
    bus.on_online_change = lambda n, o: changes.append((n, o))
    try:
        await bus.start()
        assert bus.get("wav617b").needs_reinit                          # start bez Normal mode
        snap = await bus.read_all_inputs()
        assert snap["wav617b"] is None and not bus.is_online("wav617b")
        await late.start()                                              # modul naběhl později
        for _ in range(60):
            snap = await bus.read_all_inputs()
            if snap["wav617b"] is not None:
                break
            await asyncio.sleep(0.05)
        assert snap["wav617b"] == [True] * 8
        assert bus.is_online("wav617b") and ("wav617b", True) in changes
        assert [late.registers[0x1000 + r] for r in range(8)] == [0] * 8  # Normal mode znovu
        assert late.coils == [False] * 8                                # all_off po návratu
        assert not bus.get("wav617b").needs_reinit
        assert await bus.set(HwRef("wav617b", 0), True) is True and late.coils[0] is True
    finally:
        await bus.stop()
        await late.stop()


async def test_online_return_outside_probe_triggers_reinit(sims):
    """Návrat online jinou cestou (např. all_off z Velína) také vynutí obnovu modulu."""
    m = Wav617("wav617a", ModbusTcpClient("127.0.0.1", sims["wav617a"].port, timeout_ms=200,
                                          retry_delays_ms=(5,), offline_after=1, name="wav617a"))
    hw = _hw(sims)
    bus = IoBus(hw)
    bus.modules = {"wav617a": m}
    m.client.on_online_change = bus._online_changed
    try:
        m.client._set_online(False)                                     # simulace výpadku
        sims["wav617a"].registers[0x1002] = 1
        assert await m.all_off() is True                                # modul odpověděl → online
        assert m.online and m.needs_reinit
        snap = await bus.read_all_inputs()                              # inline obnova před čtením
        assert snap["wav617a"] == [True] * 8 and not m.needs_reinit
        assert sims["wav617a"].registers[0x1002] == 0
    finally:
        await bus.stop()


async def test_stopped_bus_is_zombie_proof(sims):
    """Nález 3: po stop() je modul trvale uzavřený — žádný reconnect, žádné spínání relé."""
    bus = IoBus(_hw(sims))
    await bus.start()
    await bus.read_all_inputs()
    assert bus.is_online("wav645")
    await bus.stop()
    before = sims["wav617a"].request_count
    assert bus.closed and all(m.closed for m in bus.modules.values())
    assert not bus.is_online("wav645") and not bus.get("wav645").online
    assert await bus.set(HwRef("wav645", 9), True) is False
    assert await bus.pulse(HwRef("wav645", 0), 500) is False
    assert sims["wav645"].coils == [False] * 16                         # nic se nesepnulo
    assert await bus.read_all_inputs() == {"wav645": None, "wav617a": None, "wav617b": None}
    assert not bus.get("wav645").client.connected                       # spojení se neobnovilo
    with pytest.raises(ModbusError):
        await bus.get("wav617a").read_inputs()
    assert await bus.get("wav617a").set_normal_mode() is False
    assert await bus.get("wav617a").all_off() is False
    assert await bus.get("wav617a").pulse(0, 20) is False
    assert sims["wav617a"].request_count == before                      # žádné další requesty
