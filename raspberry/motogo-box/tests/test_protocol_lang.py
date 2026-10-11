"""Jazyk obrazovky u podpisu protokolu (`lang`, CONTRACT §28, 1.2.12): ověření, trvalá fronta, edge přes HTTP."""
from __future__ import annotations

import pytest

from motogo_box.handover_submit import doc_lang
from motogo_box.storage import Storage
from motogo_box.supabase_api import SupabaseApi

from tests.handover_fakes import DEVICE_ID, SIG, TOKEN, FakeCtrl, protocol, rr_moto
from tests.test_api import ANON, FakePostgrest

FORM = {"mileage": "1200", "accessories": [{"key": "helmet", "who": "rider", "size": "L", "checked": True}]}
NET_DOWN = {"ok": False, "permanent": False, "error": "network: ConnectError", "already_filled": False}


@pytest.fixture
def ctrl(tmp_path):
    c = FakeCtrl(tmp_path)
    c.cache([{"code": "123456", "kind": "motorcycle", "booking_id": "b1", "door_id": "d3", "box_number": 3}],
            [protocol("b1")])
    yield c
    c.close()


async def _sign(ctrl, form) -> dict:
    hm = ctrl.handover
    await hm.require_before_open(rr_moto(proto=protocol("b1")), ctrl.zones[3], "ui")
    return await hm.submit("b1", form, SIG, None)


def test_doc_lang_validation():
    assert [doc_lang(x) for x in ("en", " DE ", "uk", "pl", "nl", "fr", "es")] == ["en", "de", "uk", "pl", "nl", "fr", "es"]
    # cs = výchozí obrazovka → edge vezme jazyk rezervace; neplatné hodnoty se ignorují
    for bad in ("cs", "CS", "", "xx", "ua", "en-US", None, 5, ["en"], {"lang": "en"}):
        assert doc_lang(bad) is None, bad


async def test_lang_present_goes_to_payload_not_form(ctrl):
    res = await _sign(ctrl, {**FORM, "lang": "de"})
    assert res["ok"] and res["status"] == "saved"
    sent = ctrl.api.submits[0]
    assert sent["lang"] == "de" and "lang" not in sent["form"] and sent["form"] == FORM


@pytest.mark.parametrize("raw", [None, "cs", "xx", 7])
async def test_lang_missing_cs_or_invalid_is_not_sent(ctrl, raw):
    form = dict(FORM) if raw is None else {**FORM, "lang": raw}
    assert (await _sign(ctrl, form))["ok"]
    sent = ctrl.api.submits[0]
    assert "lang" not in sent and "lang" not in sent["form"] and sent["form"] == FORM


async def test_lang_survives_offline_queue_and_restart(ctrl, tmp_path):
    ctrl.api.results.append(NET_DOWN)
    res = await _sign(ctrl, {**FORM, "lang": "uk"})
    assert res["ok"] and res["status"] == "queued"
    reopened = Storage(str(tmp_path / "handover.db"))          # restart jednotky: fronta je na disku
    try:
        rows = reopened.protocol_queue_pending()
    finally:
        reopened.close()
    assert len(rows) == 1 and rows[0]["payload"]["lang"] == "uk" and "lang" not in rows[0]["payload"]["form"]
    assert await ctrl.handover.flush() == 1
    assert ctrl.api.submits[-1]["lang"] == "uk" and ctrl.storage.protocol_queue_pending() == []


async def test_old_queued_item_without_lang_still_submits(ctrl):
    old = {"booking_id": "b9", "form": {"mileage": "1"}, "signature": SIG, "signed_at": "2026-10-01T10:00:00+00:00"}
    ctrl.storage.protocol_queue_put("b9", old)                 # položka z 1.2.11 (bez pole lang)
    ctrl.handover.refresh_queue()
    assert await ctrl.handover.flush() == 1
    assert ctrl.api.submits[-1] == old and ctrl.storage.protocol_queue_pending() == []


async def test_lang_reaches_edge_over_http_after_outage(ctrl):
    """Displej → handover_submit → trvalá fronta → SupabaseApi → edge (mock HTTP): `lang` nahoře v těle, mode kiosk."""
    srv = FakePostgrest()
    await srv.start()
    api = SupabaseApi(f"http://127.0.0.1:{srv.port}", ANON, DEVICE_ID, TOKEN, ctrl.storage, "1.2.12+test")
    ctrl.api = api
    try:
        srv.edge_status, srv.edge_body = 503, None            # edge/síť dole → podpis čeká ve frontě
        res = await _sign(ctrl, {**FORM, "lang": "fr"})
        assert res["ok"] and res["status"] == "queued"
        assert ctrl.storage.protocol_queue_pending()[0]["payload"]["lang"] == "fr"
        srv.edge_status, srv.edge_body = 200, {"success": True}
        assert await ctrl.handover.flush() == 1
        bodies = [b for name, b, _h in srv.calls if name == "submit-handover-protocol"]
        assert len(bodies) == 2 and all(b["lang"] == "fr" for b in bodies)
        body = bodies[-1]
        assert body["mode"] == "kiosk" and body["device_id"] == DEVICE_ID and body["booking_id"] == "b1"
        assert "lang" not in body["form"] and body["signature"] == SIG
    finally:
        await api.close()
        await srv.stop()
