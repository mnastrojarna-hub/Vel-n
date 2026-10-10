"""Velikosti výbavy na samoobsluze (`gear_limits.py`, zadání 2026-10-10): helma S–3XL, bunda/kalhoty/rukavice do 4XL."""
from __future__ import annotations

from motogo_box import gear_limits as gl
from motogo_box.handover import HandoverManager

from tests.handover_fakes import FakeCtrl, protocol, rr_moto

ADULT = ["S", "M", "L", "XL", "2XL", "3XL", "4XL"]
# jako živá DB 2026-10-10: řádek `jacket` chybí, rukavice do 5XL, kalhoty do 6XL, helma od XS
LIVE = {"adult": {"helmet": ["XS", "S", "M", "L", "XL", "2XL", "3XL"], "gloves": ADULT + ["5XL"],
                  "pants": ADULT + ["5XL", "6XL"], "boots": [str(n) for n in range(39, 49)]},
        "child": {"helmet": ["YM", "XS", "S"], "gloves": ["4–7 let", "8–12 let"], "pants": ADULT + ["5XL", "6XL"]}}


def test_rank_normalizes_and_aliases():
    assert gl.rank(" xxl ") == gl.rank("2XL") and gl.rank("XXXL") == gl.rank("3XL") and gl.rank("xxxxl") == gl.rank("4XL")
    assert gl.rank("XXS") < gl.rank("XS") < gl.rank("S") < gl.rank("4XL") < gl.rank("5XL") < gl.rank("6XL")
    assert gl.rank("43") is None and gl.rank(43) is None and gl.rank("4–7 let") is None and gl.rank(None) is None


def test_allowed_sizes_adult_rule_and_fallback():
    assert gl.allowed_sizes("helmet", LIVE["adult"]["helmet"]) == ["S", "M", "L", "XL", "2XL", "3XL"]
    assert gl.allowed_sizes("gloves", LIVE["adult"]["gloves"]) == ADULT
    assert gl.allowed_sizes("pants", LIVE["adult"]["pants"]) == ADULT
    assert gl.allowed_sizes("jacket", None) == ADULT and gl.allowed_sizes("jacket", []) == ADULT    # chybějící klíč
    assert gl.allowed_sizes("helmet", None) == ADULT[:-1]
    assert gl.allowed_sizes("boots", LIVE["adult"]["boots"]) == LIVE["adult"]["boots"] and gl.allowed_sizes("boots", None) == []
    assert gl.allowed_sizes("balaclava", ["UNI"]) == ["UNI"]
    assert gl.allowed_sizes("jacket", ["XS", "XXL", "xxxl", "XXXXL", "XXXXXL"]) == ["XS", "XXL", "xxxl", "XXXXL"]


def test_allowed_sizes_child_unchanged():
    assert gl.allowed_sizes("helmet", ["YM", "XS", "S"], True) == ["YM", "XS", "S"]
    assert gl.allowed_sizes("pants", LIVE["child"]["pants"], True) == LIVE["child"]["pants"]
    assert gl.allowed_sizes("jacket", None, True) == []                 # záloha jen pro dospělé


def test_clamp_nearest_offered_never_empty():
    assert gl.clamp("jacket", "5XL", ADULT) == "4XL" and gl.clamp("pants", " 6xl", ADULT) == "4XL"
    assert gl.clamp("helmet", "XS", ADULT[:-1]) == "S" and gl.clamp("helmet", "4XL", ADULT[:-1]) == "3XL"
    assert gl.clamp("gloves", "6XL", ["S", "M", "L", "XL", "2XL"]) == "2XL"     # nejbližší z nabídky
    assert gl.clamp("jacket", "XXXXXL", ["XXL", "XXXXL"]) == "XXXXL"          # zápis z nabídky
    assert gl.clamp("jacket", "5XL", []) == "4XL" and gl.clamp("helmet", "XXS", None) == "S"   # bez nabídky = mez
    assert gl.clamp("jacket", "M", ["L"]) == "M" and gl.clamp("boots", "47", ["43"]) == "47"   # v rozsahu beze změny
    assert gl.clamp("helmet", "XS", ["YM", "XS"], True) == "XS" and gl.clamp("jacket", "6XL", [], True) == "6XL"


def test_clamp_gear_copies():
    gear = [{"key": "jacket", "who": "rider", "size": "5XL"}, {"key": "boots", "size": "45"}, "x"]
    out = gl.clamp_gear(gear, {"jacket": ADULT})
    assert out[0] == {"key": "jacket", "who": "rider", "size": "4XL"} and out[1] is gear[1] and out[2] == "x"
    assert gear[0]["size"] == "5XL" and gl.clamp_gear(None, {}) is None


async def test_status_filters_sizes_and_clamps_booked_gear(tmp_path):
    ctrl = FakeCtrl(tmp_path)
    try:
        hm: HandoverManager = ctrl.handover
        hm.gear_sizes = LIVE
        p = protocol("b1")
        p["data"]["gear"] = [{"key": "helmet", "who": "rider", "field": "helmet_size", "size": "XS"},
                             {"key": "jacket", "who": "rider", "field": "jacket_size", "size": "6XL"},
                             {"key": "gloves", "who": "passenger", "field": "passenger_gloves_size", "size": "5XL"},
                             {"key": "boots", "who": "rider", "field": "boots_size", "size": "48"}]
        hm.remember(rr_moto(proto=p))
        assert await hm.on_wardrobe_closed(8, "b1") == "protocol"
        a = hm.status()["active"]
        assert a["sizes"]["helmet"] == ["S", "M", "L", "XL", "2XL", "3XL"] and a["sizes"]["jacket"] == ADULT
        assert a["sizes"]["gloves"] == ADULT and a["sizes"]["pants"] == ADULT and a["sizes"]["boots"][-1] == "48"
        assert [g["size"] for g in a["data"]["gear"]] == ["S", "4XL", "4XL", "48"]
        assert [g["size"] for g in hm.items["b1"].data["gear"]] == ["XS", "6XL", "5XL", "48"]   # rezervace beze změny
        assert hm.status()["active"]["data"] == a["data"]                      # deterministické (UI gearSig)
        hm.items["b1"].is_child = True                                         # dětská motorka beze změny
        c = hm.status()["active"]
        assert c["sizes"]["helmet"] == ["YM", "XS", "S"] and c["sizes"]["jacket"] == []
        assert [g["size"] for g in c["data"]["gear"]] == ["XS", "6XL", "5XL", "48"]
    finally:
        ctrl.close()
