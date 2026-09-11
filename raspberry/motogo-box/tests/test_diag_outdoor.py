"""Venek (zóna bez dveří) v kompletní diagnostice (`diag_outdoor`): report["outdoor"] z kroku `zones`
(HW test jen bez relace / s online modulem / při zapnutém testu — světlo se NIKDY nespíná při relaci),
`config["outdoor"]`, skupina „Venek (zóna N)“ + položka „Venek“ v protokolu a `summary.outdoor`."""
from __future__ import annotations

from motogo_box import diag_protocol as dp
from tests.diag_fakes import FakeOutdoor, FakeOutdoorCfg, FakeZone
from tests.test_diag_protocol import full_ctrl, httpsrv  # noqa: F401 — fixture
from tests.test_diagnostics import sim  # noqa: F401 — fixture


async def test_outdoor_findings_skips_and_config(tmp_path, sim, httpsrv):
    """Venek: multi + selhání světla/tónu → fail položky, summary.outdoor fail, problems; relace / modul offline / vypnutý
    test → skip a světlo se NIKDY nespíná; venek bez světla i audia → bez report["outdoor"], konfigurace warn/skip."""
    ctrl = full_ctrl(tmp_path, sim, httpsrv)
    ctrl.zones = {1: FakeZone(ctrl, 1)}
    ctrl.audio.mode = "multi"
    ctrl.outdoor = FakeOutdoor(audio=ctrl.audio, result={"light": False, "audio": False})
    ctrl.io.coils["wav617b"][0] = True                       # světlo právě svítí — jen se čte
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    o, s = report["outdoor"], report["summary"]
    assert o["tested"] and o["light_ok"] is False and o["audio_ok"] is False and o["mode"] == "multi" and o["light"]["coil_on"] is True
    assert [f["key"] for f in o["findings"]] == ["light", "audio"] and len(o["problems"]) == 2 and ctrl.outdoor.tests == 1
    ids = {i["id"]: i for sec in report["protocol"] if sec["key"] == "zones" for i in sec["items"]}
    assert [i["id"] for i in ids.values()][-3:] == ["outdoor", "outdoor.light", "outdoor.audio"] and ids["outdoor"]["status"] == "fail"
    assert "wav617b R1" in ids["outdoor"]["hint"] and ids["outdoor.light"]["status"] == "fail" and "wav617b R1" in ids["outdoor.light"]["hint"]
    assert ids["outdoor.audio"]["status"] == "fail" and "multi" in ids["outdoor.audio"]["hint"] and "out9" in ids["outdoor.audio"]["message"]
    assert s["outdoor"] == "fail" and s["zones_total"] == 1 and s["zones_ok"] == 1 and s["sections"]["zones"] == "fail"
    assert any(p.startswith("Venek (zóna 9) — venkovní světlo:") for p in s["problems"]) and not any(p.startswith("Venek (zóna 9):") for p in s["problems"])
    ctrl.outdoor = FakeOutdoor(audio=ctrl.audio, active=True)          # relace venku → test se nespustí
    ctrl.diagnostics.start("velin")
    o = (await ctrl.diagnostics.wait())["outdoor"]
    assert o["active"] and o["skipped_reason"] == "session_active" and not o["tested"] and o["findings"] == [] and ctrl.outdoor.tests == 0
    ctrl.outdoor = FakeOutdoor(audio=ctrl.audio)
    ctrl.io.offline.add("wav617b")                                     # modul světla offline → nález I/O, test se nespustí
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    o, ids = report["outdoor"], {i["id"]: i for sec in report["protocol"] for i in sec["items"]}
    assert o["skipped_reason"] == "io_offline" and o["light"]["module_online"] is False and o["findings"][0]["key"] == "io" and ctrl.outdoor.tests == 0
    assert ids["outdoor.light"]["status"] == "fail" and ids["outdoor.audio"]["status"] == "skip" and report["summary"]["outdoor"] == "fail"
    ctrl.io.offline.clear()
    ctrl.local.diagnostics.zone_test = False
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    ids = {i["id"]: i for sec in report["protocol"] for i in sec["items"]}
    assert report["outdoor"]["skipped_reason"] == "zone_test_disabled" and report["summary"]["outdoor"] == "skip" and ids["outdoor"]["status"] == "skip"
    assert "vypnutý" in ids["outdoor.light"]["message"] and ctrl.outdoor.tests == 0
    ctrl.outdoor = FakeOutdoor(FakeOutdoorCfg(light=None, audio_out=None), audio=ctrl.audio)   # v mapě, ale prázdný
    ctrl.hardware.outdoor = ctrl.outdoor.cfg
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    ids = {i["id"]: i for sec in report["protocol"] for i in sec["items"]}
    assert "outdoor" not in report and report["summary"]["outdoor"] is None and "outdoor" not in ids and ctrl.outdoor.tests == 0
    assert ids["config.outdoor"]["status"] == "warn" and ids["config.outdoor"]["hint"] and report["config"]["outdoor"] == {"zone": 9, "configured": False, "present": True}
    del ctrl.outdoor                                                   # jednotka bez venku (starší program) → jen „nenastaven“
    ctrl.hardware.outdoor = None
    ctrl.diagnostics.start("velin")
    report = await ctrl.diagnostics.wait()
    ids = {i["id"]: i for sec in report["protocol"] for i in sec["items"]}
    assert "outdoor" not in report and ids["config.outdoor"]["status"] == "skip" and report["config"]["outdoor"] == {"configured": False, "present": False}


def test_protocol_outdoor_from_report_dict():
    """Jen protokol: report bez venku → nic; venek s timeoutem testu → warn/skip; otestovaný a hudba hraje → ok/skip."""
    base = {"mode": "full", "zones": [], "config": {"zones_total": 0, "outdoor": {"configured": False, "present": False}}}
    proto = dp.build_protocol(base)
    ids = {i["id"]: i for s in proto for i in s["items"]}
    assert ids["config.outdoor"]["status"] == "skip" and "outdoor" not in ids and dp.build_summary(base, proto)["outdoor"] is None
    o = {"zone": 9, "light": {"ref": "wav617b[0]", "module_online": True, "coil_on": False}, "audio_out": "out9", "mode": "multi", "active": False,
         "tested": False, "skipped_reason": "timeout", "light_ok": None, "audio_ok": None, "problems": ["HW test venku nedoběhl"],
         "findings": [{"key": "test", "status": "warn", "message": "HW test venku nedoběhl"}]}
    rep = {**base, "outdoor": o}
    proto = dp.build_protocol(rep)
    zsec = next(s for s in proto if s["key"] == "zones")
    assert [i["id"] for i in zsec["items"]] == ["zones.none", "outdoor", "outdoor.light", "outdoor.audio"] and zsec["status"] == "warn"
    ids = {i["id"]: i for i in zsec["items"]}
    assert ids["outdoor"]["status"] == "warn" and ids["outdoor.light"]["status"] == "warn" and ids["outdoor.light"]["hint"] and ids["outdoor.audio"]["status"] == "skip"
    s = dp.build_summary(rep, proto)
    assert s["outdoor"] == "skip" and s["zones_total"] == 0 and any(w.startswith("Venek (zóna 9) — venkovní světlo") for w in s["warnings"])
    o.update(tested=True, skipped_reason=None, light_ok=True, audio_ok=None, findings=[], problems=[])
    proto = dp.build_protocol(rep)
    ids = {i["id"]: i for s in proto for i in s["items"]}
    assert ids["outdoor"]["status"] == "ok" and ids["outdoor.light"]["status"] == "ok" and "hraje" in ids["outdoor.audio"]["message"]
    assert dp.build_summary(rep, proto)["outdoor"] == "ok" and not any("{" in (i.get("hint") or "") for i in ids.values())
