"""Smoke testy simulátoru hardwaru (kontrakt §20): fake Shelly RPC a řídicí API."""
from __future__ import annotations

import asyncio
import socket

import aiohttp
import pytest

from motogo_box.tools.simulator import SimControl, SimRelayModule, SimShelly, run_simulator


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def test_sim_shelly_rpc():
    shelly = SimShelly("127.0.0.1", 0, name="shelly1")
    await shelly.start()
    try:
        url = f"http://127.0.0.1:{shelly.port}/rpc"
        async with aiohttp.ClientSession() as http:
            async with http.post(url, json={"id": 1, "method": "Light.Set",
                                            "params": {"id": 2, "on": True, "brightness": 40,
                                                       "transition_duration": 0.2}}) as r:
                body = await r.json()
            assert r.status == 200 and body["id"] == 1 and body["result"] == {"was_on": False}
            assert shelly.lights[2] == {"on": True, "brightness": 40, "transition_duration": 0.2}
            async with http.post(url, json={"id": 2, "method": "Light.GetStatus", "params": {"id": 2}}) as r:
                st = (await r.json())["result"]
            assert st["output"] is True and st["brightness"] == 40
            async with http.post(url, json={"id": 3, "method": "Shelly.GetDeviceInfo"}) as r:
                assert (await r.json())["result"]["app"] == "ProRGBWWPM"
            async with http.post(url, json={"id": 4, "method": "Light.Set", "params": {"id": 7, "on": True}}) as r:
                assert r.status == 400 and "error" in await r.json()
            async with http.post(url, json={"id": 5, "method": "Nope.Method"}) as r:
                assert r.status == 404
            async with http.get(f"{url}/Light.Set", params={"id": "2", "on": "false"}) as r:
                assert r.status == 200
            assert shelly.lights[2]["on"] is False
    finally:
        await shelly.stop()


async def test_sim_control_api():
    modules = {"wav617a": SimRelayModule("wav617", "127.0.0.1", 0, name="wav617a")}
    shellies = {"shelly1": SimShelly("127.0.0.1", 0, name="shelly1")}
    control = SimControl(modules, shellies, "127.0.0.1", 0)
    for s in [*modules.values(), *shellies.values(), control]:
        await s.start()
    try:
        base = f"http://127.0.0.1:{control.port}"
        async with aiohttp.ClientSession() as http:
            async with http.post(f"{base}/sim/input", json={"dev": "wav617a", "input": 0, "value": False}) as r:
                assert r.status == 200 and (await r.json())["ok"] is True
            assert modules["wav617a"].inputs[0] is False
            async with http.post(f"{base}/sim/input", json={"dev": "wavX", "input": 0, "value": False}) as r:
                assert r.status == 404
            async with http.post(f"{base}/sim/input", json={"dev": "wav617a", "input": 9, "value": False}) as r:
                assert r.status == 400
            modules["wav617a"].coils[1] = True
            shellies["shelly1"].lights[0]["on"] = True
            async with http.get(f"{base}/sim/state") as r:
                st = await r.json()
            assert st["modules"]["wav617a"]["coils"][1] is True
            assert st["modules"]["wav617a"]["inputs"][0] is False
            assert st["shellies"]["shelly1"]["lights"]["0"]["on"] is True
            async with http.post(f"{base}/sim/reset") as r:
                assert (await r.json())["ok"] is True
            assert modules["wav617a"].coils == [False] * 8 and modules["wav617a"].inputs == [True] * 8
            assert shellies["shelly1"].lights[0]["on"] is False
    finally:
        for s in [control, *shellies.values(), *modules.values()]:
            await s.stop()


async def test_run_simulator_starts_and_stops():
    base, shelly_base, control = _free_port(), _free_port(), _free_port()
    # tři po sobě jdoucí porty pro Modbus a čtyři pro Shelly: najdeme volné bloky
    while any(_port_used(base + i) for i in range(3)):
        base = _free_port()
    while any(_port_used(shelly_base + i) for i in range(4)):
        shelly_base = _free_port()
    task = asyncio.create_task(run_simulator("127.0.0.1", base, shelly_base, control))
    try:
        async with aiohttp.ClientSession() as http:
            for _ in range(50):
                try:
                    async with http.get(f"http://127.0.0.1:{control}/sim/state") as r:
                        st = await r.json()
                    break
                except aiohttp.ClientError:
                    await asyncio.sleep(0.05)
            else:
                pytest.fail("řídicí API simulátoru nenaběhlo")
        assert set(st["modules"]) == {"wav645", "wav617a", "wav617b"}
        assert st["modules"]["wav645"]["port"] == base and st["modules"]["wav617b"]["port"] == base + 2
        assert set(st["shellies"]) == {"shelly1", "shelly2", "shelly3", "shelly4"}
        assert st["shellies"]["shelly4"]["port"] == shelly_base + 3
    finally:
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert not _port_used(control)


def _port_used(port: int) -> bool:
    with socket.socket() as s:
        return s.connect_ex(("127.0.0.1", port)) == 0
