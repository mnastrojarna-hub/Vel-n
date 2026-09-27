"""Zrcadlení obrazovky do Velína (CONTRACT §29): falešný CDP server (aiohttp) + falešné RPC `push_screen_frame`."""
from __future__ import annotations

import asyncio
import base64
import json
import re
import pathlib

import pytest
from aiohttp import web
from aiohttp.test_utils import TestServer

from motogo_box import commands
from motogo_box.config import ScreenCfg
from motogo_box.screen_mirror import ScreenMirror

FRAME_A = base64.b64encode(b"\xff\xd8\xff frame A").decode()
FRAME_B = base64.b64encode(b"\xff\xd8\xff frame B").decode()


class FakeCdp:
    """Minimální DevTools: /json/list + WS stránky. Zaznamená metody, po startScreencast pošle snímky z `frames`."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict]] = []
        self.frames: list[str] = [FRAME_A]
        self.ws: web.WebSocketResponse | None = None
        self.port = 0
        self.dialog_after_start = False

    async def list_(self, _r):
        return web.json_response([{"type": "background", "webSocketDebuggerUrl": "ws://x/nope"},
                                  {"type": "page", "webSocketDebuggerUrl": f"ws://127.0.0.1:{self.port}/devtools/page/1"}])

    async def page(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        self.ws = ws
        async for msg in ws:
            if msg.type != web.WSMsgType.TEXT:
                break
            data = json.loads(msg.data)
            method, params, mid = data.get("method"), data.get("params") or {}, data.get("id")
            self.calls.append((method, params))
            result: dict = {}
            if method == "Page.getLayoutMetrics":
                result = {"cssVisualViewport": {"clientWidth": 1920, "clientHeight": 1080}}
            await ws.send_json({"id": mid, "result": result})
            if method == "Page.startScreencast":
                for i, fr in enumerate(self.frames):
                    await ws.send_json({"method": "Page.screencastFrame", "params": {
                        "data": fr, "sessionId": i + 1, "metadata": {"deviceWidth": 960, "deviceHeight": 540}}})
                if self.dialog_after_start:
                    await ws.send_json({"method": "Page.javascriptDialogOpening",
                                        "params": {"type": "prompt", "message": "Příkaz:", "defaultPrompt": ""}})
        return ws

    async def send_frame(self, data: str, sid: int) -> None:
        assert self.ws is not None
        await self.ws.send_json({"method": "Page.screencastFrame", "params": {
            "data": data, "sessionId": sid, "metadata": {"deviceWidth": 960, "deviceHeight": 540}}})


class FakeApi:
    def __init__(self) -> None:
        self.pushes: list[dict] = []
        self.active = True
        self.control = False
        self.fail = False

    async def push_screen_frame(self, session_id, seq, frame, width, height, meta=None):
        if self.fail:
            raise RuntimeError("net down")
        self.pushes.append({"session_id": session_id, "seq": seq, "frame": frame, "w": width, "h": height, "meta": meta or {}})
        return {"ok": True, "active": self.active, "control": self.control}


@pytest.fixture
async def cdp():
    fake = FakeCdp()
    app = web.Application()
    app.router.add_get("/json/list", fake.list_)
    app.router.add_get("/devtools/page/1", fake.page)
    srv = TestServer(app)
    await srv.start_server()
    fake.port = srv.port
    yield fake
    await srv.close()


def mirror(cdp: FakeCdp, api: FakeApi, **cfg) -> ScreenMirror:
    return ScreenMirror(api, ScreenCfg(cdp_port=cdp.port, max_fps=cfg.pop("max_fps", 10.0), ping_s=cfg.pop("ping_s", 1),
                                       stall_s=cfg.pop("stall_s", 60), **cfg))


async def wait_for(cond, timeout=3.0):
    t0 = asyncio.get_running_loop().time()
    while not cond():
        if asyncio.get_running_loop().time() - t0 > timeout:
            raise AssertionError("timeout")
        await asyncio.sleep(0.02)


async def test_start_screencast_pushes_changed_frames_and_dedups(cdp):
    api = FakeApi()
    m = mirror(cdp, api)
    res = await m.start("sess-1", control=False)
    assert res["active"] and res["session_id"] == "sess-1" and not res.get("error")
    await wait_for(lambda: len(api.pushes) >= 1)
    start = next(p for m_, p in cdp.calls if m_ == "Page.startScreencast")
    assert start["format"] == "jpeg" and start["maxWidth"] == 960 and start["maxHeight"] == 540 and start["quality"] == 45
    assert api.pushes[0]["seq"] == 1 and api.pushes[0]["frame"] == FRAME_A and api.pushes[0]["w"] == 960
    assert ("Page.screencastFrameAck", {"sessionId": 1}) in cdp.calls
    await cdp.send_frame(FRAME_A, 2)          # stejný obraz → nic
    await cdp.send_frame(FRAME_B, 3)          # změna → seq 2
    await wait_for(lambda: any(p["seq"] == 2 for p in api.pushes))
    assert [p["frame"] for p in api.pushes if p["frame"]] == [FRAME_A, FRAME_B]
    assert m.frames == 2 and m.bytes == len(FRAME_A) + len(FRAME_B)
    await m.stop("test")
    assert not m.active and m.status()["stop_reason"] == "test"
    assert any(m_ == "Page.stopScreencast" for m_, _ in cdp.calls)


async def test_fps_limit_keeps_last_frame(cdp):
    api = FakeApi()
    cdp.frames = []
    m = mirror(cdp, api, max_fps=2.0)         # nejvýš 1 snímek / 0,5 s
    await m.start("s")
    await wait_for(lambda: any(m_ == "Page.startScreencast" for m_, _ in cdp.calls))
    for i in range(5):
        await cdp.send_frame(base64.b64encode(f"frame {i}".encode()).decode(), 10 + i)
    await asyncio.sleep(1.2)
    frames = [p["frame"] for p in api.pushes if p["frame"]]
    assert 1 <= len(frames) <= 3 and frames[-1] == base64.b64encode(b"frame 4").decode()   # poslední snímek vždy dojde
    await m.stop()


async def test_velin_ends_session_and_ping_without_change(cdp):
    api = FakeApi()
    m = mirror(cdp, api, ping_s=1)
    await m.start("s")
    await wait_for(lambda: len(api.pushes) >= 1)
    await wait_for(lambda: any(p["frame"] is None for p in api.pushes), timeout=3)   # ping bez snímku
    api.active = False
    await wait_for(lambda: not m.active, timeout=3)
    assert m.status()["stop_reason"] == "ended_by_velin"


async def test_cdp_unavailable_returns_error_without_task():
    api = FakeApi()
    m = ScreenMirror(api, ScreenCfg(cdp_port=1))          # nic neposlouchá
    res = await m.start("s")
    assert res["error"] == "cdp_unavailable" and not m.active and api.pushes == []


async def test_tap_requires_control_and_dispatches_click(cdp):
    api = FakeApi()
    m = mirror(cdp, api)
    await m.start("s", control=False)
    await wait_for(lambda: len(api.pushes) >= 1)
    ok, res = await m.tap(0.5, 0.5, session_id="s")
    assert not ok and res["error"] == "control_disabled"
    api.control = True
    await cdp.send_frame(FRAME_B, 5)
    await wait_for(lambda: m.control)
    ok, res = await m.tap(0.5, 0.25, session_id="s")
    assert ok and res["x"] == 960 and res["y"] == 270
    kinds = [p["type"] for m_, p in cdp.calls if m_ == "Input.dispatchMouseEvent"]
    assert kinds == ["mouseMoved", "mousePressed", "mouseReleased"]
    ok, res = await m.tap(2, -1, session_id="s")           # ořez 0..1
    assert ok and (res["x"], res["y"]) == (1920, 0)
    ok, res = await m.tap(0.1, 0.1, session_id="other")
    assert not ok and res["error"] == "session_mismatch"
    ok, res = await m.tap(0.1, 0.1, session_id="s", sent_at="2020-01-01T00:00:00+00:00")
    assert not ok and res["error"] == "stale_input"
    await m.stop()


async def test_dialog_reported_in_meta_and_handled(cdp):
    api = FakeApi()
    api.control = True
    cdp.dialog_after_start = True
    m = mirror(cdp, api)
    await m.start("s", control=True)
    await wait_for(lambda: any((p["meta"] or {}).get("dialog") for p in api.pushes))
    d = next(p["meta"]["dialog"] for p in api.pushes if (p["meta"] or {}).get("dialog"))
    assert d["type"] == "prompt" and d["message"] == "Příkaz:"
    ok, res = await m.dialog("ip route", session_id="s")
    assert ok and res["accepted"] is True
    assert ("Page.handleJavaScriptDialog", {"accept": True, "promptText": "ip route"}) in cdp.calls
    await m.stop()


async def test_commands_screen_mirror_and_input(cdp):
    class Ctrl:
        pass
    c = Ctrl()
    api = FakeApi()
    api.control = True
    c.screen = mirror(cdp, api)
    ok, res = await commands.execute(c, "screen_mirror", {"session_id": "s1", "on": True, "control": True, "ttl_s": 120})
    assert ok and res["active"] and res["control"]
    await wait_for(lambda: len(api.pushes) >= 1)
    ok, res = await commands.execute(c, "screen_input", {"session_id": "s1", "kind": "tap", "x": 0.5, "y": 0.5})
    assert ok and res["x"] == 960
    ok, res = await commands.execute(c, "screen_input", {"session_id": "s1", "kind": "tap", "x": "a", "y": 0})
    assert not ok and res["error"] == "bad_coordinates"
    ok, res = await commands.execute(c, "screen_mirror", {"session_id": "s1", "on": False})
    assert ok and not res["active"] and not c.screen.active
    ok, res = await commands.execute(c, "screen_input", {"session_id": "s1", "kind": "tap", "x": 0.5, "y": 0.5})
    assert not ok and res["error"] == "not_active"
    assert "screen_mirror" not in commands.HW_COMMANDS and "screen_input" not in commands.HW_COMMANDS
    assert "screen_mirror" not in commands.TERMINAL_COMMANDS


def test_commands_check_migration_covers_all_handlers():
    """Poslední migrace CHECK `kiosk_commands_command_check` musí znát každý příkaz z HANDLERS (CLAUDE.md: nový příkaz = migrace)."""
    mig = sorted(pathlib.Path(__file__).resolve().parents[3].glob("supabase/migrations/*.sql"))
    latest = None
    for f in mig:
        if "kiosk_commands_command_check" in f.read_text(encoding="utf-8"):
            latest = f
    assert latest is not None
    body = latest.read_text(encoding="utf-8")
    block = body[body.rfind("kiosk_commands_command_check"):]
    names = set(re.findall(r"'([a-z_]+)'", block[block.find("CHECK"):block.find("));") + 1]))
    assert set(commands.HANDLERS) <= names, set(commands.HANDLERS) - names


def test_kiosk_ui_script_has_loopback_only_cdp():
    sh = (pathlib.Path(__file__).resolve().parents[1] / "scripts" / "kiosk-ui.sh").read_text(encoding="utf-8")
    assert '--remote-debugging-port="$CDP_PORT"' in sh and 'CDP_PORT="${MOTOGO_CDP_PORT:-9222}"' in sh
    assert "--remote-debugging-address" not in sh.replace("nepřidávat --remote-debugging-address", "")
    assert "--remote-allow-origins" not in sh.replace("--remote-allow-origins=*; controller", "")
    policy = json.loads((pathlib.Path(__file__).resolve().parents[1] / "systemd" / "motogo-chromium-policy.json").read_text(encoding="utf-8"))
    assert policy["RemoteDebuggingAllowed"] is True
