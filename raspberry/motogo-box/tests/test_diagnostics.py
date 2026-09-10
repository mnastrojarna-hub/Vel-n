"""Testy diagnostiky sítě: sondy `net_scan` proti in-process simulátoru, běh
`NetworkDiagnostics` s falešným controllerem, diagnostický kód v `submit_code`,
příkaz `diagnostics`, web API a offline cache účelu servisního hesla."""
from __future__ import annotations

import asyncio
import socket
import time
from datetime import datetime, timezone

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from motogo_box import commands, controller_codes as cc, diagnostics as dg, net_scan
from motogo_box.config import LocalConfig
from motogo_box.models import EventKind
from motogo_box.pins import hmac_code
from motogo_box.tools.simulator import SimRelayModule, SimShelly
from motogo_box.webserver import WebServer
from tests.diag_fakes import DEVICE_ID, TOKEN, FakeCtrl

@pytest.fixture
async def sim(monkeypatch):
    """WAV645 + WAV617 + Shelly na localhostu; identifikace přesměrovaná na jejich porty."""
    w645, w617 = SimRelayModule("wav645", name="wav645"), SimRelayModule("wav617", name="wav617a")
    sh = SimShelly(name="shelly1")
    for s in (w645, w617, sh):
        await s.start()
    monkeypatch.setattr(dg, "MODBUS_PORTS", (w645.port, w617.port))
    monkeypatch.setattr(dg, "WEB_PORTS", (sh.port,))
    monkeypatch.setattr(dg, "INTERNET_TCP", ("127.0.0.1", sh.port))
    monkeypatch.setattr(net_scan, "interfaces", _fake_interfaces)
    yield {"wav645": w645, "wav617a": w617, "shelly1": sh}
    for s in (w645, w617, sh):
        await s.stop()


async def _fake_interfaces() -> list[dict]:
    return [{"name": "eth0", "mac": "aa:bb:cc:dd:ee:ff", "state": "up", "ipv4": [{"addr": "127.0.0.1", "prefix": 30}], "ipv6": []}]


def hw_for(sim) -> dict:
    return {"devices": {
        "wav645": {"type": "wav645", "host": "127.0.0.1", "port": sim["wav645"].port},
        "wav617a": {"type": "wav617", "host": "127.0.0.1", "port": sim["wav617a"].port},
        "shelly1": {"type": "shelly_rgbww", "host": "127.0.0.1", "port": sim["shelly1"].port},
        "ghost": {"type": "wav617", "host": "127.0.0.1", "port": _closed_port()},
    }, "polling": {"modbus_timeout_ms": 400, "retry_delays_ms": []}}


def _closed_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ─── net_scan ────────────────────────────────────────────────────────────────
async def test_net_scan_probes(sim):
    assert net_scan.subnet_hosts("192.168.50.10/24") == [f"192.168.50.{i}" for i in range(1, 255)]
    assert net_scan.subnet_hosts("10.0.0.0/8") == [] and net_scan.subnet_hosts("nesmysl") == []
    ok, ms, err = await net_scan.tcp_probe("127.0.0.1", sim["wav645"].port)
    assert ok and err is None and ms >= 0
    ok, _, err = await net_scan.tcp_probe("127.0.0.1", _closed_port(), 0.5)
    assert not ok and err
    found = await net_scan.scan_hosts(["127.0.0.1", "127.0.0.2"], [sim["wav645"].port, sim["shelly1"].port, _closed_port()])
    assert set(found.get("127.0.0.1", {})) == {sim["wav645"].port, sim["shelly1"].port}
    assert (await net_scan.modbus_identify("127.0.0.1", sim["wav645"].port))["guess"] == "wav645"
    w617 = await net_scan.modbus_identify("127.0.0.1", sim["wav617a"].port)
    assert w617 == {"modbus": True, "coils": 8, "inputs": 8, "guess": "wav617"}
    assert await net_scan.modbus_identify("127.0.0.1", sim["shelly1"].port, timeout_ms=300) is None
    assert await net_scan.modbus_identify("127.0.0.1", _closed_port(), timeout_ms=300) is None
    sh = await net_scan.shelly_identify("127.0.0.1", sim["shelly1"].port)
    assert sh and sh["model"] == "SPDC-0D5PE16EU" and sh["gen"] == 2
    assert await net_scan.shelly_identify("127.0.0.1", _closed_port()) is None
    info = await net_scan.http_info("127.0.0.1", sim["shelly1"].port)
    assert info and info["status"] in (200, 404)
    assert isinstance(net_scan.dns_servers(), list)
    ifaces = await net_scan.interfaces.__wrapped__() if hasattr(net_scan.interfaces, "__wrapped__") else net_scan._interfaces_fallback()
    assert isinstance(ifaces, list) and all("name" in i for i in ifaces)
    res = await net_scan.resolve("127.0.0.1")
    assert res["addresses"] == ["127.0.0.1"]


# ─── NetworkDiagnostics ─────────────────────────────────────────────────────
async def test_diagnostics_run_full_report(tmp_path, sim):
    ctrl = FakeCtrl(tmp_path, hw_for(sim))
    diag = ctrl.diagnostics
    assert diag.matches_local_code(" NET diag ") and not diag.matches_local_code("netdiag1")
    res = diag.start("local_code", "test")
    assert res["ok"] and res["started"] and diag.running
    assert diag.start("velin")["error"] == "already_running"
    report = await diag.wait()
    assert report and not diag.running and report["id"] == res["id"]
    assert set(dg.STEPS) <= set(report["steps"]) | {"summary"} and all(report["steps"][s]["ok"] for s in ("system", "interfaces", "devices", "lan", "arp"))
    devs = {d["name"]: d for d in report["devices"]}
    assert devs["wav645"]["reachable"] and devs["wav645"]["identified"]["guess"] == "wav645"
    assert devs["wav617a"]["identified"]["guess"] == "wav617" and devs["shelly1"]["identified"]["model"] == "SPDC-0D5PE16EU"
    assert devs["ghost"]["reachable"] is False
    lan = report["lan"]
    assert lan["subnets"] == ["127.0.0.1/30"] and lan["scanned_hosts"] == 2
    host = next(h for h in lan["hosts"] if h["ip"] == "127.0.0.1")
    assert host["modbus"] and host["shelly"] and host["configured_as"] == "wav645, wav617a, shelly1, ghost"
    assert report["supabase"]["ok"] is True and report["internet"]["tcp"]["open"] is True
    summary = report["summary"]
    assert summary["ok"] is False and any("ghost" in p for p in summary["problems"])
    assert summary["devices_ok"] == 3 and summary["devices_total"] == 4 and summary["hosts"] >= 1
    # uloženo, odesláno, zalogováno
    assert diag.last_report()["id"] == report["id"] and ctrl.api.reports[-1]["id"] == report["id"]
    ev = [e for e in ctrl.events if e.kind == EventKind.DIAGNOSTICS]
    assert len(ev) == 1 and ev[0].detail["report_id"] == report["id"] and ev[0].level == "warn"
    st = diag.status()
    assert st["running"] is False and st["last"]["id"] == report["id"] and st["last"]["problems"] >= 1


async def test_diagnostics_unpaired_queues_report(tmp_path, sim):
    ctrl = FakeCtrl(tmp_path, {"devices": {}}, paired=False)
    ctrl.diagnostics.start("local_code")
    report = await ctrl.diagnostics.wait()
    assert report["supabase"]["ok"] is None and report["supabase"]["error"] == "not_paired"
    assert any("spárované" in p for p in report["summary"]["problems"])
    assert ctrl.api.reports and ctrl.api.reports[0]["paired"] is False


async def test_step_failure_is_isolated(tmp_path, sim, monkeypatch):
    async def boom(*a, **k):
        raise RuntimeError("kaboom")

    monkeypatch.setattr(net_scan, "arp_table", boom)
    ctrl = FakeCtrl(tmp_path, {"devices": {}})
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    assert report["steps"]["arp"] == {"ok": False, "error": "kaboom", "ms": report["steps"]["arp"]["ms"]}
    assert report["steps"]["system"]["ok"] and any("ARP" in w for w in report["summary"]["warnings"])
    assert not any("ARP" in p for p in report["summary"]["problems"])      # selhaný krok = varování, ne problém


# ─── kódy: lokální diagnostický kód a servisní heslo s účelem diagnostics ───
async def test_submit_code_local_diag_code_even_when_not_ready(tmp_path, sim):
    ctrl = FakeCtrl(tmp_path, {"devices": {}})
    ctrl.ready = False
    res = await ctrl.submit_code("NETDIAG", "ui")
    assert res["ok"] and res["kind"] == "diagnostics" and res["diagnostics"]["started"]
    report = await ctrl.diagnostics.wait()
    assert report["source"] == "local_code" and report["reason"] == "ui"     # Velín SOURCE_CZ
    # během PIN lockoutu se ani diagnostický kód nepřijme (hádání kódů)
    ctrl.storage.set_lockout_until(time.time() + 600)
    assert (await ctrl.submit_code("netdiag", "ui"))["error"] == "locked"
    ctrl.storage.set_lockout_until(None)
    res = await ctrl.submit_code("netdiag", "ui")
    assert res["ok"] and res["kind"] == "diagnostics" and res["diagnostics"]["started"]
    again = await ctrl.submit_code("netdiag", "ui")
    assert again["ok"] and again["kind"] == "diagnostics" and again["message"].endswith("už běží")
    await ctrl.diagnostics.wait()
    ctrl.local.diagnostics.code = ""          # prázdný kód = lokální spouštění vypnuto
    res = await ctrl.submit_code("", "ui")
    assert res["error"] == "empty"
    res = await ctrl.submit_code("netdiag", "ui")
    assert res["error"] == "not_ready"


async def test_submit_code_service_action_diagnostics_online_and_offline(tmp_path, sim):
    ctrl = FakeCtrl(tmp_path, {"devices": {}})
    ctrl.api.resolve = {"ok": True, "kind": "service", "action": "diagnostics", "doors": []}
    res = await ctrl.submit_code("diag9", "ui")
    assert res["kind"] == "diagnostics" and res["ok"] and res["service_token"] is None
    await ctrl.diagnostics.wait()
    ctrl.api.resolve = {"ok": True, "kind": "service", "doors": []}          # bez action = servisní panel
    res = await ctrl.submit_code("servis1", "ui")
    assert res["kind"] == "service" and res["service_token"]
    # offline: cache z kiosk_sync_config s action
    ctrl.api.resolve = None
    ctrl.storage.save_code_cache({"service_codes": [{"h": hmac_code(DEVICE_ID, TOKEN, "diagoff"), "action": "diagnostics", "label": "D"},
                                                    {"h": hmac_code(DEVICE_ID, TOKEN, "svc"), "action": "service"}], "codes": [], "doors": []})
    rr = ctrl.resolver.resolve("diagoff", ctrl.storage.load_code_cache(), datetime.now(timezone.utc))
    assert rr.is_diagnostics and rr.action == "diagnostics"
    assert ctrl.resolver.resolve("svc", ctrl.storage.load_code_cache(), datetime.now(timezone.utc)).action == "service"
    res = await ctrl.submit_code("diagoff", "ui")
    assert res["kind"] == "diagnostics"
    await ctrl.diagnostics.wait()


def test_hash_legacy_payload_keeps_action():
    out = cc.hash_legacy_payload({"service_codes": [{"h": "ab", "action": "diagnostics", "label": "L"}, {"code": "x", "action": "service"}, "plain"],
                                  "codes": []}, DEVICE_ID, TOKEN)
    assert out["service_codes"][0] == {"h": "ab", "action": "diagnostics", "label": "L"}
    assert out["service_codes"][1] == {"h": hmac_code(DEVICE_ID, TOKEN, "x"), "action": "service"}
    assert out["service_codes"][2] == {"h": hmac_code(DEVICE_ID, TOKEN, "plain")}


# ─── příkaz z Velína + web API ──────────────────────────────────────────────
async def test_command_and_web_api(tmp_path, sim):
    ctrl = FakeCtrl(tmp_path, {"devices": {}})
    server = WebServer(ctrl, ctrl.api, ctrl.storage, LocalConfig())
    async with TestClient(TestServer(server.app)) as client:
        r = await client.post("/api/diagnostics/run", json={})
        assert r.status == 403
        ctrl.api.resolve = {"ok": False, "error": "invalid_code"}
        r = await client.post("/api/diagnostics/run", json={"code": "spatne"})
        assert r.status == 403 and (await r.json())["error"] == "invalid_code"
        ctrl.api.resolve = None
        # zákaznický PIN v okně diagnostiky NIKDY neotevře dveře a odpovídá jako neplatný kód (bez orákula)
        ctrl.api.resolve = {"ok": True, "kind": "motorcycle", "booking_id": "bk", "box_number": 1, "door": {"id": "d1"}}
        ctrl.zones = {1: type("Z", (), {"number": 1, "zone": type("ZZ", (), {"door_id": "d1", "box_number": 1, "display_name": "Kóje 1"})()})()}
        r = await client.post("/api/diagnostics/run", json={"code": "123456"})
        assert r.status == 403 and (await r.json())["error"] == "invalid_code"
        assert ctrl.storage.pin_failures_since(0) == 2 and not ctrl.diagnostics.running
        # běžné servisní heslo v okně diagnostiky → jen diagnostika, žádný servisní token
        ctrl.api.resolve = {"ok": True, "kind": "service", "doors": []}
        r = await client.post("/api/diagnostics/run", json={"code": "servis1"})
        assert (await r.json())["started"] is True and not ctrl.service_tokens
        await ctrl.diagnostics.wait()
        ctrl.api.resolve = None
        r = await client.post("/api/diagnostics/run", json={"service_token": "svc-ok", "mode": "network"})
        body = await r.json()
        assert body["ok"] and body["started"] and body["mode"] == "network"
        assert ctrl.diagnostics.status()["mode"] == "network" and "zones" not in ctrl.diagnostics.status()["steps"]
        await ctrl.diagnostics.wait()
        r = await client.get("/api/diagnostics")
        body = await r.json()
        assert body["ok"] and body["status"]["running"] is False and body["report"]["id"] == body["status"]["last"]["id"]
        r = await client.get("/api/diagnostics?report=0")
        assert (await r.json())["report"] is None
        st = await (await client.get("/api/state")).json()
        assert st["diagnostics"]["last"]["id"] == body["report"]["id"]
        r = await client.post("/api/diagnostics/run", json={"code": "netdiag", "mode": "network"})
        assert (await r.json())["started"] is True and ctrl.diagnostics.mode == "network" and ctrl.diagnostics.pending_mode is None
        ok, res = await commands.execute(ctrl, "diagnostics", {"reason": "velin"})
        assert ok is False and res["error"] == "already_running"
        await ctrl.diagnostics.wait()
        ok, res = await commands.execute(ctrl, "diagnostics", {})
        assert ok and res["started"] and "diagnostics" not in commands.HW_COMMANDS
        await ctrl.diagnostics.wait()
    await ctrl.diagnostics.cancel()
