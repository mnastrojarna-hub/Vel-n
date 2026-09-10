"""Testy config.py: brno mapa, merge, validace (kolize kanálů, zámek jen WAV645) a `_fill`."""
from __future__ import annotations

import copy
import logging
import os

from motogo_box.config import (AudioCfg, HardwareConfig, SecurityCfg, SignalCfg, TimingsCfg, _fill,
                               blocking_problems, load_hardware_file, merge_hardware, validate_hardware)

HW_FILE = os.path.join(os.path.dirname(__file__), "..", "config", "brno-9zone.yaml")


def _brno() -> dict:
    return load_hardware_file(HW_FILE)


def _with_zone1(**overrides) -> HardwareConfig:
    """Brno mapa jen se zónou 1, jejíž hw položky přepíšeme."""
    d = _brno()
    d["zones"] = [dict(d["zones"][0], **overrides)]
    return HardwareConfig.from_dict(d)


# ─── Načtení výchozí mapy ────────────────────────────────────────────────────
def test_brno_map_loads_nine_valid_zones():
    hw = HardwareConfig.from_dict(_brno())
    assert [z.number for z in hw.zones] == list(range(1, 10))
    for z in hw.zones:
        assert all(getattr(z.hw, r) is not None for r in ("lock", "contact", "light", "audio", "red", "green"))
        assert z.hw.lock.dev == "wav645"
    assert validate_hardware(hw) == []
    assert set(hw.modbus_devices()) == {"wav645", "wav617a", "wav617b"}
    assert len(hw.shelly_devices()) == 4


def test_brno_map_channels_are_unique():
    hw = HardwareConfig.from_dict(_brno())
    coils = [(r.dev, r.idx) for z in hw.zones for r in (z.hw.lock, z.hw.light, z.hw.audio)]
    lights = [(r.dev, r.idx) for z in hw.zones for r in (z.hw.red, z.hw.green)]
    inputs = [(r.dev, r.idx) for z in hw.zones for r in (z.hw.contact,)]
    for lst in (coils, lights, inputs):
        assert len(lst) == len(set(lst))


def test_zones_from_doors_take_precedence():
    doors = [{"id": "d1", "box_number": 3, "door_kind": "motorcycle", "label": "Kóje 3",
              "hw": {"zone": 3, "lock": {"dev": "wav645", "coil": 2}, "contact": {"dev": "wav617a", "input": 2}}},
             {"id": "d2", "box_number": 4, "hw": {}}]
    hw = HardwareConfig.from_dict(_brno(), doors)
    assert [z.number for z in hw.zones] == [3]
    assert hw.zone_by_door("d1").box_number == 3 and hw.zone_by_box(3).door_id == "d1"
    assert validate_hardware(hw) == []


# ─── merge_hardware ──────────────────────────────────────────────────────────
def test_merge_remote_overrides_timings_but_never_zones():
    local = _brno()
    merged = merge_hardware(local, {"timings": {"lock_pulse_ms": 500}, "zones": [], "audio": None})
    assert merged["timings"]["lock_pulse_ms"] == 500
    assert merged["timings"]["door_open_timeout_s"] == 30      # ostatní klíče zůstaly
    assert merged["zones"] == local["zones"]
    assert merged["audio"] == local["audio"]
    assert merge_hardware(local, None) == local


# ─── validate_hardware ───────────────────────────────────────────────────────
def test_validate_reports_unknown_device_and_missing_roles():
    hw = _with_zone1(lock={"dev": "neexistuje", "coil": 0}, contact=None)
    problems = validate_hardware(hw)
    assert any("neznámé zařízení 'neexistuje'" in p for p in problems)
    assert any("chybí contact" in p for p in problems)


def test_validate_rejects_lock_and_audio_on_same_coil_within_zone():
    """Nález: lock == audio v téže zóně by držel zámek pod napětím po dobu hudby."""
    hw = _with_zone1(audio={"dev": "wav645", "coil": 0})
    problems = validate_hardware(hw)
    assert len(problems) == 1 and "audio a lock sdílí wav645[0]" in problems[0]


def test_validate_rejects_light_and_audio_on_same_coil_within_zone():
    """Nález: light == audio obchází exkluzivitu audio selektoru."""
    hw = _with_zone1(audio={"dev": "wav617a", "coil": 0})
    problems = validate_hardware(hw)
    assert len(problems) == 1 and "audio a light sdílí wav617a[0]" in problems[0]


def test_validate_rejects_shared_channel_between_zones():
    d = _brno()
    d["zones"][1]["lock"] = {"dev": "wav645", "coil": 0}                 # zámek zóny 1
    d["zones"][2]["contact"] = {"dev": "wav617a", "input": 0}            # kontakt zóny 1
    d["zones"][3]["red"] = {"dev": "shelly1", "light": 1}                # zelená zóny 1
    d["zones"][4]["light"] = {"dev": "wav645", "coil": 9}                # audio zóny 8 (WAV645 R10)
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert any("Zóna 2: lock wav645[0] už používá zóna 1 (lock)" in p for p in problems)
    assert any("Zóna 3: contact wav617a[0] už používá zóna 1 (contact)" in p for p in problems)
    assert any("Zóna 4: red shelly1[1] už používá zóna 1 (green)" in p for p in problems)
    assert any("Zóna 8: audio wav645[9] už používá zóna 5 (light)" in p for p in problems)


def test_validate_requires_lock_on_wav645():
    """Nález: zámek na WAV617 = softwarový pulz → při pádu procesu zůstane pod napětím."""
    hw = _with_zone1(lock={"dev": "wav617a", "coil": 3})
    problems = validate_hardware(hw)
    assert len(problems) == 1 and "lock musí být relé WAV645" in problems[0]
    # light/audio smí být na WAV645 i WAV617, contact jen WAV617, red/green jen Shelly
    assert validate_hardware(_with_zone1(audio={"dev": "wav645", "coil": 11})) == []
    assert any("contact musí být vstup WAV617" in p
               for p in validate_hardware(_with_zone1(contact={"dev": "wav645", "input": 0})))
    assert any("red musí být na Shelly" in p
               for p in validate_hardware(_with_zone1(red={"dev": "wav645", "light": 12})))


def test_validate_rejects_duplicate_zone_numbers_and_negative_index():
    d = _brno()
    d["zones"][1]["zone"] = 1
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert "Duplicitní čísla zón." in problems
    assert any("záporný index" in p for p in validate_hardware(_with_zone1(light={"dev": "wav617a", "coil": -1})))


# ─── _fill / from_dict — robustní koerce ─────────────────────────────────────
def test_audio_device_string_does_not_crash_from_dict():
    """Nález (critical): `audio.device` (default None) → dříve TypeError → restart smyčka služby."""
    d = _brno()
    d["audio"]["device"] = "alsa/plughw:CARD=Device"
    hw = HardwareConfig.from_dict(d)
    assert hw.audio.device == "alsa/plughw:CARD=Device"
    assert hw.audio.volume == 70 and hw.audio.shuffle is True
    assert HardwareConfig.from_dict(_brno()).audio.device is None


def test_fill_coerces_types_and_keeps_defaults_on_invalid(caplog):
    assert _fill(SecurityCfg, {"mask_pin_on_screen": "false"}).mask_pin_on_screen is False
    assert _fill(SecurityCfg, {"mask_pin_on_screen": "ano"}).mask_pin_on_screen is True
    assert _fill(SecurityCfg, {"mask_pin_on_screen": 0}).mask_pin_on_screen is False
    assert _fill(AudioCfg, {"volume": "55", "fade_in_ms": 1000.0}).volume == 55
    assert _fill(SignalCfg, {"transition_s": 1}).transition_s == 1.0
    t = _fill(TimingsCfg, {"overtime_alert_minutes": [5], "unknown_key": 1, "lock_pulse_ms": None})
    assert t.overtime_alert_minutes == [5] and t.lock_pulse_ms == 800
    with caplog.at_level(logging.WARNING, logger="motogo.config"):
        a = _fill(AudioCfg, {"volume": "hodne", "fade_out_ms": 12.5, "shuffle": "možná"})
    assert (a.volume, a.fade_out_ms, a.shuffle) == (70, 500, True)
    assert sum("ponechávám výchozí" in r.getMessage() for r in caplog.records) == 3


def test_from_dict_raw_is_deep_copy():
    d = _brno()
    hw = HardwareConfig.from_dict(d)
    d["timings"]["lock_pulse_ms"] = 1
    assert hw.raw["timings"]["lock_pulse_ms"] == 800 and hw.timings.lock_pulse_ms == 800
    assert copy.deepcopy(hw.raw) == hw.raw


# ─── audio: režim multi / kanály ─────────────────────────────────────────────
def _multi(**audio) -> HardwareConfig:
    d = _brno()
    d["audio"].update({"mode": "multi", "outputs": {"out1": {"device": "alsa/a"}, "out2": {"device": "alsa/b"},
                                                    "out9": {"device": "alsa/v"}}, **audio})
    d["zones"] = [dict(d["zones"][0], audio={"out": "out1"}), dict(d["zones"][1], audio={"out": "out2"})]
    return HardwareConfig.from_dict(d)


def test_validate_multi_ok_and_unknown_output():
    assert validate_hardware(_multi(channels={"outdoor": {"out": "out9"}})) == []
    hw = _multi()
    hw.zones[1].hw = hw.zones[1].hw.__class__(zone=2, lock=hw.zones[1].hw.lock, contact=hw.zones[1].hw.contact,
                                              audio_out="outX")
    assert any("Zóna 2: audio výstup 'outX' není v audio.outputs" in p for p in validate_hardware(hw))


def test_validate_multi_shared_output_and_channel_without_output():
    d = _brno()
    d["audio"].update({"mode": "multi", "outputs": {"out1": {"device": "alsa/a"}}, "channels": {"outdoor": {}}})
    d["zones"] = [dict(d["zones"][0], audio={"out": "out1"}), dict(d["zones"][1], audio={"out": "out1"})]
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert any("Zóna 2: audio výstup 'out1' už používá zóna 1" in p for p in problems)
    assert any("Kanál outdoor: chybí výstup" in p for p in problems)
    problems = validate_hardware(_multi(channels={"outdoor": {"out": "out2"}}))
    assert any("Kanál outdoor: audio výstup 'out2' už používá zóna 2" in p for p in problems)
    assert any("není v audio.outputs" in p for p in validate_hardware(_multi(channels={"outdoor": {"out": "out7"}})))


def test_validate_selector_with_channels_is_only_warning():
    d = _brno()
    d["audio"]["channels"] = {"outdoor": {"out": "out9"}}
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert len(problems) == 1 and problems[0].startswith("Upozornění:") and "selector" in problems[0]
    assert blocking_problems(problems) == []
    d["audio"]["mode"] = "MULTI "                       # normalizace režimu
    d["audio"]["outputs"] = {"out9": {"device": "alsa/v"}}
    hw = HardwareConfig.from_dict(d)
    assert hw.audio.engine_mode == "multi" and hw.audio.output_devices() == {"out9": "alsa/v"}
    problems = validate_hardware(hw)
    assert all(p.startswith("Upozornění:") and "nemá audio výstup" in p for p in problems) and len(problems) == 9
    d["audio"]["mode"] = "divny"
    assert any("audio.mode 'divny'" in p for p in validate_hardware(HardwareConfig.from_dict(d)))
    d["audio"]["outputs"] = "nesmysl"                    # vadný tvar z Velína nesmí shodit start
    hw = HardwareConfig.from_dict(d)
    assert hw.audio.output_devices() == {} and hw.audio.engine_mode == "selector"


def test_validate_multi_channel_relay_collisions_block():
    """Relé „enable“ kanálu nesmí ležet na cívce zámku/světla zóny ani jiného kanálu, ani mimo rozsah (§12)."""
    d = _brno()
    lock = d["zones"][0]["lock"]
    d["audio"].update({"mode": "multi", "outputs": {"out1": {"device": "alsa/a"}, "out8": {"device": "alsa/s"},
                                                    "out9": {"device": "alsa/v"}},
                       "channels": {"outdoor": {"out": "out9", "dev": lock["dev"], "coil": lock["coil"]}}})
    d["zones"] = [dict(d["zones"][0], audio={"out": "out1"})]
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert any(f"Kanál outdoor: relé {lock['dev']}[{lock['coil']}] už používá zóna 1 (lock)" in p for p in problems)
    assert blocking_problems(problems)                   # blokuje — mapa se neuplatní
    d["audio"]["channels"] = {"outdoor": {"out": "out9", "dev": "wav645", "coil": 16},
                              "satna": {"out": "out8", "dev": "wav645", "coil": 15},
                              "chodba": {"out": "out8", "dev": "wav645", "coil": 15}}
    problems = validate_hardware(HardwareConfig.from_dict(d))
    assert any("Kanál outdoor: relé wav645[16] je mimo rozsah modulu wav645 (0–15)" in p for p in problems)
    assert any("Kanál chodba: relé wav645[15] už používá kanál satna" in p for p in problems)
    d["audio"]["channels"] = {"outdoor": {"out": "out9", "dev": "wav645", "coil": 15}}
    assert blocking_problems(validate_hardware(HardwareConfig.from_dict(d))) == []
