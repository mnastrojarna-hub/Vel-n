"""Testy Shelly RPC klienta a SignalControlleru proti in-test aiohttp fake Shelly."""
from __future__ import annotations

import asyncio

import pytest
from aiohttp import web

from motogo_box.config import DeviceCfg, SignalCfg
from motogo_box.models import HwRef, Signal, ZoneHw
from motogo_box.shelly import ShellyRgbww, SignalController, shelly_base_url


class FakeShelly:
    """Minimální fake Shelly: `POST /rpc` Light.Set → zaznamená params, vrátí result."""

    def __init__(self) -> None:
        self.requests: list[dict] = []
        self.lights: dict[int, dict] = {i: {"on": False, "brightness": 0} for i in range(5)}
        self.fail = False
        self._runner: web.AppRunner | None = None
        self.port = 0

    async def _rpc(self, request: web.Request) -> web.Response:
        body = await request.json()
        self.requests.append(body)
        if self.fail:
            return web.Response(status=500, text="boom")
        if body.get("method") != "Light.Set":
            return web.json_response({"id": body.get("id"), "error": {"code": 404, "message": "no method"}})
        p = body["params"]
        st = self.lights[int(p["id"])]
        st["on"] = bool(p["on"])
        if "brightness" in p:
            st["brightness"] = p["brightness"]
        return web.json_response({"id": body.get("id"), "src": "fake", "result": {"was_on": False}})

    async def start(self) -> None:
        app = web.Application()
        app.router.add_post("/rpc", self._rpc)
        self._runner = web.AppRunner(app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, "127.0.0.1", 0)
        await site.start()
        self.port = site._server.sockets[0].getsockname()[1]  # noqa: SLF001

    async def stop(self) -> None:
        if self._runner is not None:
            await self._runner.cleanup()

    def params(self, light_id: int) -> list[dict]:
        return [r["params"] for r in self.requests if r["params"]["id"] == light_id]


@pytest.fixture
async def fake():
    srv = FakeShelly()
    await srv.start()
    try:
        yield srv
    finally:
        await srv.stop()


def _cfg(**kw) -> SignalCfg:
    base = dict(brightness=100, blink_ms=40, pulse_ms=60, transition_s=0.2)
    base.update(kw)
    return SignalCfg(**base)


def _zone(dev: str = "s1") -> ZoneHw:
    return ZoneHw(zone=1, red=HwRef(dev, 0), green=HwRef(dev, 1))


def test_base_url_rules():
    assert shelly_base_url("192.168.50.31") == "http://192.168.50.31"
    assert shelly_base_url("192.168.50.31", 502) == "http://192.168.50.31"
    assert shelly_base_url("127.0.0.1", 18031) == "http://127.0.0.1:18031"
    assert shelly_base_url("127.0.0.1:18031", 502) == "http://127.0.0.1:18031"
    assert shelly_base_url("http://x.local/", None) == "http://x.local"
    dev = DeviceCfg(name="shelly1", type="shelly_rgbww", host="192.168.50.31")
    assert ShellyRgbww.from_device(dev).base_url == "http://192.168.50.31"


async def test_light_set_payload(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    try:
        assert await sh.light_set(3, True, 80, 0.5) is True
        assert await sh.light_set(3, False) is True
        assert sh.online and sh.failures == 0
    finally:
        await sh.close()
    first, second = fake.requests
    assert first["method"] == "Light.Set"
    assert first["params"] == {"id": 3, "on": True, "brightness": 80, "transition_duration": 0.5}
    assert second["params"] == {"id": 3, "on": False}
    assert first["id"] != second["id"]


async def test_all_off_sends_five(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    try:
        assert await sh.all_off() is True
    finally:
        await sh.close()
    assert [r["params"]["id"] for r in fake.requests] == [0, 1, 2, 3, 4]
    assert all(r["params"]["on"] is False for r in fake.requests)


async def test_offline_after_failures_and_recovery(fake: FakeShelly):
    changes: list[tuple[str, bool]] = []
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port, offline_after=3)
    sh.on_online_change = lambda n, o: changes.append((n, o))
    try:
        fake.fail = True
        for _ in range(2):
            assert await sh.light_set(0, True) is False
        assert sh.online is True
        assert await sh.light_set(0, True) is False
        assert sh.online is False and sh.failures == 3
        fake.fail = False
        assert await sh.light_set(0, True) is True
        assert sh.online is True and sh.failures == 0
    finally:
        await sh.close()
    assert changes == [("s1", False), ("s1", True)]


async def test_unreachable_host_goes_offline():
    sh = ShellyRgbww("dead", "127.0.0.1", port=1, timeout_s=0.3, offline_after=2)
    try:
        assert await sh.light_set(0, True) is False
        assert await sh.light_set(0, True) is False
        assert sh.online is False
    finally:
        await sh.close()


async def test_signal_red_green_off_payloads(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    ctl = SignalController({"s1": sh}, _cfg(brightness=90, transition_s=0.3))
    hw = _zone()
    try:
        assert ctl.current(1) == Signal.OFF
        await ctl.set(hw, Signal.RED)
        assert ctl.current(1) == Signal.RED
        assert fake.params(0) == [{"id": 0, "on": True, "brightness": 90, "transition_duration": 0.3}]
        assert fake.params(1) == [{"id": 1, "on": False, "transition_duration": 0.3}]
        n = len(fake.requests)
        await ctl.set(hw, Signal.RED)              # idempotentní — nic neposílá
        assert len(fake.requests) == n
        await ctl.set(hw, Signal.GREEN)
        assert fake.params(1)[-1] == {"id": 1, "on": True, "brightness": 90, "transition_duration": 0.3}
        assert fake.params(0)[-1] == {"id": 0, "on": False, "transition_duration": 0.3}
        await ctl.set(hw, Signal.OFF)
        assert fake.lights[0]["on"] is False and fake.lights[1]["on"] is False
        n = len(fake.requests)
        await ctl.refresh(hw)                      # vynucené znovuposlání OFF
        assert len(fake.requests) == n + 2
        assert ctl.online("s1") is True and ctl.online("nope") is False
    finally:
        await ctl.close()


async def test_red_blink_alternates_and_cancels_on_red(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    ctl = SignalController({"s1": sh}, _cfg(blink_ms=30))
    hw = _zone()
    try:
        await ctl.set(hw, Signal.RED_BLINK)
        task = ctl._tasks[1]  # noqa: SLF001
        await asyncio.sleep(0.2)
        reds = [p["on"] for p in fake.params(0)]
        assert len(reds) >= 4
        assert all(a != b for a, b in zip(reds, reds[1:])), reds   # střídá on/off
        assert fake.params(1) == [{"id": 1, "on": False, "transition_duration": 0.2}]
        on_frames = [p for p in fake.params(0) if p["on"]]
        assert all(p["brightness"] == 100 for p in on_frames)
        await ctl.set(hw, Signal.RED)
        assert task.done() and 1 not in ctl._tasks  # noqa: SLF001
        n = len(fake.requests)
        await asyncio.sleep(0.12)
        assert len(fake.requests) == n              # blink task už nic neposílá
        assert fake.params(0)[-1] == {"id": 0, "on": True, "brightness": 100, "transition_duration": 0.2}
        assert fake.lights[0]["on"] is True
    finally:
        await ctl.close()


async def test_green_pulse_and_both_blink(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    ctl = SignalController({"s1": sh}, _cfg(pulse_ms=100, blink_ms=30))
    hw = _zone()
    try:
        await ctl.set(hw, Signal.GREEN_PULSE)
        await asyncio.sleep(0.35)
        greens = fake.params(1)
        levels = [p["brightness"] for p in greens if p["on"]]
        assert len(levels) >= 3 and set(levels) == {100, 15}
        assert all(a != b for a, b in zip(levels, levels[1:]))
        assert all(p["transition_duration"] == pytest.approx(0.1) for p in greens if p["on"])
        assert fake.params(0) == [{"id": 0, "on": False, "transition_duration": 0.2}]
        fake.requests.clear()
        await ctl.set(hw, Signal.BOTH_BLINK)
        await asyncio.sleep(0.1)
        assert len(fake.params(0)) >= 2 and len(fake.params(1)) >= 2
        await ctl.all_off()
        assert 1 not in ctl._tasks  # noqa: SLF001
        assert ctl.current(1) == Signal.OFF
        assert all(not st["on"] for st in fake.lights.values())
    finally:
        await ctl.close()


async def test_missing_refs_and_unknown_device_are_skipped(fake: FakeShelly):
    sh = ShellyRgbww("s1", "127.0.0.1", port=fake.port)
    ctl = SignalController({"s1": sh}, _cfg())
    try:
        await ctl.set(ZoneHw(zone=2, red=HwRef("s1", 4)), Signal.GREEN)   # bez zelené
        assert fake.params(4) == [{"id": 4, "on": False, "transition_duration": 0.2}]
        await ctl.set(ZoneHw(zone=3, red=HwRef("ghost", 0)), Signal.RED)  # neznámé Shelly
        assert ctl.current(3) == Signal.RED
    finally:
        await ctl.close()
