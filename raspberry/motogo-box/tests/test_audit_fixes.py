"""Regresní testy k nálezům revize 2026-09-10: souběh hudby, Shelly 4xx, pulz zámku, meze mapy,
odložená přestavba HW, expirace cache servisních hesel, strop outboxu, UUID kanonizace."""
from __future__ import annotations

import asyncio
import time

import pytest
from aiohttp import web

from motogo_box.audio import AudioController, AudioSelector
from motogo_box.config import AudioCfg, HardwareConfig, validate_hardware
from motogo_box.io_devices import IoBus
from motogo_box.models import HwRef, Zone, ZoneHw
from motogo_box.mpv_player import MpvPlayer
from motogo_box.shelly import ShellyRgbww
from motogo_box.storage import OUTBOX_MAX, Storage
from motogo_box.supabase_api import canonical_uuid
from motogo_box.tools.simulator import SimRelayModule


def _hw(port: int) -> HardwareConfig:
    return HardwareConfig.from_dict({
        "devices": {"wav617b": {"type": "wav617", "host": "127.0.0.1", "port": port}},
        "audio": {"fade_in_ms": 0, "fade_out_ms": 200, "selector_settle_ms": 50, "selector_on_ms": 10},
        "polling": {"modbus_timeout_ms": 300, "retry_delays_ms": []},
        "zones": [{"zone": 1, "lock": {"dev": "wav617b", "coil": 0}, "contact": {"dev": "wav617b", "input": 0}, "audio": {"dev": "wav617b", "coil": 1}},
                  {"zone": 2, "lock": {"dev": "wav617b", "coil": 2}, "contact": {"dev": "wav617b", "input": 1}, "audio": {"dev": "wav617b", "coil": 3}}],
    })


class SlowPlayer(MpvPlayer):
    """Dummy mpv s pomalým fade (simuluje 500 ms fade_out během play_zone jiné zóny)."""

    def __init__(self, tmp) -> None:
        super().__init__(str(tmp / "mpv.sock"), str(tmp), None)
        self._dummy = True
        self.playlist_count = 3
        self.volume = 50

    @property
    def alive(self) -> bool:  # type: ignore[override]
        return True

    async def fade(self, to: int, ms: int) -> bool:
        await asyncio.sleep(0.2)
        self.volume = to
        return True

    async def set_volume(self, v: int) -> bool:
        self.volume = v
        return True

    async def pause(self) -> bool:
        return True

    async def play(self) -> bool:
        return True


async def test_stop_zone_does_not_kill_music_of_new_zone(tmp_path):
    """zone-safety#0: čekající stop zóny 1 nesmí vypnout hudbu zóně 2, která reproduktor převzala."""
    sim = SimRelayModule("wav617", name="wav617b")
    await sim.start()
    try:
        hw = _hw(sim.port)
        bus = IoBus(hw)
        await bus.start()
        audio = AudioController(SlowPlayer(tmp_path), AudioSelector(bus, hw.zones, hw.audio), hw.audio)
        assert await audio.play_zone(1)
        t2 = asyncio.create_task(audio.play_zone(2))      # drží zámek a fade-outuje zónu 1
        await asyncio.sleep(0.05)
        assert audio.playing_zone == 1                     # stále 1 (uvnitř _stop_locked)
        stopped = await audio.stop_zone(1)                 # čeká na zámek → po převzetí zónou 2 nic nedělá
        await t2
        assert stopped is False and audio.playing_zone == 2 and audio.selector.active_zone == 2
        assert await audio.stop_zone(2) is True and audio.playing_zone is None
        await audio.close()
        await bus.stop()
    finally:
        await sim.stop()


async def test_shelly_4xx_keeps_device_online():
    """io-layer#0: odmítnutý RPC (4xx) = zařízení online; offline až síťová chyba / 5xx."""
    calls = {"n": 0}

    async def rpc(request: web.Request) -> web.Response:
        calls["n"] += 1
        return web.json_response({"error": {"code": -103, "message": "bad id"}}, status=400)

    app = web.Application()
    app.router.add_post("/rpc", rpc)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]      # noqa: SLF001
    try:
        dev = ShellyRgbww("s1", f"127.0.0.1:{port}", offline_after=2)
        for _ in range(4):
            assert await dev.light_set(9, True) is False
        assert dev.online is True and dev.failures == 0
        await dev.close()
    finally:
        await runner.cleanup()


async def test_pulse_verification_after_pulse_end_counts_as_delivered(monkeypatch):
    """io-layer#2: ověření FC01 doběhlo až po skončení pulzu (relé už legitimně odpadlo) → pulz doručen."""
    sim = SimRelayModule("wav645", name="wav645")
    await sim.start()
    try:
        hw = HardwareConfig.from_dict({"devices": {"wav645": {"type": "wav645", "host": "127.0.0.1", "port": sim.port}},
                                       "polling": {"modbus_timeout_ms": 300, "retry_delays_ms": []}})
        bus = IoBus(hw)
        await bus.start()
        module = bus.get("wav645")
        real_read = module.client.read_coils

        async def slow_read(addr, count):
            await asyncio.sleep(0.15)                      # pulz 100 ms už skončil
            return await real_read(addr, count)

        monkeypatch.setattr(module.client, "read_coils", slow_read)
        assert await bus.pulse(HwRef("wav645", 0), 100) is True
        await bus.stop()
    finally:
        await sim.stop()


async def test_flash_on_is_sent_without_retry(monkeypatch):
    """io-layer#3: FC05 flash-on je neidempotentní — při ztracené odpovědi se NEopakuje."""
    sim = SimRelayModule("wav645", name="wav645")
    await sim.start()
    try:
        hw = HardwareConfig.from_dict({"devices": {"wav645": {"type": "wav645", "host": "127.0.0.1", "port": sim.port}},
                                       "polling": {"modbus_timeout_ms": 200, "retry_delays_ms": [10, 10]}})
        bus = IoBus(hw)
        await bus.start()
        client = bus.get("wav645").client
        seen: list[bool] = []
        real = client._request_locked

        async def spy(pdu, retry=True):
            seen.append(retry)
            return await real(pdu, retry)

        monkeypatch.setattr(client, "_request_locked", spy)
        assert await bus.pulse(HwRef("wav645", 1), 200) is True
        assert seen[0] is False and all(seen[1:])           # flash-on bez retry, ověření s retry
        await bus.stop()
    finally:
        await sim.stop()


def test_validate_hardware_channel_bounds_and_pulse_range():
    base = {"devices": {"wav645": {"type": "wav645", "host": "a"}, "wav617a": {"type": "wav617", "host": "b"},
                        "shelly1": {"type": "shelly_rgbww", "host": "c"}}}
    ok = dict(base, zones=[{"zone": 1, "lock": {"dev": "wav645", "coil": 15}, "contact": {"dev": "wav617a", "input": 7},
                            "light": {"dev": "wav617a", "coil": 7}, "red": {"dev": "shelly1", "light": 4}}])
    assert validate_hardware(HardwareConfig.from_dict(ok)) == []
    bad = dict(base, zones=[{"zone": 1, "lock": {"dev": "wav645", "coil": 16}, "contact": {"dev": "wav617a", "input": 8},
                             "light": {"dev": "wav617a", "coil": 8}, "red": {"dev": "shelly1", "light": 5}}],
               timings={"lock_pulse_ms": 50})
    problems = validate_hardware(HardwareConfig.from_dict(bad))
    assert sum("mimo rozsah modulu" in p for p in problems) == 4 and any("lock_pulse_ms" in p for p in problems)


def test_outbox_is_capped(tmp_path):
    st = Storage(str(tmp_path / "o.db"))
    st.outbox_add("log_open", {"p_kind": "motorcycle"})
    for i in range(OUTBOX_MAX + 20):
        st.outbox_add("log_event", {"i": i})
    assert st.outbox_count() == OUTBOX_MAX
    kinds = [k for _, k, _ in st.outbox_pending(limit=OUTBOX_MAX)]
    assert "log_open" in kinds                            # audit dveří přežil, zahazují se nejstarší log_event
    st.close()


def test_canonical_uuid():
    u = "6F1C2B8E-3A4D-4E5F-9A0B-1C2D3E4F5A6B"
    assert canonical_uuid("{" + u + "}") == u.lower() == canonical_uuid("urn:uuid:" + u) == canonical_uuid(" " + u + " ")
    assert canonical_uuid("nic") == "nic" and canonical_uuid(None) == ""
