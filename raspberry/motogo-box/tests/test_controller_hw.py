"""Testy `controller_hw.build_hardware`: venek z lokální šablony platí jen s lokálními zónami (zóny z Velína
bez sekce `outdoor` → šablonový venek pryč — jeho světlo by mohlo sdílet cívku se starou zónou 9 z DB)."""
from __future__ import annotations

import copy

from motogo_box.config import load_hardware_file, validate_hardware
from motogo_box.controller_hw import BUNDLED_HW_FILE, build_hardware
from motogo_box.models import HwRef

OLD_ZONE9 = {"zone": 9, "lock": {"dev": "wav645", "coil": 8}, "contact": {"dev": "wav617b", "input": 0},
             "light": {"dev": "wav617b", "coil": 0}}          # stará zóna 9 z DB: světlo na cívce venkovního světla


def _local() -> dict:
    return load_hardware_file(BUNDLED_HW_FILE)


def _doors(local: dict, old_zone9: bool = True) -> list[dict]:
    zones = [copy.deepcopy(z) for z in local["zones"]] + ([copy.deepcopy(OLD_ZONE9)] if old_zone9 else [])
    return [{"id": f"door-{z['zone']}", "box_number": z["zone"], "door_kind": "motorcycle", "hw": z} for z in zones]


def test_local_template_outdoor_only_with_local_zones():
    local = _local()
    for payload in (None, {"hardware": {}, "doors": []}, {"doors": [{"id": "x", "box_number": 1, "hw": {}}]}):
        hw = build_hardware(local, payload)                  # bez zón z Velína: šablona = 8 zón + venek
        assert hw.source == "local" and len(hw.zones) == 8 and hw.outdoor.light == HwRef("wav617b", 0), payload


def test_remote_zones_without_outdoor_drop_template_outdoor():
    local = _local()
    doors = _doors(local)
    for payload in ({"hardware": {}, "doors": doors}, {"doors": doors},
                    {"legacy": True, "hardware": {"outdoor": {"zone": 9}}, "doors": doors}):   # legacy: hardware se ignoruje
        hw = build_hardware(local, payload)
        assert hw.source == "remote" and [z.number for z in hw.zones] == list(range(1, 10)), payload
        assert hw.zone_by_number(9).hw.light == HwRef("wav617b", 0)    # cívka šablonového venku patří zóně 9
        assert hw.outdoor.light is None and not hw.outdoor.configured and not hw.outdoor.present, payload
        assert validate_hardware(hw) == [], payload            # žádná kolize → runtime nepostaví dvě smyčky na R1
    hw = build_hardware(local, {"hardware": {}, "doors": doors})
    assert hw.devices.keys() == local["devices"].keys()       # zařízení/timings ze šablony zůstávají, jen venek pryč


def test_remote_outdoor_wins_with_remote_zones():
    local = _local()
    doors = _doors(local, old_zone9=False)
    remote = {"hardware": {"outdoor": {"zone": 9, "light": {"dev": "wav645", "coil": 15}}}, "doors": doors}
    hw = build_hardware(local, remote)
    assert hw.source == "remote" and hw.outdoor.light == HwRef("wav645", 15) and validate_hardware(hw) == []
    hw = build_hardware(local, {"hardware": {"outdoor": {}}, "doors": doors})     # prázdný venek z Velína = present
    assert hw.outdoor.present and not hw.outdoor.configured
    hw = build_hardware(local, {"hardware": {"timings": {}}, "doors": doors})     # mapa z Velína bez venku (merge_hardware)
    assert not hw.outdoor.present
