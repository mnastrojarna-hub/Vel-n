"""Lokální simulátor hardwaru MotoGo Boxu (kontrakt §20) — `python -m motogo_box simulate`.

- Modbus TCP: WAV645 (base_port), WAV617-A (base+1), WAV617-B (base+2) — `SimRelayModule`.
- Fake Shelly Pro RGBWW PM ×4 (`POST /rpc` Light.Set / Light.GetStatus / Shelly.GetDeviceInfo).
- Řídicí HTTP server (`control_port`): `POST /sim/input`, `GET /sim/state`, `POST /sim/reset`.
Odpovídá mapě `config/sim-9zone.yaml`. Žádný přístup mimo localhost.
"""
from __future__ import annotations

import asyncio
import json
import logging
import socket

from aiohttp import web

from .sim_modbus import SimRelayModule

__all__ = ["SimRelayModule", "SimShelly", "SimControl", "run_simulator"]

log = logging.getLogger("motogo.sim")
LIGHT_COUNT = 5


def _bound_socket(host: str, port: int) -> socket.socket:
    """Naváže TCP socket (port 0 = dynamický) — kvůli zjištění skutečného portu."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    sock.listen(64)
    sock.setblocking(False)
    return sock


class _AiohttpServer:
    """Společný základ: aiohttp aplikace na daném hostu/portu se skutečným portem v `.port`."""

    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = int(port)
        self._runner: web.AppRunner | None = None

    def build_app(self) -> web.Application:  # pragma: no cover — přepisují podtřídy
        raise NotImplementedError

    async def start(self) -> None:
        if self._runner is not None:
            return
        sock = _bound_socket(self.host, self.port)
        self.port = sock.getsockname()[1]
        self._runner = web.AppRunner(self.build_app(), access_log=None)
        await self._runner.setup()
        await web.SockSite(self._runner, sock).start()

    async def stop(self) -> None:
        runner, self._runner = self._runner, None
        if runner is not None:
            await runner.cleanup()


class SimShelly(_AiohttpServer):
    """Falešný Shelly Pro RGBWW PM v režimu Lights × 5 (lokální RPC přes HTTP)."""

    def __init__(self, host: str = "127.0.0.1", port: int = 0, *, name: str = "shelly") -> None:
        super().__init__(host, port)
        self.name = name
        self.lights: dict[int, dict] = {}
        self.calls: list[dict] = []
        self.reset()

    def reset(self) -> None:
        self.lights = {i: {"on": False, "brightness": 100, "transition_duration": 0.0} for i in range(LIGHT_COUNT)}
        self.calls.clear()

    def build_app(self) -> web.Application:
        app = web.Application()
        app.router.add_post("/rpc", self._rpc_post)
        app.router.add_get("/rpc/{method}", self._rpc_get)
        return app

    async def _rpc_post(self, request: web.Request) -> web.Response:
        try:
            body = await request.json()
        except (json.JSONDecodeError, UnicodeDecodeError):
            return web.json_response({"error": {"code": -103, "message": "invalid JSON"}}, status=400)
        if not isinstance(body, dict):
            return web.json_response({"error": {"code": -103, "message": "object expected"}}, status=400)
        return self._dispatch(body.get("id", 0), str(body.get("method") or ""), body.get("params") or {})

    async def _rpc_get(self, request: web.Request) -> web.Response:
        params: dict = {}
        for k, v in request.query.items():
            try:
                params[k] = json.loads(v)
            except json.JSONDecodeError:
                params[k] = v
        return self._dispatch(0, request.match_info["method"], params)

    def _dispatch(self, rpc_id, method: str, params: dict) -> web.Response:
        self.calls.append({"method": method, "params": dict(params)})
        try:
            if method == "Light.Set":
                result = self._light_set(params)
            elif method == "Light.GetStatus":
                result = self._light_status(params)
            elif method == "Shelly.GetDeviceInfo":
                result = {"id": f"shellyprorgbwwpm-{self.name}", "name": self.name, "model": "SPDC-0D5PE16EU",
                          "app": "ProRGBWWPM", "gen": 2, "fw_id": "sim", "profile": "light"}
            else:
                return web.json_response({"id": rpc_id, "src": self.name,
                                          "error": {"code": 404, "message": f"No handler for {method}"}}, status=404)
        except (KeyError, TypeError, ValueError) as exc:
            return web.json_response({"id": rpc_id, "src": self.name,
                                      "error": {"code": -103, "message": f"Invalid argument: {exc}"}}, status=400)
        return web.json_response({"id": rpc_id, "src": self.name, "result": result})

    def _light(self, params: dict) -> tuple[int, dict]:
        lid = int(params["id"])
        if lid not in self.lights:
            raise ValueError(f"light {lid} neexistuje")
        return lid, self.lights[lid]

    def _light_set(self, params: dict) -> dict:
        lid, light = self._light(params)
        was_on = light["on"]
        if "on" in params:
            light["on"] = bool(params["on"])
        if params.get("brightness") is not None:
            b = int(params["brightness"])
            if not 0 <= b <= 100:
                raise ValueError("brightness 0..100")
            light["brightness"] = b
        if params.get("transition_duration") is not None:
            light["transition_duration"] = float(params["transition_duration"])
        log.debug("%s light %d: on=%s brightness=%s", self.name, lid, light["on"], light["brightness"])
        return {"was_on": was_on}

    def _light_status(self, params: dict) -> dict:
        lid, light = self._light(params)
        return {"id": lid, "source": "sim", "output": light["on"], "brightness": light["brightness"],
                "apower": 4.2 if light["on"] else 0.0, "temperature": {"tC": 31.0}}

    def state(self) -> dict:
        return {"host": self.host, "port": self.port, "lights": {str(i): dict(l) for i, l in self.lights.items()}}


class SimControl(_AiohttpServer):
    """Řídicí HTTP API simulátoru: nastavení vstupů, stav, reset."""

    def __init__(self, modules: dict[str, SimRelayModule], shellies: dict[str, SimShelly],
                 host: str = "127.0.0.1", port: int = 18099) -> None:
        super().__init__(host, port)
        self.modules = modules
        self.shellies = shellies

    def build_app(self) -> web.Application:
        app = web.Application()
        app.router.add_post("/sim/input", self._input)
        app.router.add_get("/sim/state", self._state)
        app.router.add_post("/sim/reset", self._reset)
        return app

    def snapshot(self) -> dict:
        return {"modules": {n: m.state() for n, m in self.modules.items()},
                "shellies": {n: s.state() for n, s in self.shellies.items()}}

    async def _input(self, request: web.Request) -> web.Response:
        try:
            body = await request.json()
            dev = str(body["dev"])
            idx = int(body["input"])
            value = bool(body["value"])
        except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
            return web.json_response({"ok": False, "error": f"bad_request: {exc}"}, status=400)
        module = self.modules.get(dev)
        if module is None:
            return web.json_response({"ok": False, "error": "unknown_device"}, status=404)
        try:
            module.set_input(idx, value)
        except IndexError as exc:
            return web.json_response({"ok": False, "error": str(exc)}, status=400)
        log.info("vstup %s[%d] = %s", dev, idx, value)
        return web.json_response({"ok": True, "dev": dev, "inputs": list(module.inputs)})

    async def _state(self, _request: web.Request) -> web.Response:
        return web.json_response(self.snapshot())

    async def _reset(self, _request: web.Request) -> web.Response:
        for m in self.modules.values():
            m.reset()
        for s in self.shellies.values():
            s.reset()
        log.info("simulátor resetován")
        return web.json_response({"ok": True})


async def run_simulator(host: str = "127.0.0.1", base_port: int = 15020,
                        shelly_base_port: int = 18031, control_port: int = 18099) -> None:
    """Spustí kompletní simulátor (3 Modbus moduly, 4 Shelly, řídicí API) a běží do zrušení."""
    modules = {
        "wav645": SimRelayModule("wav645", host, base_port, name="wav645"),
        "wav617a": SimRelayModule("wav617", host, base_port + 1, name="wav617a"),
        "wav617b": SimRelayModule("wav617", host, base_port + 2, name="wav617b"),
    }
    shellies = {f"shelly{i}": SimShelly(host, shelly_base_port + i - 1, name=f"shelly{i}") for i in range(1, 5)}
    control = SimControl(modules, shellies, host, control_port)
    started: list = []
    try:
        for server in [*modules.values(), *shellies.values(), control]:
            await server.start()
            started.append(server)
        for n, m in modules.items():
            log.info("Modbus %s: %s:%d", n, host, m.port)
        for n, s in shellies.items():
            log.info("Shelly %s: http://%s:%d/rpc", n, host, s.port)
        log.info("Řídicí API: http://%s:%d/sim/state", host, control.port)
        await asyncio.Event().wait()
    finally:
        for server in reversed(started):
            await server.stop()
        log.info("simulátor ukončen")
