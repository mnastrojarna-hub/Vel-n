"""Testy venku (`outdoor.OutdoorController`): světlo dle relací s doběhem, ruční override, obnova
modulu, all_off, servisní test, retry po chybě relé, stav."""
from __future__ import annotations

import asyncio

from motogo_box.config import TimingsCfg
from motogo_box.config_outdoor import OutdoorCfg
from motogo_box.models import HwRef
from motogo_box.outdoor import RETRY_S, OutdoorController

LIGHT = HwRef("wav617b", 0)


class FakeIo:
    def __init__(self, ok: bool = True) -> None:
        self.ok = ok
        self.calls: list[tuple[HwRef, bool]] = []
        self.raise_exc = False

    async def set(self, ref: HwRef, on: bool) -> bool:
        if self.raise_exc:
            raise RuntimeError("bus down")
        self.calls.append((ref, on))
        return self.ok


class FakeAudio:
    mode = "multi"

    def __init__(self) -> None:
        self.channels_playing: list[str] = []
        self.tests: list[tuple[str, int]] = []
        self.test_ok = True

    async def test_channel(self, name: str, seconds: int = 3) -> bool:
        self.tests.append((name, seconds))
        return self.test_ok


class Clock:
    def __init__(self) -> None:
        self.t = 1000.0

    def __call__(self) -> float:
        return self.t


def _rig(cfg: OutdoorCfg | None = None, io: FakeIo | None = None, audio=None, **timings):
    cfg = cfg or OutdoorCfg(zone=9, light=LIGHT, audio_out="out9", present=True)
    io = io or FakeIo()
    clock = Clock()
    audio = FakeAudio() if audio is None else audio
    ctl = OutdoorController(cfg, io, TimingsCfg(light_after_close_s=30, **timings), audio, clock=clock)
    return ctl, io, clock


async def test_light_follows_sessions_with_delay():
    ctl, io, clock = _rig()
    await ctl.sync([])
    assert io.calls == [] and ctl.light_on is False and ctl.status()["off_in_s"] is None
    await ctl.sync([3])                                  # první relace → světlo hned
    assert io.calls == [(LIGHT, True)] and ctl.light_on and ctl.active
    await ctl.sync([3, 5])
    assert io.calls == [(LIGHT, True)]                   # už svítí → žádné další set
    await ctl.sync([])                                   # poslední relace skončila → doběh
    assert ctl.light_on and ctl.off_at == clock.t + 30 and ctl.status()["off_in_s"] == 30
    clock.t += 29
    await ctl.sync([])
    assert ctl.light_on
    await ctl.sync([4])                                  # nová relace ruší doběh
    assert ctl.off_at is None and ctl.light_on
    await ctl.sync([])
    clock.t += 30
    await ctl.sync([])
    assert io.calls[-1] == (LIGHT, False) and ctl.light_on is False and ctl.off_at is None


async def test_own_light_after_close_overrides_timings():
    ctl, io, clock = _rig(OutdoorCfg(zone=9, light=LIGHT, light_after_close_s=5, present=True))
    await ctl.sync([1])
    await ctl.sync([])
    assert ctl.off_at == clock.t + 5
    clock.t += 5
    await ctl.sync([])
    assert ctl.light_on is False


async def test_manual_override():
    ctl, io, clock = _rig()
    assert await ctl.set_light(True) is True             # ručně rozsvítit — drží i bez relace
    assert ctl.manual is True and ctl.light_on
    clock.t += 1000
    await ctl.sync([])
    assert ctl.light_on and io.calls == [(LIGHT, True)] and ctl.status()["manual"] is True
    await ctl.sync([2])                                  # relace ruší ruční režim
    assert ctl.manual is None and ctl.light_on
    assert await ctl.set_light(False) is True            # ručně zhasnout během relace
    assert ctl.manual is False and ctl.light_on is False and io.calls[-1] == (LIGHT, False)
    await ctl.sync([2])                                  # běžící relace světlo zase rozsvítí
    assert ctl.manual is None and ctl.light_on
    await ctl.sync([])
    clock.t += 30
    await ctl.sync([])
    assert ctl.light_on is False
    assert await ctl.set_light(False) is True
    await ctl.sync([])
    assert ctl.light_on is False and ctl.manual is False


async def test_module_reinit_and_all_off():
    ctl, io, clock = _rig()
    await ctl.on_module_reinit("wav617b")                # nesvítí → nic
    assert io.calls == []
    await ctl.sync([1])
    await ctl.on_module_reinit("wav645")                 # cizí modul → nic
    assert io.calls == [(LIGHT, True)]
    await ctl.on_module_reinit("wav617b")
    assert io.calls == [(LIGHT, True), (LIGHT, True)]
    await ctl.all_off()
    assert io.calls[-1] == (LIGHT, False) and ctl.light_on is False and ctl.manual is None
    assert ctl.off_at is None and ctl.active is False
    await ctl.all_off()                                  # už zhasnuté → žádné další set
    assert io.calls[-1] == (LIGHT, False) and len(io.calls) == 3


async def test_test_sequence_busy_ok_not_configured(monkeypatch):
    monkeypatch.setattr("motogo_box.outdoor.TEST_LIGHT_S", 0)
    ctl, io, clock = _rig()
    await ctl.sync([1])
    assert await ctl.test_sequence() == {"light": False, "audio": None, "error": "busy"}
    await ctl.sync([])
    clock.t += 30
    await ctl.sync([])
    io.calls.clear()
    res = await ctl.test_sequence()
    assert res == {"light": True, "audio": True} and io.calls == [(LIGHT, True), (LIGHT, False)]
    assert ctl.audio.tests == [("outdoor", 3)] and ctl.light_on is False
    ctl.audio.channels_playing = ["outdoor"]             # kanál hraje → audio se netestuje
    assert (await ctl.test_sequence())["audio"] is None
    ctl.audio.channels_playing, ctl.audio.mode = [], "selector"
    assert (await ctl.test_sequence())["audio"] is None
    ctl.audio.mode, ctl.audio.test_ok = "multi", False
    assert (await ctl.test_sequence())["audio"] is False
    empty, _, _ = _rig(OutdoorCfg(zone=9, present=True))
    assert await empty.test_sequence() == {"light": False, "audio": None, "error": "not_configured"}
    await empty.sync([1])
    assert empty.status()["configured"] is False and empty.light_on is False


async def test_test_sequence_restores_previous_light(monkeypatch):
    monkeypatch.setattr("motogo_box.outdoor.TEST_LIGHT_S", 0)
    ctl, io, clock = _rig()
    await ctl.set_light(True)
    res = await ctl.test_sequence()
    assert res["light"] is True and ctl.light_on is True and io.calls[-1] == (LIGHT, True)
    monkeypatch.setattr("motogo_box.outdoor.TEST_LIGHT_S", 5)
    task = asyncio.create_task(ctl.test_sequence())
    await asyncio.sleep(0.05)
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    assert ctl.light_on is True and io.calls[-1] == (LIGHT, True)   # i po zrušení obnoven původní stav


async def test_relay_failure_retries_after_delay(caplog):
    io = FakeIo(ok=False)
    ctl, io, clock = _rig(io=io)
    with caplog.at_level("WARNING", logger="motogo.outdoor"):
        await ctl.sync([1])
        await ctl.sync([1])
        await ctl.sync([1])
    assert io.calls == [(LIGHT, True)] and ctl.light_on is False       # další pokus až za RETRY_S
    assert any("další pokus" in r.getMessage() for r in caplog.records)
    clock.t += RETRY_S
    io.ok = True
    await ctl.sync([1])
    assert io.calls == [(LIGHT, True), (LIGHT, True)] and ctl.light_on
    io.raise_exc = True                                   # výjimka sběrnice → jen warning
    await ctl.sync([])
    clock.t += 30
    await ctl.sync([])
    assert ctl.light_on is True and ctl.off_at is not None
    io.raise_exc = False
    clock.t += RETRY_S
    await ctl.sync([])
    assert ctl.light_on is False and io.calls[-1] == (LIGHT, False)
    assert await ctl.set_light(True) and io.calls[-1] == (LIGHT, True)   # ruční příkaz backoff obchází


async def test_status_shape():
    ctl, io, clock = _rig()
    st = ctl.status()
    assert st == {"zone": 9, "configured": True, "light": False, "active": False, "manual": None,
                  "audio_out": "out9", "music": False, "light_ref": "wav617b[0]", "off_in_s": None}
    ctl.audio.channels_playing = ["outdoor"]
    await ctl.sync([1])
    st = ctl.status()
    assert st["light"] is True and st["active"] is True and st["music"] is True
    ctl.update_cfg(OutdoorCfg(zone=9, light=LIGHT, present=True), TimingsCfg(light_after_close_s=7))
    await ctl.sync([])
    assert ctl.status()["audio_out"] is None and ctl.status()["off_in_s"] == 7
    none = OutdoorController(OutdoorCfg(), io, TimingsCfg(), None)
    assert none.status()["configured"] is False and none.status()["music"] is False
