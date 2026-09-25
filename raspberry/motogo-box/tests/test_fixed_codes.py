"""Pevné servisní kódy 39301A–H (kóje 1–7 + šatna) v `submit_code` — bez Velína i bez sítě."""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from motogo_box import controller_codes as cc
from motogo_box import fixed_codes


class FakeZone:
    def __init__(self, number: int, kind: str = "motorcycle", result: tuple[bool, str] = (True, "ok")):
        self.number, self.result, self.calls = number, result, []
        name = "Šatna" if kind == "accessories" else f"Kóje {number}"
        self.zone = SimpleNamespace(kind=kind, door_id=f"d{number}", box_number=number, display_name=name)

    async def grant_access(self, *, booking_id, kind, source):
        self.calls.append((booking_id, kind, source))
        return self.result


class FakeGuard:
    def __init__(self, locked=None):
        self.locked, self.ok = locked, []

    def locked_until(self):
        return self.locked

    def register_success(self, masked):
        self.ok.append(masked)


class FakeApi:
    async def resolve_code(self, code):   # pevný kód se na Velín nesmí ptát
        raise AssertionError("resolve_code nemá být volán")


class FakeCtrl:
    def __init__(self, zones, ready=True, locked=None):
        self.zones = {z.number: z for z in zones}
        self.ready, self.pin_guard, self.api, self.events = ready, FakeGuard(locked), FakeApi(), []
        self.diagnostics = None

    def find_zone(self, *, door_id=None, zone=None, box_number=None):
        return self.zones.get(int(zone)) if zone is not None else None

    async def emit(self, event):
        self.events.append(event)


def brno():
    return [FakeZone(n) for n in range(1, 8)] + [FakeZone(8, "accessories")]


@pytest.mark.parametrize("code,letter", [("39301A", "A"), ("39301g", "G"), (" 39301 H ", None), ("39301H", "H")])
def test_target(code, letter):
    assert fixed_codes.target(code.strip()) == letter


@pytest.mark.parametrize("code", ["39301", "39301I", "39301AA", "393011", "49301A", ""])
def test_target_rejects(code):
    assert fixed_codes.target(code) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("letter,zone", [(ch, i + 1) for i, ch in enumerate("ABCDEFG")])
async def test_letters_open_boxes(letter, zone):
    ctrl = FakeCtrl(brno())
    res = await cc.submit_code(ctrl, f"39301{letter.lower()}", "ui")
    assert res["ok"] and res["zone"] == zone and res["kind"] == "service_door"
    assert ctrl.zones[zone].calls == [(None, "service", fixed_codes.SOURCE)]
    assert res["message"] == f"Otevřeno — Kóje {zone}."


@pytest.mark.asyncio
async def test_h_opens_wardrobe_by_kind():
    zones = [FakeZone(n) for n in range(1, 9)] + [FakeZone(9, "accessories")]
    ctrl = FakeCtrl(zones)
    res = await cc.submit_code(ctrl, "39301H", "ui")
    assert res["ok"] and res["zone"] == 9 and ctrl.zones[9].calls
    assert not ctrl.zones[8].calls


@pytest.mark.asyncio
async def test_missing_zone_and_failure():
    ctrl = FakeCtrl([FakeZone(1, result=(False, "door_open"))])
    res = await cc.submit_code(ctrl, "39301C", "ui")
    assert not res["ok"] and res["error"] == "zone_not_configured"
    res = await cc.submit_code(ctrl, "39301A", "ui")
    assert not res["ok"] and res["error"] == "door_open" and ctrl.events


@pytest.mark.asyncio
async def test_lockout_not_ready_and_diag_window_block():
    assert (await cc.submit_code(FakeCtrl(brno(), locked="x"), "39301A", "ui"))["error"] == "locked"
    assert (await cc.submit_code(FakeCtrl(brno(), ready=False), "39301A", "ui"))["error"] == "not_ready"
    ctrl = FakeCtrl(brno())
    ctrl.api = SimpleNamespace(resolve_code=_none)
    ctrl.storage = SimpleNamespace(load_code_cache=lambda: None)
    res = await cc.submit_code(ctrl, "39301A", "diag_ui", diagnostics_only=True)
    assert not res["ok"] and not ctrl.zones[1].calls


async def _none(code):
    return None
