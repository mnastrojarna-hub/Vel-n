"""Kompletní diagnostika pobočky (režim `full`): kroky software/config/zones/power/cameras,
protokol (`diag_protocol`) a souhrn; bezpečnost HW testu zón (busy/fault/not_ready/zámek se nepulzuje).
Venek v diagnostice: `test_diag_outdoor.py` (zde jen výchozí venek FakeCtrl v kompletním běhu)."""
from __future__ import annotations

import asyncio
import dataclasses

import pytest
from aiohttp import web
from aiohttp.test_utils import TestServer

from motogo_box import commands, diag_protocol as dp, diag_steps, diagnostics as dg
from motogo_box.models import EventKind, HwRef, Signal, ZoneState
from motogo_box.shelly import ShellyRgbww
from tests.diag_fakes import FakeCtrl, FakeSignals, FakeZone, zone_hw
from tests.test_diagnostics import hw_for, sim  # noqa: F401 — fixture

SECTIONS = ["system", "software", "network", "lte", "internet", "velin", "modules", "config", "zones", "power", "cameras", "lan", "steps"]


@pytest.fixture
async def httpsrv():
    """Lokální HTTP: JSON měniče FV, snímek kamery, stream (tělo se nečte) a chybující URL."""
    async def power(_r):
        return web.json_response({"soc": 55, "pvPower": 120.5, "battery": {"vBat": 52.1}, "grid": True})

    async def snap(_r):
        return web.Response(body=b"\xff\xd8\xff", content_type="image/jpeg")

    async def stream(_r):
        resp = web.StreamResponse(headers={"Content-Type": "multipart/x-mixed-replace"})
        await resp.prepare(_r)
        await resp.write(b"--frame\r\n")
        return resp

    async def fail(_r):
        return web.Response(status=500)

    app = web.Application()
    app.router.add_get("/power", power)
    app.router.add_get("/snap.jpg", snap)
    app.router.add_get("/stream", stream)
    app.router.add_get("/fail", fail)
    srv = TestServer(app)
    await srv.start_server()
    yield f"http://127.0.0.1:{srv.port}"
    await srv.close()


def full_ctrl(tmp_path, sim, httpsrv) -> FakeCtrl:
    ctrl = FakeCtrl(tmp_path, hw_for(sim))
    shelly = ShellyRgbww("shelly1", "127.0.0.1", port=sim["shelly1"].port)
    shelly.online = True
    ctrl.signals = FakeSignals({"shelly1": shelly})
    sim["shelly1"].lights[0]["on"] = True                    # červená svítí, zelená zhasnutá = RED
    ctrl.zones = {
        1: FakeZone(ctrl, 1),
        2: FakeZone(ctrl, 2, result={"light": False, "signal": True, "audio": True}),
        3: FakeZone(ctrl, 3, state=ZoneState.DOOR_OPEN, door_closed=False),
        4: FakeZone(ctrl, 4),
    }
    ctrl.hardware.zones = [zc.zone for zc in ctrl.zones.values()]     # HW mapa = běžící zóny (jako controller)
    ctrl.io.coils["wav645"][3] = True                         # zámek zóny 4 sepnutý v klidu
    ctrl.io.inputs["wav617a"][2] = False                      # zóna 3 má dveře otevřené (relace)
    ctrl.io.inputs["wav617a"][3] = False                      # zóna 4: modul čte otevřeno, program hlásí zavřeno
    ctrl.power_status_url = f"{httpsrv}/power"
    ctrl.health = {"ts": dg.now_iso(), "internet": True}
    ctrl.realtime = type("RT", (), {"connected": True})()
    ctrl.updater = type("Up", (), {"last": {"kind": "software", "state": "done"}})()
    ctrl.storage.save_code_cache({"codes": [{"h": "a"}, {"h": "b"}], "service_codes": [{"h": "c"}], "doors": []})
    return ctrl


async def test_full_run_report_protocol_summary(tmp_path, sim, httpsrv):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    cams = [{"name": "Vjezd", "kind": "ip", "snapshot_url": f"{httpsrv}/snap.jpg", "stream_url": f"{httpsrv}/fail",
             "control_url": f"{httpsrv}/fail"}, {"name": "X", "snapshot_url": "ftp://nic"}]
    res = ctrl.diagnostics.start("velin", cameras=cams)
    assert res["mode"] == "full" and ctrl.diagnostics.status()["mode"] == "full"
    assert ctrl.storage.kv_get(dg.KV_CAMERAS) == cams
    report = await ctrl.diagnostics.wait()
    assert report["mode"] == "full" and set(dg.STEPS) - {"summary"} <= set(report["steps"]) and all(s["ok"] for s in report["steps"].values())
    assert [s["key"] for s in report["protocol"]] == SECTIONS
    for sec in report["protocol"]:
        assert sec["status"] in ("ok", "warn", "fail", "skip") and all({"id", "label", "status", "value", "message"} <= set(i) for i in sec["items"])
    # software
    sw = report["software"]
    assert sw["realtime"]["connected"] is True and sw["health_age_s"] < 5 and sw["last_update"]["state"] == "done"
    assert sw["code_cache"]["codes"] == 2 and sw["code_cache"]["service_codes"] == 1 and sw["audio"]["playlist_count"] == 3
    assert set(sw["services"]) == {"motogo-controller", "motogo-health", "motogo-ui"} and isinstance(sw["recent_errors"], list)
    # config
    cfg = report["config"]
    assert cfg["zones_total"] == 4 and cfg["zones"][0]["roles"]["lock"] == "wav645:0" and cfg["cameras_provided"] == 2
    assert cfg["power_status_url"] == ctrl.power_status_url and cfg["timings_problems"] == [] and "lockout_minutes" in cfg["security"]
    # zóny: pořadí, HW test jen v prázdných zónách, zámek se nikdy nepulzuje
    zs = {z["zone"]: z for z in report["zones"]}
    assert [z["zone"] for z in report["zones"]] == [1, 2, 3, 4] and not ctrl.io.pulses
    assert zs[1]["tested"] and zs[1]["light"] and zs[1]["audio"] and zs[1]["problems"] == [] and zs[1]["lock"]["coil_off"] is True
    assert zs[1]["shelly"]["red"] == {"on": True, "brightness": 100} and zs[1]["shelly"]["matches"] is True and zs[1]["shelly"]["expected"] == "red"
    assert zs[2]["tested"] and zs[2]["light"] is False and any("světlo: relé wav617a R2" in p for p in zs[2]["problems"])
    assert zs[3]["tested"] is False and zs[3]["skipped_reason"] == "session_active" and zs[3]["session_active"] and ctrl.zones[3].tests == 0
    assert zs[4]["lock"]["coil_off"] is False and any("SEPNUTÉ" in p for p in zs[4]["problems"])
    assert zs[4]["contact_raw"] is False and zs[4]["contact_consistent"] is False and any("kontakt" in p for p in zs[4]["problems"])
    zsec = next(s for s in report["protocol"] if s["key"] == "zones")
    ids = {i["id"]: i for i in zsec["items"]}
    assert zsec["status"] == "fail" and ids["zone.1"]["status"] == "ok" and ids["zone.3"]["status"] == "skip"
    assert ids["zone.2.light"]["status"] == "fail" and "R2" in ids["zone.2.light"]["hint"] and ids["zone.4.lock"]["status"] == "fail"
    assert "wav617a R2" in ids["zone.2"]["hint"]                          # souhrn zóny má doplněné {dev}/{ch}
    assert not any("{" in (i.get("hint") or "") for sec in report["protocol"] for i in sec["items"])   # žádné nevyplněné šablony
    # napájení, kamery
    assert report["power"]["ok"] and report["power"]["values"]["battery_soc"] == 55 and report["power"]["values"]["battery_voltage"] == 52.1
    assert report["power"]["values"]["grid_present"] is True and "pvPower" in report["power"]["raw_keys"]
    cams_out = {(c["name"], c["url_kind"]): c for c in report["cameras"]}
    assert set(cams_out) == {("Vjezd", "snapshot"), ("Vjezd", "stream")}          # control_url a ftp se netestují
    assert cams_out[("Vjezd", "snapshot")]["ok"] and cams_out[("Vjezd", "snapshot")]["content_type"].startswith("image/jpeg")
    assert cams_out[("Vjezd", "stream")]["ok"] is False and cams_out[("Vjezd", "stream")]["error"] == "HTTP 500"
    # souhrn + událost
    s = report["summary"]
    assert s["ok"] is False and s["mode"] == "full" and s["zones_total"] == 4 and s["zones_tested"] == 3 and s["zones_ok"] == 2
    assert s["checks"]["total"] == sum(s["checks"][k] for k in ("ok", "warn", "fail", "skip")) and s["checks"]["fail"] >= 3
    assert any(p.startswith("Kóje 2 — světlo:") for p in s["problems"]) and any("ghost" in p for p in s["problems"])
    assert ids["zone.2"]["group"] is True and not any(p.startswith("Kóje 2:") for p in s["problems"])   # souhrn zóny není duplicitní problém
    assert not any("sdílí adresu" in p for p in s["problems"])            # stejná IP, jiný port (simulátor) = žádný konflikt
    assert s["devices_total"] == 4 and s["hosts"] >= 1 and s["sections"]["zones"] == "fail"
    ev = next(e for e in ctrl.events if e.kind == EventKind.DIAGNOSTICS)
    assert ev.message.startswith("Diagnostika pobočky: ") and "problémů" in ev.message and "2/4 zón OK" in ev.message
    assert ev.detail["mode"] == "full" and ev.detail["checks"] == s["checks"]
    st = ctrl.diagnostics.status()["last"]
    assert st["mode"] == "full" and st["zones_ok"] == 2 and st["warnings"] == len(s["warnings"])
    # venek (FakeCtrl.outdoor: světlo wav617b[0], audio out9, selektor → tón se netestuje); do zón se nepočítá
    o = report["outdoor"]
    assert o["zone"] == 9 and o["tested"] and o["light_ok"] is True and o["audio_ok"] is None and o["mode"] == "selector" and ctrl.outdoor.tests == 1
    assert o["light"] == {"ref": "wav617b[0]", "module_online": True, "coil_on": False} and o["problems"] == [] and o["skipped_reason"] is None
    assert ids["outdoor"]["group"] and ids["outdoor"]["status"] == "ok" and ids["outdoor"]["label"] == "Venek (zóna 9)"
    assert ids["outdoor.light"]["status"] == "ok" and ids["outdoor.audio"]["status"] == "skip" and "multi" in ids["outdoor.audio"]["message"]
    assert s["outdoor"] == "ok" and s["zones_total"] == 4 and cfg["outdoor"] == {"zone": 9, "light": {"dev": "wav617b", "coil": 0}, "audio": {"out": "out9"},
                                                                                  "configured": True, "present": True}
    csec = {i["id"]: i for sec in report["protocol"] if sec["key"] == "config" for i in sec["items"]}
    assert csec["config.outdoor"]["status"] == "ok" and csec["config.outdoor"]["value"] == "zóna 9 — světlo wav617b R1, audio out9"


async def test_network_mode_skips_full_steps(tmp_path, sim, httpsrv):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ok, res = await commands.execute(ctrl, "diagnostics", {"mode": "network", "cameras": [{"name": "A", "snapshot_url": f"{httpsrv}/snap.jpg"}]})
    assert ok and res["mode"] == "network" and ctrl.diagnostics.status()["steps"] == list(dg.NETWORK_STEPS)
    report = await ctrl.diagnostics.wait()
    assert report["mode"] == "network" and not ({"zones", "software", "config", "power", "cameras"} & set(report))
    assert [s["key"] for s in report["protocol"]] == [k for k in SECTIONS if k not in ("software", "config", "zones", "power", "cameras")]
    assert report["summary"]["mode"] == "network" and report["summary"]["zones_total"] == 0 and ctrl.zones[1].tests == 0
    ev = next(e for e in ctrl.events if e.kind == EventKind.DIAGNOSTICS)
    assert "zón OK" not in ev.message and "zařízení v LAN" in ev.message       # bez kroku zones žádné „0/0 zón OK“
    # kamery z příkazu zůstaly v kv → lokální full běh (kód z displeje) je použije
    assert ctrl.storage.kv_get(dg.KV_CAMERAS) == [{"name": "A", "snapshot_url": f"{httpsrv}/snap.jpg"}]
    ctrl.diagnostics.start("local_code")
    report = await ctrl.diagnostics.wait()
    assert report["mode"] == "full" and report["cameras"][0]["name"] == "A" and report["cameras"][0]["ok"]


async def test_zone_safety_rules(tmp_path, sim, httpsrv):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ctrl.zones[2] = FakeZone(ctrl, 2, state=ZoneState.FAULT, fault="forced_open", door_closed=False)
    ctrl.io.inputs["wav617a"][1] = False                       # dveře zóny 2 skutečně otevřené
    ctrl.zones[4] = FakeZone(ctrl, 4, hw=dataclasses.replace(zone_hw(4), light=HwRef("wav617b", 0)))
    ctrl.io.offline.add("wav617b")                             # modul světla zóny 4 offline → io_offline
    ctrl.local.diagnostics.zone_test = False
    ctrl.diagnostics.start("service_panel")
    zs = {z["zone"]: z for z in (await ctrl.diagnostics.wait())["zones"]}
    assert all(z["skipped_reason"] == "zone_test_disabled" and not z["tested"] for z in zs.values()) and ctrl.zones[1].tests == 0
    ctrl.local.diagnostics.zone_test = True
    ctrl.ready = False
    ctrl.diagnostics.start("service_panel")
    zs = {z["zone"]: z for z in (await ctrl.diagnostics.wait())["zones"]}
    assert all(z["skipped_reason"] == "not_ready" for z in zs.values()) and ctrl.zones[1].tests == 0
    ctrl.ready = True
    ctrl.diagnostics.start("service_panel")
    report = await ctrl.diagnostics.wait()
    zs = {z["zone"]: z for z in report["zones"]}
    assert zs[1]["tested"] and zs[2]["skipped_reason"] == "fault" and zs[2]["fault"] == "forced_open" and ctrl.zones[2].tests == 0
    assert zs[4]["skipped_reason"] == "io_offline" and "wav617b" in zs[4]["io_problems"] and any("I/O" in p for p in zs[4]["problems"])
    assert not ctrl.io.pulses
    ids = {i["id"]: i for s in report["protocol"] if s["key"] == "zones" for i in s["items"]}
    assert ids["zone.2"]["status"] == "warn" and "porucha" in ids["zone.2.fault"]["label"] and ids["zone.2.fault"]["hint"]


async def test_shelly_mismatch_and_missing(tmp_path, sim, httpsrv):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ctrl.zones = {1: FakeZone(ctrl, 1)}
    ctrl.signals.signal[1] = Signal.GREEN                       # program chce zelenou, Shelly má červenou
    ctrl.diagnostics.start("velin")
    z = (await ctrl.diagnostics.wait())["zones"][0]
    assert z["shelly"]["expected"] == "green" and z["shelly"]["matches"] is False
    assert any("zelená signalizace má svítit" in p for p in z["problems"]) and any("červená signalizace má být zhasnutá" in p for p in z["problems"])
    ctrl.signals.signal[1] = Signal.RED_BLINK                   # blikání = okamžitý stav nelze porovnat
    ctrl.diagnostics.start("velin")
    assert (await ctrl.diagnostics.wait())["zones"][0]["shelly"]["matches"] is None
    ctrl.zones = {}
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    zsec = next(s for s in report["protocol"] if s["key"] == "zones")
    assert report["zones"] == [] and zsec["status"] == "warn" and "Žádné zóny" in zsec["items"][0]["message"]


async def test_power_and_camera_errors(tmp_path, sim, httpsrv):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ctrl.zones = {}
    ctrl.power_status_url = f"{httpsrv}/fail"
    ctrl.diagnostics.start("velin", cameras=[{"name": "K", "stream_url": "http://127.0.0.1:1/x"}])
    report = await ctrl.diagnostics.wait()
    assert report["power"]["ok"] is False and report["power"]["error"] == "HTTP 500" and report["power"]["values"] is None
    assert report["cameras"][0]["ok"] is False and report["cameras"][0]["error"].startswith("ConnectError")
    ids = {i["id"]: i for s in report["protocol"] for i in s["items"]}
    assert ids["power.url"]["status"] == "fail" and ids["camera.K.stream"]["status"] == "fail" and "Kamera K" in ids["camera.K.stream"]["hint"]
    ctrl.power_status_url = None
    ctrl.storage.kv_delete(dg.KV_CAMERAS)
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    assert report["power"] == {"configured": False, "url": None, "ok": None, "status": None, "ms": None, "error": None, "values": None, "raw_keys": []}
    ids = {i["id"]: i for s in report["protocol"] for i in s["items"]}
    assert report["cameras"] == [] and ids["cameras.none"]["status"] == "skip" and ids["power.url"]["status"] == "skip"


# ─── diag_protocol: jednotkové ──────────────────────────────────────────────
def test_section_status_and_items():
    assert dp.section_status([]) == "skip" and dp.section_status([dp.item("a", "A", "skip")]) == "skip"
    assert dp.section_status([dp.item("a", "A", "ok"), dp.item("b", "B", "skip")]) == "ok"
    assert dp.section_status([dp.item("a", "A", "ok"), dp.item("b", "B", "warn")]) == "warn"
    assert dp.section_status([dp.item("a", "A", "warn"), dp.item("b", "B", "fail"), dp.item("c", "C", "ok")]) == "fail"
    assert "hint" not in dp.item("a", "A", "ok", 1) and dp.item("a", "A", "fail", None, "m", "h")["hint"] == "h"
    assert dp.item("a", "A", "nesmysl")["status"] == "warn"


def test_build_protocol_on_empty_and_hints():
    proto = dp.build_protocol({})
    assert [s["key"] for s in proto] == ["system", "network", "lte", "internet", "velin", "modules", "lan", "steps"]
    ids = {i["id"]: i for s in proto for i in s["items"]}
    assert ids["network.gateway"]["status"] == "fail" and ids["velin.paired"]["status"] == "fail"
    assert all(i["hint"] for s in proto for i in s["items"] if i["status"] in ("warn", "fail"))
    summary = dp.build_summary({}, proto)
    assert summary["ok"] is False and summary["checks"]["fail"] >= 2 and summary["hosts"] == 0 and summary["mode"] == "network"
    rep = {"mode": "full", "software": None, "config": None, "zones": None, "power": None, "cameras": None,
           "steps": {"zones": {"ok": False, "error": "timeout"}}}
    proto = dp.build_protocol(rep)
    assert [s["key"] for s in proto] == ["system", "software", "network", "lte", "internet", "velin", "modules", "config", "zones", "power", "cameras", "lan", "steps"]
    zsec = next(s for s in proto if s["key"] == "zones")
    assert zsec["status"] == "skip" and "timeout" in zsec["items"][0]["message"]
    assert next(i for s in proto for i in s["items"] if i["id"] == "step.zones")["status"] == "warn"


class SlowZone(FakeZone):
    """HW test trvá `delay` s; `restored` = obnova světla/signálu po testu proběhla (nesmí ji přerušit zrušení)."""

    def __init__(self, ctrl, n, *, delay: float, **kw) -> None:
        super().__init__(ctrl, n, **kw)
        self.delay, self.restored = delay, False

    async def test_sequence(self) -> dict:
        self.tests += 1
        await asyncio.sleep(self.delay)
        self.restored = True
        return dict(self.result)


async def test_zone_hw_test_budget_shield_and_timeout(tmp_path, sim, httpsrv, monkeypatch):
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    diag = ctrl.diagnostics
    # 1) zbývá málo času běhu → HW test se vůbec nespustí (skipped_reason timeout), zóna se jen čte
    diag.time_left = lambda: diag_steps.ZONE_TEST_BUDGET_S - 1
    diag.start("velin")
    report = await diag.wait()
    skipped = {z["zone"]: z["skipped_reason"] for z in report["zones"]}
    assert skipped == {1: "timeout", 2: "timeout", 3: "session_active", 4: "timeout"}     # relace má přednost před limitem
    assert not any(z["tested"] for z in report["zones"]) and ctrl.zones[1].tests == 0
    assert report["zones"][0]["lock"]["coil_off"] is True and report["zones"][3]["contact_consistent"] is False   # čtení proběhlo
    ids = {i["id"]: i for s in report["protocol"] if s["key"] == "zones" for i in s["items"]}
    assert ids["zone.1"]["status"] == "skip" and "časový limit" in ids["zone.1"]["message"]
    del diag.time_left
    # 2) zrušení kroku (limit běhu) uprostřed HW testu test NEPŘERUŠÍ — obnova světla/signálu doběhne
    slow = SlowZone(ctrl, 1, delay=0.3)
    ctrl.zones = {1: slow}
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(diag_steps.zones(diag, {}), timeout=0.05)
    assert slow.tests == 1 and not slow.restored
    await asyncio.sleep(0.4)
    assert slow.restored
    # 3) vlastní limit jednoho testu → nález „HW test“ (warn), test dobíhá na pozadí, zámek se nikdy nepulzuje
    monkeypatch.setattr(diag_steps, "ZONE_TEST_TIMEOUT_S", 0.05)
    slow = SlowZone(ctrl, 1, delay=0.2)
    ctrl.zones = {1: slow}
    diag.start("velin")
    z = (await diag.wait())["zones"][0]
    assert z["tested"] is False and z["skipped_reason"] == "timeout" and z["light"] is None
    assert any(f["key"] == "test" and f["status"] == "warn" for f in z["findings"]) and not ctrl.io.pulses
    await asyncio.sleep(0.3)
    assert slow.restored
    ids = {i["id"]: i for s in diag.last_report()["protocol"] if s["key"] == "zones" for i in s["items"]}
    assert ids["zone.1"]["status"] == "warn" and ids["zone.1.test"]["hint"] and "HW test" in ids["zone.1.test"]["label"]


def test_summary_zones_total_after_zones_timeout():
    rep = {"mode": "full", "config": {"zones_total": 9}, "zones": [{"zone": 1, "tested": True, "findings": []}],
           "steps": {"zones": {"ok": False, "error": "timeout", "partial": True}}}
    s = dp.build_summary(rep, dp.build_protocol(rep))
    assert s["zones_total"] == 9 and s["zones_ok"] == 1 and s["zones_tested"] == 1
    rep["steps"]["zones"] = {"ok": True}
    assert dp.build_summary(rep, dp.build_protocol(rep))["zones_total"] == 1
